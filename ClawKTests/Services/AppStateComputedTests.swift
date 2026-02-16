import XCTest
@testable import ClawK

@MainActor
final class AppStateComputedTests: XCTestCase {

    private var appState: AppState!

    override func setUp() async throws {
        appState = AppState()
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "pollingInterval")
        appState = nil
    }

    // MARK: - Helpers

    private func makeSession(
        key: String = "agent:main:main",
        sessionId: String = UUID().uuidString,
        model: String? = "claude-sonnet-4-5",
        totalTokens: Int? = 50_000,
        updatedAt: Int64? = nil
    ) -> SessionInfo {
        SessionInfo(
            key: key,
            kind: nil,
            channel: nil,
            label: nil,
            displayName: nil,
            deliveryContext: nil,
            updatedAt: updatedAt,
            sessionId: sessionId,
            model: model,
            contextTokens: 200_000,
            totalTokens: totalTokens,
            thinkingLevel: nil,
            systemSent: nil,
            abortedLastRun: nil,
            lastChannel: nil,
            lastTo: nil,
            lastAccountId: nil,
            transcriptPath: nil
        )
    }

    private func makeCronJob(
        name: String = "test-job",
        enabled: Bool? = true,
        lastRunAtMs: Int64? = nil,
        nextRunAtMs: Int64? = nil,
        lastDurationMs: Int64? = nil,
        everyMs: Int64? = 1800000
    ) -> CronJob {
        CronJob(
            id: UUID().uuidString,
            agentId: nil,
            name: name,
            enabled: enabled,
            createdAtMs: nil,
            updatedAtMs: nil,
            schedule: CronSchedule(kind: "every", expr: nil, tz: nil, everyMs: everyMs, atMs: nil),
            sessionTarget: nil,
            wakeMode: nil,
            payload: nil,
            state: CronState(nextRunAtMs: nextRunAtMs, lastRunAtMs: lastRunAtMs, lastStatus: nil, lastDurationMs: lastDurationMs, consecutiveErrors: nil),
            isolation: nil,
            description: nil,
            deleteAfterRun: nil,
            delivery: nil
        )
    }

    // MARK: - showSkeleton

    func testShowSkeletonTrueWhenInitialLoadAndEmpty() {
        // AppState starts with isInitialLoad = true
        XCTAssertTrue(appState.showSkeleton(for: [SessionInfo]()))
    }

    func testShowSkeletonFalseWhenNotInitialLoad() {
        appState.isInitialLoad = false
        XCTAssertFalse(appState.showSkeleton(for: [SessionInfo]()))
    }

    func testShowSkeletonFalseWhenDataPresent() {
        let sessions = [makeSession()]
        XCTAssertFalse(appState.showSkeleton(for: sessions))
    }

    func testShowSkeletonOptionalTrueWhenNil() {
        XCTAssertTrue(appState.showSkeleton(for: nil as String?))
    }

    func testShowSkeletonOptionalFalseWhenPresent() {
        XCTAssertFalse(appState.showSkeleton(for: "data" as String?))
    }

    // MARK: - mainSession

    func testMainSessionFindsCorrectKey() {
        let mainKey = AppConfiguration.shared.mainSessionKey
        let mainSession = makeSession(key: mainKey, sessionId: "main-1")
        let otherSession = makeSession(key: "agent:main:subagent:abc", sessionId: "sub-1")
        appState.sessions = [otherSession, mainSession]

        XCTAssertEqual(appState.mainSession?.sessionId, "main-1")
    }

    func testMainSessionReturnsNilWhenAbsent() {
        appState.sessions = [makeSession(key: "agent:main:subagent:abc")]
        XCTAssertNil(appState.mainSession)
    }

    // MARK: - telegramSession

    func testTelegramSessionFiltersByPrefix() {
        let prefix = AppConfiguration.shared.telegramSessionKeyPrefix
        let telegramSession = makeSession(
            key: "\(prefix)12345",
            sessionId: "tg-1",
            updatedAt: 1700000000000
        )
        appState.sessions = [
            makeSession(key: "agent:main:main", sessionId: "main-1"),
            telegramSession
        ]

        XCTAssertEqual(appState.telegramSession?.sessionId, "tg-1")
    }

    func testTelegramSessionReturnsMostRecent() {
        let prefix = AppConfiguration.shared.telegramSessionKeyPrefix
        let older = makeSession(key: "\(prefix)111", sessionId: "tg-old", updatedAt: 1700000000000)
        let newer = makeSession(key: "\(prefix)222", sessionId: "tg-new", updatedAt: 1700001000000)
        appState.sessions = [older, newer]

        XCTAssertEqual(appState.telegramSession?.sessionId, "tg-new")
    }

    // MARK: - activeSubagents

    func testActiveSubagentsFiltersCorrectly() {
        appState.sessions = [
            makeSession(key: "agent:main:main"),
            makeSession(key: "agent:main:subagent:abc"),
            makeSession(key: "agent:main:subagent:def"),
            makeSession(key: "agent:main:cron:heartbeat")
        ]

        XCTAssertEqual(appState.activeSubagents.count, 2)
    }

    func testActiveSubagentsEmptyWhenNoSubagents() {
        appState.sessions = [makeSession(key: "agent:main:main")]
        XCTAssertTrue(appState.activeSubagents.isEmpty)
    }

    // MARK: - activeMainSessions

    func testActiveMainSessionsExcludesCronAndSubagent() {
        appState.sessions = [
            makeSession(key: "agent:main:main"),
            makeSession(key: "agent:main:telegram:12345"),
            makeSession(key: "agent:main:subagent:abc"),
            makeSession(key: "agent:main:cron:heartbeat")
        ]

        let mains = appState.activeMainSessions
        XCTAssertEqual(mains.count, 2, "Should include main and telegram, exclude subagent and cron")
    }

    func testActiveMainSessionsSortedByMostRecent() {
        let older = makeSession(key: "agent:main:main", sessionId: "old", updatedAt: 1700000000000)
        let newer = makeSession(key: "agent:main:telegram:1", sessionId: "new", updatedAt: 1700001000000)
        appState.sessions = [older, newer]

        let mains = appState.activeMainSessions
        XCTAssertEqual(mains.first?.sessionId, "new")
    }

    // MARK: - totalTokensUsed

    func testTotalTokensUsedSumsAllSessions() {
        appState.sessions = [
            makeSession(totalTokens: 10_000),
            makeSession(totalTokens: 20_000),
            makeSession(totalTokens: 30_000)
        ]

        XCTAssertEqual(appState.totalTokensUsed, 60_000)
    }

    func testTotalTokensUsedHandlesNilTokens() {
        appState.sessions = [
            makeSession(totalTokens: 10_000),
            makeSession(totalTokens: nil),
            makeSession(totalTokens: 5_000)
        ]

        XCTAssertEqual(appState.totalTokensUsed, 15_000)
    }

    func testTotalTokensUsedZeroWhenEmpty() {
        appState.sessions = []
        XCTAssertEqual(appState.totalTokensUsed, 0)
    }

    // MARK: - contextWindow(for:)

    func testContextWindowNilModelReturnsDefault() {
        XCTAssertEqual(appState.contextWindow(for: nil), 200_000)
    }

    func testContextWindowOpus46Returns200K() {
        // Without models loaded, falls back to hardcoded check
        XCTAssertEqual(appState.contextWindow(for: "claude-opus-4-6"), 200_000)
    }

    func testContextWindowGPT4Returns128K() {
        XCTAssertEqual(appState.contextWindow(for: "gpt-4-turbo"), 128_000)
    }

    func testContextWindowUnknownModelReturnsDefault() {
        XCTAssertEqual(appState.contextWindow(for: "some-unknown-model"), 200_000)
    }

    func testContextWindowUsesModelCatalog() {
        // Load a model with explicit context window
        appState.models = [
            ModelInfo(id: "custom-model", contextWindow: 500_000, supportsVision: nil, supportsFunctionCalling: nil, tags: nil)
        ]

        XCTAssertEqual(appState.contextWindow(for: "custom-model"), 500_000)
    }

    func testContextWindowCacheInvalidatesOnModelChange() {
        // First lookup with no models
        _ = appState.contextWindow(for: "claude-sonnet-4-5")

        // Add models — cache should invalidate
        appState.models = [
            ModelInfo(id: "claude-sonnet-4-5", contextWindow: 180_000, supportsVision: nil, supportsFunctionCalling: nil, tags: nil)
        ]

        XCTAssertEqual(appState.contextWindow(for: "claude-sonnet-4-5"), 180_000)
    }

    // MARK: - upcomingJobs

    func testUpcomingJobsExcludesRunningJobs() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let running = makeCronJob(name: "running", lastRunAtMs: now, lastDurationMs: 600000)
        let upcoming = makeCronJob(name: "upcoming", lastRunAtMs: nil, nextRunAtMs: now + 3600000)
        appState.cronJobs = [running, upcoming]

        let result = appState.upcomingJobs
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.name, "upcoming")
    }

    func testUpcomingJobsExcludesDisabled() {
        let disabled = makeCronJob(name: "disabled", enabled: false)
        let enabled = makeCronJob(name: "enabled", enabled: true)
        appState.cronJobs = [disabled, enabled]

        let upcoming = appState.upcomingJobs
        XCTAssertTrue(upcoming.allSatisfy { $0.isEnabled })
    }

    func testUpcomingJobsSortedByNextRun() {
        let later = makeCronJob(name: "later", nextRunAtMs: 2000000000000)
        let sooner = makeCronJob(name: "sooner", nextRunAtMs: 1000000000000)
        appState.cronJobs = [later, sooner]

        let upcoming = appState.upcomingJobs
        XCTAssertEqual(upcoming.first?.name, "sooner")
    }

    // MARK: - pollingInterval

    func testPollingIntervalDefaultIsFiveSeconds() {
        // Clear any existing value
        UserDefaults.standard.removeObject(forKey: "pollingInterval")
        let state = AppState()
        XCTAssertEqual(state.pollingInterval, 5.0)
    }

    func testPollingIntervalClampedToMinimum() {
        appState.pollingInterval = 0.1
        XCTAssertEqual(appState.pollingInterval, 1.0, accuracy: 0.01)
    }

    func testPollingIntervalClampedToMaximum() {
        appState.pollingInterval = 100.0
        XCTAssertEqual(appState.pollingInterval, 30.0, accuracy: 0.01)
    }
}
