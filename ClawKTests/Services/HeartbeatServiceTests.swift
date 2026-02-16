import XCTest
@testable import ClawK

final class HeartbeatServiceTests: XCTestCase {

    private let service = HeartbeatService.shared

    // MARK: - Helper

    private func makeConfig(enabled: Bool = true, everyMs: Int64 = 1_800_000) -> HeartbeatConfig {
        HeartbeatConfig(enabled: enabled, every: "\(everyMs / 60_000)m", everyMs: everyMs, model: nil, target: nil)
    }

    // MARK: - determineStatus: Priority 1 — API Error

    func testDetermineStatusApiErrorTimeout() {
        let error = GatewayError.timeout
        let result = service.determineStatus(config: nil, lastHeartbeatSent: nil, apiError: error)
        XCTAssertEqual(result.status, .critical)
        XCTAssertEqual(result.statusMessage, "Can't Connect")
        XCTAssertTrue(result.statusSubtitle.contains("timed out"))
        XCTAssertTrue(result.isStale)
    }

    func testDetermineStatusApiErrorGeneric() {
        let error = GatewayError.networkError(NSError(domain: "test", code: -1))
        let result = service.determineStatus(config: nil, lastHeartbeatSent: nil, apiError: error)
        XCTAssertEqual(result.status, .critical)
        XCTAssertEqual(result.statusMessage, "Can't Connect")
        XCTAssertTrue(result.statusSubtitle.contains("Unable to connect"))
    }

    // MARK: - determineStatus: Priority 2 — No Config

    func testDetermineStatusNoConfig() {
        let result = service.determineStatus(config: nil, lastHeartbeatSent: nil, apiError: nil)
        XCTAssertEqual(result.status, .unknown)
        XCTAssertEqual(result.statusMessage, "Not Set Up")
        XCTAssertFalse(result.isStale)
    }

    // MARK: - determineStatus: Priority 3 — Disabled

    func testDetermineStatusDisabled() {
        let config = makeConfig(enabled: false)
        let result = service.determineStatus(config: config, lastHeartbeatSent: nil, apiError: nil)
        XCTAssertEqual(result.status, .unknown)
        XCTAssertEqual(result.statusMessage, "Paused")
    }

    // MARK: - determineStatus: Priority 4 — No Last Heartbeat

    func testDetermineStatusNoLastHeartbeat() {
        let config = makeConfig()
        let result = service.determineStatus(config: config, lastHeartbeatSent: nil, apiError: nil)
        XCTAssertEqual(result.status, .unknown)
        XCTAssertEqual(result.statusMessage, "Starting Up")
        XCTAssertNotNil(result.nextCheck)
    }

    // MARK: - determineStatus: Priority 5 — OK (ratio ≤ 1.5)

    func testDetermineStatusOk() {
        let now = Date()
        let config = makeConfig(everyMs: 1_800_000) // 30 minutes
        let lastSent = now.addingTimeInterval(-1200) // 20 minutes ago → ratio ~0.67
        let result = service.determineStatus(config: config, lastHeartbeatSent: lastSent, apiError: nil, now: now)
        XCTAssertEqual(result.status, .ok)
        XCTAssertEqual(result.statusMessage, "Running Fine")
        XCTAssertFalse(result.isStale)
    }

    // MARK: - determineStatus: Priority 6 — Alert (1.5 < ratio ≤ 2.0)

    func testDetermineStatusAlert() {
        let now = Date()
        let config = makeConfig(everyMs: 1_800_000) // 30 minutes = 1800s
        let lastSent = now.addingTimeInterval(-3000) // 50 minutes ago → ratio ~1.67
        let result = service.determineStatus(config: config, lastHeartbeatSent: lastSent, apiError: nil, now: now)
        XCTAssertEqual(result.status, .alert)
        XCTAssertEqual(result.statusMessage, "Running Late")
        XCTAssertTrue(result.isStale)
    }

    // MARK: - determineStatus: Priority 7 — Critical (ratio > 2.0)

    func testDetermineStatusCritical() {
        let now = Date()
        let config = makeConfig(everyMs: 1_800_000) // 30 minutes = 1800s
        let lastSent = now.addingTimeInterval(-4000) // ~67 minutes ago → ratio ~2.22
        let result = service.determineStatus(config: config, lastHeartbeatSent: lastSent, apiError: nil, now: now)
        XCTAssertEqual(result.status, .critical)
        XCTAssertEqual(result.statusMessage, "Something's Wrong")
        XCTAssertTrue(result.isStale)
    }

    // MARK: - formatTimeAgo

    func testFormatTimeAgoJustNow() {
        let now = Date()
        XCTAssertEqual(service.formatTimeAgo(now.addingTimeInterval(-30), now: now), "just now")
    }

    func testFormatTimeAgoOneMinute() {
        let now = Date()
        XCTAssertEqual(service.formatTimeAgo(now.addingTimeInterval(-60), now: now), "1 minute ago")
    }

    func testFormatTimeAgoMinutes() {
        let now = Date()
        XCTAssertEqual(service.formatTimeAgo(now.addingTimeInterval(-300), now: now), "5 minutes ago")
    }

    func testFormatTimeAgoOneHour() {
        let now = Date()
        XCTAssertEqual(service.formatTimeAgo(now.addingTimeInterval(-3600), now: now), "1 hour ago")
    }

    func testFormatTimeAgoHours() {
        let now = Date()
        XCTAssertEqual(service.formatTimeAgo(now.addingTimeInterval(-7200), now: now), "2 hours ago")
    }

    func testFormatTimeAgoOverADay() {
        let now = Date()
        XCTAssertEqual(service.formatTimeAgo(now.addingTimeInterval(-90000), now: now), "over a day ago")
    }

    func testFormatTimeAgoOverADayUseOverFalse() {
        let now = Date()
        XCTAssertEqual(service.formatTimeAgo(now.addingTimeInterval(-90000), now: now, useOver: false), "a day")
    }

    // MARK: - contextWindow

    func testContextWindowKnownModel() {
        let models = [ModelInfo(id: "claude-sonnet-4-5", contextWindow: 200_000, supportsVision: nil, supportsFunctionCalling: nil, tags: nil)]
        XCTAssertEqual(service.contextWindow(for: "claude-sonnet-4-5", models: models), 200_000)
    }

    func testContextWindowOpus46Fallback() {
        XCTAssertEqual(service.contextWindow(for: "claude-opus-4-6", models: []), 200_000)
    }

    func testContextWindowNilModel() {
        XCTAssertEqual(service.contextWindow(for: nil, models: []), 200_000)
    }

    func testContextWindowUnknownModel() {
        XCTAssertEqual(service.contextWindow(for: "unknown-model", models: []), 200_000)
    }

    // MARK: - calculateContextPercent

    func testCalculateContextPercentEmpty() {
        let result = service.calculateContextPercent(sessions: [], models: [])
        XCTAssertNil(result.percent)
        XCTAssertEqual(result.activeCount, 0)
        XCTAssertNil(result.mostRecentSession)
    }

    func testCalculateContextPercentFiltersCronAndSubagent() {
        let now = Date()
        let recentMs = Int64(now.timeIntervalSince1970 * 1000) - 1000 // 1s ago

        let mainSession = SessionInfo(
            key: "agent:main:main", kind: nil, channel: nil, label: nil, displayName: nil,
            deliveryContext: nil, updatedAt: recentMs, sessionId: "main-session",
            model: "claude-sonnet-4-5", contextTokens: 200_000, totalTokens: 100_000,
            thinkingLevel: nil, systemSent: nil, abortedLastRun: nil, lastChannel: nil,
            lastTo: nil, lastAccountId: nil, transcriptPath: nil
        )
        let cronSession = SessionInfo(
            key: "agent:main:cron:heartbeat", kind: nil, channel: nil, label: nil, displayName: nil,
            deliveryContext: nil, updatedAt: recentMs, sessionId: "cron-session",
            model: "claude-haiku-4", contextTokens: 200_000, totalTokens: 50_000,
            thinkingLevel: nil, systemSent: nil, abortedLastRun: nil, lastChannel: nil,
            lastTo: nil, lastAccountId: nil, transcriptPath: nil
        )
        let subagentSession = SessionInfo(
            key: "agent:main:subagent:abc-123", kind: nil, channel: nil, label: nil, displayName: nil,
            deliveryContext: nil, updatedAt: recentMs, sessionId: "subagent-session",
            model: "claude-sonnet-4-5", contextTokens: 200_000, totalTokens: 80_000,
            thinkingLevel: nil, systemSent: nil, abortedLastRun: nil, lastChannel: nil,
            lastTo: nil, lastAccountId: nil, transcriptPath: nil
        )

        let models = [ModelInfo(id: "claude-sonnet-4-5", contextWindow: 200_000, supportsVision: nil, supportsFunctionCalling: nil, tags: nil)]
        let result = service.calculateContextPercent(sessions: [mainSession, cronSession, subagentSession], models: models, now: now)

        // Only main session should be counted
        XCTAssertEqual(result.activeCount, 1)
        XCTAssertNotNil(result.percent)
        XCTAssertEqual(result.percent!, 50.0, accuracy: 0.1) // 100K / 200K
        XCTAssertEqual(result.mostRecentSession?.sessionId, "main-session")
    }
}
