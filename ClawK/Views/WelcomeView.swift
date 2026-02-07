//
//  WelcomeView.swift
//  ClawK
//
//  First-run welcome & onboarding experience.
//  Phase 3: Error States, Graceful Degradation, and First-Run Experience
//

import SwiftUI

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case detection = 1
    case confirmation = 2
}

// MARK: - Detection State

enum DetectionState: Equatable {
    case idle
    case scanning
    case found
    case notInstalled
    case notRunning
    case configError(String)
}

// MARK: - Welcome View

struct WelcomeView: View {
    @ObservedObject private var config = AppConfiguration.shared
    @State private var currentStep: OnboardingStep = .welcome
    @State private var detectionState: DetectionState = .idle
    @State private var customPath: String = ""
    @State private var showCustomPath = false
    @State private var isStartingGateway = false
    @State private var gatewayStartResult: String?
    
    /// Called when onboarding completes
    var onComplete: () -> Void
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.black,
                    Color(red: 0.05, green: 0.05, blue: 0.12)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Content
            VStack(spacing: 0) {
                // Step indicator
                StepIndicator(current: currentStep)
                    .padding(.top, 32)
                    .padding(.bottom, 24)
                
                // Main content area
                Group {
                    switch currentStep {
                    case .welcome:
                        WelcomeStepView {
                            withAnimation(DSAnimation.standard) {
                                currentStep = .detection
                            }
                        }
                    case .detection:
                        DetectionStepView(
                            detectionState: $detectionState,
                            customPath: $customPath,
                            showCustomPath: $showCustomPath,
                            isStartingGateway: $isStartingGateway,
                            gatewayStartResult: $gatewayStartResult,
                            onContinue: {
                                withAnimation(DSAnimation.standard) {
                                    currentStep = .confirmation
                                }
                            },
                            onBack: {
                                withAnimation(DSAnimation.standard) {
                                    currentStep = .welcome
                                }
                            }
                        )
                    case .confirmation:
                        ConfirmationStepView(
                            onLaunch: {
                                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                                onComplete()
                            },
                            onBack: {
                                withAnimation(DSAnimation.standard) {
                                    currentStep = .detection
                                }
                            }
                        )
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                
                Spacer()
            }
            .frame(maxWidth: 520)
        }
        .frame(minWidth: 580, minHeight: 520)
    }
}

// MARK: - Step Indicator

private struct StepIndicator: View {
    let current: OnboardingStep
    
    var body: some View {
        HStack(spacing: 12) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step.rawValue <= current.rawValue ? Color.accentColor : Color.white.opacity(0.2))
                    .frame(width: 8, height: 8)
                    .scaleEffect(step == current ? 1.3 : 1.0)
                    .animation(DSAnimation.springSmooth, value: current)
            }
        }
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStepView: View {
    let onGetStarted: () -> Void
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0
    
    var body: some View {
        ScrollView {
        VStack(spacing: 24) {
            Spacer(minLength: 20)
            
            // Logo area
            VStack(spacing: 16) {
                ZStack {
                    // Glow ring
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.accentColor.opacity(0.3), Color.clear],
                                center: .center,
                                startRadius: 30,
                                endRadius: 70
                            )
                        )
                        .frame(width: 140, height: 140)
                    
                    // Icon
                    Text("🦞")
                        .font(.system(size: 72))
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                .onAppear {
                    withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                        logoScale = 1.0
                        logoOpacity = 1.0
                    }
                }
                
                Text("Welcome to ClawK")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text("Your companion app for OpenClaw on macOS")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            // Features preview
            VStack(spacing: 12) {
                FeatureRow(icon: "gauge.with.dots.needle.bottom.50percent", title: "Mission Control", description: "Monitor sessions, cron jobs, and agent activity")
                FeatureRow(icon: "brain", title: "Memory Browser", description: "Explore your agent's memory with 3D visualization")
                FeatureRow(icon: "rectangle.on.rectangle", title: "Canvas Control", description: "Manage visual content your agent presents")
            }
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Get Started button
            Button(action: onGetStarted) {
                HStack(spacing: 8) {
                    Text("Get Started")
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
            
            Spacer(minLength: 10)
        }
        .frame(maxWidth: .infinity)
        } // ScrollView
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
    }
}

// MARK: - Step 2: Detection

private struct DetectionStepView: View {
    @ObservedObject private var config = AppConfiguration.shared
    @Binding var detectionState: DetectionState
    @Binding var customPath: String
    @Binding var showCustomPath: Bool
    @Binding var isStartingGateway: Bool
    @Binding var gatewayStartResult: String?
    let onContinue: () -> Void
    let onBack: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Detection content
            Group {
                switch detectionState {
                case .idle, .scanning:
                    ScanningView()
                case .found:
                    FoundView(onContinue: onContinue)
                case .notInstalled:
                    NotInstalledView(
                        showCustomPath: $showCustomPath,
                        customPath: $customPath,
                        onRetry: { startDetection() }
                    )
                case .notRunning:
                    NotRunningView(
                        isStartingGateway: $isStartingGateway,
                        gatewayStartResult: $gatewayStartResult,
                        onRetry: { startDetection() }
                    )
                case .configError(let msg):
                    ConfigErrorView(
                        message: msg,
                        onRetry: { startDetection() }
                    )
                }
            }
            
            Spacer()
            
            // Back button
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                    Text("Back")
                }
                .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 32)
        }
        .onAppear {
            if detectionState == .idle {
                startDetection()
            }
        }
    }
    
    private func startDetection() {
        detectionState = .scanning
        
        // Run discovery after a brief delay for visual effect
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            config.discover()
            
            withAnimation(DSAnimation.standard) {
                if config.isConfigured {
                    detectionState = .found
                } else {
                    switch config.errorType {
                    case .openclawNotInstalled:
                        detectionState = .notInstalled
                    case .configNotFound, .gatewayNotRunning:
                        detectionState = .notRunning
                    case .configParseError:
                        detectionState = .configError(config.configError ?? "Configuration file is invalid.")
                    case .none:
                        detectionState = .found
                    }
                }
            }
        }
    }
}

// MARK: - Scanning State

private struct ScanningView: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 3)
                    .frame(width: 80, height: 80)
                
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(rotation))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            rotation = 360
                        }
                    }
                
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
            }
            
            Text("Looking for OpenClaw...")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
            
            Text("Scanning your system for an OpenClaw installation")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
        }
    }
}

// MARK: - Found State

private struct FoundView: View {
    @ObservedObject private var config = AppConfiguration.shared
    let onContinue: () -> Void
    @State private var checkScale: CGFloat = 0
    @State private var tokenInput: String = ""
    @State private var tokenStatus: TokenStatus = .empty
    @State private var isTestingToken: Bool = false
    
    enum TokenStatus {
        case empty, testing, valid, invalid
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Success icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.green)
                    .scaleEffect(checkScale)
                    .onAppear {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.5)) {
                            checkScale = 1
                        }
                    }
            }
            
            Text("OpenClaw Found!")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            
            // Discovered info
            VStack(alignment: .leading, spacing: 10) {
                DiscoveredInfoRow(icon: "folder", label: "Home", value: shortenPath(config.openclawHome))
                DiscoveredInfoRow(icon: "doc.text", label: "Workspace", value: shortenPath(config.workspacePath))
                DiscoveredInfoRow(icon: "network", label: "Gateway", value: config.gatewayURL)
                DiscoveredInfoRow(icon: "person", label: "Agent", value: config.agentName)
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal, 24)
            
            // Gateway Token input
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "key")
                        .foregroundColor(.accentColor)
                        .font(.system(size: 14))
                    Text("Gateway Token")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Status indicator
                    switch tokenStatus {
                    case .empty:
                        EmptyView()
                    case .testing:
                        ProgressView()
                            .scaleEffect(0.7)
                    case .valid:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 14))
                    case .invalid:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 14))
                    }
                }
                
                SecureField("Paste your gateway token here", text: $tokenInput)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)
                    .font(.system(size: 12, design: .monospaced))
                    .onChange(of: tokenInput) { _, newValue in
                        if newValue.count > 10 {
                            testToken(newValue)
                        } else {
                            tokenStatus = .empty
                        }
                    }
                
                Text("Find your token at: ~/.openclaw/gateway.token\nor run: cat ~/.openclaw/gateway.token")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                
                if tokenStatus == .invalid {
                    Text("Token rejected by gateway. Check that it's correct and the gateway is running.")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.8))
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal, 24)
            
            // Continue button
            Button(action: {
                // Save token before continuing
                if !tokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    GatewayConfig.shared.storedToken = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                onContinue()
            }) {
                HStack(spacing: 8) {
                    Text("Continue")
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(tokenStatus == .valid ? Color.green : Color.green.opacity(0.5))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
        }
        .onAppear {
            // Pre-fill if token already exists
            let existing = GatewayConfig.shared.token ?? ""
            if !existing.isEmpty {
                tokenInput = existing
                testToken(existing)
            }
        }
    }
    
    private func testToken(_ token: String) {
        tokenStatus = .testing
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = config.gatewayURL + "/tools/invoke"
        guard let url = URL(string: urlString) else { tokenStatus = .invalid; return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmed)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["tool": "sessions_list"])
        request.timeoutInterval = 5
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    tokenStatus = .valid
                } else {
                    tokenStatus = .invalid
                }
            }
        }.resume()
    }
    
    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

private struct DiscoveredInfoRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(.accentColor)
                .frame(width: 18)
            
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 70, alignment: .leading)
            
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Not Installed State

private struct NotInstalledView: View {
    @Binding var showCustomPath: Bool
    @Binding var customPath: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            
            Text("OpenClaw Not Found")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            
            Text("ClawK requires an OpenClaw installation to function.\nWe couldn't find one at ~/.openclaw")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            
            VStack(spacing: 12) {
                // Install link
                Link(destination: URL(string: "https://docs.openclaw.ai")!) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right.square")
                        Text("Install OpenClaw")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding(.horizontal, 40)
                
                // Custom path toggle
                Button(action: { withAnimation { showCustomPath.toggle() } }) {
                    HStack(spacing: 6) {
                        Image(systemName: showCustomPath ? "chevron.up" : "chevron.down")
                        Text("Custom installation?")
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                
                if showCustomPath {
                    HStack(spacing: 8) {
                        TextField("Path to ~/.openclaw", text: $customPath)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(8)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                        
                        Button("Apply") {
                            // Override home and re-discover
                            onRetry()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 40)
                }
                
                // Retry
                Button(action: onRetry) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Detection")
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Not Running State

private struct NotRunningView: View {
    @Binding var isStartingGateway: Bool
    @Binding var gatewayStartResult: String?
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bolt.slash.fill")
                .font(.system(size: 44))
                .foregroundColor(.yellow)
            
            Text("Gateway Not Running")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            
            Text("OpenClaw is installed but the configuration\nappears incomplete or the gateway isn't running.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            
            VStack(spacing: 12) {
                // Start gateway button
                Button(action: {
                    startGateway()
                }) {
                    HStack(spacing: 8) {
                        if isStartingGateway {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text("Start OpenClaw Gateway")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(isStartingGateway)
                .padding(.horizontal, 40)
                
                if let result = gatewayStartResult {
                    Text(result)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(result.contains("✓") ? .green : .orange)
                        .padding(.horizontal, 40)
                }
                
                // Retry
                Button(action: onRetry) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry Detection")
                    }
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func startGateway() {
        isStartingGateway = true
        gatewayStartResult = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["openclaw", "gateway", "start"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                DispatchQueue.main.async {
                    isStartingGateway = false
                    if process.terminationStatus == 0 {
                        gatewayStartResult = "✓ Gateway started. Retrying detection..."
                        // Auto-retry after gateway start
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            onRetry()
                        }
                    } else {
                        gatewayStartResult = "Could not start gateway: \(output.prefix(100))"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isStartingGateway = false
                    gatewayStartResult = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Config Error State

private struct ConfigErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.badge.gearshape.fill")
                .font(.system(size: 44))
                .foregroundColor(.red)
            
            Text("Configuration Error")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            // Copyable fix command
            VStack(alignment: .leading, spacing: 6) {
                Text("Try running:")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.4))
                
                HStack {
                    Text("openclaw gateway config.get")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.accentColor)
                    
                    Spacer()
                    
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("openclaw gateway config.get", forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
            }
            .padding(.horizontal, 40)
            
            Button(action: onRetry) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Step 3: Confirmation

private struct ConfirmationStepView: View {
    @ObservedObject private var config = AppConfiguration.shared
    let onLaunch: () -> Void
    let onBack: () -> Void
    @State private var rocketOffset: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            
            // Rocket icon
            Text("🚀")
                .font(.system(size: 56))
                .offset(y: rocketOffset)
                .onAppear {
                    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                        rocketOffset = -8
                    }
                }
            
            Text("You're All Set!")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            
            Text("Here's your configuration summary:")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
            
            // Configuration summary
            VStack(spacing: 1) {
                SummaryRow(label: "Gateway URL", value: config.gatewayURL, icon: "network")
                SummaryRow(label: "Agent Name", value: config.agentName, icon: "person.circle")
                SummaryRow(label: "Workspace", value: shortenPath(config.workspacePath), icon: "folder")
                SummaryRow(label: "Memory Path", value: shortenPath(config.memoryPath), icon: "brain")
                SummaryRow(label: "Sessions", value: shortenPath(config.sessionsPath), icon: "rectangle.stack")
            }
            .background(Color.white.opacity(0.03))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Launch button
            Button(action: onLaunch) {
                HStack(spacing: 8) {
                    Text("Launch ClawK")
                        .fontWeight(.bold)
                    Image(systemName: "arrow.right.circle.fill")
                }
                .font(.system(size: 16))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
            
            // Back
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                    Text("Back")
                }
                .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
        }
    }
    
    private func shortenPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

private struct SummaryRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(.accentColor)
                .frame(width: 24)
            
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
