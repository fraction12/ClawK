//
//  MissionControlView.swift
//  ClawK
//
//  Main Mission Control dashboard - Operational focus
//

import SwiftUI

struct MissionControlView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                // Header
                DSPageHeaderWithTime(
                    emoji: "🦞",
                    title: "CLAWK",
                    subtitle: "Mission Control",
                    lastUpdated: appState.lastRefresh
                )
                
                // Main Content Grid
                HStack(alignment: .top, spacing: Spacing.xxl) {
                    // Left Column
                    VStack(spacing: Spacing.xxl) {
                        // Sessions + Agents side by side
                        HStack(alignment: .top, spacing: Spacing.lg) {
                            ActiveNowCard()
                                .frame(maxWidth: .infinity)
                            SubagentsCard()
                                .frame(maxWidth: .infinity)
                        }
                        ClawKStatusCard()  // Heartbeat Monitor card with timeline graph
                        
                        // Crons + Activity side by side
                        HStack(alignment: .top, spacing: Spacing.lg) {
                            UpcomingCronsCard()
                                .frame(maxWidth: .infinity)
                            RecentActivityCard()
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(minWidth: Spacing.Layout.columnMinWidth)
                    
                    // Right Column
                    VStack(spacing: Spacing.xxl) {
                        ModelUsageCard()
                        SystemStatusCard()
                    }
                    .frame(minWidth: Spacing.Layout.columnMinWidth)
                }
            }
            .pagePadding()
        }
        .background(Color.Surface.primary)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    Task { await appState.manualRefresh() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(appState.isManualRefresh ? 360 : 0))
                        .animation(appState.isManualRefresh ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: appState.isManualRefresh)
                }
                .accessibilityLabel("Refresh data")
                .accessibilityHint("Fetches latest status from Gateway")
                .help("Refresh")
                .disabled(appState.isManualRefresh)  // Only disable during manual refresh, not auto-polling
            }
        }
    }
}

// MARK: - Header (Now using DSPageHeaderWithTime from Design System)

// MARK: - Active Now Card

struct ActiveNowCard: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        DSCard(
            title: "⚡ ACTIVE SESSIONS",
            color: Color.CardHeader.activeNow,
            tooltip: "Active conversation sessions (excludes cron jobs and sub-agents). Sorted by most recent activity."
        ) {
            if appState.isInitialLoad && appState.sessions.isEmpty && appState.isConnected {
                // Skeleton loading state (only on initial load when connected)
                VStack(spacing: Spacing.lg) {
                    SkeletonSessionRow()
                    SkeletonSessionRow()
                }
            } else if !appState.isConnected && !appState.isInitialLoad && appState.sessions.isEmpty {
                DSGatewayUnreachableState(
                    gatewayURL: AppConfiguration.shared.gatewayURL,
                    onRetry: {
                        Task { await appState.manualRefresh() }
                    }
                )
            } else if appState.activeMainSessions.isEmpty {
                DSNoSessionsState()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        ForEach(appState.activeMainSessions) { session in
                            DSSessionRow(
                                icon: sessionIcon(for: session.key),
                                iconColor: Color.forSessionType(session.key),
                                title: session.friendlyName,
                                subtitle: "\((session.totalTokens ?? 0).formatted()) tokens • \(session.modelShortName)",
                                trailing: session.lastUpdatedDate?.formatted(.relative(presentation: .named))
                            )
                        }
                    }
                }
            }
        }
        .frame(height: 220)
    }
    
    private func sessionIcon(for key: String) -> String {
        SessionInfo.icon(for: key)
    }
}

// MARK: - Upcoming Crons Card

struct UpcomingCronsCard: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        DSCard(
            title: "📅 UPCOMING CRONS",
            color: Color.CardHeader.upcomingCrons
        ) {
            if appState.isInitialLoad && appState.cronJobs.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonCronRow()
                    }
                }
            } else if appState.upcomingJobs.isEmpty {
                DSNoCronsState()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(appState.upcomingJobs) { job in
                            DSCronRow(
                                name: job.name,
                                isEnabled: job.isEnabled,
                                modelName: job.modelName,
                                nextRun: job.nextRunDate
                            )
                        }
                    }
                }
            }
        }
        .frame(height: 220)
    }
}

// MARK: - Subagents Card

struct SubagentsCard: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        DSCard(
            title: "🤖 ACTIVE SUBAGENTS",
            color: Color.CardHeader.subagents
        ) {
            if appState.isInitialLoad && appState.sessions.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack {
                            SkeletonCircle(size: 8)
                            SkeletonBox(width: 140, height: 14, cornerRadius: 4)
                            Spacer()
                            SkeletonBox(width: 50, height: 12, cornerRadius: 3)
                            SkeletonBox(width: 40, height: 12, cornerRadius: 3)
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                }
            } else if appState.activeSubagents.isEmpty {
                DSNoSubagentsState()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(appState.activeSubagents) { session in
                            DSSubagentRow(
                                name: session.friendlyName,
                                modelName: session.modelShortName,
                                tokenCount: session.totalTokens ?? 0
                            )
                        }
                    }
                }
            }
        }
        .frame(height: 220)
    }
}

// MARK: - Recent Activity Card

struct RecentActivityCard: View {
    @EnvironmentObject var appState: AppState
    
    var recentCronRuns: [CronJob] {
        appState.cronJobs
            .filter { $0.state?.lastRunAtMs != nil }
            .sorted { ($0.state?.lastRunAtMs ?? 0) > ($1.state?.lastRunAtMs ?? 0) }
            .prefix(5)
            .map { $0 }
    }
    
    var body: some View {
        DSCard(
            title: "📜 RECENT ACTIVITY",
            color: Color.CardHeader.recentActivity
        ) {
            if appState.isInitialLoad && appState.cronJobs.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(0..<3, id: \.self) { index in
                        HStack(spacing: Spacing.md) {
                            SkeletonCircle(size: 16)
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                SkeletonBox(width: 120, height: 14, cornerRadius: 4)
                                SkeletonBox(width: 80, height: 10, cornerRadius: 3)
                            }
                            Spacer()
                            SkeletonBox(width: 70, height: 12, cornerRadius: 4)
                        }
                        .padding(.vertical, Spacing.xs)
                        
                        if index < 2 {
                            Divider()
                        }
                    }
                }
            } else if recentCronRuns.isEmpty {
                DSNoActivityState()
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(recentCronRuns) { job in
                            HStack(spacing: 10) {
                                Image(systemName: job.state?.lastStatus == "ok" ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(job.state?.lastStatus == "ok" ? Color.Semantic.success : Color.Semantic.error)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.name)
                                        .font(.system(.body))
                                        .lineLimit(1)
                                    
                                    if let duration = job.state?.lastDurationMs {
                                        Text("Took \(formatDuration(duration))")
                                            .font(.ClawK.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Spacer()
                                
                                if let lastRun = job.lastRunDate {
                                    Text(lastRun.formatted(.relative(presentation: .named)))
                                        .font(.ClawK.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            
                            if job.id != recentCronRuns.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 220)
    }
    
    private func formatDuration(_ ms: Int64) -> String {
        let seconds = ms / 1000
        if seconds >= 60 {
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(seconds)s"
    }
}

// MARK: - Model Usage Card (Universal + Claude-specific)

struct ModelUsageCard: View {
    @EnvironmentObject var appState: AppState
    
    // MARK: - Computed Properties
    
    private var quota: ClaudeMaxQuota? {
        appState.quotaStatus
    }
    
    private var showSkeleton: Bool {
        appState.isInitialLoad && appState.sessions.isEmpty
    }
    
    private var mainSession: SessionInfo? {
        appState.mainSession
    }
    
    private var telegramSession: SessionInfo? {
        appState.telegramSession
    }
    
    /// Derive provider name from model string
    private var activeModelName: String {
        guard let model = mainSession?.model else { return "—" }
        // Strip provider prefix if present (e.g., "anthropic/claude-opus-4-6" → "claude-opus-4-6")
        return model.components(separatedBy: "/").last ?? model
    }
    
    /// Derive provider badge from model name
    private var providerInfo: (name: String, color: Color) {
        guard let model = mainSession?.model?.lowercased() else {
            return ("Unknown", .secondary)
        }
        if model.contains("claude") || model.contains("anthropic") {
            return ("Anthropic", Color.Accent.opus)
        } else if model.contains("gpt") || model.contains("openai") || model.contains("o1") || model.contains("o3") || model.contains("o4") {
            return ("OpenAI", Color.green)
        } else if model.contains("gemini") || model.contains("google") {
            return ("Google", Color.orange)
        } else if model.contains("llama") || model.contains("meta") {
            return ("Meta", Color.blue)
        } else if model.contains("mistral") || model.contains("mixtral") {
            return ("Mistral", Color.orange)
        } else if model.contains("local") || model.contains("ollama") {
            return ("Local", Color.gray)
        }
        return ("AI", Color.purple)
    }
    
    /// Whether current model is Claude (show Claude-specific quota section)
    private var isClaudeModel: Bool {
        guard let model = mainSession?.model else { return false }
        return model.lowercased().contains("claude")
    }
    
    /// Sum of totalTokens across all sessions updated today
    private var totalContextTokens: Int {
        return appState.sessions
            .reduce(0) { $0 + ($1.totalTokens ?? 0) }
    }
    
    /// Sessions updated in last 30 minutes
    private var recentlyActiveSessions: Int {
        let cutoff = Date().addingTimeInterval(-30 * 60)
        return appState.sessions.filter { session in
            guard let updatedAt = session.updatedAt else { return false }
            let sessionDate = Date(timeIntervalSince1970: Double(updatedAt) / 1000)
            return sessionDate >= cutoff
        }.count
    }
    
    var body: some View {
        DSCard(
            title: "📊 MODEL USAGE",
            color: Color.CardHeader.modelUsage,
            tooltip: "Active model info, token usage, and context utilization across all providers."
        ) {
            if showSkeleton {
                SkeletonQuotaContent()
            } else {
                cardContent
            }
        }
    }
    
    // MARK: - Card Content
    
    @ViewBuilder
    private var cardContent: some View {
        VStack(spacing: 16) {
            // === UNIVERSAL SECTION (all providers) ===
            
            // Row 1: Active Model + Provider Badge
            activeModelRow
            
            Divider()
            
            // Row 2: Token Usage Today
            tokenUsageTodayRow
            
            Divider()
            
            // Row 3: Context Utilization
            contextUtilizationSection
            
            Divider()
            
            // Row 4: Active Sessions
            activeSessionsRow
            
            // === CLAUDE-SPECIFIC SECTION (conditional) ===
            if isClaudeModel, let quota = quota, quota.hasData {
                Divider()
                    .padding(.vertical, 4)
                
                claudeQuotaSection(quota: quota)
            }
        }
    }
    
    // MARK: - Row 1: Active Model
    
    @ViewBuilder
    private var activeModelRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Active Model")
                    .font(.ClawK.caption)
                    .foregroundColor(.secondary)
                
                Text(activeModelName)
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Provider badge
            HStack(spacing: 4) {
                Circle()
                    .fill(providerInfo.color)
                    .frame(width: 6, height: 6)
                Text(providerInfo.name)
                    .font(.ClawK.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(providerInfo.color.backgroundMedium)
            .foregroundColor(providerInfo.color)
            .cornerRadius(6)
        }
    }
    
    // MARK: - Row 2: Total Context Tokens
    
    @ViewBuilder
    private var tokenUsageTodayRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.ClawK.caption)
                    .foregroundColor(Color.Accent.quota)
                Text("Total Context Tokens")
                    .font(.ClawK.label)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(totalContextTokens.formattedTokens + " tokens")
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
        }
    }
    
    // MARK: - Row 3: Context Utilization
    
    @ViewBuilder
    private var contextUtilizationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Context Utilization")
                .font(.ClawK.caption)
                .foregroundColor(.secondary)
            
            // Main session context bar
            if let session = mainSession {
                contextBar(
                    label: "Main",
                    session: session
                )
            }
            
            // Telegram session context bar (if different from main)
            if let telegram = telegramSession, telegram.sessionId != mainSession?.sessionId {
                contextBar(
                    label: "Telegram",
                    session: telegram
                )
            }
            
            // Show a placeholder if no sessions
            if mainSession == nil && telegramSession == nil {
                HStack {
                    Image(systemName: "tray")
                        .foregroundColor(.secondary)
                    Text("No active sessions")
                        .font(.ClawK.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private func contextBar(label: String, session: SessionInfo) -> some View {
        let maxTokens = appState.contextWindow(for: session.model)
        let used = session.totalTokens ?? 0
        let percent = maxTokens > 0 ? (Double(used) / Double(maxTokens)) * 100 : 0
        
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.ClawK.label)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)
                
                Spacer()
                
                Text("\(used.formattedTokens) / \(maxTokens.formattedTokens)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Text(String(format: "(%.0f%%)", percent))
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundColor(Color.Progress.forPercent(percent))
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.Border.normal)
                        .frame(height: 6)
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.Progress.forPercent(percent))
                        .frame(width: geo.size.width * CGFloat(min(percent, 100) / 100), height: 6)
                }
            }
            .frame(height: 6)
        }
    }
    
    // MARK: - Row 4: Active Sessions
    
    @ViewBuilder
    private var activeSessionsRow: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.ClawK.caption)
                    .foregroundColor(Color.Semantic.info)
                Text("Sessions")
                    .font(.ClawK.label)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Text("\(recentlyActiveSessions)")
                    .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                    .foregroundColor(recentlyActiveSessions > 0 ? Color.Semantic.success : .secondary)
                Text("active")
                    .font(.ClawK.caption)
                    .foregroundColor(.secondary)
                Text("/ \(appState.sessions.count) total")
                    .font(.ClawK.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Claude-Specific Quota Section
    
    @ViewBuilder
    private func claudeQuotaSection(quota: ClaudeMaxQuota) -> some View {
        VStack(spacing: 12) {
            // Section header
            HStack {
                HStack(spacing: 6) {
                    Text("🅲")
                        .font(.ClawK.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.Accent.opus)
                        .cornerRadius(4)
                    
                    Text("Claude Quota")
                        .font(.ClawK.label)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                // Data source + Plan badges
                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Text(quota.dataSource.icon)
                            .font(.ClawK.captionSmall)
                        Text(quota.dataSource.description)
                            .font(.ClawK.captionSmall)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(claudeDataSourceColor.opacity(0.15))
                    .cornerRadius(4)
                    
                    if let planType = quota.planType {
                        Text(planType.capitalized)
                            .font(.ClawK.captionSmall)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.Accent.model.backgroundMedium)
                            .foregroundColor(Color.Accent.model)
                            .cornerRadius(4)
                    }
                }
            }
            
            if quota.hasPercentageData {
                claudePercentageView(quota: quota)
            } else {
                claudeTokenView(quota: quota)
            }
            
            // Refresh button
            HStack {
                if quota.isStale {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.ClawK.captionSmall)
                        Text("Stale")
                            .font(.ClawK.captionSmall)
                    }
                    .foregroundColor(Color.Semantic.stale)
                }
                
                Spacer()
                
                Button(action: {
                    Task { await appState.forceRefreshQuota() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.ClawK.captionSmall)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(10)
        .background(Color.Accent.opus.opacity(0.04))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.Accent.opus.opacity(0.12), lineWidth: 1)
        )
    }
    
    private var claudeDataSourceColor: Color {
        guard let quota = quota else { return Color.Semantic.neutral }
        switch quota.dataSource {
        case .claudeDesktopApp: return Color.Semantic.success
        case .localFiles: return Color.Semantic.info
        case .none: return Color.Semantic.neutral
        }
    }
    
    // MARK: - Claude Percentage-Based View (Desktop App API)
    
    @ViewBuilder
    private func claudePercentageView(quota: ClaudeMaxQuota) -> some View {
        VStack(spacing: 12) {
            // Session Window (5-hour)
            claudeWindowRow(
                window: quota.sessionWindow,
                title: "Session (5h)",
                titleColor: .secondary,
                showPace: false
            )
            
            // Weekly Window (7-day)
            claudeWindowRow(
                window: quota.weeklyWindow,
                title: "Weekly (7d)",
                titleColor: .secondary,
                showPace: true
            )
            
            // Model-specific windows
            if let opusWindow = quota.weeklyOpusWindow, opusWindow.percentUsed > 0 {
                claudeWindowRow(
                    window: opusWindow,
                    title: "🔷 Opus",
                    titleColor: Color.Accent.opus,
                    showPace: true,
                    barHeight: 5
                )
            }
            
            if let sonnetWindow = quota.weeklySonnetWindow, sonnetWindow.percentUsed > 0 {
                claudeWindowRow(
                    window: sonnetWindow,
                    title: "✨ Sonnet",
                    titleColor: Color.Accent.sonnet,
                    showPace: true,
                    barHeight: 5
                )
            }
        }
    }
    
    @ViewBuilder
    private func claudeWindowRow(
        window: QuotaWindow,
        title: String,
        titleColor: Color,
        showPace: Bool,
        barHeight: CGFloat = 6
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.ClawK.captionSmall)
                    .foregroundColor(titleColor)
                Spacer()
                Text(window.percentFormatted)
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
                    .foregroundColor(claudePaceAwareColor(window: window))
                if window.resetsAt != nil {
                    Text("• \(window.resetFormatted)")
                        .font(.ClawK.captionSmall)
                        .foregroundColor(.secondary)
                }
            }
            
            QuotaProgressBar(
                percent: Int(window.percentUsed),
                color: claudePaceAwareColor(window: window),
                height: barHeight
            )
            
            // Pace indicator (compact)
            if showPace && window.shouldShowPace, let pace = window.pace {
                let status = window.paceStatus
                HStack(spacing: 4) {
                    Text(status.icon)
                        .font(.ClawK.captionSmall)
                    Text("\(Int(pace))% pace")
                        .font(.ClawK.captionSmall)
                        .foregroundColor(status.color)
                    Text("(\(status.rawValue))")
                        .font(.ClawK.captionSmall)
                        .foregroundColor(status.color.opacity(0.7))
                }
            }
        }
    }
    
    private func claudePaceAwareColor(window: QuotaWindow) -> Color {
        if window.percentUsed >= 100 { return Color.Progress.high }
        if window.shouldShowPace { return window.paceStatus.color }
        return Color.Progress.forPercent(window.percentUsed)
    }
    
    // MARK: - Claude Token-Based View (CLI local files)
    
    @ViewBuilder
    private func claudeTokenView(quota: ClaudeMaxQuota) -> some View {
        VStack(spacing: 10) {
            // Total tokens
            HStack {
                Text("CLI Tokens (7d)")
                    .font(.ClawK.captionSmall)
                    .foregroundColor(.secondary)
                Spacer()
                Text(TokensByModel.format(quota.totalTokensUsed))
                    .font(.system(.caption, design: .monospaced, weight: .semibold))
            }
            
            // Model breakdown (compact)
            HStack(spacing: 8) {
                ModelTokenBadge(emoji: "✨", name: "Sonnet", tokens: quota.tokensByModel.sonnet, color: Color.Accent.sonnet)
                ModelTokenBadge(emoji: "🔷", name: "Opus", tokens: quota.tokensByModel.opus, color: Color.Accent.opus)
                ModelTokenBadge(emoji: "⚡", name: "Haiku", tokens: quota.tokensByModel.haiku, color: Color.Accent.haiku)
            }
        }
    }
}

// MARK: - Model Token Badge

struct ModelTokenBadge: View {
    let emoji: String
    let name: String
    let tokens: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Text(emoji)
                    .font(.ClawK.captionSmall)
                Text(name)
                    .font(.ClawK.captionSmall)
                    .foregroundColor(.secondary)
            }
            
            Text(TokensByModel.format(tokens))
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundColor(tokens > 0 ? color : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(tokens > 0 ? color.backgroundLight : Color.Semantic.neutral.opacity(Color.Opacity.ultraLight))
        .cornerRadius(6)
    }
}

// MARK: - Quota Progress Bar

struct QuotaProgressBar: View {
    let percent: Int
    let color: Color
    var height: CGFloat = 8
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.Border.normal)
                    .frame(height: height)
                
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(percent, 100)) / 100, height: height)
            }
        }
        .frame(height: height)
    }
}

// MARK: - System Status Card (NEW)

struct SystemStatusCard: View {
    @EnvironmentObject var appState: AppState
    
    private var status: SystemStatus {
        appState.systemStatus
    }
    
    private var showSkeleton: Bool {
        appState.isInitialLoad && status.lastHealthCheck == nil
    }
    
    var body: some View {
        DSCard(
            title: "🖥️ SYSTEM STATUS",
            color: Color.CardHeader.systemStatus
        ) {
            if showSkeleton {
                // Skeleton loading state
                VStack(spacing: 12) {
                    // Gateway row
                    HStack {
                        SkeletonCircle(size: 16)
                        SkeletonBox(width: 60, height: 14, cornerRadius: 4)
                        Spacer()
                        SkeletonBox(width: 90, height: 14, cornerRadius: 4)
                    }
                    
                    Divider()
                    
                    // Nodes row
                    HStack {
                        SkeletonCircle(size: 16)
                        SkeletonBox(width: 50, height: 14, cornerRadius: 4)
                        Spacer()
                        SkeletonBox(width: 100, height: 14, cornerRadius: 4)
                    }
                    
                    Divider()
                    
                    // Last Activity row
                    HStack {
                        SkeletonCircle(size: 16)
                        SkeletonBox(width: 80, height: 14, cornerRadius: 4)
                        Spacer()
                        SkeletonBox(width: 60, height: 14, cornerRadius: 4)
                    }
                    
                    // Last check row
                    HStack {
                        SkeletonBox(width: 70, height: 12, cornerRadius: 3)
                        Spacer()
                        SkeletonBox(width: 80, height: 12, cornerRadius: 3)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    // Gateway
                    HStack {
                    Image(systemName: "network")
                        .foregroundColor(Color.Accent.system)
                    Text("Gateway")
                    Spacer()
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(status.gatewayConnected ? Color.Semantic.connected : Color.Semantic.disconnected)
                            .frame(width: 8, height: 8)
                        Text(status.gatewayConnected ? "Connected" : "Disconnected")
                            .font(.ClawK.label)
                    }
                    
                    if let latency = status.gatewayLatencyMs {
                        Text("(\(latency)ms)")
                            .font(.ClawK.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Nodes
                HStack {
                    Image(systemName: "iphone.homebutton")
                        .foregroundColor(Color.Accent.system)
                    Text("Nodes")
                    Spacer()
                    
                    if status.nodeCount > 0 {
                        Text("\(status.connectedNodes)/\(status.nodeCount) connected")
                            .font(.ClawK.label)
                    } else {
                        Text("No nodes")
                            .font(.ClawK.label)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                // Last Activity (relabeled from Uptime - shows time since last session update)
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(Color.Accent.system)
                    Text("Last Activity")
                    Spacer()
                    
                    Text(status.lastActivityFormatted)
                        .font(.system(.subheadline, design: .monospaced))
                }
                .help("Time since last session activity (not actual system uptime)")
                
                // Last health check
                if let lastCheck = status.lastHealthCheck {
                    HStack {
                        Text("Last check:")
                            .font(.ClawK.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(lastCheck.formatted(.relative(presentation: .named)))
                            .font(.ClawK.caption)
                            .foregroundColor(.secondary)
                    }
                }
                }
            }
        }
    }
}

// Preview removed for SPM compatibility
