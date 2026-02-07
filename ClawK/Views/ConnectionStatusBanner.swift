//
//  ConnectionStatusBanner.swift
//  ClawK
//
//  Persistent connection status banner for the main app.
//  Phase 3: Shows gateway connection issues with actionable recovery.
//

import SwiftUI

struct ConnectionStatusBanner: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var config = AppConfiguration.shared
    @State private var isRetrying = false
    @State private var showBanner = false
    @State private var retryCount = 0
    
    var body: some View {
        Group {
            if !config.isConfigured {
                // Configuration error banner
                configBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if showBanner && !appState.isConnected && !appState.isInitialLoad {
                // Disconnection banner
                disconnectedBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(DSAnimation.standard, value: showBanner)
        .animation(DSAnimation.standard, value: appState.isConnected)
        .animation(DSAnimation.standard, value: config.isConfigured)
        .onChange(of: appState.isConnected) { _, isConnected in
            if isConnected {
                // Auto-dismiss when reconnected
                withAnimation(DSAnimation.standard) {
                    showBanner = false
                    retryCount = 0
                }
            } else if !appState.isInitialLoad {
                // Show after a brief delay to avoid flash on startup
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    if !appState.isConnected {
                        withAnimation(DSAnimation.standard) {
                            showBanner = true
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Config Error Banner
    
    private var configBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.white)
                .font(.system(size: 14))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Configuration Issue")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(config.configError ?? "OpenClaw configuration not found.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: {
                config.discover()
            }) {
                Text("Re-scan")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.9))
        .cornerRadius(8)
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
    
    // MARK: - Disconnected Banner
    
    private var disconnectedBanner: some View {
        HStack(spacing: 10) {
            // Pulsing dot
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(Color.red.opacity(0.5), lineWidth: 2)
                        .scaleEffect(1.5)
                        .opacity(isRetrying ? 0 : 0.8)
                        .animation(
                            .easeOut(duration: 1).repeatForever(autoreverses: false),
                            value: isRetrying
                        )
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Gateway Disconnected")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                
                Text("Can't reach \(config.gatewayURL) — \(retryCount > 0 ? "Retried \(retryCount)×" : "Retrying...")")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: {
                reconnect()
            }) {
                HStack(spacing: 4) {
                    if isRetrying {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                    }
                    Text("Reconnect")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.2))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .disabled(isRetrying)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [Color.red.opacity(0.85), Color.red.opacity(0.7)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(8)
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
    
    private func reconnect() {
        isRetrying = true
        retryCount += 1
        
        Task {
            await appState.manualRefresh()
            isRetrying = false
        }
    }
}
