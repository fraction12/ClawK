//
//  MemoryBrowserView.swift
//  ClawK
//
//  Main Memory Browser view with sidebar and content
//

import SwiftUI

struct MemoryBrowserView: View {
    @StateObject private var viewModel = MemoryViewModel()
    @State private var windowWidth: CGFloat = 1000
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: Spacing.xxl) {
                    // Header
                    MemoryHeaderView(viewModel: viewModel)
                    
                    // Main Content - Responsive layout
                    if geometry.size.width > Spacing.Layout.wideBreakpoint {
                        // Two-column layout for wide windows
                        HStack(alignment: .top, spacing: Spacing.xxl) {
                            MemoryTreeCard(viewModel: viewModel)
                                .frame(minWidth: 320, idealWidth: 380, maxWidth: 480)
                            
                            MemoryContentCard(viewModel: viewModel)
                                .frame(minWidth: 400)
                        }
                    } else {
                        // Single-column layout for narrow windows
                        VStack(spacing: Spacing.xxl) {
                            MemoryTreeCard(viewModel: viewModel)
                                .frame(maxWidth: .infinity)
                            
                            MemoryContentCard(viewModel: viewModel)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .pagePadding()
            }
            .background(Color.Surface.primary)
            .onChange(of: geometry.size.width) { _, newWidth in
                windowWidth = newWidth
            }
        }
        .task {
            await viewModel.loadInitialData()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                DSRefreshButton(action: {
                    Task { await viewModel.refresh() }
                }, isRefreshing: viewModel.isLoading)
            }
        }
    }
}

// MARK: - Header

struct MemoryHeaderView: View {
    @ObservedObject var viewModel: MemoryViewModel
    
    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Title row
            DSPageHeader(
                emoji: "🧠",
                title: "MEMORY",
                subtitle: "Memory system browser & search"
            )
            
            // Controls row
            HStack(spacing: Spacing.xl) {
                // View mode picker - label hidden to prevent wrapping
                Picker("", selection: $viewModel.viewMode) {
                    ForEach(MemoryViewMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode.icon)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("View mode")
                .frame(minWidth: 240, maxWidth: 280)
                
                Spacer()
                
                // Search field
                HStack(spacing: Spacing.md) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13))
                    
                    TextField("Search memory...", text: $viewModel.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(.body))
                        .frame(minWidth: 150, maxWidth: 200)
                        .onSubmit {
                            // Immediate search on Enter
                            if !viewModel.searchQuery.isEmpty {
                                viewModel.viewMode = .search
                                Task {
                                    await viewModel.performSearch(query: viewModel.searchQuery)
                                }
                            }
                        }
                    
                    if viewModel.isSearching {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 16, height: 16)
                    } else if !viewModel.searchQuery.isEmpty {
                        Button(action: { 
                            viewModel.searchQuery = ""
                            viewModel.searchResults = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary.opacity(0.8))
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.md)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
            }
        }
        .padding(.bottom, Spacing.md)
    }
}

// MARK: - Tree Card

struct MemoryTreeCard: View {
    @ObservedObject var viewModel: MemoryViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.Card.contentSpacing) {
            // Header
            DSCardHeader(
                title: "📁 FILE BROWSER",
                color: Color.CardHeader.fileBrowser,
                trailing: viewModel.stats.map { stats in
                    AnyView(
                        HStack(spacing: Spacing.lg) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "doc.text")
                                    .font(.ClawK.caption)
                                Text("\(stats.totalFiles)")
                                    .font(.ClawK.numberSmall)
                            }
                            .foregroundColor(.secondary)
                            
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "textformat.abc")
                                    .font(.ClawK.caption)
                                Text(formatTokens(stats.totalTokens))
                                    .font(.ClawK.numberSmall)
                            }
                            .foregroundColor(.secondary)
                        }
                    )
                }
            )
            
            Divider()
            
            // Content
            if viewModel.isLoading && viewModel.memoryStructure.isEmpty {
                // Skeleton loading state for file tree
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    // Hot tier skeleton
                    HStack(spacing: Spacing.sm) {
                        SkeletonBox(width: Spacing.xxl, height: Spacing.xxl, cornerRadius: Spacing.xs)
                        SkeletonBox(width: 100, height: Spacing.xl, cornerRadius: Spacing.xs)
                    }
                    .padding(.bottom, Spacing.xs)
                    
                    ForEach(0..<4, id: \.self) { _ in
                        SkeletonFileTreeItem(indent: Spacing.xxl)
                    }
                    
                    // Warm tier skeleton
                    HStack(spacing: Spacing.sm) {
                        SkeletonBox(width: Spacing.xxl, height: Spacing.xxl, cornerRadius: Spacing.xs)
                        SkeletonBox(width: 110, height: Spacing.xl, cornerRadius: Spacing.xs)
                    }
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xs)
                    
                    ForEach(0..<2, id: \.self) { _ in
                        SkeletonFileTreeItem(indent: Spacing.xxl)
                    }
                    
                    // Cold tier skeleton
                    HStack(spacing: Spacing.sm) {
                        SkeletonBox(width: Spacing.xxl, height: Spacing.xxl, cornerRadius: Spacing.xs)
                        SkeletonBox(width: 90, height: Spacing.xl, cornerRadius: Spacing.xs)
                    }
                    .padding(.top, Spacing.lg)
                    .padding(.bottom, Spacing.xs)
                    
                    ForEach(0..<2, id: \.self) { _ in
                        SkeletonFileTreeItem(indent: Spacing.xxl)
                    }
                }
                .padding(.bottom, Spacing.md)
                .frame(minHeight: Spacing.Layout.cardMinHeight, maxHeight: Spacing.Layout.cardMaxHeight)
            } else if viewModel.isLoading {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        // Hot tier
                        MemoryTierSection(
                            tier: .hot,
                            files: viewModel.memoryStructure.hot,
                            viewModel: viewModel
                        )
                        
                        // Warm tier
                        MemoryTierSection(
                            tier: .warm,
                            folders: viewModel.memoryStructure.warm,
                            viewModel: viewModel
                        )
                        
                        // Cold tier
                        MemoryTierSection(
                            tier: .cold,
                            folders: viewModel.memoryStructure.cold,
                            viewModel: viewModel
                        )
                        
                        // Archive tier
                        MemoryTierSection(
                            tier: .archive,
                            files: viewModel.memoryStructure.archive,
                            viewModel: viewModel
                        )
                    }
                    .padding(.bottom, Spacing.md)
                }
                .frame(minHeight: Spacing.Layout.cardMinHeight, maxHeight: Spacing.Layout.cardMaxHeight)
            }
        }
        .padding(Spacing.Card.padding)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(Spacing.Card.cornerRadius)
        .shadow(color: Color.Shadow.color, radius: Spacing.Shadow.radius, x: 0, y: Spacing.Shadow.y)
    }
    
    private func formatTokens(_ count: Int) -> String {
        count.formattedTokens
    }
}

// MARK: - Content Card

struct MemoryContentCard: View {
    @ObservedObject var viewModel: MemoryViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Header
            HStack {
                switch viewModel.viewMode {
                case .search:
                    Text("🔍 SEARCH RESULTS")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(Color.Accent.model)
                case .browse:
                    Text("📄 FILE PREVIEW")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.green)
                case .visualization:
                    Text("🎨 3D VISUALIZATION")
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.orange)
                }
                
                Spacer()
            }
            
            Divider()
            
            // Content
            Group {
                switch viewModel.viewMode {
                case .search:
                    MemorySearchResultsView(viewModel: viewModel)
                case .browse:
                    MemoryFilePreviewView(viewModel: viewModel)
                case .visualization:
                    Memory3DVisualizationView(viewModel: viewModel)
                }
            }
            .frame(minHeight: Spacing.Layout.cardMinHeight, maxHeight: Spacing.Layout.cardMaxHeight)
        }
        .padding(Spacing.Card.padding)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(Spacing.Card.cornerRadius)
        .shadow(color: Color.Shadow.color, radius: Spacing.Shadow.radius, x: 0, y: Spacing.Shadow.y)
    }
}
