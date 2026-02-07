//
//  QuickActionsView.swift
//  ClawK
//
//  Command palette for quick actions (⌘K)
//

import SwiftUI

// MARK: - Quick Action Model

struct QuickAction: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let icon: String
    let category: ActionCategory
    let action: () async -> Void
    
    enum ActionCategory: String, CaseIterable {
        case navigation = "Navigation"
        case cron = "Cron Jobs"
        case system = "System"
    }
}

// MARK: - Quick Actions View

struct QuickActionsView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var selectedIndex = 0
    @FocusState private var isSearchFocused: Bool
    
    var actions: [QuickAction] {
        var result: [QuickAction] = []
        
        // Navigation actions
        result.append(QuickAction(
            title: "Mission Control",
            subtitle: "View dashboard",
            icon: "gauge.with.dots.needle.bottom.50percent",
            category: .navigation,
            action: { 
                NotificationCenter.default.post(name: .navigateToTab, object: "mission")
                isPresented = false
            }
        ))
        
        result.append(QuickAction(
            title: "Memory Browser",
            subtitle: "Explore AI memory",
            icon: "brain",
            category: .navigation,
            action: {
                NotificationCenter.default.post(name: .navigateToTab, object: "memory")
                isPresented = false
            }
        ))
        
        result.append(QuickAction(
            title: "Canvas",
            subtitle: "Control visual canvas",
            icon: "rectangle.on.rectangle",
            category: .navigation,
            action: {
                NotificationCenter.default.post(name: .navigateToTab, object: "canvas")
                isPresented = false
            }
        ))
        
        result.append(QuickAction(
            title: "Settings",
            subtitle: "Configure app",
            icon: "gear",
            category: .navigation,
            action: {
                NotificationCenter.default.post(name: .navigateToTab, object: "settings")
                isPresented = false
            }
        ))
        
        // Cron job actions
        for job in appState.cronJobs.filter({ $0.isEnabled }) {
            result.append(QuickAction(
                title: "Run: \(job.name)",
                subtitle: job.scheduleDescription,
                icon: "play.circle",
                category: .cron,
                action: { [job] in
                    await triggerCronJob(job)
                    isPresented = false
                }
            ))
        }
        
        // System actions
        result.append(QuickAction(
            title: "Send to ClawK",
            subtitle: "Send a message to the main session",
            icon: "paperplane.fill",
            category: .system,
            action: {
                isPresented = false
                // Small delay to let this overlay dismiss first
                try? await Task.sleep(nanoseconds: 100_000_000)
                NotificationCenter.default.post(name: .showSendMessage, object: nil)
            }
        ))
        
        result.append(QuickAction(
            title: "Refresh Data",
            subtitle: "Update all dashboard data",
            icon: "arrow.clockwise",
            category: .system,
            action: {
                await appState.refresh()
                isPresented = false
            }
        ))
        
        return result
    }
    
    var filteredActions: [QuickAction] {
        if searchText.isEmpty {
            return actions
        }
        return actions.filter { action in
            action.title.localizedCaseInsensitiveContains(searchText) ||
            (action.subtitle?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.title3)
                
                TextField("Search actions...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isSearchFocused)
                    .onSubmit {
                        executeSelectedAction()
                    }
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Text("⌘K")
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Actions list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(filteredActions.enumerated()), id: \.element.id) { index, action in
                            QuickActionRow(
                                action: action,
                                isSelected: index == selectedIndex
                            )
                            .id(index)
                            .onTapGesture {
                                selectedIndex = index
                                executeSelectedAction()
                            }
                        }
                        
                        if filteredActions.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                    Text("No matching actions")
                                        .foregroundColor(.secondary)
                                }
                                .padding(40)
                                Spacer()
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: selectedIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
            
            Divider()
            
            // Footer hints
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption2)
                    Text("Navigate")
                        .font(.caption)
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "return")
                        .font(.caption2)
                    Text("Select")
                        .font(.caption)
                }
                
                HStack(spacing: 4) {
                    Text("esc")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(3)
                    Text("Close")
                        .font(.caption)
                }
                
                Spacer()
                
                Text("\(filteredActions.count) actions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.secondary)
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 500, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            selectedIndex = 0
            searchText = ""
            isSearchFocused = true
        }
        .onChange(of: searchText) { _, _ in
            selectedIndex = 0
        }
        .onKeyPress(.upArrow) {
            moveSelection(up: true)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveSelection(up: false)
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }
    
    private func moveSelection(up: Bool) {
        let count = filteredActions.count
        guard count > 0 else { return }
        
        if up {
            selectedIndex = selectedIndex > 0 ? selectedIndex - 1 : count - 1
        } else {
            selectedIndex = selectedIndex < count - 1 ? selectedIndex + 1 : 0
        }
    }
    
    private func executeSelectedAction() {
        guard selectedIndex < filteredActions.count else { return }
        let action = filteredActions[selectedIndex]
        Task {
            await action.action()
        }
    }
    
    private func triggerCronJob(_ job: CronJob) async {
        // This would call the gateway to trigger the job
        // For now, just refresh
        await appState.refresh()
    }
}

// MARK: - Quick Action Row

struct QuickActionRow: View {
    let action: QuickAction
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.body)
                    .foregroundColor(.primary)
                
                if let subtitle = action.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text(action.category.rawValue)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(8)
        .contentShape(Rectangle())
    }
    
    private var iconColor: Color {
        switch action.category {
        case .navigation: return .blue
        case .cron: return .orange
        case .system: return .green
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let navigateToTab = Notification.Name("navigateToTab")
    static let showQuickActions = Notification.Name("showQuickActions")
}
