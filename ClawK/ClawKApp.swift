//
//  ClawKApp.swift
//  ClawK
//
//  OpenClaw: ClawK Edition - Menu Bar Mission Control Dashboard
//

import SwiftUI
import AppKit
import Carbon.HIToolbox

@main
struct ClawKApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Empty scene - we manage windows through the menu bar
        Settings {
            EmptyView()
        }
    }
}

// MARK: - Deep Link Destination

enum DeepLinkDestination: String {
    case missionControl = "mission-control"
    case memory = "memory"
    case canvas = "canvas"
    case settings = "settings"
    case talk = "talk"

    static func from(url: URL) -> DeepLinkDestination? {
        guard url.scheme == "clawk" else { return nil }
        return DeepLinkDestination(rawValue: url.host ?? "")
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var menuBarManager: MenuBarManager?
    var appState: AppState?
    var welcomeWindow: NSWindow?
    var talkOverlayPanel: TalkOverlayPanel?
    private var hotkeyRef: EventHotKeyRef?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Singleton check - only one instance allowed
        let runningApps = NSWorkspace.shared.runningApplications
        let existingInstances = runningApps.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0 != NSRunningApplication.current
        }
        if !existingInstances.isEmpty {
            // Activate existing instance and exit
            existingInstances.first?.activate()
            NSApp.terminate(nil)
            return
        }
        
        // Run discovery on launch
        AppConfiguration.shared.discover()
        
        // Check if onboarding is needed
        let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        
        if !hasCompleted {
            // Show Welcome / Onboarding (first run or config became invalid)
            // Do NOT set .accessory yet — welcome window needs dock presence
            showWelcomeWindow()
        } else if !AppConfiguration.shared.isConfigured {
            // Previously completed but config is now invalid — re-onboard
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
            showWelcomeWindow()
        } else {
            // Hide dock icon (only when skipping onboarding)
            NSApp.setActivationPolicy(.accessory)
            launchMainApp()
        }
        
        // Register URL scheme handler
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }
    
    /// Launch the main menu bar app (called after onboarding or directly)
    private func launchMainApp() {
        // Close welcome window if open
        welcomeWindow?.close()
        welcomeWindow = nil
        
        // Hide dock icon again (in case we showed it during onboarding)
        NSApp.setActivationPolicy(.accessory)
        
        Task { @MainActor in
            // Initialize state
            let state = AppState()
            self.appState = state
            
            // Initialize menu bar manager
            let manager = MenuBarManager()
            self.menuBarManager = manager
            
            manager.setup(appState: state)

            // Start polling
            state.startPolling()

            // Initialize Talk Mode — start TTS server at app launch (Bug 1 + 4)
            TalkConversationManager.shared.startTTSServer()

            // Register global hotkey (Option+Space)
            self.registerTalkHotkey()
        }
    }

    // MARK: - Talk Mode Hotkey

    private func registerTalkHotkey() {
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(0x434C574B) // "CLWK"
        hotKeyID.id = 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            Task { @MainActor in
                guard let delegate = NSApp.delegate as? AppDelegate else { return }
                delegate.toggleTalkOverlay()
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, nil)

        // Option+Space: kVK_Space = 0x31, optionKey modifier = 0x0800
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(optionKey), hotKeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
    }

    @MainActor
    func toggleTalkOverlay() {
        if let panel = talkOverlayPanel, panel.isVisible {
            panel.orderOut(nil)
            return
        }

        if talkOverlayPanel == nil {
            let panel = TalkOverlayPanel()
            let contentView = TalkOverlayContentView(conversationManager: TalkConversationManager.shared)
            panel.contentViewController = NSHostingController(rootView: contentView)
            self.talkOverlayPanel = panel
        }

        talkOverlayPanel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Show the first-run welcome window
    /// Show the first-run welcome window (also callable from Settings)
    func showWelcomeWindow() {
        Task { @MainActor in
            let welcomeView = WelcomeView(onComplete: { [weak self] in
                self?.launchMainApp()
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
            // Temporarily show in dock during onboarding
            NSApp.setActivationPolicy(.regular)
            
            self.welcomeWindow = window
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        appState?.flushHeartbeatHistory()
        appState?.stopPolling()
        TalkConversationManager.shared.stopTTSServer()
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Show window when clicking dock icon (if it ever appears)
        Task { @MainActor in
            menuBarManager?.showMainWindow()
        }
        return true
    }
    
    // MARK: - URL Scheme Handler
    
    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        
        handleDeepLink(url)
    }
    
    private func handleDeepLink(_ url: URL) {
        guard let destination = DeepLinkDestination.from(url: url) else {
            debugLog("Unknown deep link: \(url)")
            return
        }
        
        Task { @MainActor in
            // Always show main window first
            menuBarManager?.showMainWindow()
            
            // Navigate to the appropriate view
            switch destination {
            case .missionControl:
                menuBarManager?.navigateTo(.missionControl)
            case .memory:
                menuBarManager?.navigateTo(.memory)
            case .canvas:
                menuBarManager?.navigateTo(.canvas)
            case .settings:
                menuBarManager?.navigateTo(.settings)
            case .talk:
                menuBarManager?.navigateTo(.talk)
            }
        }
    }
}
