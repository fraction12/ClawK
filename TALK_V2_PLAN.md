# ClawK Talk Mode v2.0 — Implementation Plan

> Generated: 2026-02-08 | Based on full codebase analysis + OpenClaw reference comparison

---

## Feature 1: Mid-Sentence Interrupts via Transcript Echo Detection

**Complexity:** High  
**Estimated Claude Code time:** 45–60 minutes  
**Files to create:**
- `Services/Talk/TalkEchoDetector.swift` — echo detection logic

**Files to modify:**
- `TalkConversationManager.swift` — remove `guard !ttsClient.isPlaying` from audio level forwarding, keep STT running during speaking, wire echo detector
- `TalkSpeechRecognizer.swift` — add ability to run during playback (new mode flag)
- `TalkAudioEngine.swift` — support simultaneous monitoring + recognition
- `TalkVoiceActivityDetector.swift` — integrate with echo detector instead of raw RMS
- `AudioStreamPlayer.swift` — add `currentTimeSeconds()` via `AudioQueueGetCurrentTime` for interrupt timestamp
- `TalkStreamingTTSClient.swift` — expose `currentlySpokenText` for echo comparison

**Dependencies:** None (foundational)

**Implementation steps:**

1. **Create `TalkEchoDetector`** — standalone class that holds `lastSpokenText` and provides:
   ```swift
   func isLikelyEcho(_ transcript: String) -> Bool {
       guard let spoken = lastSpokenText?.lowercased() else { return false }
       let incoming = transcript.lowercased()
       // Check if incoming words are a substring of what's being spoken
       let spokenWords = Set(spoken.split(separator: " ").map(String.init))
       let incomingWords = incoming.split(separator: " ").map(String.init)
       let overlap = incomingWords.filter { spokenWords.contains($0) }.count
       return Double(overlap) / Double(max(incomingWords.count, 1)) > 0.6
   }
   ```

2. **Remove audio suppression** — In `setupAudioLevelForwarding()`, remove the `guard !self.ttsClient.isPlaying` line. Instead feed ALL audio levels through but gate interrupt logic on echo detection.

3. **Keep STT running during speaking** — In `transition(to: .speaking)`, don't stop speech recognizer. Instead, set a flag `isInSpeakingMode = true` on the recognizer so it knows to filter through echo detection.

4. **Wire interrupt logic** — In `handleRecognition` (new method), during `.speaking` state:
   - Check `echoDetector.isLikelyEcho(transcript)` → ignore if echo
   - Check confidence > 0.6 (from `SFSpeechRecognitionResult.bestTranscription.segments`)
   - Check recent speech energy (`voiceActivityDetector.recentRMS > minSpeechRMS`)
   - If all pass → interrupt

5. **Add interrupt timestamp** — Add to `AudioStreamPlayer`:
   ```swift
   func currentTimeSeconds() -> Double? {
       guard let queue = audioQueue, sampleRate > 0 else { return nil }
       var timestamp = AudioTimeStamp()
       var size = UInt32(MemoryLayout<AudioTimeStamp>.size)
       let status = AudioQueueGetProperty(queue, kAudioQueueProperty_CurrentTime, &timestamp, &size)
       guard status == noErr else { return nil }
       return timestamp.mSampleTime / sampleRate
   }
   ```

6. **Feed interrupt context to gateway** — Store `lastInterruptedAtSeconds` and include in next `sendMessage()` prompt: `"[The user interrupted your previous response at approximately X seconds in.]"`

7. **Update `TalkStreamingTTSClient`** — Track which sentence is currently playing and expose `currentlySpokenText` for echo comparison. Update as each sentence starts playback.

**Testing approach:**
- Play TTS while speaking into mic — verify echo doesn't trigger interrupt
- Speak clearly different words during TTS — verify interrupt triggers
- Verify interrupt timestamp is reasonable
- Test with low/high ambient noise

**Risk areas:**
- Echo detection false positives/negatives — needs tuning
- STT recognizing TTS output through speakers (need good echo detection)
- AudioQueueGetCurrentTime accuracy during streaming
- Potential for mic picking up speaker output if no headphones

---

## Feature 2: Adaptive Silence Detection

**Complexity:** Medium  
**Estimated Claude Code time:** 25–30 minutes  
**Files to create:** None

**Files to modify:**
- `TalkVoiceActivityDetector.swift` — add noise floor tracking, adaptive thresholds
- `TalkSpeechRecognizer.swift` — reduce default silence threshold, integrate energy-based confirmation
- `TalkConversationManager.swift` — update default `silenceThreshold` from 1.5 to 0.7

**Dependencies:** None

**Implementation steps:**

1. **Add noise floor tracking to `TalkVoiceActivityDetector`**:
   ```swift
   private var noiseFloorRMS: Float = 1e-4
   private let noiseFloorAlpha: Float = 0.02 // slow adaptation
   private let speechBoostFactor: Float = 6.0
   private let minSpeechRMS: Float = 0.001
   
   func feedAudioLevel(_ rms: Float) {
       // Update noise floor (slow moving average, only when no speech)
       if consecutiveFramesAboveThreshold == 0 {
           noiseFloorRMS = max(1e-7, noiseFloorRMS + (rms - noiseFloorRMS) * noiseFloorAlpha)
       }
       let adaptiveThreshold = max(minSpeechRMS, noiseFloorRMS * speechBoostFactor)
       // Use adaptiveThreshold instead of fixed speechThreshold
       ...
   }
   ```

2. **Reduce silence window** — Change default from 1.5s to 0.7s. Keep configurable via settings but update the slider range to 0.3–2.0s.

3. **Add energy-based silence confirmation** — In `TalkSpeechRecognizer`, before firing `onSilenceDetected`, check that recent audio energy has actually dropped below the noise floor (not just that no new transcript arrived). Request last N audio levels from the audio engine.

4. **Progressive threshold** — Start first turn at 1.0s, reduce to 0.7s after first successful exchange (user has established speaking pattern).

**Testing approach:**
- Test in quiet room vs noisy environment — verify noise floor adapts
- Measure end-of-utterance to thinking transition latency
- Verify no premature cutoffs during pauses within sentences

**Risk areas:**
- Too aggressive threshold cutting off mid-sentence pauses
- Noise floor adaptation too slow in changing environments

---

## Feature 3: Proper Swift Actor Isolation

**Complexity:** High  
**Estimated Claude Code time:** 60–90 minutes  
**Files to create:**
- `Services/Talk/TalkModeController.swift` — @MainActor @Observable UI-facing controller (like OpenClaw's pattern)

**Files to modify:**
- `TalkConversationManager.swift` — convert from `@MainActor class` to `actor`, move UI properties to controller
- `TalkStreamingTTSClient.swift` — review isolation, potentially convert to actor
- `GatewayWebSocket.swift` — ensure callback-to-actor bridging is correct
- `AudioStreamPlayer.swift` — verify C callback safety with actor model (already uses locks — should be fine)
- `TalkView.swift` — observe `TalkModeController` instead of `TalkConversationManager` directly
- `TalkOverlayPanel.swift` — same
- `TalkOverlayContentView` — same

**Dependencies:** Should be done before Features 1, 4, 5 to establish correct foundation. However, can be done after if careful.

**Implementation steps:**

1. **Create `TalkModeController`** — @MainActor @Observable class that holds all UI-facing state:
   ```swift
   @MainActor @Observable
   final class TalkModeController {
       static let shared = TalkModeController()
       var state: TalkConversationState = .idle
       var userTranscript: String = ""
       var claudeResponse: String = ""
       var errorMessage: String?
       var messages: [TalkChatMessage] = []
       var audioLevel: Float = 0
       var recentLevels: [Float] = Array(repeating: 0, count: 32)
       var isConnected: Bool = false
       var connectionState: GatewayWebSocket.ConnectionState = .disconnected
       
       func updatePhase(_ phase: TalkConversationState) { state = phase }
       func updateLevel(_ level: Float) { audioLevel = level }
       // ... other update methods
   }
   ```

2. **Convert `TalkConversationManager` to `actor`**:
   - Remove `@MainActor` annotation, add `actor` keyword
   - Remove `@Published` from all properties
   - Add explicit `await MainActor.run { TalkModeController.shared.updateX() }` calls where needed
   - Network calls, TTS processing, STT management stay on actor's executor (off main thread)

3. **Update views** — Replace `@ObservedObject var conversationManager` with `TalkModeController.shared` observation.

4. **Review `AudioStreamPlayer`** — Already uses `@unchecked Sendable` with explicit locks. C callbacks use `Unmanaged` pointers with teardown checks. This should work fine with actor isolation. No changes needed.

5. **Review `GatewayWebSocket`** — Currently `@MainActor`. Could stay `@MainActor` since it's relatively lightweight, or convert to actor. The callback closures (`onResponseChunk`) need to bridge to the `TalkConversationManager` actor via `Task { await manager.handleChunk() }`.

6. **Review `TalkStreamingTTSClient`** — Currently `@MainActor`. The WebSocket operations and audio processing could benefit from being off main thread. Consider making it an actor, keeping only `isPlaying` exposed via the controller.

**Testing approach:**
- Verify no data races with Thread Sanitizer enabled
- Verify UI updates still happen promptly
- Full conversation cycle test
- Verify no deadlocks in audio callback → actor → MainActor chain

**Risk areas:**
- Actor reentrancy causing unexpected state during async suspension points
- C callbacks in AudioStreamPlayer cannot be `async` — need careful bridging
- `DispatchSemaphore.wait()` in AudioStreamPlayer blocks threads — must NEVER be called from actor executor
- Migration scope creep — many interdependent files

---

## Feature 4: Pause/Resume Support

**Complexity:** Low–Medium  
**Estimated Claude Code time:** 20–30 minutes  
**Files to create:** None

**Files to modify:**
- `TalkModels.swift` — add `.paused` case to `TalkConversationState`
- `TalkConversationManager.swift` — add `pause()`/`resume()` methods, handle `.paused` state
- `AudioStreamPlayer.swift` — add `pause()`/`resume()` using `AudioQueuePause`/`AudioQueueStart`
- `TalkStreamingTTSClient.swift` — add `pausePlayback()`/`resumePlayback()`
- `TalkView.swift` — update button for pause state
- `TalkOverlayPanel.swift` — update overlay for pause state
- `TalkStateIndicator.swift` — add paused visual

**Dependencies:** None

**Implementation steps:**

1. **Add `.paused` to state enum**:
   ```swift
   enum TalkConversationState: String, CaseIterable, Sendable {
       case idle, listening, thinking, speaking, paused
   }
   ```

2. **Add `AudioQueuePause`/resume to `AudioStreamPlayer`**:
   ```swift
   func pause() {
       guard let queue = audioQueue, queueStarted else { return }
       AudioQueuePause(queue)
   }
   func resume() {
       guard let queue = audioQueue, queueStarted else { return }
       AudioQueueStart(queue, nil)
   }
   ```

3. **Add pause/resume to `TalkStreamingTTSClient`**:
   ```swift
   func pausePlayback() {
       streamPlayer?.pause()
       isPlaying = false
   }
   func resumePlayback() {
       streamPlayer?.resume()
       isPlaying = true
   }
   ```

4. **Add pause/resume to `TalkConversationManager`**:
   ```swift
   func togglePause() {
       if state == .paused {
           resume()
       } else if state == .speaking || state == .listening {
           pause()
       }
   }
   
   private func pause() {
       let previousState = state
       // Store previous state for resume
       pausedFromState = previousState
       if previousState == .speaking {
           ttsClient.pausePlayback()
       }
       speechRecognizer.stopRecognition()
       audioEngine.stop()
       voiceActivityDetector.stopMonitoring()
       transition(to: .paused)
   }
   
   private func resume() {
       guard state == .paused else { return }
       if pausedFromState == .speaking {
           ttsClient.resumePlayback()
           transition(to: .speaking)
       } else {
           startListening()
       }
   }
   ```

5. **Update UI** — In control button, map `.paused` to a "Resume" button with play icon. In `TalkStateIndicator`, show a paused orb (dimmed, static). In overlay, single-click toggles pause.

**Testing approach:**
- Pause during speaking → verify audio stops, resumes from same position
- Pause during listening → verify mic stops, resumes listening
- Rapid pause/unpause toggle

**Risk areas:**
- AudioQueuePause/Start may not work perfectly with streaming (untested edge case)
- Resuming TTS mid-sentence might have audio glitches
- State machine complexity increase

---

## Feature 5: Voice Directives

**Complexity:** Medium  
**Estimated Claude Code time:** 30–40 minutes  
**Files to create:**
- `Services/Talk/TalkDirectiveParser.swift` — parse directives from AI response text

**Files to modify:**
- `tts_server.py` — accept `voice`, `rate`, `pitch`, `volume` parameters in JSON messages
- `TalkStreamingTTSClient.swift` — pass voice parameters when sending to TTS server
- `TalkConversationManager.swift` — parse directives from response, strip from display text

**Dependencies:** None

**Implementation steps:**

1. **Create `TalkDirectiveParser`**:
   ```swift
   struct TalkDirective {
       var voice: String?   // Edge TTS voice name
       var rate: String?    // e.g., "+20%", "-10%"
       var pitch: String?   // e.g., "+5Hz", "-2Hz"
       var volume: String?  // e.g., "+10%"
   }
   
   struct TalkDirectiveParser {
       /// Parse `[voice: key=value, ...]` from text
       static func parse(_ text: String) -> (directive: TalkDirective?, stripped: String) {
           let pattern = /\[voice:\s*([^\]]+)\]/
           guard let match = text.firstMatch(of: pattern) else {
               return (nil, text)
           }
           let params = String(match.1)
           var directive = TalkDirective()
           for param in params.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
               let kv = param.split(separator: "=", maxSplits: 1)
               guard kv.count == 2 else { continue }
               let key = kv[0].trimmingCharacters(in: .whitespaces).lowercased()
               let value = kv[1].trimmingCharacters(in: .whitespaces)
               switch key {
               case "voice": directive.voice = value
               case "rate", "speed": directive.rate = value
               case "pitch": directive.pitch = value
               case "volume": directive.volume = value
               default: break
               }
           }
           let stripped = text.replacing(pattern, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
           return (directive, stripped)
       }
   }
   ```

2. **Update `tts_server.py`** — Already accepts JSON with `text` and `voice` fields. Add `rate`, `pitch`, `volume`:
   ```python
   rate = msg.get("rate", "+0%")
   pitch = msg.get("pitch", "+0Hz")
   volume = msg.get("volume", "+0%")
   communicate = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch, volume=volume)
   ```

3. **Update `TalkStreamingTTSClient`** — Change `enqueueSentence` to accept optional directive. When streaming to TTS server, send JSON instead of plain text:
   ```swift
   func enqueueSentence(_ sentence: String, directive: TalkDirective? = nil) {
       // ... existing logic, but store directive alongside sentence
   }
   
   // In streamSentenceAttempt, send JSON:
   let payload: [String: Any] = [
       "text": text,
       "voice": directive?.voice ?? "en-GB-RyanNeural",
       "rate": directive?.rate ?? "+0%",
       "pitch": directive?.pitch ?? "+0Hz",
       "volume": directive?.volume ?? "+0%"
   ]
   let jsonData = try JSONSerialization.data(withJSONObject: payload)
   try await ws.send(.data(jsonData))
   ```

4. **Update `TalkConversationManager`** — In `handleResponseChunk`, parse directives from the response and strip them from display text. Pass directive to TTS client.

5. **Update system prompt** — Add to the instruction in `sendMessage()`: `"You may optionally include voice directives like [voice: speed=1.2, pitch=+5Hz] at the start of your response to control voice parameters."`

**Testing approach:**
- Send message asking AI to speak faster → verify rate change
- Test with invalid directives → verify graceful fallback
- Verify directive text is stripped from displayed response

**Risk areas:**
- AI may not reliably produce directives in correct format
- Edge TTS parameter ranges differ from what AI might suggest
- Directive parsing regex edge cases

---

## Feature 6: Animated Orb Overlay (OpenClaw-style)

**Complexity:** Medium–High  
**Estimated Claude Code time:** 45–60 minutes  
**Files to create:**
- `Views/Talk/TalkOrbView.swift` — animated orb with wave rings and orbit arcs
- `Views/Talk/TalkOrbOverlayPanel.swift` — borderless NSPanel for orb display
- `Views/Talk/TalkOrbInteractionView.swift` — NSViewRepresentable for click/drag/double-click

**Files to modify:**
- `ClawKApp.swift` — add toggle between HUD panel and orb overlay
- `TalkConversationManager.swift` — expose audio level for orb animation

**Dependencies:** Feature 4 (pause/resume for single-click behavior)

**Implementation steps:**

1. **Create `TalkOrbView`** — Direct port of OpenClaw's orb:
   ```swift
   struct TalkOrbView: View {
       let phase: TalkConversationState
       let level: Double
       let accent: Color
       let isPaused: Bool
       
       var body: some View {
           if isPaused {
               Circle().fill(orbGradient)
                   .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                   .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
           } else {
               TimelineView(.animation) { context in
                   let t = context.date.timeIntervalSinceReferenceDate
                   let listenScale = phase == .listening ? (1 + CGFloat(level) * 0.12) : 1
                   let pulse = phase == .speaking ? (1 + 0.06 * sin(t * 6)) : 1
                   ZStack {
                       Circle().fill(orbGradient)
                           .overlay(Circle().stroke(Color.white.opacity(0.45), lineWidth: 1))
                           .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
                           .scaleEffect(pulse * listenScale)
                       TalkWaveRings(phase: phase, level: level, time: t, accent: accent)
                       if phase == .thinking {
                           TalkOrbitArcs(time: t)
                       }
                   }
               }
           }
       }
   }
   ```

2. **Create wave rings and orbit arcs** — Port from OpenClaw's `TalkWaveRings` and `TalkOrbitArcs` (as shown in reference code).

3. **Create `TalkOrbInteractionView`** — NSViewRepresentable wrapping an NSView that handles:
   - Single click → toggle pause (Feature 4)
   - Double click → stop speaking / end conversation
   - Drag → move window (`window?.performDrag(with:)`)
   - Hover → show X close button

4. **Create `TalkOrbOverlayPanel`** — Borderless, transparent NSPanel:
   ```swift
   class TalkOrbOverlayPanel: NSPanel {
       init() {
           super.init(contentRect: NSRect(x: 0, y: 0, width: 120, height: 120),
                      styleMask: [.borderless, .nonactivatingPanel],
                      backing: .buffered, defer: false)
           isFloatingPanel = true
           level = .floating
           isOpaque = false
           backgroundColor = .clear
           hasShadow = false
           isMovableByWindowBackground = true
           hidesOnDeactivate = false
           // Position top-right of screen
           if let screen = NSScreen.main {
               let x = screen.visibleFrame.maxX - 130
               let y = screen.visibleFrame.maxY - 130
               setFrameOrigin(NSPoint(x: x, y: y))
           }
       }
   }
   ```

5. **Add setting to choose overlay style** — "Compact Orb" vs "Full Panel" in settings. Wire Option+Space to show the selected style.

6. **Wire audio level** — Forward `TalkAudioEngine.audioLevel` to the orb's `level` parameter for responsive animation during listening.

**Testing approach:**
- Verify orb animates correctly for each phase
- Test drag to reposition
- Test single-click pause, double-click stop
- Verify hover shows X button
- Test with different accent colors

**Risk areas:**
- SwiftUI `TimelineView(.animation)` performance (continuous redraw)
- Window dragging interaction with click detection
- Borderless panel focus/activation behavior

---

## Feature 7: Production-Quality UI Polish

**Complexity:** Medium  
**Estimated Claude Code time:** 40–50 minutes  
**Files to modify:**
- `TalkView.swift` — accessibility, keyboard shortcuts, virtualized list, error states
- `TalkOverlayPanel.swift` / `TalkOverlayContentView` — accessibility, animations
- `TalkStateIndicator.swift` — polish animations, accessibility
- `TalkWaveformView.swift` — optimize rendering
- `TalkControlButton` — keyboard shortcut support
- `TalkModels.swift` — add `.paused` display name and icon

**Dependencies:** Features 4, 6 (for complete state coverage)

**Implementation steps:**

1. **Accessibility** — Add labels to all interactive elements:
   ```swift
   TalkControlButton(state: state, action: action)
       .accessibilityLabel(state == .idle ? "Start voice conversation" : "Stop voice conversation")
       .accessibilityHint("Double tap to toggle voice input")
   ```
   Add VoiceOver announcements for state changes via `AccessibilityNotification.Announcement`.

2. **Keyboard shortcuts**:
   - `Space` or `Return` to toggle listening (when Talk view is focused)
   - `Escape` to stop/cancel
   - `P` to pause/resume
   - `Cmd+K` to clear history
   Add via `.keyboardShortcut()` modifiers.

3. **Error states** — Create a `TalkErrorBanner` view with:
   - Retry button for connection errors
   - Dismiss button
   - Auto-dismiss after 10s for transient errors
   - Different styling for warning vs error

4. **Animations** — Add transitions to state changes:
   ```swift
   .animation(.spring(response: 0.3), value: conversationManager.state)
   .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
   ```

5. **Virtualized conversation list** — Use `LazyVStack` inside `ScrollViewReader` with auto-scroll to bottom:
   ```swift
   ScrollViewReader { proxy in
       LazyVStack(spacing: Spacing.md) {
           ForEach(conversationManager.messages) { message in
               TalkMessageBubble(message: message).id(message.id)
           }
       }
       .onChange(of: conversationManager.messages.count) { _, _ in
           if let last = conversationManager.messages.last {
               proxy.scrollTo(last.id, anchor: .bottom)
           }
       }
   }
   ```

6. **Loading/progress indicators**:
   - Thinking state: show elapsed time counter
   - Connecting: show connection progress
   - TTS server starting: show setup progress

7. **Settings validation** — Validate silence threshold range (0.3–3.0s), show warning for extreme values. Validate TTS server URL format.

8. **Dark mode** — Verify all custom colors work in both modes. The design system (`Color.Surface.primary`, `Color.Semantic.*`) should handle this, but verify edge cases.

**Testing approach:**
- VoiceOver testing — navigate entire Talk UI with screen reader
- Keyboard-only navigation test
- Window resize from minimum to maximum
- Test with 100+ messages for scroll performance
- Light and dark mode visual check

**Risk areas:**
- `LazyVStack` with `ScrollViewReader` can have scroll positioning bugs
- Accessibility announcements timing with state changes
- Animation performance with continuous waveform updates

---

## Implementation Order

```
Phase 1 (Foundation):     Feature 2 (Adaptive Silence)     [25 min]
                          Feature 4 (Pause/Resume)          [25 min]
                          ─── Can be parallelized ───

Phase 2 (Core):           Feature 1 (Mid-Sentence Interrupts) [55 min]
                          Feature 5 (Voice Directives)         [35 min]
                          ─── Can be parallelized ───

Phase 3 (UI):             Feature 6 (Animated Orb)          [50 min]
                          Feature 7 (UI Polish)              [45 min]
                          ─── Can be parallelized ───

Phase 4 (Architecture):   Feature 3 (Actor Isolation)       [75 min]
                          ─── Must be solo, touches everything ───
```

**Dependency graph:**
```
Feature 2 ──┐
             ├──→ Feature 1 (uses adaptive thresholds)
Feature 4 ──┤
             ├──→ Feature 6 (orb needs pause gesture)
             └──→ Feature 7 (needs all states defined)
Feature 5 ──────→ standalone
Feature 3 ──────→ do last (refactors everything)
```

**Estimated total time:** ~5–6 hours of Claude Code execution

---

## Claude Code Execution Strategy

### Agent 1: Silence + Pause (Phase 1)
**Prompt scope:** Features 2 + 4 combined  
**Token budget:** ~80K context  
**Rationale:** Both are relatively small, modify overlapping files, low risk. Good warm-up.

### Agent 2: Mid-Sentence Interrupts (Phase 2a)
**Prompt scope:** Feature 1 only  
**Token budget:** ~100K context  
**Rationale:** Most complex feature, needs full focus. Touches audio pipeline deeply. Needs all source files loaded for context.

### Agent 3: Voice Directives (Phase 2b)  
**Prompt scope:** Feature 5 only  
**Token budget:** ~60K context  
**Rationale:** Self-contained across Swift + Python. Can run in parallel with Agent 2.

### Agent 4: Orb + Polish (Phase 3)
**Prompt scope:** Features 6 + 7 combined  
**Token budget:** ~90K context  
**Rationale:** Both are UI work, related files. The orb is mostly new code (less merge risk). Polish touches existing views.

### Agent 5: Actor Isolation (Phase 4)
**Prompt scope:** Feature 3 only  
**Token budget:** ~120K context  
**Rationale:** Refactors the entire codebase. Must run last after all other features are stable. Largest context needed (all files). Highest risk — may need iteration.

### Parallelization
- **Round 1:** Agent 1 (Features 2+4)
- **Round 2:** Agent 2 (Feature 1) ‖ Agent 3 (Feature 5) — parallel
- **Round 3:** Agent 4 (Features 6+7)
- **Round 4:** Agent 5 (Feature 3) — solo, after everything else

### Key instructions for each agent
- Always include the full file path in the prompt
- Load the comparison analysis doc for reference patterns
- Specify "preserve existing bug fix comments (e.g., `// Bug 12 fix:`, `// #14:`)"
- Require compilation check after each feature
- Request the agent run `swift build` or Xcode build equivalent to verify
