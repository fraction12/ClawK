//
//  MainWindowView.swift
//  ClawK
//
//  Main window content wrapper for menu bar app
//

import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var menuBarManager: MenuBarManager
    @State private var selectedTab = "mission"
    @State private var showQuickActions = false
    @State private var showSendMessage = false
    @StateObject private var memoryViewModel = MemoryViewModel()
    
    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView(selectedTab: $selectedTab)
            } detail: {
                VStack(spacing: 0) {
                    // Connection status banner — sits at top of detail area
                    ConnectionStatusBanner()
                    
                    Group {
                        switch selectedTab {
                        case "memory":
                            if MemoryNotConfiguredView.isMemoryConfigured {
                                MemoryBrowserView()
                            } else {
                                MemoryNotConfiguredView()
                            }
                        case "vitals":
                            if MemoryNotConfiguredView.isMemoryConfigured {
                                MemoryVitalsView(viewModel: memoryViewModel)
                            } else {
                                MemoryNotConfiguredView()
                            }
                        case "mission":
                            MissionControlView()
                        case "canvas":
                            CanvasView()
                        case "talk":
                            TalkView()
                        case "settings":
                            SettingsView()
                        default:
                            MissionControlView()
                        }
                    }
                    .id(selectedTab)
                }
            }
            
            // Quick Actions Overlay
            if showQuickActions {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showQuickActions = false
                    }
                    .transition(.opacity)
                
                QuickActionsView(isPresented: $showQuickActions)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
            
            // Send Message Overlay
            if showSendMessage {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showSendMessage = false
                    }
                    .transition(.opacity)
                
                SendMessageView(isPresented: $showSendMessage)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        // Apply monochrome filter when enabled
        .grayscale(appState.isMonochrome ? 1.0 : 0.0)
        .animation(.easeOut(duration: 0.15), value: showQuickActions)
        .animation(.easeOut(duration: 0.15), value: showSendMessage)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showSendMessage = true }) {
                    Image(systemName: "paperplane")
                }
                .help("Send to ClawK (⌘J)")
                .keyboardShortcut("j", modifiers: .command)
            }
            
            ToolbarItem(placement: .automatic) {
                Button(action: { showQuickActions = true }) {
                    Image(systemName: "command")
                }
                .help("Quick Actions (⌘K)")
                .keyboardShortcut("k", modifiers: .command)
            }
        }
        .onKeyPress(keys: [.init("k")], phases: .down) { press in
            if press.modifiers.contains(.command) {
                showQuickActions.toggle()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(keys: [.init("j")], phases: .down) { press in
            if press.modifiers.contains(.command) {
                showSendMessage.toggle()
                return .handled
            }
            return .ignored
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToTab)) { notification in
            if let tab = notification.object as? String {
                selectedTab = tab
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showQuickActions)) { _ in
            showQuickActions = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSendMessage)) { _ in
            showSendMessage = true
        }
        // Polling is started by AppDelegate — no need to start here
    }
}
