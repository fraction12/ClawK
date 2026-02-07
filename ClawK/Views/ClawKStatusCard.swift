//
//  ClawKStatusCard.swift
//  ClawK
//
//  Heartbeat Monitor card with timeline graph
//  Round 21: Design system standardization
//

import SwiftUI

// MARK: - Heartbeat Monitor Card

struct ClawKStatusCard: View {
    @EnvironmentObject var appState: AppState
    
    private var status: ClawKStatusState {
        appState.clawkStatus
    }
    
    private var showSkeleton: Bool {
        appState.isInitialLoad && status.lastCheck == nil && status.statusMessage == "Loading..."
    }
    
    private var statusColor: Color {
        switch status.status {
        case .ok: return Color.Semantic.success
        case .alert: return Color.Semantic.warning
        case .critical: return Color.Semantic.error
        case .unknown: return Color.Semantic.neutral
        }
    }
    
    var body: some View {
        DSCard(
            title: "💓 HEARTBEAT MONITOR",
            color: showSkeleton ? Color.Semantic.neutral : statusColor,
            tooltip: "Monitors ClawK heartbeat and memory activity",
            isLoading: showSkeleton
        ) {
            if showSkeleton {
                skeletonContent
            } else {
                cardContent
            }
        }
    }
    
    // MARK: - Main Content
    
    @ViewBuilder
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            statusRow
            DSDivider()
            CustomHeartbeatChart(history: appState.heartbeatHistory)
            DSDivider()
            nextCheckRow
        }
    }
    
    // MARK: - Status Row
    
    private var statusRow: some View {
        HStack(spacing: Spacing.lg) {
            // Status badge
            HStack(spacing: Spacing.sm) {
                Text(status.status.emoji)
                Text(status.statusMessage)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(statusColor.backgroundMedium)
            .foregroundColor(statusColor)
            .cornerRadius(Spacing.md)
            
            Spacer()
            
            // Last check time
            HStack(spacing: Spacing.sm) {
                Text("•")
                    .font(.ClawK.caption)
                    .foregroundColor(.secondary)
                
                if let lastCheck = status.lastCheck {
                    Text(formatTimeAgo(lastCheck))
                        .font(.ClawK.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("—")
                        .font(.ClawK.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Next Check Row
    
    private var nextCheckRow: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Next check:")
                .font(.ClawK.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            if let nextCheck = status.nextCheck {
                let isOverdue = nextCheck.timeIntervalSince(Date()) <= 0
                Text(formatNextIn(nextCheck))
                    .font(.ClawK.numberSmall)
                    .foregroundColor(isOverdue ? Color.Semantic.error : .secondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(isOverdue ? Color.Semantic.error.backgroundLight : Color.secondary.opacity(Color.Opacity.ultraLight))
                    .cornerRadius(Spacing.sm)
            } else {
                Text("—")
                    .font(.ClawK.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Skeleton Content
    
    private var skeletonContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(spacing: Spacing.lg) {
                SkeletonBox(width: 120, height: 28, cornerRadius: Spacing.md)
                Spacer()
                HStack(spacing: Spacing.sm) {
                    Text("•").foregroundColor(.secondary)
                    SkeletonBox(width: 60, height: 14, cornerRadius: Spacing.xs)
                }
            }
            
            DSDivider()
            
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    SkeletonBox(width: 110, height: 12, cornerRadius: Spacing.xxs)
                    Spacer()
                    SkeletonBox(width: 90, height: 12, cornerRadius: Spacing.xxs)
                }
                SkeletonBox(height: 120, cornerRadius: Spacing.md)
            }
            
            DSDivider()
            
            HStack(spacing: Spacing.md) {
                SkeletonCircle(size: 14)
                SkeletonBox(width: 70, height: 12, cornerRadius: Spacing.xxs)
                Spacer()
                SkeletonBox(width: 60, height: 24, cornerRadius: Spacing.sm)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatTimeAgo(_ date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        let seconds = Int(elapsed)
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        
        if seconds < 30 { return "just now" }
        if minutes < 1 { return "just now" }
        if minutes < 60 { return minutes == 1 ? "1 min ago" : "\(minutes) min ago" }
        if hours < 24 { return hours == 1 ? "1 hour ago" : "\(hours) hours ago" }
        if days < 7 { return days == 1 ? "1 day ago" : "\(days) days ago" }
        return "over a week ago"
    }
    
    private func formatNextIn(_ date: Date) -> String {
        let remaining = date.timeIntervalSince(Date())
        
        if remaining <= 0 {
            let overdue = -remaining
            let overdueMin = Int(overdue / 60)
            return overdueMin < 5 ? "now" : "overdue"
        }
        
        let minutes = Int(remaining / 60)
        let hours = minutes / 60
        let mins = minutes % 60
        
        if minutes < 1 { return "< 1 min" }
        if hours < 1 { return "in \(minutes) min" }
        return "in \(hours) hr \(mins) min"
    }
}
