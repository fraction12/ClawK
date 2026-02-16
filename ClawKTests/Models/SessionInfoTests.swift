import XCTest
@testable import ClawK

final class SessionInfoTests: XCTestCase {

    // MARK: - Helper

    private func makeSession(
        key: String = "agent:main:main",
        kind: String? = nil,
        label: String? = nil,
        displayName: String? = nil,
        updatedAt: Int64? = nil,
        sessionId: String = "test-session-id",
        model: String? = "claude-sonnet-4-5",
        contextTokens: Int? = 200_000,
        totalTokens: Int? = 50_000,
        thinkingLevel: String?? = nil
    ) -> SessionInfo {
        SessionInfo(
            key: key,
            kind: kind,
            channel: nil,
            label: label,
            displayName: displayName,
            deliveryContext: nil,
            updatedAt: updatedAt,
            sessionId: sessionId,
            model: model,
            contextTokens: contextTokens,
            totalTokens: totalTokens,
            thinkingLevel: thinkingLevel,
            systemSent: nil,
            abortedLastRun: nil,
            lastChannel: nil,
            lastTo: nil,
            lastAccountId: nil,
            transcriptPath: nil
        )
    }

    // MARK: - modelShortName

    func testModelShortNameOpus() {
        let session = makeSession(model: "anthropic/claude-opus-4-5")
        XCTAssertEqual(session.modelShortName, "Opus")
    }

    func testModelShortNameSonnet() {
        let session = makeSession(model: "claude-sonnet-4-5")
        XCTAssertEqual(session.modelShortName, "Sonnet")
    }

    func testModelShortNameHaiku() {
        let session = makeSession(model: "claude-haiku-4")
        XCTAssertEqual(session.modelShortName, "Haiku")
    }

    func testModelShortNameNil() {
        let session = makeSession(model: nil)
        XCTAssertEqual(session.modelShortName, "—")
    }

    func testModelShortNameUnknown() {
        let session = makeSession(model: "gpt-4-turbo")
        XCTAssertEqual(session.modelShortName, "gpt-4-turbo")
    }

    // MARK: - sessionType

    func testSessionTypeMain() {
        let session = makeSession(key: "agent:main:main")
        XCTAssertEqual(session.sessionType, .main)
    }

    func testSessionTypeSubagent() {
        let session = makeSession(key: "agent:main:subagent:abc-def-123")
        XCTAssertEqual(session.sessionType, .subagent)
    }

    func testSessionTypeCron() {
        let session = makeSession(key: "agent:main:cron:daily-check")
        XCTAssertEqual(session.sessionType, .cron)
    }

    func testSessionTypeOther() {
        // Key must not contain ":main", "subagent", or "cron"
        let session = makeSession(key: "agent:telegram:12345")
        XCTAssertEqual(session.sessionType, .other)
    }

    // MARK: - friendlyName

    func testFriendlyNameUsesLabel() {
        let session = makeSession(label: "My Session", displayName: "Display")
        XCTAssertEqual(session.friendlyName, "My Session")
    }

    func testFriendlyNameUsesDisplayNameWhenNoLabel() {
        let session = makeSession(label: nil, displayName: "Display Name")
        XCTAssertEqual(session.friendlyName, "Display Name")
    }

    func testFriendlyNameSubagentSuffix() {
        let session = makeSession(key: "agent:main:subagent:abc12345-6789-0abc-def0-123456789abc")
        XCTAssertEqual(session.friendlyName, "Subagent (56789abc)")
    }

    func testFriendlyNameCronWithJobName() {
        // dropFirst(2) on ["agent","main","cron","daily-check"] → "cron:daily-check"
        let session = makeSession(key: "agent:main:cron:daily-check")
        XCTAssertEqual(session.friendlyName, "Cron: cron:daily-check")
    }

    func testFriendlyNameMainSession() {
        let session = makeSession(key: "agent:main:main")
        XCTAssertEqual(session.friendlyName, "Main")
    }

    // MARK: - contextUsagePercent

    func testContextUsagePercent() {
        let session = makeSession(contextTokens: 200_000, totalTokens: 100_000)
        XCTAssertEqual(session.contextUsagePercent, 50.0, accuracy: 0.01)
    }

    func testContextUsagePercentZeroContext() {
        let session = makeSession(contextTokens: 0, totalTokens: 100_000)
        XCTAssertEqual(session.contextUsagePercent, 0.0)
    }

    func testContextUsagePercentNilTokens() {
        let session = makeSession(contextTokens: 200_000, totalTokens: nil)
        XCTAssertEqual(session.contextUsagePercent, 0.0)
    }

    // MARK: - lastUpdatedDate

    func testLastUpdatedDate() {
        let ms: Int64 = 1707000000000 // Some known timestamp
        let session = makeSession(updatedAt: ms)
        let expected = Date(timeIntervalSince1970: 1707000000)
        XCTAssertEqual(session.lastUpdatedDate, expected)
    }

    func testLastUpdatedDateNil() {
        let session = makeSession(updatedAt: nil)
        XCTAssertNil(session.lastUpdatedDate)
    }

    // MARK: - id

    func testIdMatchesSessionId() {
        let session = makeSession(sessionId: "my-session-123")
        XCTAssertEqual(session.id, "my-session-123")
    }
}
