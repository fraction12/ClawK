# ClawK Update Plan: v1.0 → v1.1 (OpenClaw 2026.2.3 → 2026.2.13)

**Date:** 2026-02-15  
**Status:** Ready to implement  
**Estimated effort:** 2-3 hours

---

## 1. Root Cause Analysis

### Why ClawK shows "Disconnected"

**Primary root cause: `SessionInfo.totalTokens` is declared as non-optional `Int`, but the OpenClaw 2026.2.13 API now omits `totalTokens` from sessions without fresh token snapshot data.**

The failure chain:
1. `refresh()` calls `fetchSessions()` → calls `/tools/invoke` with `sessions_list`
2. API returns HTTP 200 with 27 sessions — **3 of which are missing `totalTokens`**:
   - `agent:main:subagent:*` (no totalTokens, no contextTokens)
   - `agent:main:imessage:dm:+919833719955` (no totalTokens, no contextTokens)
   - `agent:main:cron:2104040d-*` (no totalTokens, has contextTokens)
3. `JSONDecoder` tries to decode `SessionInfo` which has `let totalTokens: Int` (non-optional)
4. Decoder throws `keyNotFound` error because `totalTokens` is missing from some sessions
5. `fetchSessions()` throws `GatewayError.decodingError`
6. `refresh()` catches this → sets `isConnected = false`
7. UI shows "Disconnected"

**What changed in OpenClaw:** Changelog entry from 2026.2.13:
> Status/Sessions: stop clamping derived `totalTokens` to context-window size, keep prompt-token snapshots wired through session accounting, and surface context usage as unknown when fresh snapshot data is missing to avoid false 100% reports. (#15114)

Previously, `totalTokens` was always present (even if 0 or clamped). Now it's omitted when unknown.

### Secondary Issues Discovered

| # | Issue | Severity | Tool | HTTP Status |
|---|-------|----------|------|-------------|
| 1 | `totalTokens` non-optional decode failure | **CRITICAL** | sessions_list | 200 (decode fails) |
| 2 | `exec` tool blocked by new security policy | HIGH | exec | 404 |
| 3 | `sessions_send` tool blocked by security policy | HIGH | sessions_send | 404 |
| 4 | `memory_search` response fields don't match model | MEDIUM | memory_search | 200 (content=nil) |
| 5 | New session fields not captured | LOW | sessions_list | 200 |
| 6 | New cron fields not captured | LOW | cron list | 200 |

### Tools Status (Verified via curl)

| Tool | Used By | Status | Notes |
|------|---------|--------|-------|
| `sessions_list` | `fetchSessions()`, `healthCheck()` | ✅ HTTP 200 | Response parseable if model fixed |
| `cron` (action: list) | `fetchCronJobs()` | ✅ HTTP 200 | Works, extra fields ignored |
| `nodes` (action: status) | `fetchNodesStatus()` | ✅ HTTP 200 | Works fine |
| `sessions_history` | `fetchSessionHistory()` | ✅ HTTP 200 | Works fine |
| `memory_search` | `searchMemory()` | ✅ HTTP 200 | Fields mismatch (see #4) |
| `canvas` | All canvas methods | ✅ HTTP 200 | Works fine |
| `exec` | `fetchModels()` | ❌ HTTP 404 | **Blocked by security policy** |
| `sessions_send` | `sendMessage()` | ❌ HTTP 404 | **Blocked by security policy** |
| `sessions_spawn` | Not used | ❌ HTTP 404 | Blocked, not relevant |

---

## 2. All Changes Needed

### Priority 1: CRITICAL — Fix session decoding (restores connection)

**File: `ClawK/Models/SessionInfo.swift`**

```swift
// BEFORE (breaks on missing field):
let totalTokens: Int

// AFTER (tolerates missing field):
let totalTokens: Int?
```

Also update all code that references `.totalTokens` to handle the optional:
- `SessionInfo.contextUsagePercent` — guard against nil
- `AppState.totalTokensUsed` — use `?? 0`
- `AppState.contextWindow(for:)` — use `?? 0`
- `AppState.fetchHeartbeatFromSession()` — use `?? 0`
- `AppState.recordHeartbeatEntry()` — use `?? 0`
- `HeartbeatService.calculateContextPercent()` — use `?? 0`
- Any views that display token counts

Add new optional fields from the API:
```swift
let thinkingLevel: String?       // NEW in 2026.2.13
let transcriptPath: String?      // NEW in 2026.2.13
```

### Priority 2: HIGH — Fix blocked tools

**Option A (Recommended): Gateway config override**

Add to `~/.openclaw/openclaw.json`:
```json
{
  "gateway": {
    "tools": {
      "allow": ["exec", "sessions_send"]
    }
  }
}
```
Then restart gateway: `openclaw gateway restart`

**Option B: Refactor to avoid blocked tools**

For `fetchModels()` — switch from `exec` tool to direct CLI execution (like `fetchGatewayHealth()` already does):
```swift
// BEFORE: Uses exec tool via /tools/invoke (now blocked)
func fetchModels() async throws -> [ModelInfo] {
    let data = try await invokeToolRaw(tool: "exec", args: ["command": "openclaw models list --json"])
    // ...
}

// AFTER: Run CLI directly via Process
func fetchModels() async throws -> [ModelInfo] {
    let result = await Self.runOpenClawCommand(["models", "list", "--json"])
    guard result.exitCode == 0 else { return [] }
    // Parse result.stdout as JSON...
}
```

For `sendMessage()` — this is harder since there's no direct CLI equivalent. Options:
1. Use `gateway.tools.allow` config (Option A) — simplest
2. Use the gateway WebSocket API directly
3. Use `openclaw message send` CLI command via Process

**Recommendation: Use Option A (config override) for `sessions_send`, and Option B (CLI) for `fetchModels()`.**

### Priority 3: MEDIUM — Fix memory search response parsing

**File: `ClawK/Services/GatewayClient.swift`**

The `memory_search` API response fields changed:

```
ClawK expects:           API returns:
─────────────           ─────────────
content: String?    →   snippet: String?    (renamed)
score: Double?      →   score: Double?      (same)
metadata: [S:S]?    →   path: String?       (new structure)
                        startLine: Int?
                        endLine: Int?
                        source: String?
                        citation: String?
```

Update `MemorySearchHit`:
```swift
// BEFORE:
struct MemorySearchHit: Codable {
    let content: String?
    let score: Double?
    let metadata: [String: String]?
}

// AFTER:
struct MemorySearchHit: Codable {
    let path: String?
    let snippet: String?
    let score: Double?
    let startLine: Int?
    let endLine: Int?
    let source: String?
    let citation: String?
    
    // Backward compat — views that use .content
    var content: String? { snippet }
}
```

### Priority 4: LOW — Add new model fields

**File: `ClawK/Models/CronJob.swift`**

Add new fields:
```swift
struct CronJob: Codable, Identifiable {
    // ... existing fields ...
    let description: String?          // NEW
    let deleteAfterRun: Bool?         // NEW
    let delivery: CronDelivery?       // NEW (replaces isolation)
}

struct CronDelivery: Codable {
    let mode: String?
    let channel: String?
    let to: String?
    let bestEffort: Bool?
}

struct CronState: Codable {
    // ... existing fields ...
    let consecutiveErrors: Int?       // NEW
}
```

**File: `ClawK/Models/ModelInfo.swift`**

The `key` → `id` mapping may need review. When fetched via CLI (`openclaw models list --json`), the field might be `key` or `id` depending on the output format. Test this after switching to CLI-based model fetching.

---

## 3. File-by-File Breakdown

### `ClawK/Models/SessionInfo.swift`
- [ ] Change `let totalTokens: Int` → `let totalTokens: Int?`
- [ ] Update `contextUsagePercent` to handle optional: `guard let total = contextTokens, total > 0, let tokens = totalTokens else { return 0 }`
- [ ] Add `let thinkingLevel: String?`
- [ ] Add `let transcriptPath: String?`

### `ClawK/AppState.swift`
- [ ] Update `totalTokensUsed`: `$0 + ($1.totalTokens ?? 0)`
- [ ] Update `contextWindow(for:)` references that use `.totalTokens`
- [ ] Update `fetchHeartbeatFromSession()`: `telegram.totalTokens` → `telegram.totalTokens ?? 0`
- [ ] Update `recordHeartbeatEntry()`: `telegram.totalTokens` → `telegram.totalTokens ?? 0`

### `ClawK/Services/GatewayClient.swift`
- [ ] Refactor `fetchModels()` to use `runOpenClawCommand(["models", "list", "--json"])` instead of exec tool
- [ ] Update `MemorySearchHit` struct to match new API fields
- [ ] Update `searchMemory()` if needed for new response structure
- [ ] Add better error messages for 404 (tool blocked) responses

### `ClawK/Services/HeartbeatService.swift`
- [ ] Update `calculateContextPercent()`: `mostRecent.totalTokens` → `mostRecent.totalTokens ?? 0`
- [ ] Guard `maxTokens > 0 && tokens > 0` → `maxTokens > 0 && (mostRecent.totalTokens ?? 0) > 0`

### `ClawK/Models/CronJob.swift`
- [ ] Add `let description: String?`
- [ ] Add `let deleteAfterRun: Bool?`
- [ ] Add `let delivery: CronDelivery?` struct
- [ ] Add `let consecutiveErrors: Int?` to `CronState`

### `ClawK/Models/ModelInfo.swift`
- [ ] Review `CodingKeys` mapping after switching to CLI-based fetching
- [ ] May need to handle both `key` and `id` field names

### `ClawK/Views/` (any views displaying token counts)
- [ ] Audit all views that display `.totalTokens` — use `?? 0` or show "—" for nil
- [ ] Update any session detail views to show `thinkingLevel` if present

---

## 4. OpenClaw Config Changes

### Required: Allow blocked tools for ClawK

Add to `~/.openclaw/openclaw.json` under the `gateway` key:

```json
{
  "gateway": {
    "tools": {
      "allow": ["sessions_send"]
    }
  }
}
```

Then restart: `openclaw gateway restart`

**Note:** We recommend allowing only `sessions_send` via config and switching `fetchModels()` to CLI execution. This minimizes the security surface area — `exec` is blocked for good reason (arbitrary command execution), while `sessions_send` is a controlled operation.

If you also want `exec` allowed (simpler but less secure):
```json
{
  "gateway": {
    "tools": {
      "allow": ["exec", "sessions_send"]
    }
  }
}
```

---

## 5. Build and Test Instructions

### Step 1: Apply the critical fix (SessionInfo.totalTokens)
```bash
cd ~/Documents/Projects/ClawK
# Make totalTokens optional and update all references
# Build to verify no compile errors
xcodebuild -scheme ClawK -configuration Debug build 2>&1 | tail -5
```

### Step 2: Test connection
1. Run ClawK from Xcode
2. Check the menu bar icon — should show connected status
3. Open the app — sessions list should populate
4. Check Settings → Connection → should show "Connected"

### Step 3: Apply gateway config (for sessions_send)
```bash
# Add tools.allow to openclaw.json
openclaw config set gateway.tools.allow '["sessions_send"]'
openclaw gateway restart
```

### Step 4: Test all features
- [ ] Sessions list loads (verify count matches curl test: 27 sessions)
- [ ] Cron jobs list loads (6 jobs)
- [ ] Models list loads (after CLI refactor)
- [ ] Node status shows (1 node connected)
- [ ] Heartbeat status displays correctly
- [ ] Memory search returns results with snippets
- [ ] Session history loads (click a session)
- [ ] Send message works (after config change)
- [ ] Canvas operations work (snapshot, present, hide)
- [ ] ClawK Status Card shows correct status
- [ ] Context usage percentages display correctly
- [ ] Token counts handle missing values gracefully (show "—" not crash)

### Step 5: Clean build for release
```bash
xcodebuild -scheme ClawK -configuration Release build 2>&1 | tail -10
```

---

## 6. Priority Order (What to Fix First)

### Phase 1: Get it connecting (5 minutes)
1. **`SessionInfo.totalTokens` → make optional** — This alone fixes the "Disconnected" status
2. **Update all `.totalTokens` references** — Compile-time catches from the type change

### Phase 2: Restore blocked features (30 minutes)
3. **Refactor `fetchModels()` to use CLI** — Models tab starts working
4. **Add `gateway.tools.allow` config** — sendMessage starts working
5. **Fix `MemorySearchHit` fields** — Memory search shows content

### Phase 3: Polish (30 minutes)
6. **Add new session/cron fields** — thinkingLevel, delivery, etc.
7. **Improve error handling for 404s** — Better UX for blocked tools
8. **Update version to 1.1.0** — In AboutCard

### Phase 4: Test (30 minutes)
9. **Full integration test** — All features against live gateway
10. **Edge case testing** — Sessions with no tokens, empty models, etc.

---

## Appendix A: Verified API Responses

### sessions_list (HTTP 200) — 3 sessions missing totalTokens
```
✓ totalTokens=present    agent:main:telegram:direct:5170764535
✗ totalTokens=MISSING    agent:main:subagent:a98c7595-*
✓ totalTokens=present    agent:main:main
✗ totalTokens=MISSING    agent:main:imessage:dm:+919833719955
✗ totalTokens=MISSING    agent:main:cron:2104040d-*
(24 more sessions with totalTokens present)
```

### exec (HTTP 404) — BLOCKED
```json
{"ok":false,"error":{"type":"not_found","message":"Tool not available: exec"}}
```

### sessions_send (HTTP 404) — BLOCKED
```json
{"ok":false,"error":{"type":"not_found","message":"Tool not available: sessions_send"}}
```

### memory_search (HTTP 200) — Fields changed
```
ClawK expects: content, score, metadata
API returns:   path, snippet, score, startLine, endLine, source, citation
```

### Working tools: cron list, nodes status, sessions_history, canvas — all HTTP 200

## Appendix B: Relevant Changelog Entries

From OpenClaw 2026.2.13:

1. **Sessions token accounting** (#15114): "stop clamping derived `totalTokens` to context-window size ... surface context usage as unknown when fresh snapshot data is missing" — **THIS BROKE SESSION DECODING**

2. **Security tool blocking** (#15390): "block high-risk tools (`sessions_spawn`, `sessions_send`, `gateway`, `whatsapp_login`) from HTTP `/tools/invoke` by default with `gateway.tools.{allow,deny}` overrides" — **BROKE SEND MESSAGE + EXEC**

3. **Error sanitization** (#13185): "sanitize `/tools/invoke` execution failures while preserving `400` for tool input errors and returning `500` for unexpected runtime failures" — Changed error response format (ClawK handles this OK)
