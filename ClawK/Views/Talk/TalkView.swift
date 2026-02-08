//
//  TalkView.swift
//  ClawK
//
//  Main Talk Mode view — sidebar tab with conversation history and controls
//

import SwiftUI

struct TalkView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var conversationManager = TalkConversationManager()

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Spacing.xxl) {
                    // Header
                    DSPageHeader(
                        emoji: "\u{1F399}\u{FE0F}",
                        title: "TALK",
                        subtitle: "Voice conversation with Claude"
                    )

                    // State Indicator + Waveform
                    DSCard(title: "\u{1F50A} VOICE", color: .cyan) {
                        VStack(spacing: Spacing.xl) {
                            TalkStateIndicator(
                                state: conversationManager.state,
                                audioLevels: conversationManager.audioEngine.recentLevels
                            )
                            .frame(height: 120)

                            // Live transcript
                            if !conversationManager.userTranscript.isEmpty
                                && conversationManager.state == .listening
                            {
                                Text(conversationManager.userTranscript)
                                    .font(.ClawK.body)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(Spacing.md)
                                    .background(Color.green.backgroundLight)
                                    .cornerRadius(Spacing.md)
                            }

                            // Claude response
                            if !conversationManager.claudeResponse.isEmpty
                                && (conversationManager.state == .thinking
                                    || conversationManager.state == .speaking)
                            {
                                Text(conversationManager.claudeResponse)
                                    .font(.ClawK.body)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(Spacing.md)
                                    .background(Color.blue.backgroundLight)
                                    .cornerRadius(Spacing.md)
                                    .lineLimit(6)
                            }

                            // Error message
                            if let error = conversationManager.errorMessage {
                                HStack(spacing: Spacing.sm) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(Color.Semantic.error)
                                    Text(error)
                                        .font(.ClawK.caption)
                                        .foregroundColor(Color.Semantic.error)
                                }
                                .padding(Spacing.md)
                                .background(Color.red.backgroundLight)
                                .cornerRadius(Spacing.md)
                            }

                            // Control Button
                            TalkControlButton(state: conversationManager.state) {
                                conversationManager.toggleListening()
                            }

                            // Connection status
                            HStack(spacing: Spacing.sm) {
                                DSStatusDot(
                                    color: conversationManager.gatewayWebSocket.isConnected
                                        ? Color.Semantic.connected : .gray
                                )
                                Text(conversationManager.gatewayWebSocket.connectionState.rawValue)
                                    .font(.ClawK.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(conversationManager.state.displayName)
                                    .font(.ClawK.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    // Conversation History
                    if !conversationManager.messages.isEmpty {
                        DSCard(title: "\u{1F4AC} CONVERSATION", color: .blue) {
                            VStack(spacing: Spacing.md) {
                                ForEach(conversationManager.messages.suffix(20)) { message in
                                    TalkMessageBubble(message: message)
                                }
                            }
                        }
                    }

                    // Actions
                    if !conversationManager.messages.isEmpty {
                        HStack {
                            Spacer()
                            Button(action: { conversationManager.clearHistory() }) {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "trash")
                                    Text("Clear History")
                                }
                                .font(.ClawK.caption)
                                .foregroundColor(Color.Semantic.error)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .pagePadding()
            }
            .background(Color.Surface.primary)
        }
        .navigationTitle("")
        .onAppear {
            conversationManager.startTTSServer()
        }
    }
}

// MARK: - Control Button

struct TalkControlButton: View {
    let state: TalkConversationState
    let action: () -> Void

    private var buttonColor: Color {
        switch state {
        case .idle: return Color.Semantic.info
        case .listening: return Color.Semantic.error
        case .thinking: return Color.Semantic.warning
        case .speaking: return Color.Semantic.success
        }
    }

    private var buttonIcon: String {
        switch state {
        case .idle: return "mic.fill"
        case .listening: return "stop.fill"
        case .thinking: return "brain"
        case .speaking: return "speaker.wave.3.fill"
        }
    }

    private var buttonLabel: String {
        switch state {
        case .idle: return "Start Talking"
        case .listening: return "Stop"
        case .thinking: return "Thinking\u{2026}"
        case .speaking: return "Interrupt"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.md) {
                Image(systemName: buttonIcon)
                    .font(.title3)
                Text(buttonLabel)
                    .font(.ClawK.bodyBold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
            .background(buttonColor)
            .foregroundColor(.white)
            .cornerRadius(Spacing.Card.cornerRadius)
        }
        .buttonStyle(.plain)
        .disabled(state == .thinking)
    }
}

// MARK: - Message Bubble

struct TalkMessageBubble: View {
    let message: TalkChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            if message.role == .assistant {
                Circle()
                    .fill(Color.blue.gradient)
                    .frame(width: 24, height: 24)
                    .overlay(Text("\u{1F99E}").font(.caption2))
            }

            VStack(
                alignment: message.role == .user ? .trailing : .leading,
                spacing: Spacing.xxs
            ) {
                Text(message.text)
                    .font(.ClawK.body)
                    .padding(Spacing.md)
                    .background(
                        message.role == .user
                            ? Color.green.backgroundLight
                            : Color.blue.backgroundLight
                    )
                    .cornerRadius(Spacing.md)

                Text(message.relativeTime)
                    .font(.ClawK.captionSmall)
                    .foregroundColor(Color.Text.tertiary)
            }
            .frame(
                maxWidth: .infinity,
                alignment: message.role == .user ? .trailing : .leading
            )

            if message.role == .user {
                Circle()
                    .fill(Color.green.gradient)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.caption2)
                            .foregroundColor(.white)
                    )
            }
        }
    }
}
