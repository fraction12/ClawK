# ClawK

macOS SwiftUI menu bar app for monitoring OpenClaw agents. Swift 6, macOS 14.0+, zero external dependencies.

## Commands

```bash
# Generate Xcode project (required after changing project.yml)
make generate-xcodeproj

# Build (Xcode — includes widgets)
make xcode-build

# Build (SwiftPM — no widgets)
make build

# Run
make run

# Clean
make clean

# Install to /Applications
make install
```

## Architecture

```
ClawK/
├── ClawKApp.swift          # Entry point + AppDelegate (both in same file)
├── AppState.swift           # Central @MainActor ObservableObject — all app state
├── MenuBar/                 # NSStatusItem, hover popover, window management
├── Views/                   # SwiftUI views (MissionControl, Memory, Canvas, Settings)
│   ├── Memory/              # Memory browser, vitals, 3D visualization, search
│   └── Components/          # Heartbeat chart, quick stats
├── ViewModels/              # MemoryViewModel (only view model currently)
├── Services/                # Backend: GatewayClient (actor), HeartbeatService, MemoryService, QuotaService
├── Models/                  # Codable data models (sessions, crons, heartbeats, memory, quota)
└── DesignSystem/            # Color/typography/spacing tokens + reusable DS components
```

## Key Patterns

- **No AppDelegate.swift file** — `AppDelegate` is defined inside `ClawKApp.swift`
- **Singletons**: `AppConfiguration.shared`, `GatewayConfig.shared` use `nonisolated(unsafe) static let shared`
- **AppState**: Single instance created by AppDelegate (not a static singleton), injected via `@EnvironmentObject`
- **State in views**: Use `@ObservedObject` with `.shared` singletons, NOT `@StateObject` (which creates new instances)
- **Concurrency**: `@MainActor` on all UI-touching classes. `GatewayClient` is an `actor` for thread-safe HTTP
- **Networking**: `GatewayClient` talks to local OpenClaw gateway REST API. Some endpoints use CLI fallback (`Process` running `openclaw` commands) when HTTP tool invocation is blocked by security policy
- **Design system**: Use `DS*` components (`DSCard`, `DSHeader`, `DSStatusBadge`, etc.) and tokens from `Colors`, `Typography`, `Spacing` — don't hardcode colors/fonts/spacing
- **Error handling**: Each service has its own error enum conforming to `LocalizedError`
- **UserDefaults**: For settings persistence. JSON files for history data

## Gotchas

- `@StateObject` with `.shared` singletons creates separate instances — always use `@ObservedObject`
- Guard continuation resumes with flags to prevent double-resume crashes
- `GatewayClient.runOpenClawCommand()` searches multiple paths for the `openclaw` binary (`/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`)
- The app hides its dock icon (`NSApp.setActivationPolicy(.accessory)`) — all UI is via menu bar
- Build config: `SWIFT_STRICT_CONCURRENCY: minimal` — don't add `Sendable` conformances unless needed
- Tests: 212 XCTests in `ClawKTests/` covering models, services, charts, and decoding. Run with `xcodebuild -scheme ClawK -configuration Debug test`
- project.yml is the source of truth for build config — don't edit .xcodeproj directly

## Build Config

- **XcodeGen**: `project.yml` generates `ClawK.xcodeproj`
- **Bundle ID**: `ai.openclaw.clawk`
- **Swift**: 6 with `SWIFT_STRICT_CONCURRENCY: minimal`
- **Target**: macOS 14.0+
- **Signing**: Automatic, no team required
- **Dependencies**: None (system frameworks only — Foundation, AppKit, SwiftUI)

## Deep Links

The app handles `clawk://` URL scheme: `mission-control`, `memory`, `canvas`, `settings`
