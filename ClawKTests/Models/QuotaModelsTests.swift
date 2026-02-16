import XCTest
@testable import ClawK

final class QuotaModelsTests: XCTestCase {

    // MARK: - QuotaWindow

    func testPercentFormatted() {
        let window = QuotaWindow(percentUsed: 42.7, resetsAt: nil)
        XCTAssertEqual(window.percentFormatted, "43%")
    }

    func testPercentRemaining() {
        let window = QuotaWindow(percentUsed: 30.0, resetsAt: nil)
        XCTAssertEqual(window.percentRemaining, 70.0, accuracy: 0.01)
    }

    func testPercentRemainingClampedToZero() {
        let window = QuotaWindow(percentUsed: 120.0, resetsAt: nil)
        XCTAssertEqual(window.percentRemaining, 0.0, accuracy: 0.01)
    }

    func testResetFormattedNil() {
        let window = QuotaWindow(percentUsed: 0, resetsAt: nil)
        XCTAssertEqual(window.resetFormatted, "—")
    }

    func testResetFormattedPast() {
        let window = QuotaWindow(percentUsed: 0, resetsAt: Date().addingTimeInterval(-100))
        XCTAssertEqual(window.resetFormatted, "Now")
    }

    func testResetFormattedFutureHours() {
        let window = QuotaWindow(percentUsed: 0, resetsAt: Date().addingTimeInterval(3700)) // ~1h
        let result = window.resetFormatted
        XCTAssertTrue(result.contains("h"), "Expected hours format, got: \(result)")
    }

    func testResetFormattedFutureDays() {
        let window = QuotaWindow(percentUsed: 0, resetsAt: Date().addingTimeInterval(90000)) // ~1d
        let result = window.resetFormatted
        XCTAssertTrue(result.contains("d"), "Expected days format, got: \(result)")
    }

    func testWindowDurationSession() {
        var window = QuotaWindow(percentUsed: 0, resetsAt: nil)
        window.windowType = "session"
        XCTAssertEqual(window.windowDuration, 5 * 3600, accuracy: 0.01)
    }

    func testWindowDurationWeekly() {
        var window = QuotaWindow(percentUsed: 0, resetsAt: nil)
        window.windowType = "weekly"
        XCTAssertEqual(window.windowDuration, 7 * 24 * 3600, accuracy: 0.01)
    }

    // MARK: - PaceStatus thresholds

    func testPaceStatusUnderPace() {
        // Create a window where pace < 90
        // Weekly window, 50% time elapsed, 30% usage => pace = 60
        let resetDate = Date().addingTimeInterval(3.5 * 24 * 3600) // 3.5 days from now (half of 7d)
        var window = QuotaWindow(percentUsed: 30.0, resetsAt: resetDate)
        window.windowType = "weekly"
        // pace = 30/50 * 100 = 60 → underPace
        XCTAssertEqual(window.paceStatus, .underPace)
    }

    func testPaceStatusUnknownWhenNotEnoughData() {
        // Very recently started window, not enough elapsed time
        let resetDate = Date().addingTimeInterval(6.9 * 24 * 3600) // ~6.9 days remaining (just started)
        var window = QuotaWindow(percentUsed: 5.0, resetsAt: resetDate)
        window.windowType = "weekly"
        // elapsed < 24h minimum → pace = nil → unknown
        XCTAssertEqual(window.paceStatus, .unknown)
    }

    func testShouldShowPaceWeekly() {
        // Weekly window with enough data
        let resetDate = Date().addingTimeInterval(3 * 24 * 3600) // 3 days remaining
        var window = QuotaWindow(percentUsed: 50.0, resetsAt: resetDate)
        window.windowType = "weekly"
        // 4 days elapsed > 24h minimum → pace available
        XCTAssertTrue(window.shouldShowPace)
    }

    func testShouldShowPaceSessionReturnsFalse() {
        let resetDate = Date().addingTimeInterval(2 * 3600) // 2h remaining
        var window = QuotaWindow(percentUsed: 50.0, resetsAt: resetDate)
        window.windowType = "session"
        XCTAssertFalse(window.shouldShowPace)
    }

    // MARK: - TokensByModel

    func testTokensByModelTotal() {
        let tokens = TokensByModel(sonnet: 1000, opus: 2000, haiku: 500)
        XCTAssertEqual(tokens.total, 3500)
    }

    func testTokensByModelFormatMillions() {
        XCTAssertEqual(TokensByModel.format(1_500_000), "1.5M")
    }

    func testTokensByModelFormatThousands() {
        XCTAssertEqual(TokensByModel.format(1_500), "1.5K")
    }

    func testTokensByModelFormatRaw() {
        XCTAssertEqual(TokensByModel.format(500), "500")
    }

    // MARK: - ClaudeMaxQuota

    func testHasDataTrue() {
        let quota = ClaudeMaxQuota(
            dataSource: .claudeDesktopApp,
            sessionWindow: QuotaWindow(percentUsed: 30.0, resetsAt: nil),
            weeklyWindow: .empty,
            weeklyOpusWindow: nil,
            weeklySonnetWindow: nil,
            totalTokensUsed: 0,
            tokensByModel: TokensByModel(sonnet: 0, opus: 0, haiku: 0),
            messageCount: 0,
            sessionCount: 0,
            lastSessionDate: nil,
            accountEmail: nil,
            planType: nil,
            organizationId: nil,
            lastUpdated: Date()
        )
        XCTAssertTrue(quota.hasData)
    }

    func testHasDataFalseWhenNoSource() {
        XCTAssertFalse(ClaudeMaxQuota.empty.hasData)
    }

    func testIsStaleTrue() {
        let quota = ClaudeMaxQuota(
            dataSource: .claudeDesktopApp,
            sessionWindow: .empty,
            weeklyWindow: .empty,
            weeklyOpusWindow: nil,
            weeklySonnetWindow: nil,
            totalTokensUsed: 0,
            tokensByModel: TokensByModel(sonnet: 0, opus: 0, haiku: 0),
            messageCount: 0,
            sessionCount: 0,
            lastSessionDate: nil,
            accountEmail: nil,
            planType: nil,
            organizationId: nil,
            lastUpdated: Date().addingTimeInterval(-301) // > 5 min ago
        )
        XCTAssertTrue(quota.isStale)
    }

    func testIsStaleFalse() {
        let quota = ClaudeMaxQuota(
            dataSource: .claudeDesktopApp,
            sessionWindow: .empty,
            weeklyWindow: .empty,
            weeklyOpusWindow: nil,
            weeklySonnetWindow: nil,
            totalTokensUsed: 0,
            tokensByModel: TokensByModel(sonnet: 0, opus: 0, haiku: 0),
            messageCount: 0,
            sessionCount: 0,
            lastSessionDate: nil,
            accountEmail: nil,
            planType: nil,
            organizationId: nil,
            lastUpdated: Date().addingTimeInterval(-60) // 1 min ago
        )
        XCTAssertFalse(quota.isStale)
    }
}
