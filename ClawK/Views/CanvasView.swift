//
//  CanvasView.swift
//  ClawK
//
//  Canvas control and status view - refactored to use Design System
//  Round 19: Full design system standardization
//

import SwiftUI
import AppKit

// MARK: - Canvas View

struct CanvasView: View {
    @EnvironmentObject var appState: AppState
    @State private var urlInput: String = ""
    @State private var jsCode: String = ""
    @State private var jsResult: String = ""
    @State private var showJSResult: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.page) {
                // Error Banner with Retry
                if let error = appState.canvasState.error {
                    DSErrorBanner(
                        message: error,
                        onRetry: {
                            Task {
                                await appState.refreshCanvas()
                            }
                        },
                        onDismiss: {
                            appState.dismissCanvasError()
                        }
                    )
                }
                
                // Header
                DSPageHeader(
                    emoji: "🖼️",
                    title: "Canvas",
                    subtitle: "Visual UI Display",
                    trailing: AnyView(
                        HStack(spacing: Spacing.md) {
                            DSConnectionBadge(
                                isConnected: appState.canvasState.isActive,
                                connectedLabel: "Active",
                                disconnectedLabel: "Inactive"
                            )
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .background(
                                Capsule()
                                    .fill((appState.canvasState.isActive ? Color.Semantic.connected : Color.Semantic.neutral).backgroundMedium)
                            )
                            
                            if let lastUpdate = appState.canvasState.lastUpdate {
                                Text("Updated \(lastUpdate.formatted(.relative(presentation: .named)))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    )
                )
                
                // Main Content
                HStack(alignment: .top, spacing: Spacing.xxl) {
                    // Left: Status & Controls
                    VStack(spacing: Spacing.xxl) {
                        CanvasStatusCard()
                        CanvasControlsCard(urlInput: $urlInput)
                        CanvasJSExecutionCard(jsCode: $jsCode, jsResult: $jsResult, showResult: $showJSResult)
                    }
                    .frame(minWidth: Spacing.Layout.columnMinWidth)
                    
                    // Right: Preview & Activity
                    VStack(spacing: Spacing.xxl) {
                        CanvasPreviewCard()
                        CanvasActivityCard()
                    }
                    .frame(minWidth: 450)
                }
                
                Spacer()
            }
            .pagePadding()
        }
        .background(Color.Surface.primary)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                DSRefreshButton(action: {
                    Task { await appState.refreshCanvas() }
                }, isRefreshing: appState.canvasState.isLoading)
                .help("Refresh (⌘R)")
            }
        }
        .onAppear {
            Task { await appState.refreshCanvas() }
        }
        // Keyboard shortcuts
        .background(
            KeyboardShortcutHandler(
                onSnapshot: { Task { await appState.canvasTakeSnapshot() } },
                onRefresh: { Task { await appState.refreshCanvas() } },
                onHide: { Task { await appState.canvasHide() } }
            )
        )
    }
}

// MARK: - Keyboard Shortcut Handler

struct KeyboardShortcutHandler: View {
    let onSnapshot: () -> Void
    let onRefresh: () -> Void
    let onHide: () -> Void
    
    var body: some View {
        VStack {
            Button(action: onSnapshot) { EmptyView() }
                .keyboardShortcut("s", modifiers: .command)
                .opacity(0)
            
            Button(action: onRefresh) { EmptyView() }
                .keyboardShortcut("r", modifiers: .command)
                .opacity(0)
            
            Button(action: onHide) { EmptyView() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .opacity(0)
        }
        .frame(width: 0, height: 0)
    }
}

// MARK: - Error Banner View

struct DSErrorBanner: View {
    let message: String
    var onRetry: (() -> Void)? = nil
    let onDismiss: () -> Void
    
    var body: some View {
        HStack(spacing: Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
            
            Text(message)
                .font(.ClawK.label)
                .foregroundColor(.white)
                .lineLimit(2)
            
            Spacer()
            
            if let onRetry = onRetry {
                Button(action: onRetry) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                            .font(.ClawK.caption)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(Spacing.sm)
                }
                .buttonStyle(.plain)
            }
            
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.white.opacity(Color.Opacity.solid))
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.lg)
        .background(Color.Semantic.error.opacity(0.9))
        .cornerRadius(Spacing.md)
    }
}

// MARK: - Status Card

struct CanvasStatusCard: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        DSCard(
            title: "📊 STATUS",
            color: .purple,
            tooltip: "Current canvas state and configuration",
            isLoading: appState.canvasState.isLoading && appState.canvasState.lastUpdate == nil
        ) {
            VStack(spacing: Spacing.xl) {
                DSInfoRow(label: "State", value: appState.canvasState.isActive ? "Presented" : "Hidden")
                
                DSDivider()
                
                // Target selection
                HStack {
                    Text("Target")
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { appState.canvasState.target },
                        set: { appState.setCanvasTarget($0) }
                    )) {
                        Text("Host").tag("host")
                        Text("Sandbox").tag("sandbox")
                        Text("Node").tag("node")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                
                // URL tracking
                if let url = appState.canvasState.currentURL, !url.isEmpty {
                    DSDivider()
                    
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            Text("Current URL")
                                .font(.ClawK.label)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.ClawK.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                            .help("Copy URL to clipboard")
                        }
                        Text(url)
                            .font(.ClawK.bodyMono)
                            .foregroundColor(Color.Text.primary.opacity(Color.Opacity.solid))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if let size = appState.canvasState.windowSize {
                    DSDivider()
                    DSInfoRow(label: "Window Size", value: size)
                }
            }
        }
    }
}

// MARK: - Controls Card

struct CanvasControlsCard: View {
    @EnvironmentObject var appState: AppState
    @Binding var urlInput: String
    
    var body: some View {
        DSCard(
            title: "🎮 CONTROLS",
            color: .orange,
            tooltip: "Present, hide, or navigate the canvas. Supports host, sandbox, and node targets."
        ) {
            VStack(spacing: Spacing.xl) {
                // Present/Hide Toggle
                HStack(spacing: Spacing.lg) {
                    DSCanvasActionButton(
                        title: "Present",
                        icon: "rectangle.portrait.on.rectangle.portrait",
                        color: .green,
                        isActive: appState.canvasState.isActive,
                        isLoading: appState.canvasState.isLoading
                    ) {
                        Task {
                            let url = urlInput.isEmpty ? "about:blank" : urlInput
                            await appState.canvasPresent(url: url)
                        }
                    }
                    
                    DSCanvasActionButton(
                        title: "Hide",
                        icon: "rectangle.slash",
                        color: .red,
                        isActive: !appState.canvasState.isActive,
                        isLoading: appState.canvasState.isLoading
                    ) {
                        Task { await appState.canvasHide() }
                    }
                }
                
                DSDivider()
                
                // Navigate to URL
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Navigate to URL")
                        .font(.ClawK.label)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: Spacing.md) {
                        TextField("https://...", text: $urlInput)
                            .textFieldStyle(.roundedBorder)
                            .font(.ClawK.bodyMono)
                            .onSubmit {
                                if !urlInput.isEmpty {
                                    Task {
                                        let url = urlInput
                                        await appState.canvasNavigate(to: url)
                                        if appState.canvasState.error == nil {
                                            urlInput = ""
                                        }
                                    }
                                }
                            }
                        
                        Button(action: {
                            Task {
                                let url = urlInput
                                await appState.canvasNavigate(to: url)
                                if appState.canvasState.error == nil {
                                    urlInput = ""
                                }
                            }
                        }) {
                            if appState.canvasState.isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.title2)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.blue)
                        .disabled(urlInput.isEmpty || appState.canvasState.isLoading)
                    }
                }
                
                DSDivider()
                
                // Quick Actions
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Quick Actions")
                        .font(.ClawK.label)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: Spacing.md) {
                        DSQuickActionButton(
                            title: "Snapshot",
                            icon: "camera",
                            shortcut: "⌘S",
                            isLoading: appState.canvasState.isLoading
                        ) {
                            Task { await appState.canvasTakeSnapshot() }
                        }
                        
                        DSQuickActionButton(
                            title: "Refresh",
                            icon: "arrow.clockwise",
                            shortcut: "⌘R",
                            isLoading: appState.canvasState.isLoading
                        ) {
                            Task { await appState.refreshCanvas() }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Canvas Action Button

struct DSCanvasActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let isActive: Bool
    var isLoading: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                if isLoading && isActive {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                        .font(.title2)
                }
                Text(title)
                    .font(.ClawK.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Spacing.md)
                    .fill(isActive ? color.backgroundLight : Color.Surface.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.md)
                    .stroke(isActive ? color : Color.Border.normal, lineWidth: 1)
            )
            .foregroundColor(isActive ? color : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Quick Action Button

struct DSQuickActionButton: View {
    let title: String
    let icon: String
    var shortcut: String? = nil
    var isLoading: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: icon)
                }
                Text(title)
                if let shortcut = shortcut {
                    Text(shortcut)
                        .font(.ClawK.captionSmall)
                        .foregroundColor(Color.Text.tertiary)
                }
            }
            .font(.ClawK.caption)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Spacing.sm)
                    .fill(Color.Surface.secondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.sm)
                    .stroke(Color.Border.normal, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .disabled(isLoading)
    }
}

// MARK: - JavaScript Execution Card

struct CanvasJSExecutionCard: View {
    @EnvironmentObject var appState: AppState
    @Binding var jsCode: String
    @Binding var jsResult: String
    @Binding var showResult: Bool
    
    var body: some View {
        DSCard(
            title: "⚡ JAVASCRIPT",
            color: .yellow,
            tooltip: "Execute JavaScript code in the current canvas page"
        ) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Execute Code")
                    .font(.ClawK.label)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $jsCode)
                    .font(.ClawK.bodyMono)
                    .frame(height: 80)
                    .padding(Spacing.xs)
                    .background(Color.Surface.tertiary)
                    .cornerRadius(Spacing.sm)
                    .overlay(
                        RoundedRectangle(cornerRadius: Spacing.sm)
                            .stroke(Color.Border.normal, lineWidth: 1)
                    )
                
                HStack {
                    Button(action: {
                        Task {
                            if let result = await appState.canvasExecuteJS(jsCode) {
                                jsResult = result
                                showResult = true
                            }
                        }
                    }) {
                        HStack(spacing: Spacing.xs) {
                            if appState.canvasState.isLoading {
                                ProgressView()
                                    .scaleEffect(0.6)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text("Execute")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.yellow)
                    .disabled(jsCode.isEmpty || appState.canvasState.isLoading)
                    
                    Button("Clear") {
                        jsCode = ""
                        jsResult = ""
                        showResult = false
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    if !appState.canvasState.isActive {
                        Text("⚠️ Canvas may not be active")
                            .font(.ClawK.caption)
                            .foregroundColor(Color.Semantic.warning)
                    }
                }
                
                // Result display
                if showResult && !jsResult.isEmpty {
                    DSDivider()
                    
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            Text("Result")
                                .font(.ClawK.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(action: { showResult = false }) {
                                Image(systemName: "xmark.circle")
                                    .font(.ClawK.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                        
                        ScrollView {
                            Text(jsResult)
                                .font(.ClawK.bodyMono)
                                .foregroundColor(Color.Semantic.success)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 80)
                        .padding(Spacing.sm)
                        .background(Color.Surface.tertiary.opacity(Color.Opacity.heavy))
                        .cornerRadius(Spacing.xs)
                    }
                }
            }
        }
    }
}

// MARK: - Preview Card

struct CanvasPreviewCard: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        DSCard(
            title: "👁️ PREVIEW",
            color: .blue,
            tooltip: "Visual snapshot of current canvas content. Click 'Snapshot' to capture.",
            isLoading: appState.canvasState.isLoading && appState.canvasState.snapshotData == nil
        ) {
            if let snapshotData = appState.canvasState.snapshotData,
               let nsImage = NSImage(data: snapshotData) {
                VStack(spacing: Spacing.lg) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 400)
                        .cornerRadius(Spacing.md)
                        .overlay(
                            RoundedRectangle(cornerRadius: Spacing.md)
                                .stroke(Color.Border.subtle, lineWidth: 1)
                        )
                    
                    if let timestamp = appState.canvasState.snapshotTimestamp {
                        Text("Captured \(timestamp.formatted(.relative(presentation: .named)))")
                            .font(.ClawK.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if appState.canvasState.isActive {
                DSEmptyState(
                    icon: "camera.viewfinder",
                    title: "No snapshot",
                    subtitle: "Click 'Snapshot' to capture current canvas",
                    action: {
                        Task { await appState.canvasTakeSnapshot() }
                    },
                    actionLabel: "Take Snapshot"
                )
            } else {
                DSEmptyState(
                    icon: "rectangle.dashed",
                    title: "Canvas is not active",
                    subtitle: "Present a canvas to see preview here"
                )
            }
        }
    }
}

// MARK: - Activity Card

struct CanvasActivityCard: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        DSCard(
            title: "📜 ACTIVITY",
            color: .gray,
            tooltip: "Recent canvas actions and their results"
        ) {
            if appState.canvasState.activityLog.isEmpty {
                HStack {
                    Image(systemName: "clock.badge.questionmark")
                        .foregroundColor(.secondary)
                    Text("No recent activity")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, Spacing.md)
            } else {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(appState.canvasState.activityLog.prefix(10)) { entry in
                        HStack(spacing: Spacing.md) {
                            // Status icon
                            Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(entry.success ? Color.Semantic.success : Color.Semantic.error)
                                .font(.ClawK.caption)
                            
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(entry.action)
                                    .font(.body)
                                    .lineLimit(1)
                                
                                if let details = entry.details {
                                    Text(details)
                                        .font(.ClawK.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            
                            Spacer()
                            
                            Text(entry.timestamp.formatted(.relative(presentation: .named)))
                                .font(.ClawK.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, Spacing.xs)
                        
                        if entry.id != appState.canvasState.activityLog.prefix(10).last?.id {
                            DSDivider()
                        }
                    }
                }
            }
        }
    }
}

// Preview removed for SPM compatibility
