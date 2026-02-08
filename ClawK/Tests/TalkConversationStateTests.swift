//
//  TalkConversationStateTests.swift
//  ClawKTests
//
//  Tests for TalkConversationState and TalkChatMessage models
//

import XCTest
// Source files compiled directly into test target

final class TalkConversationStateTests: XCTestCase {

    // MARK: - TalkConversationState

    func testAllStatesHaveDisplayName() {
        let states: [TalkConversationState] = [.idle, .listening, .thinking, .speaking]
        for state in states {
            XCTAssertFalse(state.displayName.isEmpty, "State \(state) should have a display name")
        }
    }

    func testAllStatesHaveMenuBarIcon() {
        let states: [TalkConversationState] = [.idle, .listening, .thinking, .speaking]
        for state in states {
            XCTAssertFalse(state.menuBarIcon.isEmpty, "State \(state) should have a menu bar icon")
        }
    }

    func testStateDisplayNames() {
        XCTAssertEqual(TalkConversationState.idle.displayName, "Ready")
        XCTAssertEqual(TalkConversationState.listening.displayName, "Listening...")
        XCTAssertEqual(TalkConversationState.thinking.displayName, "Thinking...")
        XCTAssertEqual(TalkConversationState.speaking.displayName, "Speaking...")
    }

    // MARK: - TalkChatMessage

    func testChatMessageInit() {
        let msg = TalkChatMessage(role: .user, text: "Hello")
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.text, "Hello")
        XCTAssertFalse(msg.id.uuidString.isEmpty)
    }

    func testChatMessageCodable() throws {
        let original = TalkChatMessage(role: .assistant, text: "Hi there!")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TalkChatMessage.self, from: data)
        XCTAssertEqual(decoded.role, original.role)
        XCTAssertEqual(decoded.text, original.text)
        XCTAssertEqual(decoded.id, original.id)
    }

    func testChatMessageEquatable() {
        let msg1 = TalkChatMessage(role: .user, text: "Test")
        let msg2 = msg1
        XCTAssertEqual(msg1, msg2)

        let msg3 = TalkChatMessage(role: .user, text: "Test")
        XCTAssertNotEqual(msg1, msg3) // Different UUID
    }

    func testChatMessageRelativeTime() {
        let msg = TalkChatMessage(role: .user, text: "Test")
        XCTAssertFalse(msg.relativeTime.isEmpty, "Relative time should not be empty")
    }

    func testChatMessageRoles() {
        let userMsg = TalkChatMessage(role: .user, text: "question")
        let assistantMsg = TalkChatMessage(role: .assistant, text: "answer")
        XCTAssertEqual(userMsg.role, .user)
        XCTAssertEqual(assistantMsg.role, .assistant)
    }
}
