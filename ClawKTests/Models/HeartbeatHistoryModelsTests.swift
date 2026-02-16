import XCTest
@testable import ClawK

final class HeartbeatHistoryModelsTests: XCTestCase {

    // MARK: - HeartbeatEntry Codable

    func testHeartbeatEntryEncodeDecode() {
        let entry = HeartbeatEntry(
            timestamp: Date(timeIntervalSince1970: 1700000000),
            status: "HEARTBEAT_OK",
            contextPercent: 45.5,
            sessionsChecked: 3,
            sessionsActive: 2,
            statusDescription: "All systems running"
        )

        let data = try! JSONEncoder().encode(entry)
        let decoded = try! JSONDecoder().decode(HeartbeatEntry.self, from: data)

        XCTAssertEqual(decoded.status, "HEARTBEAT_OK")
        XCTAssertEqual(decoded.contextPercent, 45.5)
        XCTAssertEqual(decoded.sessionsChecked, 3)
        XCTAssertEqual(decoded.sessionsActive, 2)
        XCTAssertEqual(decoded.statusDescription, "All systems running")
    }

    func testHeartbeatEntryWithNilOptionals() {
        let entry = HeartbeatEntry(
            timestamp: Date(timeIntervalSince1970: 1700000000),
            status: "HEARTBEAT_ALERT",
            contextPercent: nil,
            sessionsChecked: nil,
            sessionsActive: nil,
            statusDescription: nil
        )

        let data = try! JSONEncoder().encode(entry)
        let decoded = try! JSONDecoder().decode(HeartbeatEntry.self, from: data)

        XCTAssertEqual(decoded.status, "HEARTBEAT_ALERT")
        XCTAssertNil(decoded.contextPercent)
        XCTAssertNil(decoded.sessionsChecked)
        XCTAssertNil(decoded.sessionsActive)
        XCTAssertNil(decoded.statusDescription)
    }

    // MARK: - HeartbeatHistoryResult

    func testSuccessResultHasNoError() {
        let entries = [
            HeartbeatEntry(
                timestamp: Date(),
                status: "HEARTBEAT_OK",
                contextPercent: nil,
                sessionsChecked: nil,
                sessionsActive: nil,
                statusDescription: nil
            )
        ]
        let result = HeartbeatHistoryResult.success(entries)

        XCTAssertTrue(result.isSuccess)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.entries.count, 1)
    }

    func testFailureResultHasError() {
        let result = HeartbeatHistoryResult.failure(.mainSessionNotFound)

        XCTAssertFalse(result.isSuccess)
        XCTAssertNotNil(result.error)
        XCTAssertTrue(result.entries.isEmpty)
    }

    func testSuccessWithEmptyEntries() {
        let result = HeartbeatHistoryResult.success([])

        XCTAssertTrue(result.isSuccess)
        XCTAssertTrue(result.entries.isEmpty)
    }

    // MARK: - HeartbeatHistoryError Descriptions

    func testSessionsIndexNotFoundDescription() {
        let error = HeartbeatHistoryError.sessionsIndexNotFound
        XCTAssertEqual(error.errorDescription, "Session index file not found")
    }

    func testSessionsIndexParseErrorDescription() {
        let error = HeartbeatHistoryError.sessionsIndexParseError
        XCTAssertEqual(error.errorDescription, "Could not parse session index")
    }

    func testMainSessionNotFoundDescription() {
        let error = HeartbeatHistoryError.mainSessionNotFound
        XCTAssertEqual(error.errorDescription, "Main session not configured")
    }

    func testSessionFileNotFoundDescription() {
        let error = HeartbeatHistoryError.sessionFileNotFound(sessionId: "abc-123")
        XCTAssertTrue(error.errorDescription!.contains("abc-123"))
    }

    func testSessionFileReadErrorDescription() {
        let error = HeartbeatHistoryError.sessionFileReadError(path: "/tmp/test.jsonl")
        XCTAssertTrue(error.errorDescription!.contains("/tmp/test.jsonl"))
    }

    // MARK: - HeartbeatHistoryError Recovery Suggestions

    func testConfigErrorsHaveGatewaySuggestion() {
        let errors: [HeartbeatHistoryError] = [
            .sessionsIndexNotFound,
            .sessionsIndexParseError,
            .mainSessionNotFound
        ]
        for error in errors {
            XCTAssertTrue(
                error.recoverySuggestion!.contains("Gateway"),
                "\(error) should suggest checking Gateway"
            )
        }
    }

    func testFileErrorsHaveRestartSuggestion() {
        let errors: [HeartbeatHistoryError] = [
            .sessionFileNotFound(sessionId: "test"),
            .sessionFileReadError(path: "/tmp/test")
        ]
        for error in errors {
            XCTAssertTrue(
                error.recoverySuggestion!.contains("restart") || error.recoverySuggestion!.contains("Gateway"),
                "\(error) should suggest restarting"
            )
        }
    }
}
