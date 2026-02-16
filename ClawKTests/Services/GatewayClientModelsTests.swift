import XCTest
@testable import ClawK

final class GatewayClientModelsTests: XCTestCase {

    // MARK: - CLIResult.error

    func testCLIResultSuccessHasNoError() {
        let result = GatewayClient.CLIResult(stdout: "output", stderr: "", exitCode: 0)
        XCTAssertNil(result.error)
    }

    func testCLIResultFailureReturnsStderr() {
        let result = GatewayClient.CLIResult(stdout: "", stderr: "command not found", exitCode: 127)
        XCTAssertEqual(result.error, "command not found")
    }

    func testCLIResultFailureWithEmptyStderrReturnsExitCode() {
        let result = GatewayClient.CLIResult(stdout: "", stderr: "", exitCode: 1)
        XCTAssertEqual(result.error, "Command failed with exit code 1")
    }

    // MARK: - SessionMessage.textContent

    func testTextContentSingleBlock() {
        let message = GatewayClient.SessionMessage(
            role: "assistant",
            content: [
                .init(type: "text", text: "Hello world")
            ],
            timestamp: nil
        )
        XCTAssertEqual(message.textContent, "Hello world")
    }

    func testTextContentMultipleBlocks() {
        let message = GatewayClient.SessionMessage(
            role: "assistant",
            content: [
                .init(type: "text", text: "First block"),
                .init(type: "text", text: "Second block")
            ],
            timestamp: nil
        )
        XCTAssertEqual(message.textContent, "First block\nSecond block")
    }

    func testTextContentSkipsNonTextBlocks() {
        let message = GatewayClient.SessionMessage(
            role: "assistant",
            content: [
                .init(type: "tool_use", text: nil),
                .init(type: "text", text: "Only this")
            ],
            timestamp: nil
        )
        XCTAssertEqual(message.textContent, "Only this")
    }

    func testTextContentReturnsNilWhenNoTextBlocks() {
        let message = GatewayClient.SessionMessage(
            role: "assistant",
            content: [
                .init(type: "tool_use", text: nil),
                .init(type: "image", text: nil)
            ],
            timestamp: nil
        )
        XCTAssertNil(message.textContent)
    }

    func testTextContentReturnsNilForEmptyContent() {
        let message = GatewayClient.SessionMessage(
            role: "assistant",
            content: [],
            timestamp: nil
        )
        XCTAssertNil(message.textContent)
    }

    // MARK: - SessionMessage.date

    func testDateConvertsMillisecondsToDate() {
        let ms: Double = 1707000000000
        let message = GatewayClient.SessionMessage(
            role: "user",
            content: [],
            timestamp: ms
        )
        let expected = Date(timeIntervalSince1970: 1707000000)
        XCTAssertEqual(message.date, expected)
    }

    func testDateReturnsNilWhenTimestampNil() {
        let message = GatewayClient.SessionMessage(
            role: "user",
            content: [],
            timestamp: nil
        )
        XCTAssertNil(message.date)
    }

    // MARK: - GatewayError.isTimeout

    func testIsTimeoutTrueForTimeout() {
        let error = GatewayError.timeout
        XCTAssertTrue(error.isTimeout)
    }

    func testIsTimeoutFalseForOtherErrors() {
        let errors: [GatewayError] = [
            .invalidURL,
            .unauthorized,
            .notFound,
            .noToken,
            .serverError("test"),
            .toolBlocked("exec")
        ]
        for error in errors {
            XCTAssertFalse(error.isTimeout, "\(error) should not be timeout")
        }
    }

    // MARK: - GatewayError Descriptions

    func testAllErrorsHaveDescriptions() {
        let errors: [GatewayError] = [
            .invalidURL,
            .unauthorized,
            .notFound,
            .toolBlocked("exec"),
            .serverError("bad request"),
            .decodingError(NSError(domain: "test", code: 0)),
            .networkError(NSError(domain: "test", code: 0)),
            .timeout,
            .noToken
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "\(error) description should not be empty")
        }
    }

    func testToolBlockedIncludesToolName() {
        let error = GatewayError.toolBlocked("exec")
        XCTAssertTrue(error.errorDescription!.contains("exec"))
    }

    func testServerErrorIncludesMessage() {
        let error = GatewayError.serverError("rate limited")
        XCTAssertTrue(error.errorDescription!.contains("rate limited"))
    }

    // MARK: - MemorySearchHit.content Backward Compatibility

    func testMemorySearchHitContentEqualsSnippet() {
        let hit = GatewayClient.MemorySearchHit(
            snippet: "test snippet",
            score: 0.95,
            path: "/memory/test.md",
            startLine: 1,
            endLine: 5,
            source: nil,
            citation: nil
        )
        XCTAssertEqual(hit.content, hit.snippet)
    }

    func testMemorySearchHitContentNilWhenSnippetNil() {
        let hit = GatewayClient.MemorySearchHit(
            snippet: nil,
            score: nil,
            path: nil,
            startLine: nil,
            endLine: nil,
            source: nil,
            citation: nil
        )
        XCTAssertNil(hit.content)
    }
}
