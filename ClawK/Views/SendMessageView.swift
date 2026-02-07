//
//  SendMessageView.swift
//  ClawK
//
//  Send message to ClawK overlay
//

import SwiftUI

struct SendMessageView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var messageText = ""
    @State private var isSending = false
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "paperplane.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                Text("Send to ClawK")
                    .font(.headline)
                
                Spacer()
                
                if let session = appState.mainSession {
                    Text(session.sessionDisplayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Message Input
            VStack(spacing: 12) {
                TextEditor(text: $messageText)
                    .font(.body)
                    .focused($isTextFieldFocused)
                    .frame(minHeight: 100, maxHeight: 200)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        Group {
                            if messageText.isEmpty {
                                Text("Type your message...")
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 12)
                                    .padding(.top, 16)
                            }
                        },
                        alignment: .topLeading
                    )
                
                // Error message
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
                
                // Success message
                if showSuccess {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Message sent!")
                            .font(.caption)
                            .foregroundColor(.green)
                        Spacer()
                    }
                }
            }
            .padding(16)
            
            Divider()
            
            // Footer with actions
            HStack(spacing: 12) {
                // Keyboard hint
                HStack(spacing: 4) {
                    Text("⌘↵")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(3)
                    Text("Send")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    Text("esc")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(3)
                    Text("Close")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Button(action: sendMessage) {
                    if isSending {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 60)
                    } else {
                        Text("Send")
                            .frame(width: 60)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .keyboardShortcut(.return, modifiers: .command)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            isTextFieldFocused = true
        }
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isSending = true
        errorMessage = nil
        
        Task {
            do {
                try await appState.sendMessage(messageText)
                showSuccess = true
                
                // Auto-dismiss after success
                try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
                isPresented = false
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}

// MARK: - Session Helper

extension SessionInfo {
    var sessionDisplayName: String {
        // Use existing displayName if available
        if let name = displayName, !name.isEmpty {
            return name
        }
        // Fallback to computed name from key
        if key.contains(":main") {
            return "Main Session"
        } else if key.contains("subagent") {
            return "Subagent"
        } else if key.contains("cron") {
            return "Cron Session"
        }
        return key
    }
}

// MARK: - Notification

extension Notification.Name {
    static let showSendMessage = Notification.Name("showSendMessage")
}
