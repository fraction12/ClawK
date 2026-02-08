#!/usr/bin/env python3
"""WebSocket streaming TTS server using edge-tts."""

import asyncio
import json
import logging
import os
import signal
import time

import edge_tts
import websockets

DEFAULT_VOICE = os.environ.get("EDGE_TTS_VOICE", "en-GB-RyanNeural")
HOST = "localhost"
PORT = 8765

# --- Limits (#29, #31) ---
MAX_TEXT_LENGTH = 5000
MAX_CONNECTIONS = 5
RATE_LIMIT_WINDOW = 60  # seconds
RATE_LIMIT_MAX_REQUESTS = 20

# --- Allowed voices (#30) ---
ALLOWED_VOICES = {
    "en-GB-RyanNeural",
    "en-US-GuyNeural",
    "en-US-JennyNeural",
    "en-US-AriaNeural",
    "en-GB-SoniaNeural",
    "en-AU-NatashaNeural",
    "en-AU-WilliamNeural",
    "en-IN-NeerjaNeural",
    "en-IN-PrabhatNeural",
}

# --- Shutdown (#32) ---
SHUTDOWN_TIMEOUT = 5  # seconds

SERVER_VERSION = "1.0.0"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("tts_server")

# Track connected clients (#31, #32)
connected_clients: set = set()

# Rate limit tracker: remote_address -> list of request timestamps (#31)
rate_limit_tracker: dict = {}


def check_rate_limit(remote) -> bool:
    """Return True if the request is allowed, False if rate-limited."""
    key = str(remote)
    now = time.monotonic()
    timestamps = rate_limit_tracker.get(key, [])
    # Prune old timestamps outside the window
    timestamps = [t for t in timestamps if now - t < RATE_LIMIT_WINDOW]
    if len(timestamps) >= RATE_LIMIT_MAX_REQUESTS:
        rate_limit_tracker[key] = timestamps
        return False
    timestamps.append(now)
    rate_limit_tracker[key] = timestamps
    return True


async def handle_tts(websocket):
    remote = websocket.remote_address

    # Connection limit (#31)
    if len(connected_clients) >= MAX_CONNECTIONS:
        log.warning("Connection rejected (limit %d): %s", MAX_CONNECTIONS, remote)
        await websocket.close(1013, "Maximum connections reached")
        return

    connected_clients.add(websocket)
    log.info("Client connected: %s (%d active)", remote, len(connected_clients))
    try:
        async for raw in websocket:
            # Rate limiting (#31)
            if not check_rate_limit(remote):
                log.warning("Rate limit exceeded for %s", remote)
                await websocket.send(
                    json.dumps({"error": "Rate limit exceeded. Try again later."})
                )
                continue

            # Parse request
            try:
                msg = json.loads(raw)

                # Health check (#33)
                if msg.get("command") == "health":
                    await websocket.send(json.dumps({
                        "status": "ok",
                        "version": SERVER_VERSION,
                        "connections": len(connected_clients),
                    }))
                    continue

                text = msg["text"]
                voice = msg.get("voice", DEFAULT_VOICE)
            except (json.JSONDecodeError, KeyError, TypeError):
                # Plain string fallback
                if isinstance(raw, str) and raw.strip():
                    text = raw.strip()
                    voice = DEFAULT_VOICE
                else:
                    await websocket.send(
                        json.dumps({"error": "Send JSON with 'text' field or a plain text string"})
                    )
                    continue

            # Input length validation (#29)
            if len(text) > MAX_TEXT_LENGTH:
                log.warning("Text too long from %s: %d chars (max %d)", remote, len(text), MAX_TEXT_LENGTH)
                await websocket.send(
                    json.dumps({"error": f"Text exceeds maximum length of {MAX_TEXT_LENGTH} characters"})
                )
                continue

            # Voice validation (#30)
            if voice not in ALLOWED_VOICES:
                log.warning("Invalid voice %r from %s, falling back to %s", voice, remote, DEFAULT_VOICE)
                voice = DEFAULT_VOICE

            log.info("Request from %s: voice=%s text=%r", remote, voice, text[:80])

            # Stream TTS audio chunks
            try:
                communicate = edge_tts.Communicate(text, voice)
                chunk_count = 0
                async for chunk in communicate.stream():
                    if chunk["type"] == "audio":
                        await websocket.send(chunk["data"])
                        chunk_count += 1

                await websocket.send(b"END")
                log.info("Finished: %d audio chunks sent to %s", chunk_count, remote)

            except Exception as e:
                log.exception("TTS streaming error for %s", remote)
                await websocket.send(json.dumps({"error": f"TTS failed: {e}"}))
                await websocket.send(b"END")

    except websockets.ConnectionClosed:
        log.info("Client disconnected: %s", remote)
    finally:
        connected_clients.discard(websocket)
        # Clean up rate limit entry
        key = str(remote)
        rate_limit_tracker.pop(key, None)
        log.info("Client removed: %s (%d active)", remote, len(connected_clients))


async def main():
    loop = asyncio.get_running_loop()
    stop = loop.create_future()

    def on_signal():
        if not stop.done():
            log.info("Shutdown signal received")
            stop.set_result(None)

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, on_signal)

    server = await websockets.serve(handle_tts, HOST, PORT)
    log.info("TTS server listening on ws://%s:%d", HOST, PORT)

    await stop

    # Graceful shutdown (#32)
    log.info("Shutting down: closing %d client connections...", len(connected_clients))

    # Close all connected client WebSockets
    close_tasks = []
    for ws in list(connected_clients):
        close_tasks.append(asyncio.create_task(ws.close(1001, "Server shutting down")))

    if close_tasks:
        await asyncio.wait(close_tasks, timeout=SHUTDOWN_TIMEOUT)

    server.close()
    await asyncio.wait_for(server.wait_closed(), timeout=SHUTDOWN_TIMEOUT)

    log.info("Server shut down")


if __name__ == "__main__":
    asyncio.run(main())
