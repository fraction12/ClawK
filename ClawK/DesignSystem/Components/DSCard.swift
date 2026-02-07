//
//  DSCard.swift
//  ClawK
//
//  Standardized card component
//  Part of Design System - Round 6
//

import SwiftUI

// MARK: - Standard Dashboard Card

/// Primary card component used throughout the app.
/// Replaces the ad-hoc DashboardCard implementations.
struct DSCard<Content: View>: View {
    let title: String
    let color: Color
    var tooltip: String? = nil
    var isLoading: Bool = false
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.Card.contentSpacing) {
            // Header
            DSCardHeader(
                title: title,
                color: color,
                tooltip: tooltip
            )
            
            // Content with loading overlay
            ZStack {
                content()
                    .opacity(isLoading ? 0.3 : 1)
                
                if isLoading {
                    ProgressView()
                }
            }
        }
        .cardPadding()
        .cardBackground()
    }
}

// MARK: - Card Header

struct DSCardHeader: View {
    let title: String
    let color: Color
    var tooltip: String? = nil
    var trailing: AnyView? = nil
    
    var body: some View {
        HStack {
            Text(title)
                .cardHeaderTitle(color)
            
            if let tooltip = tooltip {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .help(tooltip)
            }
            
            Spacer()
            
            if let trailing = trailing {
                trailing
            }
        }
    }
}

// MARK: - Card Variants

/// Compact card for smaller contexts
struct DSCardCompact<Content: View>: View {
    let title: String
    let color: Color
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .font(.ClawK.caption)
                .foregroundColor(color)
            
            content()
        }
        .padding(Spacing.lg)
        .background(Color.Surface.secondary)
        .cornerRadius(Spacing.md)
    }
}

/// Expandable card with disclosure
struct DSCardExpandable<Content: View>: View {
    let title: String
    let color: Color
    @State private var isExpanded: Bool = true
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.Card.contentSpacing) {
            // Header with expand button
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Text(title)
                        .cardHeaderTitle(color)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            // Content
            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardPadding()
        .cardBackground()
    }
}

// MARK: - Section Card (for grouping)

struct DSSectionCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if let title = title {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            content()
        }
        .padding(Spacing.lg)
        .background(Color.Surface.secondary.opacity(0.5))
        .cornerRadius(Spacing.md)
    }
}

// MARK: - Stat Card (for grid layouts)

struct DSStatCard: View {
    let label: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.ClawK.valueLarge)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
        .background(color.backgroundLight)
        .cornerRadius(Spacing.md)
    }
}

// MARK: - Card with Status

struct DSCardWithStatus<Content: View>: View {
    let title: String
    let color: Color
    let status: Status
    @ViewBuilder let content: () -> Content
    
    enum Status {
        case success
        case warning
        case error
        case loading
        case neutral
        case none
        
        var color: Color {
            switch self {
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            case .neutral: return .gray
            case .loading, .none: return .clear
            }
        }
        
        var icon: String? {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            case .neutral: return "minus.circle.fill"
            case .loading, .none: return nil
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.Card.contentSpacing) {
            // Header with status
            HStack {
                Text(title)
                    .cardHeaderTitle(color)
                
                Spacer()
                
                if status == .loading {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if let icon = status.icon {
                    Image(systemName: icon)
                        .foregroundColor(status.color)
                }
            }
            
            content()
        }
        .cardPadding()
        .cardBackground()
        .overlay(
            RoundedRectangle(cornerRadius: Spacing.Card.cornerRadius)
                .stroke(status.color.opacity(status == .none ? 0 : 0.3), lineWidth: 1)
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ScrollView {
        VStack(spacing: Spacing.xxl) {
            DSCard(title: "📊 STANDARD CARD", color: .blue) {
                Text("This is the standard card content")
            }
            
            DSCardCompact(title: "COMPACT", color: .purple) {
                Text("Smaller card")
            }
            
            DSCardExpandable(title: "📁 EXPANDABLE", color: .green) {
                Text("Click the header to collapse")
            }
            
            HStack {
                DSStatCard(label: "Tokens", value: "45K", icon: "number", color: .blue)
                DSStatCard(label: "Sessions", value: "3", icon: "rectangle.stack", color: .orange)
            }
            
            DSCardWithStatus(title: "⚡ STATUS CARD", color: .orange, status: .success) {
                Text("Connected and running")
            }
        }
        .padding()
    }
    .background(Color.Surface.primary)
}
#endif
