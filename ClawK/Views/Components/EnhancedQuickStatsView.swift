//
//  EnhancedQuickStatsView.swift
//  ClawK
//
//  Enhanced popover view with health status, telegram session, quota tracking
//  and quick action buttons - "Mission Control Mini"
//

import SwiftUI

struct EnhancedQuickStatsView: View {
    @EnvironmentObject var appState: AppState
    var onOpenWindow: (() -> Void)?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with health badge
            headerSection
            
            Divider()
                .padding(.vertical, 2)
            
            // Telegram Session Context
            telegramSessionSection
            
            // Claude Max Quota (if available)
            if let quota = appState.quotaStatus, quota.hasData {
                quotaSection(quota: quota)
            }
            
            // Active Work
            activeWorkSection
            
            Divider()
                .padding(.vertical, 2)
            
            // Quick Action Buttons
            quickActionsSection
            
            // Last Updated
            footerSection
        }
        .padding(12)
        .frame(width: 280)
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        HStack {
            Text("🦞")
                .font(.title2)
            Text("CLAWK")
                .font(.system(size: 14, weight: .bold, design: .rounded))
            
            Spacer()
            
            healthBadge
        }
    }
    
    private var healthBadge: some View {
        let status = computeHealthStatus()
        return HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(status.text)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(status.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.15))
        .cornerRadius(12)
    }
    
    // MARK: - Telegram Session Section
    
    private var telegramSessionSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.blue)
                Text("Telegram Session")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            if let session = appState.telegramSession {
                let contextWindow = appState.contextWindow(for: session.model)
                let percent = Double(session.totalTokens ?? 0) / Double(contextWindow) * 100
                let usedStr = formatTokens(session.totalTokens ?? 0)
                let totalStr = formatTokens(contextWindow)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(usedStr)/\(totalStr)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        Text("(\(Int(percent))%)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(colorForPercent(percent))
                        
                        Spacer()
                        
                        // Model badge
                        Text(session.modelShortName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .cornerRadius(4)
                    }
                    
                    // Progress bar
                    ProgressBarView(percent: percent, height: 6)
                }
            } else {
                Text("Not connected")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Quota Section
    
    private func quotaSection(quota: ClaudeMaxQuota) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                Text("Claude Max Quota")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            HStack(spacing: 12) {
                // Session Window (5h)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Session")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(quota.sessionWindow.percentUsed))%")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(colorForPercent(quota.sessionWindow.percentUsed))
                    }
                    ProgressBarView(percent: quota.sessionWindow.percentUsed, height: 4)
                }
                .frame(maxWidth: .infinity)
                
                // Weekly Window (7d)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Weekly")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(quota.weeklyWindow.percentUsed))%")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(colorForPercent(quota.weeklyWindow.percentUsed))
                    }
                    ProgressBarView(percent: quota.weeklyWindow.percentUsed, height: 4)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Active Work Section
    
    private var activeWorkSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.yellow)
                Text("Active Work")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
            }
            
            HStack(spacing: 16) {
                // Subagents
                HStack(spacing: 4) {
                    Text("🤖")
                        .font(.system(size: 10))
                    Text("\(appState.activeSubagents.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Text("subagents")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                // Crons
                HStack(spacing: 4) {
                    Text("⏰")
                        .font(.system(size: 10))
                    Text("\(appState.cronJobs.filter { $0.isEnabled }.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Text("crons")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Quick Actions Section
    
    private var quickActionsSection: some View {
        HStack(spacing: 8) {
            // Monochrome toggle
            PopoverActionButton(
                icon: appState.isMonochrome ? "circle.fill" : "paintpalette.fill",
                label: appState.isMonochrome ? "Mono" : "Color",
                isActive: appState.isMonochrome,
                action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        appState.isMonochrome.toggle()
                    }
                }
            )
            .frame(maxWidth: .infinity)
            
            // Open Mission Control
            PopoverActionButton(
                icon: "rectangle.expand.vertical",
                label: "Open",
                action: {
                    onOpenWindow?()
                }
            )
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Footer Section
    
    private var footerSection: some View {
        HStack {
            if let lastRefresh = appState.lastRefresh {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text("Updated \(lastRefresh.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Connection indicator
            Circle()
                .fill(appState.isConnected ? Color.green : Color.red)
                .frame(width: 6, height: 6)
        }
    }
    
    // MARK: - Health Status Computation
    
    private struct HealthStatus {
        let text: String
        let color: Color
    }
    
    private func computeHealthStatus() -> HealthStatus {
        // Check telegram session context usage
        var contextPercent: Double = 0
        if let session = appState.telegramSession {
            let contextWindow = appState.contextWindow(for: session.model)
            contextPercent = Double(session.totalTokens ?? 0) / Double(contextWindow) * 100
        }
        
        // Check quota usage
        var sessionQuotaPercent: Double = 0
        var weeklyQuotaPercent: Double = 0
        if let quota = appState.quotaStatus {
            sessionQuotaPercent = quota.sessionWindow.percentUsed
            weeklyQuotaPercent = quota.weeklyWindow.percentUsed
        }
        
        // Determine health status
        // Critical: context >70% OR quota >90%
        if contextPercent > 70 || sessionQuotaPercent > 90 || weeklyQuotaPercent > 90 {
            return HealthStatus(text: "Critical", color: .red)
        }
        
        // Pressure: context >60% OR quota >70%
        if contextPercent > 60 || sessionQuotaPercent > 70 || weeklyQuotaPercent > 70 {
            return HealthStatus(text: "Pressure", color: .orange)
        }
        
        // Nominal
        return HealthStatus(text: "Nominal", color: .green)
    }
    
    // MARK: - Helpers
    
    private func formatTokens(_ count: Int) -> String {
        count.formattedTokens
    }
    
    private func colorForPercent(_ percent: Double) -> Color {
        if percent >= 80 { return .red }
        if percent >= 60 { return .orange }
        return .green
    }
}

// MARK: - Progress Bar Component

struct ProgressBarView: View {
    let percent: Double
    var height: CGFloat = 6
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.secondary.opacity(0.2))
                
                // Fill
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(fillColor)
                    .frame(width: max(0, geometry.size.width * min(percent, 100) / 100))
            }
        }
        .frame(height: height)
    }
    
    private var fillColor: Color {
        if percent >= 80 { return .red }
        if percent >= 60 { return .orange }
        return .green
    }
}

// MARK: - Popover Action Button Component

struct PopoverActionButton: View {
    let icon: String
    let label: String
    var isActive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isActive ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? Color.blue : Color.secondary.opacity(0.15))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
struct EnhancedQuickStatsView_Previews: PreviewProvider {
    static var previews: some View {
        EnhancedQuickStatsView()
            .environmentObject(AppState())
    }
}
#endif
