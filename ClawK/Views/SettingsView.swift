//
//  SettingsView.swift
//  ClawK
//
//  Settings and configuration view - Redesigned to match Mission Control style
//

import SwiftUI

// MARK: - Main Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Spacing.xxl) {
                    // Header
                    DSPageHeader(
                        emoji: "⚙️",
                        title: "SETTINGS",
                        subtitle: "Configuration & Preferences"
                    )
                    
                    // Main Content - Responsive layout
                    if geometry.size.width > Spacing.Layout.twoColumnBreakpoint {
                        // Two-column layout for wide windows
                        HStack(alignment: .top, spacing: Spacing.xxl) {
                            // Left Column - Primary Settings
                            VStack(spacing: Spacing.xxl) {
                                ConnectionCard()
                                RefreshCard()
                            }
                            .frame(minWidth: Spacing.Layout.columnMinWidth)
                            
                            // Right Column - Info
                            VStack(spacing: Spacing.xxl) {
                                DiscoveryCard()
                                AboutCard()
                            }
                            .frame(minWidth: Spacing.Layout.columnMinWidth)
                        }
                    } else {
                        // Single-column layout for narrow windows
                        VStack(spacing: Spacing.xxl) {
                            ConnectionCard()
                            RefreshCard()
                            DiscoveryCard()
                            AboutCard()
                        }
                    }
                }
                .pagePadding()
            }
            .background(Color.Surface.primary)
        }
        .navigationTitle("")
    }
}

// MARK: - Connection Card

struct ConnectionCard: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var gatewayConfig = GatewayConfig.shared
    @State private var customURLInput: String = ""
    @State private var tokenInput: String = ""
    @State private var showToken: Bool = false
    
    private var showSkeleton: Bool {
        appState.isLoading && appState.lastRefresh == nil
    }
    
    var body: some View {
        DSCard(
            title: "🌐 CONNECTION",
            color: Color.CardHeader.connection,
            tooltip: "Configure gateway connection settings"
        ) {
            VStack(spacing: 16) {
                // Status Row
                HStack {
                    Text("Status")
                        .foregroundColor(.secondary)
                    Spacer()
                    if showSkeleton {
                        SkeletonConnectionStatus()
                    } else {
                        StatusBadge(
                            isConnected: appState.isConnected,
                            connectedText: "Connected",
                            disconnectedText: "Disconnected"
                        )
                    }
                }
                
                Divider()
                
                // Gateway URL
                SettingsTextField(
                    label: "Gateway URL",
                    placeholder: "http://127.0.0.1:18789",
                    text: $customURLInput,
                    isCustom: gatewayConfig.isUsingCustomURL,
                    onSave: { gatewayConfig.customURL = customURLInput },
                    onReset: {
                        gatewayConfig.resetToDefault()
                        customURLInput = ""
                    }
                )
                
                Text("Default: \(gatewayConfig.defaultURL)")
                    .font(.ClawK.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                // Gateway Token
                SettingsSecureField(
                    label: "Gateway Token",
                    placeholder: "Enter gateway token",
                    text: $tokenInput,
                    showText: $showToken,
                    isConfigured: gatewayConfig.hasToken,
                    onSave: { gatewayConfig.storedToken = tokenInput }
                )
                
                Text("Get token from: `openclaw gateway config.get`")
                    .font(.ClawK.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                // Save & Reconnect
                Button(action: saveAndReconnect) {
                    HStack {
                        Image(systemName: "arrow.clockwise.circle.fill")
                        Text("Save & Reconnect")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                
                // Last Refresh
                HStack {
                    Text("Last Refresh")
                        .font(.ClawK.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    if showSkeleton {
                        SkeletonBox(width: 80, height: 12, cornerRadius: 3)
                    } else if let lastRefresh = appState.lastRefresh {
                        Text(lastRefresh, style: .relative)
                            .font(.ClawK.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Never")
                            .font(.ClawK.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Error display
                if let error = appState.lastError {
                    ErrorBanner(message: error)
                }
            }
        }
        .onAppear {
            customURLInput = gatewayConfig.customURL
            tokenInput = gatewayConfig.storedToken
        }
    }
    
    private func saveAndReconnect() {
        if !customURLInput.isEmpty {
            gatewayConfig.customURL = customURLInput
        } else {
            gatewayConfig.resetToDefault()
        }
        
        if !tokenInput.isEmpty {
            gatewayConfig.storedToken = tokenInput
        }
        
        Task { await appState.refresh() }
    }
}

// MARK: - Refresh Card

struct RefreshCard: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        DSCard(
            title: "🔄 REFRESH",
            color: Color.CardHeader.refresh,
            tooltip: "Configure how often the app refreshes data"
        ) {
            VStack(spacing: Spacing.xl) {
                HStack {
                    Text("Polling Interval")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(appState.pollingInterval))s")
                        .font(.ClawK.valueMono)
                        .foregroundColor(.orange)
                }
                
                Slider(
                    value: Binding(
                        get: { appState.pollingInterval },
                        set: { appState.pollingInterval = $0 }
                    ),
                    in: 1...30,
                    step: 1
                )
                .tint(.orange)
                
                Text("How often to refresh data from the gateway")
                    .font(.ClawK.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Discovery Card

struct DiscoveryCard: View {
    @ObservedObject private var config = AppConfiguration.shared
    @State private var isRediscovering = false
    
    var body: some View {
        DSCard(
            title: "🔍 AUTO-DISCOVERY",
            color: .purple,
            tooltip: "OpenClaw installation discovery and agent configuration"
        ) {
            VStack(spacing: 16) {
                // Discovery Status
                HStack {
                    Text("Status")
                        .foregroundColor(.secondary)
                    Spacer()
                    if config.isConfigured {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Configured")
                                .font(.ClawK.caption)
                                .foregroundColor(.green)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Not Configured")
                                .font(.ClawK.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                if let error = config.configError {
                    ErrorBanner(message: error)
                }
                
                Divider()
                
                // Agent Name
                HStack {
                    Text("Agent Name")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(config.agentName)
                        .font(.ClawK.valueMono)
                        .foregroundColor(.purple)
                }
                
                Divider()
                
                // Discovered Paths (read-only)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Discovered Paths")
                        .font(.ClawK.caption)
                        .foregroundColor(.secondary)
                    
                    DiscoveryPathRow(label: "OpenClaw Home", path: config.openclawHome)
                    DiscoveryPathRow(label: "Workspace", path: config.workspacePath)
                    DiscoveryPathRow(label: "Memory", path: config.memoryPath)
                    DiscoveryPathRow(label: "Sessions", path: config.sessionsPath)
                    DiscoveryPathRow(label: "Memory DB", path: config.memoryDbPath)
                    DiscoveryPathRow(label: "Config", path: config.configPath)
                }
                
                Divider()
                
                // Re-discover button
                Button(action: {
                    isRediscovering = true
                    config.discover()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isRediscovering = false
                    }
                }) {
                    HStack {
                        if isRediscovering {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.clockwise.circle.fill")
                        }
                        Text("Re-discover")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(isRediscovering)
            }
        }
    }
}

struct DiscoveryPathRow: View {
    let label: String
    let path: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.ClawK.captionSmall)
                .foregroundColor(Color.Text.tertiary)
            Text(path.isEmpty ? "—" : shortenPath(path))
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
    
    private func shortenPath(_ path: String) -> String {
        // Replace home directory with ~
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - About Card

struct AboutCard: View {
    /// Build date derived from the app bundle creation date
    private static var buildDateString: String = {
        if let bundleURL = Bundle.main.executableURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: bundleURL.path),
           let creationDate = attrs[.creationDate] as? Date {
            return creationDate.formatted(date: .abbreviated, time: .omitted)
        }
        return "Unknown"
    }()
    
    var body: some View {
        DSCard(
            title: "ℹ️ ABOUT",
            color: Color.CardHeader.about
        ) {
            VStack(spacing: Spacing.xl) {
                // App Logo
                HStack {
                    Text("🦞")
                        .font(.system(size: 48))
                    
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("ClawK")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("OpenClaw Companion")
                            .font(.ClawK.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                
                Divider()
                
                // Info rows
                DSSettingsRow(label: "Version", value: "1.0.0", mono: true)
                DSSettingsRow(label: "Build", value: Self.buildDateString, mono: true)
                
                Divider()
                
                Text("A macOS menu bar companion for OpenClaw Gateway. Monitor cron jobs, sessions, and explore your AI's memory.")
                    .font(.ClawK.caption)
                    .foregroundColor(.secondary)
                
                Divider()
                
                // Run Onboarding
                Button(action: {
                    UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                    
                    // Show welcome window directly
                    NSApp.setActivationPolicy(.regular)
                    
                    let welcomeView = WelcomeView(onComplete: {
                        // After onboarding, go back to accessory mode
                        NSApp.setActivationPolicy(.accessory)
                    })
                    let hostingController = NSHostingController(rootView: welcomeView)
                    let window = NSWindow(contentViewController: hostingController)
                    window.title = "Welcome to ClawK"
                    window.styleMask = [.titled, .closable, .miniaturizable]
                    window.setContentSize(NSSize(width: 580, height: 700))
                    window.isReleasedWhenClosed = false
                    window.center()
                    window.backgroundColor = NSColor.black
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Run Setup Wizard Again")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundColor(.accentColor)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                // Credits
                VStack(spacing: 4) {
                    Text("Built by Dushyant Garg")
                        .font(.ClawK.caption)
                        .foregroundColor(.secondary)
                    Text("Built with SwiftUI")
                        .font(.ClawK.captionSmall)
                        .foregroundColor(Color.Text.tertiary)
                }
            }
        }
    }
}

// MARK: - Helper Components

struct StatusBadge: View {
    let isConnected: Bool
    let connectedText: String
    let disconnectedText: String
    
    var body: some View {
        DSConnectionBadge(
            isConnected: isConnected,
            connectedLabel: connectedText,
            disconnectedLabel: disconnectedText
        )
    }
}

struct SettingsTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isCustom: Bool = false
    var onSave: () -> Void
    var onReset: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .foregroundColor(.secondary)
                Spacer()
                if isCustom {
                    Text("Custom")
                        .font(.ClawK.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }
            }
            
            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                
                Button(action: onSave) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .help("Save")
                
                if isCustom, let reset = onReset {
                    Button(action: reset) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .help("Reset to default")
                }
            }
        }
    }
}

struct SettingsSecureField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    @Binding var showText: Bool
    var isConfigured: Bool = false
    var onSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .foregroundColor(.secondary)
                Spacer()
                if isConfigured {
                    Text("Configured")
                        .font(.ClawK.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(.green)
                        .cornerRadius(4)
                } else {
                    Text("Not Set")
                        .font(.ClawK.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.15))
                        .foregroundColor(.red)
                        .cornerRadius(4)
                }
            }
            
            HStack(spacing: 8) {
                Group {
                    if showText {
                        TextField(placeholder, text: $text)
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                
                Button(action: { showText.toggle() }) {
                    Image(systemName: showText ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(showText ? "Hide" : "Show")
                
                Button(action: onSave) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .help("Save")
            }
        }
    }
}

struct ErrorBanner: View {
    let message: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.ClawK.caption)
                .foregroundColor(.red.opacity(0.9))
                .lineLimit(3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
}

struct SettingsInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

// Preview removed for SPM compatibility
