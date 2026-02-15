# AudioFileStream Rewrite Plan for ClawK TTS

## Goal
Replace the current "collect all MP3 → write temp file → AVAudioFile decode → schedule buffer" approach with OpenClaw's proven `AudioFileStream` + `AudioQueue` pattern for true progressive MP3 streaming.

## Why This Matters
Current flow per sentence: `fetch all chunks (~500ms) → write file → decode → schedule → play`
New flow: `first chunk arrives (~30ms) → parse → play starts within ~100ms`

---

## Edge TTS Format (Verified)
- **Codec:** MPEG-2 Layer III
- **Sample rate:** 24,000 Hz
- **Chunk size:** 720 bytes (consistent, 1-2 MP3 frames per chunk)
- **Chunks per sentence:** ~16-31 depending on length
- **END marker:** `b"END"` (bytes) or `"END"` (string)
- **Server:** Python websockets on `ws://127.0.0.1:8766`, handles multiple messages per connection

---

## Architecture: What OpenClaw Does (from ElevenLabsKit)

OpenClaw's `StreamingAudioPlayback` class uses pure AudioToolbox C APIs:

### Core Components
1. **`AudioFileStreamOpen`** — Opens a progressive MP3 parser (hint: `kAudioFileMP3Type`)
2. **`AudioFileStreamParseBytes`** — Feeds raw MP3 bytes as they arrive from the network
3. **Property callback** — Fires when format (`AudioStreamBasicDescription`) is detected from MP3 headers
4. **Packets callback** — Fires when decoded audio packets are available → fills `AudioQueueBuffer`s
5. **`AudioQueue`** — Hardware-backed audio playback with rotating buffer pool
6. **3 rotating `AudioQueueBuffer`s** (32KB each) — When one finishes playing, it's recycled via output callback

### Flow
```
WebSocket chunk arrives (720 bytes MP3)
  → AudioFileStreamParseBytes(stream, bytes, count, flags)
    → propertyListenerProc: format detected → create AudioQueue + allocate 3 buffers
    → packetsProc: decoded audio packets received
      → Copy packets into current AudioQueueBuffer
      → If buffer full → AudioQueueEnqueueBuffer → AudioQueueStart (first time)
      → Grab next available buffer (semaphore-gated)
WebSocket "END" marker
  → Flush remaining data in current buffer
  → AudioQueueStop(queue, false)  // false = drain remaining buffers
  → isRunning callback fires when queue stops → signal completion
```

### Key Design Choices
- **3 buffers + semaphore**: Output callback returns used buffer to pool + signals semaphore. If all 3 are in-flight, the parse thread blocks on the semaphore (backpressure).
- **No temp files**: Everything is in-memory.
- **No AVFoundation**: Pure AudioToolbox (C API). Reliable, low-level, battle-tested.
- **Single parse thread**: All `AudioFileStreamParseBytes` calls happen on a dedicated `DispatchQueue`.

---

## Plan for ClawK

### New File: `AudioStreamPlayer.swift`
A self-contained class replacing the decode/playback portion of `TalkStreamingTTSClient`.

```swift
import AudioToolbox
import Foundation
import os

/// Progressive MP3 streaming player using AudioFileStream + AudioQueue.
/// Feed MP3 chunks via `append(_:)`, call `finishInput()` when done.
/// Plays audio as chunks arrive — no buffering of the full file.
final class AudioStreamPlayer: @unchecked Sendable {
    // Configuration
    static let bufferCount = 3
    static let bufferSize = 32 * 1024  // 32KB per buffer

    // AudioToolbox state
    private var audioFileStream: AudioFileStreamID?
    private var audioQueue: AudioQueueRef?
    private var audioFormat: AudioStreamBasicDescription?
    
    // Buffer pool
    private let bufferLock = NSLock()
    private let bufferSemaphore = DispatchSemaphore(value: bufferCount)
    private var availableBuffers: [AudioQueueBufferRef] = []
    private var currentBuffer: AudioQueueBufferRef?
    private var currentBufferSize: Int = 0
    private var currentPacketDescs: [AudioStreamPacketDescription] = []
    
    // State
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?  // true = finished ok
    private var finished = false
    private var inputFinished = false
    private var startRequested = false
    private var sampleRate: Double = 0
    
    // Threading
    private let parseQueue = DispatchQueue(label: "clawk.tts.parse")
    private let logger = Logger(subsystem: "ai.openclaw.clawk", category: "audio-stream")
    
    // ... implementation follows OpenClaw's pattern exactly
}
```

### Key Differences from OpenClaw
1. **No `AudioToolboxClient` abstraction** — We call AudioToolbox directly (OpenClaw has a testability shim; we don't need it)
2. **Simpler lifecycle** — OpenClaw manages interrupt/resume; we just play and signal done
3. **Same core algorithm** — `AudioFileStream` → property/packets callbacks → `AudioQueue` with 3 rotating buffers

### Modified File: `TalkStreamingTTSClient.swift`

The sentence processing loop changes from:
```
fetchMP3Data(sentence) → decodeMP3Data(data) → scheduleAudioBuffer(buffer)
```
To:
```
let player = AudioStreamPlayer()
ws.send(sentence)
for chunk in ws.receive():
    player.append(chunk)
player.finishInput()
await player.waitForCompletion()
```

Key changes:
- **Remove**: `decodeMP3Data()`, `ensureEngineRunning()`, `scheduleAudioBuffer()`, AVAudioEngine, AVAudioPlayerNode, temp file logic
- **Keep**: WebSocket fetch logic, sentence queue, pre-fetch pipeline, fallback speaker
- **Add**: `AudioStreamPlayer` instantiation per sentence (lightweight — OpenClaw creates one per playback session)

### Per-Sentence vs. Per-Response Player
- OpenClaw creates ONE player per full response (they don't split into sentences)
- We create ONE player per streaming session (covers all sentences)
- Each sentence's chunks are fed into the SAME `AudioStreamPlayer`
- Between sentences: no gap because the AudioQueue stays running

Wait — actually this is the key insight. We should keep ONE `AudioStreamPlayer` alive for the entire response, feeding it chunks from ALL sentences sequentially. The AudioQueue handles gapless playback naturally.

### Revised Flow
```
1. User speaks → STT → transcript
2. Send to gateway → response starts streaming
3. Create ONE AudioStreamPlayer for this response
4. As sentences are extracted:
   a. Send sentence to TTS WebSocket
   b. Feed MP3 chunks into the AudioStreamPlayer as they arrive
   c. Audio starts playing after first ~2-3 chunks (~2KB)
5. After last sentence's END marker → player.finishInput()
6. AudioQueue drains remaining buffers → completion
```

### Pre-fetch Optimization (Keep)
The pre-fetch pipeline still helps: while sentence N's chunks are being fed to the player, we can start fetching sentence N+1's chunks. The moment N finishes, N+1's chunks are ready to feed immediately.

---

## Implementation Steps

### Step 1: Create `AudioStreamPlayer.swift` (~200 lines)
- `AudioFileStreamOpen` with `kAudioFileMP3Type`
- Property listener: detect format → create `AudioQueue` → allocate 3 buffers
- Packets callback: fill buffers → enqueue → start queue on first enqueue
- `append(_: Data)` — feeds data on parse queue via `AudioFileStreamParseBytes`
- `finishInput()` — flushes current buffer, stops queue (drain mode)
- `waitForCompletion() async → Bool` — continuation-based
- `stop()` — immediate stop for interruption
- `isRunning` callback → signal completion when queue drains
- Teardown: dispose queue, close stream, release buffers

### Step 2: Modify `TalkStreamingTTSClient.swift`
- Remove AVAudioEngine, AVAudioPlayerNode, temp file decode
- Create one `AudioStreamPlayer` in `prepareForStreaming()`
- In queue loop: for each sentence, open WebSocket, send text, feed chunks directly to player
- Keep pre-fetch pipeline (fetch next sentence concurrently)
- `finalizeQueue()` → `player.finishInput()`
- `stopPlayback()` → `player.stop()`

### Step 3: Verify build & test
- `xcodegen generate && xcodebuild -scheme ClawK -configuration Debug build`
- Test with real speech

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| AudioToolbox C callbacks are tricky | Follow OpenClaw's exact pattern — it's battle-tested |
| Edge TTS MP3 format quirks | Verified: standard MPEG-2 Layer III at 24kHz, clean frames |
| Thread safety with callbacks | NSLock + DispatchSemaphore (same as OpenClaw) |
| Memory management with `Unmanaged` | Follow OpenClaw's `passUnretained` pattern exactly |
| AudioQueue might not handle MPEG-2 | AudioFileStream with `kAudioFileMP3Type` handles MPEG-1/2/2.5 Layer III |

---

## Expected Performance
- **First audio:** ~100-150ms after first WebSocket chunk (vs. ~500-1500ms currently)
- **Inter-sentence gap:** Near zero (same AudioQueue, continuous feed)
- **Memory:** ~96KB for 3 rotating buffers (vs. full MP3 file + decoded PCM in memory)
- **CPU:** Lower (no file I/O, no AVAudioFile parsing overhead)

---

## Files
- **New:** `ClawK/Services/Talk/AudioStreamPlayer.swift`
- **Modified:** `ClawK/Services/Talk/TalkStreamingTTSClient.swift`
- **Unchanged:** Everything else (GatewayWebSocket, TalkConversationManager, TTS server, etc.)
