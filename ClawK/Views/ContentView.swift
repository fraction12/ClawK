//
//  ContentView.swift
//  ClawK
//
//  Sidebar and supporting views for the main window
//

import SwiftUI

// Note: ContentView was removed — MainWindowView is the real root.
// SidebarView, MonochromeToggleButton, and ConnectionStatusView remain
// as they are used by MainWindowView.

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @Binding var selectedTab: String
    
    var body: some View {
        List(selection: $selectedTab) {
            Section("DASHBOARD") {
                Label("Mission Control", systemImage: "gauge.with.dots.needle.bottom.50percent")
                    .tag("mission")
                
                Label("Memory Browser", systemImage: "brain")
                    .tag("memory")
                
                Label("Memory Vitals", systemImage: "heart.text.square")
                    .tag("vitals")
                
                Label("Canvas", systemImage: "rectangle.on.rectangle")
                    .tag("canvas")
            }
            
            Section("CONFIGURATION") {
                Label("Settings", systemImage: "gear")
                    .tag("settings")
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                MonochromeToggleButton()
                ConnectionStatusView()
            }
            .padding()
        }
    }
}

struct MonochromeToggleButton: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.3)) {
                appState.isMonochrome.toggle()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: appState.isMonochrome ? "circle.fill" : "paintpalette.fill")
                    .font(.system(size: 12))
                    .foregroundColor(appState.isMonochrome ? .secondary : .accentColor)
                
                Text(appState.isMonochrome ? "Monochrome" : "Color Mode")
                    .font(.caption)
                    .foregroundColor(.primary)
                
                Spacer()
                
                // Visual indicator
                RoundedRectangle(cornerRadius: 4)
                    .fill(appState.isMonochrome ? Color.secondary : Color.accentColor)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .help(appState.isMonochrome ? "Switch to Color Mode" : "Switch to Monochrome Mode")
    }
}

struct ConnectionStatusView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            
            Text(appState.isConnected ? "Connected" : "Disconnected")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            // Only show loading spinner on initial load or manual refresh
            // Not during automatic background polling
            if appState.isLoading && (appState.isInitialLoad || appState.isManualRefresh) {
                ProgressView()
                    .scaleEffect(0.6)
            }
        }
    }
}

// Preview removed for SPM compatibility
