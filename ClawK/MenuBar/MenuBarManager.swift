//
//  MenuBarManager.swift
//  ClawK
//
//  Manages the menu bar status item and popover
//

import SwiftUI
import AppKit
import Combine

@MainActor
class MenuBarManager: ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var mainWindow: NSWindow?
    private var eventMonitor: Any?
    private var hoverView: StatusItemHoverView?
    
    @Published var isWindowVisible = false
    @Published var isPopoverVisible = false
    
    weak var appState: AppState?
    private var terminationObserver: NSObjectProtocol?
    
    init() {
        // Register for app termination to ensure cleanup of global event monitors
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Ensure cleanup runs on main actor
            Task { @MainActor in
                self?.cleanup()
            }
        }
    }
    
    deinit {
        // Remove termination observer
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        // Ensure event monitor cleanup (defensive - may be on non-main thread in deinit)
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    /// Cleanup all resources - called on app termination
    private func cleanup() {
        stopEventMonitor()
        // Close windows gracefully
        mainWindow?.close()
        popover?.close()
    }
    
    func setup(appState: AppState) {
        self.appState = appState
        setupStatusItem()
        setupPopover()
    }
    
    // MARK: - Status Item Setup
    
    private func setupStatusItem() {
        // Fixed width with padding for breathing room (Priority 3: Menu Bar Spacing)
        statusItem = NSStatusBar.system.statusItem(withLength: 42)
        
        if let button = statusItem?.button {
            // Create custom view for hover detection with proper padding
            let hoverView = StatusItemHoverView(frame: NSRect(x: 0, y: 0, width: 42, height: 22))
            // Create white lobster emoji icon
            let icon = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                let lobsterEmoji = "🦞"
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 14),
                    .foregroundColor: NSColor.white
                ]
                let textSize = lobsterEmoji.size(withAttributes: attrs)
                let point = NSPoint(
                    x: (rect.width - textSize.width) / 2,
                    y: (rect.height - textSize.height) / 2
                )
                lobsterEmoji.draw(at: point, withAttributes: attrs)
                return true
            }
            icon.isTemplate = false
            hoverView.icon = icon
            hoverView.horizontalPadding = 8  // Add padding on each side
            hoverView.onLeftClick = { [weak self] in
                self?.toggleMainWindow()
            }
            hoverView.onRightClick = { [weak self] in
                self?.showContextMenu()
            }
            hoverView.onMouseEnter = { [weak self] in
                self?.showPopover()
            }
            hoverView.onMouseExit = { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    guard let self = self else { return }
                    if !self.isMouseOverPopover() {
                        self.hidePopover()
                    }
                }
            }
            
            button.addSubview(hoverView)
            hoverView.frame = button.bounds
            hoverView.autoresizingMask = [.width, .height]
            
            self.hoverView = hoverView
        }
    }
    
    // MARK: - Popover Setup
    
    private func setupPopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 280, height: 260)
        
        if let appState = appState {
            let contentView = EnhancedQuickStatsView(onOpenWindow: { [weak self] in
                self?.showMainWindow()
            })
            .environmentObject(appState)
            popover.contentViewController = NSHostingController(rootView: contentView)
        }
        
        self.popover = popover
    }
    
    // MARK: - Hover Helpers
    
    private func isMouseOverPopover() -> Bool {
        guard let popover = popover, popover.isShown,
              let contentView = popover.contentViewController?.view else {
            return false
        }
        
        let mouseLocation = NSEvent.mouseLocation
        let windowFrame = contentView.window?.frame ?? .zero
        return windowFrame.contains(mouseLocation)
    }
    
    // MARK: - Popover Control
    
    func showPopover() {
        guard let button = statusItem?.button, let popover = popover else { return }
        
        // Update popover content
        if let appState = appState {
            let contentView = EnhancedQuickStatsView(onOpenWindow: { [weak self] in
                self?.hidePopover()
                self?.showMainWindow()
            })
            .environmentObject(appState)
            .grayscale(appState.isMonochrome ? 1.0 : 0.0)
            popover.contentViewController = NSHostingController(rootView: contentView)
        }
        
        if !popover.isShown && !isWindowVisible {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            isPopoverVisible = true
        }
    }
    
    func hidePopover() {
        popover?.performClose(nil)
        isPopoverVisible = false
    }
    
    // MARK: - Main Window Control
    
    func toggleMainWindow() {
        hidePopover()
        
        if isWindowVisible {
            hideMainWindow()
        } else {
            showMainWindow()
        }
    }
    
    func showMainWindow() {
        if mainWindow == nil {
            createMainWindow()
        }
        
        guard let window = mainWindow else { return }
        
        // Priority 2: Center window on screen (not near menu bar)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = window.frame.size
            
            // Calculate center position
            let x = screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2
            let y = screenFrame.origin.y + (screenFrame.height - windowSize.height) / 2
            
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        isWindowVisible = true
        
        // REMOVED: Auto-close on outside click - window should only close on explicit Close/Minimize
        // startEventMonitor()
    }
    
    func hideMainWindow() {
        mainWindow?.orderOut(nil)
        isWindowVisible = false
        stopEventMonitor()
    }
    
    private func createMainWindow() {
        guard let appState = appState else { return }
        
        let contentView = MainWindowView(menuBarManager: self)
            .environmentObject(appState)
        
        let hostingController = NSHostingController(rootView: contentView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "ClawK Mission Control"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 900, height: 700))
        window.minSize = NSSize(width: 800, height: 600)
        window.isReleasedWhenClosed = false
        window.level = .floating
        
        // Use WindowDelegate wrapper for Main Actor compatibility
        let delegate = WindowDelegateWrapper { [weak self] in
            self?.isWindowVisible = false
            self?.stopEventMonitor()
        }
        window.delegate = delegate
        
        // Keep strong reference to delegate
        objc_setAssociatedObject(window, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        
        // Rounded corners
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = false
        
        self.mainWindow = window
    }
    
    // MARK: - Context Menu
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        let openItem = NSMenuItem(title: "Open Mission Control", action: #selector(openMissionControl), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshData), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let quitItem = NSMenuItem(title: "Quit ClawK", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }
    
    @objc private func openMissionControl() {
        showMainWindow()
    }
    
    @objc private func refreshData() {
        Task {
            await appState?.refresh()
        }
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    // MARK: - Navigation
    
    enum NavigationDestination {
        case missionControl
        case memory
        case canvas
        case settings
        case vitals
        case talk

        var tabName: String {
            switch self {
            case .missionControl: return "mission"
            case .memory: return "memory"
            case .canvas: return "canvas"
            case .settings: return "settings"
            case .vitals: return "vitals"
            case .talk: return "talk"
            }
        }
    }
    
    func navigateTo(_ destination: NavigationDestination) {
        NotificationCenter.default.post(name: .navigateToTab, object: destination.tabName)
    }
    
    // MARK: - Event Monitor
    
    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let window = self.mainWindow else { return }
            
            let mouseLocation = NSEvent.mouseLocation
            if !window.frame.contains(mouseLocation) {
                // Check if clicking on status item
                if let button = self.statusItem?.button,
                   let buttonWindow = button.window {
                    let buttonFrame = buttonWindow.convertToScreen(button.frame)
                    if buttonFrame.contains(mouseLocation) {
                        return // Don't hide if clicking status item
                    }
                }
                
                DispatchQueue.main.async {
                    self.hideMainWindow()
                }
            }
        }
    }
    
    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}

// MARK: - Status Item Hover View

/// Custom view that handles hover and click events for the status item
class StatusItemHoverView: NSView {
    var title: String = "" {
        didSet { needsDisplay = true }
    }
    
    var icon: NSImage? {
        didSet { needsDisplay = true }
    }
    
    /// Horizontal padding on each side for breathing room (Priority 3)
    var horizontalPadding: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onMouseEnter: (() -> Void)?
    var onMouseExit: (() -> Void)?
    
    private var trackingArea: NSTrackingArea?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTrackingArea()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTrackingArea()
    }
    
    private func setupTrackingArea() {
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect
        ]
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        if let area = trackingArea {
            addTrackingArea(area)
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        setupTrackingArea()
    }
    
    override func draw(_ dirtyRect: NSRect) {
        if let icon = icon {
            // Draw template image (will render as white in menu bar)
            let iconSize: CGFloat = 18  // Standard menu bar icon size
            let rect = NSRect(
                x: (bounds.width - iconSize) / 2,
                y: (bounds.height - iconSize) / 2 + 1,  // Slight vertical adjustment
                width: iconSize,
                height: iconSize
            )
            icon.draw(in: rect)
        } else if !title.isEmpty {
            // Fallback to text if no icon
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16)
            ]
            let textSize = title.size(withAttributes: attributes)
            let point = NSPoint(
                x: (bounds.width - textSize.width) / 2,
                y: (bounds.height - textSize.height) / 2 + 1
            )
            title.draw(at: point, withAttributes: attributes)
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        // Don't call super - we handle it ourselves
    }
    
    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 1 {
            DispatchQueue.main.async { [weak self] in
                self?.onLeftClick?()
            }
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        // Don't call super - we handle it ourselves
    }
    
    override func rightMouseUp(with event: NSEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onRightClick?()
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onMouseEnter?()
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        DispatchQueue.main.async { [weak self] in
            self?.onMouseExit?()
        }
    }
}

// MARK: - Window Delegate Wrapper

/// Wraps window delegate to work with Main Actor
class WindowDelegateWrapper: NSObject, NSWindowDelegate {
    private let onClose: () -> Void
    
    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }
    
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.onClose()
        }
    }
}
