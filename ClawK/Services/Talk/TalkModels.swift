//
//  TalkModels.swift
//  ClawK
//
//  Data models for Talk Mode
//

import Foundation

// MARK: - Conversation State

enum TalkConversationState: String, CaseIterable, Sendable {
    case idle
    case listening
    case thinking
    case speaking

    var displayName: String {
        switch self {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .thinking: return "Thinking..."
        case .speaking: return "Speaking..."
        }
    }

    var menuBarIcon: String {
        switch self {
        case .idle: return "mic.circle"
        case .listening: return "mic.circle.fill"
        case .thinking: return "brain"
        case .speaking: return "speaker.wave.3.fill"
        }
    }
}

// MARK: - Chat Message

struct TalkChatMessage: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    let role: Role
    let text: String
    let timestamp: Date

    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    init(role: Role, text: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }

    var relativeTime: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 10 { return "just now" }
        if interval < 60 { return "\(Int(interval))s ago" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }
}
