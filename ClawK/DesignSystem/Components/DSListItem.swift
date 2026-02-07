//
//  DSListItem.swift
//  ClawK
//
//  Standardized list item components
//  Part of Design System - Round 10
//

import SwiftUI

// MARK: - Session Row

/// Standard session item display
struct DSSessionRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var trailing: String? = nil
    var backgroundColor: Color? = nil
    
    var body: some View {
        HStack(spacing: Spacing.lg) {
            // Icon
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.title2)
            
            // Content
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Trailing
            if let trailing = trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(Spacing.md)
        .background(backgroundColor ?? iconColor.backgroundLight)
        .cornerRadius(Spacing.md)
    }
}

// MARK: - Cron Job Row

/// Standard cron job item display
struct DSCronRow: View {
    let name: String
    let isEnabled: Bool
    var modelName: String? = nil
    var nextRun: Date? = nil
    
    var body: some View {
        HStack(spacing: Spacing.md) {
            // Status indicator
            DSStatusDot(color: isEnabled ? .green : .gray)
            
            // Content
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(name)
                    .font(.body)
                    .lineLimit(1)
                
                if let model = modelName {
                    Text(model)
                        .font(.caption)
                        .foregroundColor(Color.Accent.model)
                }
            }
            
            Spacer()
            
            // Next run
            if let nextRun = nextRun {
                VStack(alignment: .trailing, spacing: Spacing.xxs) {
                    Text(nextRun.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(nextRun.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(Color.Text.tertiary)
                }
            }
        }
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.md)
        .background(Color.Surface.secondary)
        .cornerRadius(Spacing.sm)
    }
}

// MARK: - Activity Row

/// Standard activity/history item display
struct DSActivityRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var subtitle: String? = nil
    var timestamp: Date? = nil
    var showDivider: Bool = true
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.md) {
                // Status icon
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                
                // Content
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(.body)
                        .lineLimit(1)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Timestamp
                if let timestamp = timestamp {
                    Text(timestamp.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, Spacing.xs)
            
            if showDivider {
                Divider()
                    .padding(.top, Spacing.xs)
            }
        }
    }
}

// MARK: - Subagent Row

/// Standard subagent item display
struct DSSubagentRow: View {
    let name: String
    let modelName: String
    let tokenCount: Int
    
    var body: some View {
        HStack {
            DSStatusDot(color: Color.Accent.subagent)
            
            Text(name)
                .font(.body)
                .lineLimit(1)
            
            Spacer()
            
            Text(modelName)
                .font(.caption)
                .foregroundColor(Color.Accent.model)
            
            Text("•")
                .foregroundColor(.secondary)
            
            Text("\(tokenCount.formatted()) tok")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - File Tree Item

/// Standard file tree item display
struct DSFileTreeItem: View {
    let icon: String
    let name: String
    var isSelected: Bool = false
    var isHighlighted: Bool = false
    var tokens: Int? = nil
    var indent: CGFloat = 0
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                Text(name)
                    .font(.system(.body))
                    .lineLimit(1)
                
                Spacer()
                
                if let tokens = tokens {
                    Text("\(tokens.formatted()) tok")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.md)
            .padding(.leading, indent)
            .background(
                RoundedRectangle(cornerRadius: Spacing.sm)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.backgroundMedium
        } else if isHighlighted {
            return Color.Accent.memoryMd.backgroundLight
        }
        return .clear
    }
}

// MARK: - Info Row (Settings style)

struct DSSettingsRow: View {
    let label: String
    let value: String
    var mono: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(mono ? .ClawK.bodyMono : .body)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: Spacing.lg) {
            Text("Session Row").font(.caption)
            DSSessionRow(
                icon: "paperplane.circle.fill",
                iconColor: .blue,
                title: "Telegram DM",
                subtitle: "45K tokens • Sonnet",
                trailing: "2 min ago"
            )
            
            Text("Cron Row").font(.caption)
            DSCronRow(
                name: "Morning Briefing",
                isEnabled: true,
                modelName: "claude-sonnet-4-5",
                nextRun: Date().addingTimeInterval(3600)
            )
            
            Text("Activity Row").font(.caption)
            DSActivityRow(
                icon: "checkmark.circle.fill",
                iconColor: .green,
                title: "Morning Briefing",
                subtitle: "Took 45s",
                timestamp: Date().addingTimeInterval(-3600)
            )
            
            Text("Subagent Row").font(.caption)
            DSSubagentRow(
                name: "Research Agent",
                modelName: "opus",
                tokenCount: 12500
            )
            
            Text("File Tree Item").font(.caption)
            DSFileTreeItem(
                icon: "doc.text",
                name: "MEMORY.md",
                isHighlighted: true,
                tokens: 2500,
                onTap: {}
            )
            
            Text("Settings Row").font(.caption)
            DSSettingsRow(label: "Version", value: "1.0.0", mono: true)
        }
        .padding()
    }
}
#endif
