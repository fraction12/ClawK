//
//  GatewayWebSocketTests.swift
//  ClawKTests
//
//  Tests for GatewayWebSocket connection state and message parsing
//

import XCTest
// Source files compiled directly into test target

final class GatewayWebSocketTests: XCTestCase {

    // MARK: - TalkGatewayIncoming Decoding

    func testDecodeConnectChallenge() throws {
        let json = """
        {
            "type": "event",
            "event": "connect.challenge",
            "payload": {
                "nonce": "abc123"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let msg = try JSONDecoder().decode(TalkGatewayIncoming.self, from: data)
        XCTAssertEqual(msg.type, "event")
        XCTAssertEqual(msg.event, "connect.challenge")
        XCTAssertEqual(msg.payload?.nonce, "abc123")
    }

    func testDecodeResponseWithOk() throws {
        let json = """
        {
            "type": "res",
            "id": "req-1",
            "ok": true,
            "payload": {
                "snapshot": {}
            }
        }
        """
        let data = json.data(using: .utf8)!
        let msg = try JSONDecoder().decode(TalkGatewayIncoming.self, from: data)
        XCTAssertEqual(msg.type, "res")
        XCTAssertEqual(msg.id, "req-1")
        XCTAssertEqual(msg.ok, true)
    }

    func testDecodeChatDelta() throws {
        let json = """
        {
            "type": "event",
            "event": "chat",
            "payload": {
                "state": "delta",
                "message": {
                    "content": [
                        {"type": "text", "text": "Hello world"}
                    ]
                }
            }
        }
        """
        let data = json.data(using: .utf8)!
        let msg = try JSONDecoder().decode(TalkGatewayIncoming.self, from: data)
        XCTAssertEqual(msg.event, "chat")
        XCTAssertEqual(msg.payload?.state, "delta")
        XCTAssertEqual(msg.payload?.message?.content?.textValue, "Hello world")
    }

    func testDecodeChatFinal() throws {
        let json = """
        {
            "type": "event",
            "event": "chat",
            "payload": {
                "state": "final",
                "message": {
                    "content": "Final response text"
                }
            }
        }
        """
        let data = json.data(using: .utf8)!
        let msg = try JSONDecoder().decode(TalkGatewayIncoming.self, from: data)
        XCTAssertEqual(msg.payload?.state, "final")
        XCTAssertEqual(msg.payload?.message?.content?.textValue, "Final response text")
    }

    func testDecodeErrorMessage() throws {
        let json = """
        {
            "type": "res",
            "id": "req-2",
            "ok": false,
            "error": {
                "message": "Authentication failed"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let msg = try JSONDecoder().decode(TalkGatewayIncoming.self, from: data)
        XCTAssertEqual(msg.ok, false)
        XCTAssertEqual(msg.error?.message, "Authentication failed")
    }

    // MARK: - TalkMessageContent

    func testMessageContentBlocksArray() throws {
        let json = """
        [{"type": "text", "text": "Hello"}, {"type": "text", "text": " World"}]
        """
        let data = json.data(using: .utf8)!
        let content = try JSONDecoder().decode(TalkMessageContent.self, from: data)
        XCTAssertEqual(content.textValue, "Hello\n World")
    }

    func testMessageContentStringValue() throws {
        let json = "\"Just a string\""
        let data = json.data(using: .utf8)!
        let content = try JSONDecoder().decode(TalkMessageContent.self, from: data)
        XCTAssertEqual(content.textValue, "Just a string")
    }

    // MARK: - TalkGatewayRequest

    func testGatewayRequestEncoding() throws {
        let params: [String: TalkAnyCodable] = [
            "message": TalkAnyCodable("Hello"),
            "deliver": TalkAnyCodable(false)
        ]
        let req = TalkGatewayRequest(method: "chat.send", params: params)
        XCTAssertEqual(req.type, "req")
        XCTAssertEqual(req.method, "chat.send")
        XCTAssertFalse(req.id.isEmpty)

        // Verify it can be encoded
        let data = try JSONEncoder().encode(req)
        XCTAssertFalse(data.isEmpty)
    }
}
