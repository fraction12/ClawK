//
//  MemoryVitalsView.swift
//  ClawK
//
//  Memory System Health dashboard - monitoring & maintenance status
//  Round 20: Design system standardization
//

import SwiftUI

struct MemoryVitalsView: View {
    @ObservedObject var viewModel: MemoryViewModel
    @EnvironmentObject var appState: AppState
    @StateObject private var vitalsLoader = MemoryVitalsLoader()
    
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                // Header
                DSPageHeader(
                    emoji: "🧠",
                    title: "Memory Vitals",
                    subtitle: "Memory system health & maintenance",
                    trailing: AnyView(
                        DSRefreshButton(
                            action: { Task { await vitalsLoader.refresh() } },
                            isRefreshing: vitalsLoader.isLoading
                        )
                    )
                )
                
                if vitalsLoader.isLoading && vitalsLoader.contextPressure == nil {
                    LoadingView()
                } else {
                    // Main Content Grid
                    HStack(alignment: .top, spacing: Spacing.xxl) {
                        // Left Column
                        VStack(spacing: Spacing.xxl) {
                            ContextPressureCard(pressure: vitalsLoader.contextPressure ?? .empty, vitalsLoader: vitalsLoader)
                            MemoryFilesStatusCard(files: vitalsLoader.memoryFiles)
                        }
                        .frame(minWidth: Spacing.Layout.columnMinWidth)
                        
                        // Right Column
                        VStack(spacing: Spacing.xxl) {
                            ArchiveHealthCard(health: vitalsLoader.archiveHealth ?? .empty)
                            CurationScheduleCard(schedule: vitalsLoader.curationSchedule ?? .empty)
                            MemoryActivityCard(activity: vitalsLoader.memoryActivity)
                        }
                        .frame(minWidth: Spacing.Layout.columnMinWidth)
                    }
                }
            }
            .pagePadding()
        }
        .background(Color.Surface.primary)
        .task {
            vitalsLoader.appState = appState
            await vitalsLoader.loadInitialData()
        }
        .onChange(of: appState.lastRefresh) { _, newRefresh in
            guard newRefresh != nil else { return }
            
            Task {
                vitalsLoader.updateContextFromAppState()
                
                let now = Date()
                if let lastRefresh = vitalsLoader.lastFullRefresh {
                    if now.timeIntervalSince(lastRefresh) >= 30 {
                        await vitalsLoader.refresh()
                        vitalsLoader.lastFullRefresh = now
                    }
                } else {
                    await vitalsLoader.refresh()
                    vitalsLoader.lastFullRefresh = now
                }
            }
        }
    }
}

// MARK: - Loading View

private struct LoadingView: View {
    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xxl) {
            VStack(spacing: Spacing.xxl) {
                SkeletonContextPressureCard()
                SkeletonMemoryFilesCard()
                SkeletonMemoryActivityCard()
            }
            .frame(minWidth: Spacing.Layout.columnMinWidth)
            
            VStack(spacing: Spacing.xxl) {
                SkeletonArchiveHealthCard()
                SkeletonCurationScheduleCard()
            }
            .frame(minWidth: Spacing.Layout.columnMinWidth)
        }
    }
}

// MARK: - Skeleton Cards

private struct SkeletonContextPressureCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack {
                SkeletonBox(width: 140, height: 20, cornerRadius: Spacing.sm)
                Spacer()
                SkeletonBox(width: 70, height: 24, cornerRadius: Spacing.md)
            }
            SkeletonContextPressureContent()
        }
        .cardPadding()
        .cardBackground()
    }
}

private struct SkeletonMemoryFilesCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SkeletonBox(width: 160, height: 20, cornerRadius: Spacing.sm)
            VStack(spacing: Spacing.md) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonMemoryFileRow()
                }
            }
        }
        .cardPadding()
        .cardBackground()
    }
}

private struct SkeletonArchiveHealthCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SkeletonBox(width: 130, height: 20, cornerRadius: Spacing.sm)
            VStack(spacing: Spacing.lg) {
                ForEach(0..<5, id: \.self) { index in
                    HStack {
                        SkeletonCircle(size: 16)
                        SkeletonBox(width: 100, height: 14, cornerRadius: Spacing.xs)
                        Spacer()
                        SkeletonBox(width: 80, height: 14, cornerRadius: Spacing.xs)
                    }
                    if index < 4 { DSDivider() }
                }
            }
        }
        .cardPadding()
        .cardBackground()
    }
}

private struct SkeletonCurationScheduleCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                SkeletonBox(width: 150, height: 20, cornerRadius: Spacing.sm)
                Spacer()
                SkeletonBox(width: 80, height: 20, cornerRadius: Spacing.sm)
            }
            VStack(spacing: Spacing.lg) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack {
                        SkeletonBox(width: 20, height: 20, cornerRadius: Spacing.xs)
                        SkeletonBox(width: 120, height: 14, cornerRadius: Spacing.xs)
                        Spacer()
                        SkeletonBox(width: 50, height: 14, cornerRadius: Spacing.xs)
                    }
                }
            }
        }
        .cardPadding()
        .cardBackground()
    }
}

private struct SkeletonMemoryActivityCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SkeletonBox(width: 130, height: 20, cornerRadius: Spacing.sm)
            HStack(spacing: Spacing.lg) {
                SkeletonStatBox()
                SkeletonStatBox()
            }
            DSDivider()
            HStack {
                SkeletonCircle(size: 16)
                SkeletonBox(width: 100, height: 14, cornerRadius: Spacing.xs)
                Spacer()
                SkeletonBox(width: 60, height: 12, cornerRadius: Spacing.xxs)
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SkeletonBox(width: 80, height: 12, cornerRadius: Spacing.xxs)
                ForEach(0..<3, id: \.self) { _ in
                    HStack {
                        SkeletonBox(width: 14, height: 14, cornerRadius: Spacing.xxs)
                        SkeletonBox(width: CGFloat.random(in: 80...140), height: 12, cornerRadius: Spacing.xxs)
                    }
                }
            }
        }
        .cardPadding()
        .cardBackground()
    }
}

// MARK: - Context Pressure Card

struct ContextPressureCard: View {
    let pressure: ContextPressure
    @ObservedObject var vitalsLoader: MemoryVitalsLoader
    
    private var pressureColor: Color {
        switch pressure.level {
        case .normal: return Color.Semantic.success
        case .warning: return Color.Semantic.warning
        case .critical: return Color.Semantic.error
        }
    }
    
    var body: some View {
        DSCard(title: "⚡ CONTEXT PRESSURE", color: pressureColor) {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Status badge
                HStack {
                    Spacer()
                    DSCustomBadge(label: pressure.level.label, color: pressureColor)
                }
                
                // Telegram Session
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    HStack {
                        Text("Telegram Session")
                            .font(.ClawK.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.1f%%", pressure.usagePercent))
                            .font(.ClawK.valueMono)
                            .foregroundColor(pressureColor)
                    }
                    
                    HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
                        Text(formatTokens(pressure.currentTokens))
                            .font(.ClawK.displayLarge)
                        Text("/")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text(formatTokens(pressure.maxTokens))
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Progress bar with thresholds
                DSProgressBarWithThresholds(percent: pressure.usagePercent, color: pressureColor)
                
                DSDivider()
                
                // Main Session
                if let mainSession = vitalsLoader.appState?.mainSession {
                    MainSessionView(session: mainSession, appState: vitalsLoader.appState)
                    DSDivider()
                }
                
                // Last compaction
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Last compaction")
                            .font(.ClawK.caption)
                            .foregroundColor(.secondary)
                        
                        if let lastFlush = pressure.lastFlush {
                            Text(lastFlush, style: .relative)
                                .font(.ClawK.label)
                        } else {
                            Text("Never")
                                .font(.ClawK.label)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }
                
                // Info box
                DSInfoBox(
                    icon: "info.circle.fill",
                    title: "Auto-Compaction",
                    message: "Automatic memory flush at ~88% (171K), compaction at ~90% (175K). Manual /compact available anytime.",
                    color: Color.Semantic.info
                )
            }
        }
    }
    
    private func formatTokens(_ count: Int) -> String {
        count.formattedTokens
    }
}

// MARK: - Progress Bar With Thresholds

struct DSProgressBarWithThresholds: View {
    let percent: Double
    let color: Color
    
    var body: some View {
        VStack(spacing: Spacing.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Spacing.sm)
                        .fill(Color.gray.opacity(Color.Opacity.normal))
                    
                    RoundedRectangle(cornerRadius: Spacing.sm)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.7), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(min(percent, 100) / 100))
                    
                    // Threshold markers
                    Rectangle()
                        .fill(Color.Semantic.warning)
                        .frame(width: 2)
                        .offset(x: geo.size.width * 0.7 - 1)
                    
                    Rectangle()
                        .fill(Color.Semantic.error)
                        .frame(width: 2)
                        .offset(x: geo.size.width * 0.9 - 1)
                }
            }
            .frame(height: Spacing.xl)
            
            // Labels
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    Text("70% warn")
                        .font(.ClawK.captionSmall)
                        .foregroundColor(Color.Semantic.warning)
                        .offset(x: geo.size.width * 0.7 - 20, y: 0)
                    
                    Text("90% crit")
                        .font(.ClawK.captionSmall)
                        .foregroundColor(Color.Semantic.error)
                        .offset(x: geo.size.width * 0.9 - 18, y: 0)
                }
            }
            .frame(height: 14)
        }
    }
}

// MARK: - Main Session View

struct MainSessionView: View {
    let session: SessionInfo
    let appState: AppState?
    
    private var contextWindow: Int {
        appState?.contextWindow(for: session.model) ?? 200_000
    }
    
    private var percent: Double {
        Double(session.totalTokens ?? 0) / Double(contextWindow) * 100
    }
    
    private var color: Color {
        percent >= 90 ? Color.Semantic.error : percent >= 70 ? Color.Semantic.warning : Color.Semantic.success
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Main Session")
                    .font(.ClawK.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.1f%%", percent))
                    .font(.ClawK.numberMedium)
                    .foregroundColor(color)
            }
            
            HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
                Text(formatTokens(session.totalTokens ?? 0))
                    .font(.ClawK.valueLarge)
                Text("/")
                    .foregroundColor(.secondary)
                Text(formatTokens(contextWindow))
                    .foregroundColor(.secondary)
            }
            
            DSProgressBar(percent: percent, color: color, height: Spacing.lg)
        }
    }
    
    private func formatTokens(_ count: Int) -> String {
        count.formattedTokens
    }
}

// MARK: - Info Box

struct DSInfoBox: View {
    let icon: String
    let title: String
    let message: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.ClawK.caption)
                    .foregroundColor(color.opacity(0.7))
                Text(title)
                    .font(.ClawK.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
            
            Text(message)
                .font(.ClawK.captionSmall)
                .foregroundColor(Color.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(color.backgroundLight)
        .cornerRadius(Spacing.md)
    }
}

// MARK: - Memory Files Status Card

struct MemoryFilesStatusCard: View {
    let files: [MemoryFileStatus]
    
    var body: some View {
        DSCard(title: "📁 MEMORY FILES STATUS", color: .blue) {
            VStack(spacing: Spacing.md) {
                ForEach(files) { file in
                    MemoryFileStatusRow(file: file)
                }
                
                if files.isEmpty {
                    DSEmptyState(
                        icon: "doc.questionmark",
                        title: "No memory files found"
                    )
                }
            }
        }
    }
}

struct MemoryFileStatusRow: View {
    let file: MemoryFileStatus
    
    private var fileIcon: String {
        if file.name == "MEMORY.md" { return "brain" }
        if file.name.hasSuffix(".md") { return "doc.text" }
        return "doc"
    }
    
    private var fileColor: Color {
        switch file.status {
        case .healthy: return Color.Semantic.info
        case .needsAttention: return Color.Semantic.warning
        case .stale: return Color.Semantic.neutral
        case .missing: return Color.Semantic.error
        }
    }
    
    private var statusBackground: Color {
        Color.Health.background(file.status.rawValue)
    }
    
    var body: some View {
        HStack {
            Image(systemName: fileIcon)
                .foregroundColor(fileColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                HStack {
                    Text(file.name)
                        .font(.ClawK.bodyMono)
                    Text(file.status.emoji)
                        .font(.ClawK.caption)
                }
                
                HStack(spacing: Spacing.md) {
                    Text(file.sizeFormatted)
                        .font(.ClawK.caption)
                        .foregroundColor(.secondary)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text("\(file.tokensFormatted) tokens")
                        .font(.ClawK.caption)
                        .foregroundColor(.secondary)
                    
                    if let entryCount = file.entryCount {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("\(entryCount) entries")
                            .font(.ClawK.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if let modified = file.lastModified {
                Text(modified, style: .relative)
                    .font(.ClawK.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(Spacing.md)
        .background(statusBackground)
        .cornerRadius(Spacing.md)
    }
}

// MARK: - Archive Health Card

struct ArchiveHealthCard: View {
    let health: ArchiveHealth
    
    var body: some View {
        DSCard(title: "📦 ARCHIVE HEALTH", color: .purple) {
            VStack(spacing: Spacing.lg) {
                // Current month folder
                DSInfoRow(
                    icon: "folder.fill",
                    label: health.currentMonthFolder.isEmpty ? "Current Month" : health.currentMonthFolder,
                    value: "\(health.currentMonthFileCount) files",
                    valueColor: Color.Semantic.warning
                )
                
                DSDivider()
                
                // Monthly summary
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(Color.Semantic.info)
                    Text("Monthly Summary")
                        .font(.ClawK.label)
                    Spacer()
                    
                    if let summary = health.lastMonthlySummary {
                        VStack(alignment: .trailing, spacing: Spacing.xxs) {
                            Text(summary.name)
                                .font(.ClawK.caption)
                            if let date = summary.date {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.ClawK.captionSmall)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("None yet")
                            .font(.ClawK.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Quarterly summary
                HStack {
                    Image(systemName: "doc.richtext.fill")
                        .foregroundColor(.purple)
                    Text("Quarterly Summary")
                        .font(.ClawK.label)
                    Spacer()
                    
                    if let summary = health.lastQuarterlySummary {
                        VStack(alignment: .trailing, spacing: Spacing.xxs) {
                            Text(summary.name)
                                .font(.ClawK.caption)
                            if let date = summary.date {
                                Text(date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.ClawK.captionSmall)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("None yet")
                            .font(.ClawK.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                DSDivider()
                
                // Total archive size
                DSInfoRow(
                    icon: "archivebox.fill",
                    label: "Total Archive",
                    value: health.totalArchiveSizeFormatted,
                    mono: true
                )
                
                // Next compression
                if let nextCompression = health.nextCompressionDue {
                    DSInfoRow(
                        icon: "calendar.badge.clock",
                        label: "Next Compression",
                        value: nextCompression.formatted(date: .abbreviated, time: .omitted),
                        valueColor: Color.Accent.system
                    )
                }
            }
        }
    }
}

// MARK: - Curation Schedule Card

struct CurationScheduleCard: View {
    let schedule: CurationSchedule
    
    private var hasAnyCrons: Bool {
        schedule.dailyCuration != nil || schedule.weeklyMaintenance != nil || schedule.monthlyCompression != nil
    }
    
    var body: some View {
        DSCardWithStatus(
            title: "⏰ CURATION SCHEDULE",
            color: .orange,
            status: hasAnyCrons ? (schedule.isOnSchedule ? .success : .warning) : .neutral
        ) {
            if hasAnyCrons {
                VStack(spacing: Spacing.lg) {
                    ScheduleRow(
                        emoji: "⏰",
                        label: "Daily Curation",
                        date: schedule.dailyCuration,
                        description: schedule.dailyCuration != nil ? schedule.dailyDescription : "Not configured"
                    )
                    
                    ScheduleRow(
                        emoji: "📅",
                        label: "Weekly Maintenance",
                        date: schedule.weeklyMaintenance,
                        description: schedule.weeklyMaintenance != nil ? schedule.weeklyDescription : "Not configured"
                    )
                    
                    ScheduleRow(
                        emoji: "📦",
                        label: "Monthly Compression",
                        date: schedule.monthlyCompression,
                        description: schedule.monthlyCompression != nil ? schedule.monthlyDescription : "Not configured"
                    )
                    
                    if let issue = schedule.scheduleIssue {
                        DSDivider()
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Color.Semantic.warning)
                            Text(issue)
                                .font(.ClawK.caption)
                                .foregroundColor(Color.Semantic.warning)
                        }
                    }
                }
            } else {
                VStack(spacing: Spacing.md) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("No curation crons detected")
                        .font(.ClawK.label)
                        .foregroundColor(.secondary)
                    
                    Text("Set up cron jobs in OpenClaw to automate memory maintenance. Name them with keywords like \"daily curation\", \"weekly maintenance\", or \"monthly compression\" so ClawK can track them here.")
                        .font(.ClawK.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.md)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.lg)
            }
        }
    }
}

struct ScheduleRow: View {
    let emoji: String
    let label: String
    let date: Date?
    let description: String
    
    var body: some View {
        HStack {
            Text(emoji)
            Text(label)
                .font(.ClawK.label)
            Spacer()
            
            VStack(alignment: .trailing, spacing: Spacing.xxs) {
                if let date = date {
                    Text(timeUntil(date))
                        .font(.ClawK.label)
                        .foregroundColor(Color.Semantic.info)
                } else {
                    Text(description)
                        .font(.ClawK.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private func timeUntil(_ date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "Now" }
        
        let hours = Int(interval / 3600)
        let days = hours / 24
        
        if days > 0 { return "in \(days)d" }
        if hours > 0 { return "in \(hours)h" }
        
        let minutes = Int(interval / 60)
        return "in \(minutes)m"
    }
}

// MARK: - Memory Activity Card

struct MemoryActivityCard: View {
    let activity: MemoryActivity
    
    var body: some View {
        DSCard(title: "📊 MEMORY ACTIVITY", color: .teal) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                // Stats grid
                HStack(spacing: Spacing.lg) {
                    DSStatCard(
                        label: "Searches Today",
                        value: "\(activity.searchesToday)",
                        icon: "magnifyingglass",
                        color: Color.Semantic.info
                    )
                    
                    DSStatCard(
                        label: "Entries Added",
                        value: "\(activity.entriesAddedToday)",
                        icon: "plus.circle",
                        color: Color.Semantic.success
                    )
                }
                
                DSDivider()
                
                // Last memory write
                DSInfoRow(
                    icon: "pencil.line",
                    label: "Last memory write",
                    value: activity.lastMemoryWrite.map { $0.formatted(.relative(presentation: .named)) } ?? "—"
                )
                
                // Most active files
                if !activity.mostActiveFiles.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Most active")
                            .font(.ClawK.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(activity.mostActiveFiles.prefix(3), id: \.self) { file in
                            HStack {
                                Image(systemName: "doc.text")
                                    .font(.ClawK.caption)
                                    .foregroundColor(.secondary)
                                Text(file)
                                    .font(.ClawK.caption)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Memory Vitals Loader

@MainActor
class MemoryVitalsLoader: ObservableObject {
    @Published var isLoading = false
    @Published var contextPressure: ContextPressure?
    @Published var memoryFiles: [MemoryFileStatus] = []
    @Published var archiveHealth: ArchiveHealth?
    @Published var curationSchedule: CurationSchedule?
    @Published var memoryActivity: MemoryActivity = .empty
    
    private let memoryService = MemoryService()
    
    weak var appState: AppState?
    var lastFullRefresh: Date?
    
    func loadInitialData() async {
        isLoading = true
        defer { isLoading = false }
        
        await loadContextPressure()
        await loadMemoryFiles()
        await loadArchiveHealth()
        await loadCurationSchedule()
        await loadMemoryActivity()
    }
    
    func refresh() async {
        await loadInitialData()
    }
    
    func updateContextFromAppState() {
        guard let appState = appState,
              let telegramSession = appState.sessions
                .filter({ $0.key.hasPrefix(AppConfiguration.shared.telegramSessionKeyPrefix) })
                .sorted(by: { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) })
                .first else {
            return
        }
        
        let currentTokens = telegramSession.totalTokens ?? 0
        let maxTokens = appState.contextWindow(for: telegramSession.model)
        
        if contextPressure?.currentTokens != currentTokens ||
           contextPressure?.maxTokens != maxTokens {
            contextPressure = ContextPressure(
                currentTokens: currentTokens,
                maxTokens: maxTokens,
                lastFlush: contextPressure?.lastFlush
            )
        }
    }
    
    func triggerFlush() async {
        let gateway = GatewayClient()
        
        // Find the most recent telegram session dynamically
        let telegramSessionKey = appState?.sessions
            .filter { $0.key.hasPrefix(AppConfiguration.shared.telegramSessionKeyPrefix) }
            .sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
            .first?.key
        
        do {
            let _ = try await gateway.sendMessage(
                "🔵 Flush Now button pressed - please compact this telegram session and write current work to memory.",
                toSession: telegramSessionKey
            )
            
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await refresh()
        } catch {
            debugLog("Failed to trigger flush: \(error)")
        }
    }
    
    func loadContextPressure() async {
        let fm = FileManager.default
        
        var lastFlush: Date? = nil
        if let telegramSession = appState?.sessions
            .filter({ $0.key.hasPrefix(AppConfiguration.shared.telegramSessionKeyPrefix) })
            .sorted(by: { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) })
            .first {
            let sessionPath = AppConfiguration.shared.sessionFilePath(sessionId: telegramSession.sessionId)
            
            if let sessionData = try? String(contentsOfFile: sessionPath, encoding: .utf8) {
                let lines = sessionData.components(separatedBy: "\n").reversed()
                for line in lines {
                    if line.contains("\"type\":\"compaction\""),
                       let data = line.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let timestamp = json["timestamp"] as? String {
                        let formatter = ISO8601DateFormatter()
                        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        lastFlush = formatter.date(from: timestamp)
                        break
                    }
                }
            }
        }
        
        if lastFlush == nil {
            let flushLogPath = AppConfiguration.shared.contextFlushLogPath
            if fm.fileExists(atPath: flushLogPath),
               let attrs = try? fm.attributesOfItem(atPath: flushLogPath) {
                lastFlush = attrs[.modificationDate] as? Date
            }
        }
        
        if let telegramSession = appState?.sessions
            .filter({ $0.key.hasPrefix(AppConfiguration.shared.telegramSessionKeyPrefix) })
            .sorted(by: { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) })
            .first {
            let currentTokens = telegramSession.totalTokens ?? 0
            let maxTokens = appState?.contextWindow(for: telegramSession.model) ?? 195_000
            
            contextPressure = ContextPressure(
                currentTokens: currentTokens,
                maxTokens: maxTokens,
                lastFlush: lastFlush
            )
        } else {
            contextPressure = ContextPressure(
                currentTokens: 0,
                maxTokens: 195_000,
                lastFlush: lastFlush
            )
        }
    }
    
    private func loadMemoryFiles() async {
        let fm = FileManager.default
        let config = AppConfiguration.shared
        let workspacePath = config.workspacePath
        let memoryPath = config.memoryPath
        
        var files: [MemoryFileStatus] = []
        let calendar = Calendar.current
        let now = Date()
        
        // MEMORY.md
        let memoryMdPath = "\(workspacePath)/MEMORY.md"
        if fm.fileExists(atPath: memoryMdPath),
           let attrs = try? fm.attributesOfItem(atPath: memoryMdPath),
           let size = attrs[.size] as? Int,
           let modified = attrs[.modificationDate] as? Date {
            
            let tokens = size / 4
            let daysSinceModified = calendar.dateComponents([.day], from: modified, to: now).day ?? 0
            let status: FileHealthStatus = daysSinceModified > 7 ? .stale : .healthy
            
            files.append(MemoryFileStatus(
                id: "MEMORY.md",
                path: "MEMORY.md",
                name: "MEMORY.md",
                sizeBytes: size,
                tokens: tokens,
                entryCount: nil,
                lastModified: modified,
                status: status
            ))
        }
        
        // Today's log
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayFileName = "\(dateFormatter.string(from: now)).md"
        let todayPath = "\(memoryPath)/\(todayFileName)"
        
        if fm.fileExists(atPath: todayPath),
           let attrs = try? fm.attributesOfItem(atPath: todayPath),
           let size = attrs[.size] as? Int,
           let modified = attrs[.modificationDate] as? Date {
            
            var entryCount = 0
            if let content = try? String(contentsOfFile: todayPath, encoding: .utf8) {
                entryCount = content.components(separatedBy: "\n")
                    .filter { $0.hasPrefix("## ") }
                    .count
            }
            
            files.append(MemoryFileStatus(
                id: todayFileName,
                path: todayFileName,
                name: "Today's Log (\(todayFileName))",
                sizeBytes: size,
                tokens: size / 4,
                entryCount: entryCount,
                lastModified: modified,
                status: .healthy
            ))
        } else {
            files.append(MemoryFileStatus(
                id: "today-missing",
                path: todayFileName,
                name: "Today's Log (\(todayFileName))",
                sizeBytes: 0,
                tokens: 0,
                entryCount: 0,
                lastModified: nil,
                status: .missing
            ))
        }
        
        // Hot tier
        var hotFileCount = 0
        var hotTotalSize = 0
        
        for dayOffset in 1...7 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) {
                let fileName = "\(dateFormatter.string(from: date)).md"
                let filePath = "\(memoryPath)/\(fileName)"
                
                if fm.fileExists(atPath: filePath),
                   let attrs = try? fm.attributesOfItem(atPath: filePath),
                   let size = attrs[.size] as? Int {
                    hotFileCount += 1
                    hotTotalSize += size
                }
            }
        }
        
        if hotFileCount > 0 {
            files.append(MemoryFileStatus(
                id: "hot-tier",
                path: "memory/*.md",
                name: "Hot Tier (Last 7 days)",
                sizeBytes: hotTotalSize,
                tokens: hotTotalSize / 4,
                entryCount: hotFileCount,
                lastModified: nil,
                status: .healthy
            ))
        }
        
        memoryFiles = files
    }
    
    private func loadArchiveHealth() async {
        let fm = FileManager.default
        let memoryPath = AppConfiguration.shared.memoryPath
        let archivePath = "\(memoryPath)/archive"
        
        let calendar = Calendar.current
        let now = Date()
        let dateFormatter = DateFormatter()
        
        dateFormatter.dateFormat = "yyyy-MM"
        let currentMonth = dateFormatter.string(from: now)
        let currentMonthPath = "\(memoryPath)/\(currentMonth)"
        
        var currentMonthFileCount = 0
        if fm.fileExists(atPath: currentMonthPath),
           let contents = try? fm.contentsOfDirectory(atPath: currentMonthPath) {
            currentMonthFileCount = contents.filter { $0.hasSuffix(".md") }.count
        }
        
        var lastMonthlySummary: SummaryInfo? = nil
        if fm.fileExists(atPath: archivePath),
           let contents = try? fm.contentsOfDirectory(atPath: archivePath) {
            let monthlySummaries = contents.filter { $0.contains("-summary") && !$0.contains("-Q") }
                .sorted()
                .reversed()
            
            if let lastSummary = monthlySummaries.first {
                let summaryPath = "\(archivePath)/\(lastSummary)"
                if let attrs = try? fm.attributesOfItem(atPath: summaryPath) {
                    lastMonthlySummary = SummaryInfo(
                        name: lastSummary,
                        date: attrs[.modificationDate] as? Date,
                        sizeBytes: attrs[.size] as? Int ?? 0
                    )
                }
            }
        }
        
        var lastQuarterlySummary: SummaryInfo? = nil
        if fm.fileExists(atPath: archivePath),
           let contents = try? fm.contentsOfDirectory(atPath: archivePath) {
            let quarterlySummaries = contents.filter { $0.contains("-Q") }
                .sorted()
                .reversed()
            
            if let lastSummary = quarterlySummaries.first {
                let summaryPath = "\(archivePath)/\(lastSummary)"
                if let attrs = try? fm.attributesOfItem(atPath: summaryPath) {
                    lastQuarterlySummary = SummaryInfo(
                        name: lastSummary,
                        date: attrs[.modificationDate] as? Date,
                        sizeBytes: attrs[.size] as? Int ?? 0
                    )
                }
            }
        }
        
        var totalArchiveSize = 0
        if fm.fileExists(atPath: archivePath) {
            totalArchiveSize = calculateDirectorySize(path: archivePath)
        }
        
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: now)!
        let nextCompressionDue = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth))
        
        archiveHealth = ArchiveHealth(
            currentMonthFolder: currentMonth,
            currentMonthFileCount: currentMonthFileCount,
            lastMonthlySummary: lastMonthlySummary,
            lastQuarterlySummary: lastQuarterlySummary,
            totalArchiveSizeBytes: totalArchiveSize,
            nextCompressionDue: nextCompressionDue
        )
    }
    
    private func loadCurationSchedule() async {
        var dailyCuration: Date? = nil
        var weeklyMaintenance: Date? = nil
        var monthlyCompression: Date? = nil
        var dailyDescription = "8:30 PM"
        var weeklyDescription = "Sunday"
        var monthlyDescription = "1st of month"
        var isOnSchedule = true
        var scheduleIssue: String? = nil
        
        if let cronJobs = appState?.cronJobs {
            for job in cronJobs where job.isEnabled {
                let name = job.name.lowercased()
                
                if name.contains("daily") && name.contains("curat") {
                    if let nextRun = job.nextRunDate {
                        dailyCuration = nextRun
                    }
                    if let expr = job.schedule.expr {
                        dailyDescription = expr
                    }
                    if let lastRun = job.lastRunDate {
                        let hoursSinceLastRun = Date().timeIntervalSince(lastRun) / 3600
                        if hoursSinceLastRun > 26 {
                            isOnSchedule = false
                            scheduleIssue = "Daily curation overdue"
                        }
                    }
                }
                
                if name.contains("weekly") && (name.contains("maintenance") || name.contains("memory")) {
                    if let nextRun = job.nextRunDate {
                        weeklyMaintenance = nextRun
                    }
                    if let expr = job.schedule.expr {
                        weeklyDescription = expr
                    }
                    if let lastRun = job.lastRunDate {
                        let daysSinceLastRun = Date().timeIntervalSince(lastRun) / 86400
                        if daysSinceLastRun > 8 {
                            isOnSchedule = false
                            scheduleIssue = "Weekly maintenance overdue"
                        }
                    }
                }
                
                if name.contains("monthly") && (name.contains("compress") || name.contains("memory")) {
                    if let nextRun = job.nextRunDate {
                        monthlyCompression = nextRun
                    }
                    if let expr = job.schedule.expr {
                        monthlyDescription = expr
                    }
                }
            }
        }
        
        // Don't fabricate fake schedules — leave nil if no matching crons found
        
        curationSchedule = CurationSchedule(
            dailyCuration: dailyCuration,
            weeklyMaintenance: weeklyMaintenance,
            monthlyCompression: monthlyCompression,
            isOnSchedule: isOnSchedule,
            dailyDescription: dailyDescription,
            weeklyDescription: weeklyDescription,
            monthlyDescription: monthlyDescription,
            scheduleIssue: scheduleIssue
        )
    }
    
    private func loadMemoryActivity() async {
        let fm = FileManager.default
        let memoryPath = AppConfiguration.shared.memoryPath
        
        let calendar = Calendar.current
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let searchesToday = GatewayClient.fetchMemorySearchCount()
        var entriesAddedToday = 0
        var lastMemoryWrite: Date? = nil
        var mostActiveFiles: [String] = []
        
        let todayFileName = "\(dateFormatter.string(from: now)).md"
        let todayPath = "\(memoryPath)/\(todayFileName)"
        
        if fm.fileExists(atPath: todayPath),
           let attrs = try? fm.attributesOfItem(atPath: todayPath),
           let content = try? String(contentsOfFile: todayPath, encoding: .utf8) {
            
            lastMemoryWrite = attrs[.modificationDate] as? Date
            entriesAddedToday = content.components(separatedBy: "\n")
                .filter { $0.hasPrefix("## ") }
                .count
        }
        
        var fileActivity: [(String, Date)] = []
        
        for dayOffset in 0...6 {
            if let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) {
                let fileName = "\(dateFormatter.string(from: date)).md"
                let filePath = "\(memoryPath)/\(fileName)"
                
                if fm.fileExists(atPath: filePath),
                   let attrs = try? fm.attributesOfItem(atPath: filePath),
                   let modified = attrs[.modificationDate] as? Date {
                    fileActivity.append((fileName, modified))
                }
            }
        }
        
        mostActiveFiles = fileActivity
            .sorted { $0.1 > $1.1 }
            .prefix(3)
            .map { $0.0 }
        
        memoryActivity = MemoryActivity(
            searchesToday: searchesToday,
            entriesAddedToday: entriesAddedToday,
            lastMemoryWrite: lastMemoryWrite,
            mostActiveFiles: mostActiveFiles
        )
    }
    
    private func calculateDirectorySize(path: String) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
        
        var totalSize = 0
        while let file = enumerator.nextObject() as? String {
            let filePath = "\(path)/\(file)"
            if let attrs = try? fm.attributesOfItem(atPath: filePath),
               let size = attrs[.size] as? Int {
                totalSize += size
            }
        }
        return totalSize
    }
}

