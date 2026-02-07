//
//  DSHeader.swift
//  ClawK
//
//  Standardized page header component
//  Part of Design System - Round 7
//

import SwiftUI

// MARK: - Page Header

/// Standard page header used at the top of each main view.
/// Replaces HeaderView, MemoryHeaderView, SettingsHeaderView, etc.
struct DSPageHeader: View {
    let emoji: String
    let title: String
    let subtitle: String
    var trailing: AnyView? = nil
    
    var body: some View {
        HStack {
            HStack(spacing: Spacing.Header.iconSpacing) {
                Text(emoji)
                    .font(.ClawK.displayEmoji)
                
                VStack(alignment: .leading, spacing: Spacing.Header.titleSpacing) {
                    Text(title)
                        .pageTitle()
                    
                    Text(subtitle)
                        .pageSubtitle()
                }
            }
            
            Spacer()
            
            if let trailing = trailing {
                trailing
            }
        }
        .padding(.bottom, Spacing.Header.bottomMargin)
    }
}

// MARK: - Header with Timestamp

struct DSPageHeaderWithTime: View {
    let emoji: String
    let title: String
    let subtitle: String
    var lastUpdated: Date? = nil
    
    var body: some View {
        DSPageHeader(
            emoji: emoji,
            title: title,
            subtitle: subtitle,
            trailing: lastUpdated.map { date in
                AnyView(
                    Text("Updated \(date.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                )
            }
        )
    }
}

// MARK: - Header with Controls

struct DSPageHeaderWithControls<Controls: View>: View {
    let emoji: String
    let title: String
    let subtitle: String
    @ViewBuilder let controls: () -> Controls
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Title row
            DSPageHeader(
                emoji: emoji,
                title: title,
                subtitle: subtitle
            )
            
            // Controls row
            controls()
        }
        .padding(.bottom, Spacing.Header.bottomMargin)
    }
}

// MARK: - Section Header

/// Smaller header for sections within a view
struct DSSectionHeader: View {
    let title: String
    var icon: String? = nil
    var color: Color = .secondary
    var trailing: AnyView? = nil
    
    var body: some View {
        HStack {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
            }
            
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color)
            
            Spacer()
            
            if let trailing = trailing {
                trailing
            }
        }
    }
}

// MARK: - Card Section Header (within cards)

struct DSCardSectionHeader: View {
    let title: String
    var action: (() -> Void)? = nil
    var actionLabel: String = "See All"
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if let action = action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Mini Header (for popover/compact views)

struct DSMiniHeader: View {
    let emoji: String
    let title: String
    var status: ConnectionStatus = .unknown
    
    enum ConnectionStatus {
        case connected
        case disconnected
        case unknown
        
        var color: Color {
            switch self {
            case .connected: return .green
            case .disconnected: return .red
            case .unknown: return .gray
            }
        }
    }
    
    var body: some View {
        HStack {
            Text(emoji)
                .font(.title2)
            
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
            
            Spacer()
            
            if status != .unknown {
                DSStatusDot(color: status.color)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(spacing: Spacing.xxl) {
        DSPageHeader(
            emoji: "🦞",
            title: "CLAWK",
            subtitle: "Mission Control"
        )
        
        DSPageHeaderWithTime(
            emoji: "🧠",
            title: "MEMORY",
            subtitle: "Memory system browser",
            lastUpdated: Date()
        )
        
        Divider()
        
        DSSectionHeader(title: "Active Sessions", icon: "bolt.fill", color: .orange)
        
        Divider()
        
        DSMiniHeader(emoji: "🦞", title: "CLAWK", status: .connected)
    }
    .padding()
}
#endif
