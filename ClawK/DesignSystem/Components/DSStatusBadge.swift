//
//  DSStatusBadge.swift
//  ClawK
//
//  Standardized status indicators and badges
//  Part of Design System - Round 8
//

import SwiftUI

// MARK: - Connection Status Badge

/// Shows connection status with dot and label
struct DSConnectionBadge: View {
    let isConnected: Bool
    var showLabel: Bool = true
    var connectedLabel: String = "Connected"
    var disconnectedLabel: String = "Disconnected"
    
    private var color: Color {
        isConnected ? Color.Semantic.connected : Color.Semantic.disconnected
    }
    
    private var label: String {
        isConnected ? connectedLabel : disconnectedLabel
    }
    
    var body: some View {
        HStack(spacing: Spacing.StatusIndicator.spacing) {
            DSStatusDot(color: color)
            
            if showLabel {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(color)
            }
        }
    }
}

// MARK: - Custom Badge

/// Shows custom status with optional icon
struct DSCustomBadge: View {
    let label: String
    let color: Color
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(color)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(color.backgroundMedium)
        .cornerRadius(Spacing.Badge.cornerRadius)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: Spacing.lg) {
        Text("Connection").font(.caption).foregroundColor(.secondary)
        HStack {
            DSConnectionBadge(isConnected: true)
            DSConnectionBadge(isConnected: false)
        }
        
        Divider()
        
        Text("Custom").font(.caption).foregroundColor(.secondary)
        HStack {
            DSCustomBadge(label: "Custom", color: .orange, icon: "star.fill")
        }
    }
    .padding()
}
#endif
