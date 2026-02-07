//
//  DSEmptyState.swift
//  ClawK
//
//  Standardized empty state components
//  Part of Design System - Round 11
//

import SwiftUI

// MARK: - Standard Empty State (already in DesignSystem.swift)
// This file provides specialized variants

// MARK: - No Data Empty State

struct DSNoDataState: View {
    let title: String
    var subtitle: String? = nil
    var icon: String = "tray"
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text(title)
                .font(.headline)
                .foregroundColor(.secondary)
            
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(Color.Text.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.empty)
    }
}

// MARK: - Loading State

struct DSLoadingState: View {
    var message: String = "Loading..."
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            ProgressView()
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }
}

// MARK: - Error State

struct DSErrorState: View {
    let message: String
    var retryAction: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(Color.Semantic.error)
            
            Text("Something went wrong")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            if let retryAction = retryAction {
                Button(action: retryAction) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Try Again")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.empty)
    }
}

// MARK: - No Search Results

struct DSNoSearchResults: View {
    let query: String
    var suggestions: [String]? = nil
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text("No results for \"\(query)\"")
                .font(.headline)
                .foregroundColor(.secondary)
            
            if let suggestions = suggestions, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Try searching for:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ForEach(suggestions, id: \.self) { suggestion in
                        Text("• \(suggestion)")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.empty)
    }
}

// MARK: - No Sessions

struct DSNoSessionsState: View {
    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
                Text("No active sessions")
                    .foregroundColor(.secondary)
            }
            Text("Start a conversation with your OpenClaw agent to see sessions here.")
                .font(.ClawK.captionSmall)
                .foregroundColor(Color.Text.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Spacing.md)
    }
}

// MARK: - No Crons

struct DSNoCronsState: View {
    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(.secondary)
                Text("No scheduled jobs")
                    .foregroundColor(.secondary)
            }
            Text("Create cron jobs in your OpenClaw config or via your agent.")
                .font(.ClawK.captionSmall)
                .foregroundColor(Color.Text.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Spacing.md)
    }
}

// MARK: - No Subagents

struct DSNoSubagentsState: View {
    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "person.2.slash")
                    .foregroundColor(.secondary)
                Text("No active subagents")
                    .foregroundColor(.secondary)
            }
            Text("Subagents appear here when your agent spawns background tasks.")
                .font(.ClawK.captionSmall)
                .foregroundColor(Color.Text.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Spacing.md)
    }
}

// MARK: - No Activity

struct DSNoActivityState: View {
    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "clock.badge.questionmark")
                    .foregroundColor(.secondary)
                Text("No recent activity")
                    .foregroundColor(.secondary)
            }
            Text("Cron job runs and their results will appear here.")
                .font(.ClawK.captionSmall)
                .foregroundColor(Color.Text.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Spacing.md)
    }
}

// MARK: - Gateway Unreachable State

struct DSGatewayUnreachableState: View {
    let gatewayURL: String
    var onRetry: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundColor(Color.Semantic.warning)
            
            Text("Gateway Unreachable")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Can't reach the OpenClaw gateway at \(gatewayURL).\nMake sure it's running.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if let onRetry = onRetry {
                Button(action: onRetry) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.empty)
    }
}

// MARK: - No Heartbeat Data State

struct DSNoHeartbeatState: View {
    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack {
                Image(systemName: "heart.slash")
                    .foregroundColor(.secondary)
                Text("No heartbeat history")
                    .foregroundColor(.secondary)
            }
            Text("Heartbeats will appear after your agent's first check-in.")
                .font(.ClawK.captionSmall)
                .foregroundColor(Color.Text.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, Spacing.md)
    }
}

// MARK: - Select Item Prompt

struct DSSelectItemPrompt: View {
    let icon: String
    let message: String
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(Color.Text.disabled)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(Color.Text.disabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: Spacing.xxl) {
            DSNoDataState(title: "No items", subtitle: "Nothing to show here")
            
            Divider()
            
            DSLoadingState()
            
            Divider()
            
            DSErrorState(message: "Could not connect to server", retryAction: {})
            
            Divider()
            
            DSNoSearchResults(query: "test", suggestions: ["testing", "test case"])
            
            Divider()
            
            VStack {
                DSNoSessionsState()
                DSNoCronsState()
                DSNoSubagentsState()
                DSNoActivityState()
            }
            
            Divider()
            
            DSSelectItemPrompt(icon: "doc.text", message: "Select a file to preview")
                .frame(height: 200)
        }
        .padding()
    }
}
#endif
