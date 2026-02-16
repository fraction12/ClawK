import XCTest
@testable import ClawK

final class ModelInfoTests: XCTestCase {

    // MARK: - effectiveContextWindow

    func testEffectiveContextWindowExplicit() {
        let model = ModelInfo(id: "claude-sonnet-4-5", contextWindow: 300_000, supportsVision: nil, supportsFunctionCalling: nil, tags: nil)
        XCTAssertEqual(model.effectiveContextWindow, 300_000)
    }

    func testEffectiveContextWindowOpus46() {
        let model = ModelInfo(id: "claude-opus-4-6", contextWindow: nil, supportsVision: nil, supportsFunctionCalling: nil, tags: nil)
        XCTAssertEqual(model.effectiveContextWindow, 1_000_000)
    }

    func testEffectiveContextWindowOpus() {
        let model = ModelInfo(id: "claude-opus-4-5", contextWindow: nil, supportsVision: nil, supportsFunctionCalling: nil, tags: nil)
        XCTAssertEqual(model.effectiveContextWindow, 200_000)
    }

    func testEffectiveContextWindowSonnet() {
        let model = ModelInfo(id: "claude-sonnet-4-5", contextWindow: nil, supportsVision: nil, supportsFunctionCalling: nil, tags: nil)
        XCTAssertEqual(model.effectiveContextWindow, 200_000)
    }

    func testEffectiveContextWindowHaiku() {
        let model = ModelInfo(id: "claude-haiku-4", contextWindow: nil, supportsVision: nil, supportsFunctionCalling: nil, tags: nil)
        XCTAssertEqual(model.effectiveContextWindow, 200_000)
    }

    func testEffectiveContextWindowUnknown() {
        let model = ModelInfo(id: "gpt-4-turbo", contextWindow: nil, supportsVision: nil, supportsFunctionCalling: nil, tags: nil)
        XCTAssertEqual(model.effectiveContextWindow, 200_000)
    }

    // MARK: - JSON Decoding with key → id mapping

    func testDecodingKeyMappedToId() throws {
        let json = """
        {
            "key": "claude-sonnet-4-5",
            "contextWindow": 200000,
            "supportsVision": true,
            "supportsFunctionCalling": true,
            "tags": ["default"]
        }
        """.data(using: .utf8)!

        let model = try JSONDecoder().decode(ModelInfo.self, from: json)
        XCTAssertEqual(model.id, "claude-sonnet-4-5")
        XCTAssertEqual(model.contextWindow, 200_000)
        XCTAssertEqual(model.supportsVision, true)
        XCTAssertEqual(model.supportsFunctionCalling, true)
        XCTAssertEqual(model.tags, ["default"])
    }

    func testDecodingMissingContextWindow() throws {
        let json = """
        {
            "key": "claude-opus-4-6"
        }
        """.data(using: .utf8)!

        let model = try JSONDecoder().decode(ModelInfo.self, from: json)
        XCTAssertEqual(model.id, "claude-opus-4-6")
        XCTAssertNil(model.contextWindow)
        XCTAssertEqual(model.effectiveContextWindow, 1_000_000) // fallback for opus-4-6
    }

    func testIdentifiable() {
        let model = ModelInfo(id: "test-model", contextWindow: nil, supportsVision: nil, supportsFunctionCalling: nil, tags: nil)
        XCTAssertEqual(model.id, "test-model")
    }
}
