import XCTest
@testable import ClawK

final class AppConfigurationTests: XCTestCase {

    private let config = AppConfiguration.shared

    // MARK: - Computed Path Properties

    func testMainSessionKey() {
        // Format: "agent:{agentName}:main"
        let key = config.mainSessionKey
        XCTAssertTrue(key.hasPrefix("agent:"))
        XCTAssertTrue(key.hasSuffix(":main"))
        XCTAssertEqual(key, "agent:\(config.agentName):main")
    }

    func testTelegramSessionKeyPrefix() {
        let prefix = config.telegramSessionKeyPrefix
        XCTAssertTrue(prefix.hasPrefix("agent:"))
        XCTAssertTrue(prefix.hasSuffix(":telegram:"))
        XCTAssertEqual(prefix, "agent:\(config.agentName):telegram:")
    }

    func testSubagentSessionKeyPrefix() {
        let prefix = config.subagentSessionKeyPrefix
        XCTAssertTrue(prefix.hasPrefix("agent:"))
        XCTAssertTrue(prefix.hasSuffix(":subagent:"))
        XCTAssertEqual(prefix, "agent:\(config.agentName):subagent:")
    }

    func testSessionsIndexPath() {
        let path = config.sessionsIndexPath
        XCTAssertTrue(path.hasSuffix("/sessions.json"))
        XCTAssertEqual(path, "\(config.sessionsPath)/sessions.json")
    }

    func testMemoryMdPath() {
        let path = config.memoryMdPath
        XCTAssertTrue(path.hasSuffix("/MEMORY.md"))
        XCTAssertEqual(path, "\(config.workspacePath)/MEMORY.md")
    }

    func testSessionFilePath() {
        let path = config.sessionFilePath(sessionId: "abc-123")
        XCTAssertTrue(path.hasSuffix("/abc-123.jsonl"))
        XCTAssertEqual(path, "\(config.sessionsPath)/abc-123.jsonl")
    }

    func testDailyLogPath() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = Date()
        let dateString = formatter.string(from: today)

        let path = config.dailyLogPath(for: today)
        XCTAssertTrue(path.hasSuffix("/\(dateString).md"))
    }

    func testContextFlushLogPath() {
        let path = config.contextFlushLogPath
        XCTAssertTrue(path.hasSuffix("/CONTEXT-FLUSH.md"))
        XCTAssertEqual(path, "\(config.memoryPath)/CONTEXT-FLUSH.md")
    }
}
