//
//  TalkOverlayPanel.swift
//  ClawK
//
//  Floating overlay panel for Talk Mode (option+Space activation)
//

import AppKit
import SwiftUI

class TalkOverlayPanel: NSPanel {
    private static let frameDefaultsKey = "TalkOverlayFrame"

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
            styleMask: [
                .titled, .closable, .resizable,
                .nonactivatingPanel, .hudWindow,
            ],
            backing: .buffered,
            defer: false
        )

        self.title = "ClawK Talk"
        self.isFloatingPanel = true
        self.level = .floating
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.minSize = NSSize(width: 300, height: 380)
        self.maxSize = NSSize(width: 600, height: 900)
        self.isReleasedWhenClosed = false

        // Restore saved frame
        if let frameString = UserDefaults.standard.string(
            forKey: Self.frameDefaultsKey
        ) {
            let frame = NSRectFromString(frameString)
            if frame.width > 0, frame.height > 0 {
                let screenFrame = NSScreen.main?.visibleFrame ?? .zero
                if screenFrame.intersects(frame) {
                    self.setFrame(frame, display: false)
                } else {
                    self.center()
                }
            } else {
                self.center()
            }
        } else {
            self.center()
        }

        // Save frame on move/resize
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            self?.saveFrame()
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            self?.saveFrame()
        }
    }

    private func saveFrame() {
        UserDefaults.standard.set(
            NSStringFromRect(frame),
            forKey: Self.frameDefaultsKey
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Overlay Content View

struct TalkOverlayContentView: View {
    @ObservedObject var conversationManager: TalkConversationManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                DSMiniHeader(
                    emoji: "\u{1F399}\u{FE0F}",
                    title: "ClawK Talk",
                    status: conversationManager.gatewayWebSocket.isConnected
                        ? .connected : .disconnected
                )
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)

            DSDivider()

            // State indicator
            TalkStateIndicator(
                state: conversationManager.state,
                audioLevels: conversationManager.audioEngine.recentLevels
            )
            .frame(height: 100)
            .padding(.vertical, Spacing.md)

            // Live user transcript
            if !conversationManager.userTranscript.isEmpty
                && conversationManager.state == .listening
            {
                Text(conversationManager.userTranscript)
                    .font(.ClawK.body)
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.backgroundLight)
                    .cornerRadius(Spacing.md)
                    .padding(.horizontal, Spacing.xl)
            }

            // Claude response — Bug 8 fix: only show during thinking/speaking
            if !conversationManager.claudeResponse.isEmpty
                && (conversationManager.state == .thinking
                    || conversationManager.state == .speaking)
            {
                Text(conversationManager.claudeResponse)
                    .font(.ClawK.body)
                    .padding(Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.backgroundLight)
                    .cornerRadius(Spacing.md)
                    .padding(.horizontal, Spacing.xl)
                    .lineLimit(8)
            }

            // Error
            if let error = conversationManager.errorMessage {
                Text(error)
                    .font(.ClawK.caption)
                    .foregroundColor(Color.Semantic.error)
                    .padding(.horizontal, Spacing.xl)
            }

            Spacer()

            // Conversation history (compact)
            ScrollView {
                VStack(spacing: Spacing.sm) {
                    ForEach(conversationManager.messages.suffix(10)) { message in
                        HStack(alignment: .top) {
                            if message.role == .assistant {
                                Text("\u{1F99E}")
                                    .font(.caption)
                            }
                            Text(message.text)
                                .font(.ClawK.caption)
                                .lineLimit(3)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: message.role == .user
                                        ? .trailing : .leading
                                )
                            if message.role == .user {
                                Image(systemName: "person.fill")
                                    .font(.caption2)
                                    .foregroundColor(Color.Semantic.success)
                            }
                        }
                        .padding(.horizontal, Spacing.sm)
                    }
                }
            }
            .padding(.horizontal, Spacing.md)

            DSDivider()

            // Control button
            TalkControlButton(state: conversationManager.state) {
                conversationManager.toggleListening()
            }
            .padding(Spacing.xl)
        }
    }
}
