//
//  MemoryViewModel.swift
//  ClawK
//
//  ViewModel for the Memory Browser
//

import SwiftUI
import Combine
import os.log

enum MemoryViewMode: String, CaseIterable {
    case search = "Search"
    case browse = "Browse"
    case visualization = "3D Visualization"
    
    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .browse: return "folder"
        case .visualization: return "cube.transparent"
        }
    }
}

@MainActor
class MemoryViewModel: ObservableObject {
    // MARK: - Published State
    @Published var memoryStructure: MemoryStructure = .empty
    @Published var selectedFile: MemoryFile?
    @Published var fileContent: String = ""
    @Published var isLoadingContent: Bool = false
    
    @Published var searchQuery: String = ""
    @Published var searchResults: [MemorySearchResult] = []
    @Published var isSearching: Bool = false
    
    @Published var embeddingPoints: [EmbeddingPoint] = []
    @Published var isLoadingEmbeddings: Bool = false
    @Published var selectedPointId: String?
    
    @Published var stats: MemoryStats?
    @Published var viewMode: MemoryViewMode = .browse
    
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    @Published var expandedFolders: Set<String> = []
    
    // MARK: - Private
    private static let logger = Logger(subsystem: "ai.openclaw.clawk", category: "MemoryViewModel")
    private let service = MemoryService()
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Caching
    /// Last time stats were refreshed
    private var lastStatsRefresh: Date?
    /// Cache expiry interval (5 minutes)
    private static let statsCacheExpiry: TimeInterval = 300
    /// Last known modification date of memory directory
    private var lastMemoryDirModification: Date?
    
    init() {
        // Debounce search with proper handling
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()  // Don't re-search for same query
            .sink { [weak self] query in
                guard let self = self else { return }
                let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
                if !trimmedQuery.isEmpty {
                    debugLog("📝 Search query changed: '\(trimmedQuery)'")
                    Task { @MainActor in
                        await self.performSearch(query: trimmedQuery)
                    }
                } else {
                    self.searchResults = []
                    self.isSearching = false
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    
    func loadInitialData() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Run verification first (logs to console)
            await service.verifyMemoryData()
            
            memoryStructure = try await service.loadMemoryStructure()
            
            // Load stats with caching
            await loadStatsWithCache(force: false)
            
            // Log summary
            debugLog("✅ Memory loaded: \(memoryStructure.hot.count) hot, \(memoryStructure.warm.count) warm folders, \(memoryStructure.cold.count) cold folders")
            
            // Verify MEMORY.md is present
            if memoryStructure.hot.contains(where: { $0.name == "MEMORY.md" }) {
                debugLog("✅ MEMORY.md found in sidebar data")
            } else {
                debugLog("⚠️ MEMORY.md NOT in sidebar data!")
            }
        } catch {
            self.error = error.localizedDescription
            debugLog("❌ Load error: \(error.localizedDescription)")
        }
    }
    
    /// Load stats with caching - only refresh if cache expired or directory changed
    private func loadStatsWithCache(force: Bool) async {
        // Check if we have cached stats and they're still valid
        if !force, let lastRefresh = lastStatsRefresh, stats != nil {
            let elapsed = Date().timeIntervalSince(lastRefresh)
            if elapsed < Self.statsCacheExpiry {
                // Check if memory directory was modified
                if !memoryDirectoryChanged() {
                    return  // Use cached stats
                }
            }
        }
        
        // Refresh stats
        do {
            stats = try await service.loadStats()
            lastStatsRefresh = Date()
            updateMemoryDirectoryTimestamp()
        } catch {
            debugLog("Failed to load stats: \(error)")
        }
    }
    
    /// Check if memory directory was modified since last check
    private func memoryDirectoryChanged() -> Bool {
        let memoryDir = URL(fileURLWithPath: AppConfiguration.shared.memoryPath)
        
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: memoryDir.path),
              let modDate = attrs[.modificationDate] as? Date else {
            return true  // Assume changed if we can't check
        }
        
        if let lastKnown = lastMemoryDirModification {
            return modDate > lastKnown
        }
        return true  // First check
    }
    
    /// Update the tracked modification timestamp
    private func updateMemoryDirectoryTimestamp() {
        let memoryDir = URL(fileURLWithPath: AppConfiguration.shared.memoryPath)
        
        if let attrs = try? FileManager.default.attributesOfItem(atPath: memoryDir.path),
           let modDate = attrs[.modificationDate] as? Date {
            lastMemoryDirModification = modDate
        }
    }
    
    func loadFileContent(file: MemoryFile) async {
        selectedFile = file
        isLoadingContent = true
        
        do {
            fileContent = try await service.loadFileContent(path: file.path)
        } catch {
            fileContent = "Error loading file: \(error.localizedDescription)"
        }
        
        isLoadingContent = false
    }
    
    func performSearch(query: String) async {
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isSearching = true
        error = nil  // Clear previous errors
        
        searchTask = Task {
            defer { self.isSearching = false }
            do {
                debugLog("🔍 Starting search for: '\(query)'")
                let results = try await service.search(query: query)
                if !Task.isCancelled {
                    self.searchResults = results
                    debugLog("✅ Search complete: \(results.count) results")
                    
                    // Auto-switch to search view if we have results
                    if !results.isEmpty && self.viewMode != .search {
                        self.viewMode = .search
                    }
                }
            } catch {
                if !Task.isCancelled {
                    debugLog("❌ Search error: \(error)")
                    self.error = error.localizedDescription
                }
            }
        }
    }
    
    func loadEmbeddings() async {
        guard embeddingPoints.isEmpty else { return } // Already loaded
        
        isLoadingEmbeddings = true
        error = nil
        Self.logger.info("🔄 Starting loadEmbeddings()")
        
        // Use a generous timeout - Python UMAP typically takes ~3s,
        // but with fallback to PCA it could take longer.
        // 30s is safe since the UI already shows a loading spinner.
        let timeoutSeconds: UInt64 = 30
        
        do {
            // Race between embedding loading and timeout
            let loadedPoints = try await withThrowingTaskGroup(of: [EmbeddingPoint]?.self) { group -> [EmbeddingPoint] in
                group.addTask {
                    try await self.service.loadEmbeddings()
                }
                
                group.addTask {
                    try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                    return nil // Sentinel for timeout
                }
                
                // Take the first non-nil result, or throw timeout
                for try await result in group {
                    if let points = result {
                        group.cancelAll()
                        return points
                    } else {
                        // Timeout sentinel returned first
                        group.cancelAll()
                        throw EmbeddingLoadError.timeout
                    }
                }
                throw EmbeddingLoadError.timeout
            }
            self.embeddingPoints = loadedPoints
        } catch is CancellationError {
            Self.logger.warning("⚠️ Embedding load cancelled")
            debugLog("⚠️ Embedding load cancelled")
            self.error = "Loading was cancelled"
        } catch EmbeddingLoadError.timeout {
            Self.logger.error("⏱️ Embedding load timed out after \(timeoutSeconds)s")
            debugLog("⏱️ Embedding load timed out after \(timeoutSeconds)s")
            self.error = "Loading timed out. The database may be too large or unavailable."
        } catch {
            Self.logger.error("❌ Embedding load error: \(error.localizedDescription)")
            debugLog("❌ Embedding load error: \(error)")
            self.error = error.localizedDescription
        }
        
        isLoadingEmbeddings = false
    }
    
    private enum EmbeddingLoadError: Error {
        case timeout
    }
    
    func refresh() async {
        await loadInitialData()
        
        // Reload embeddings if we're in viz mode
        if viewMode == .visualization {
            embeddingPoints = []
            await loadEmbeddings()
        }
    }
    
    // MARK: - Folder Expansion
    
    func toggleFolder(_ folder: MemoryFolder) {
        if expandedFolders.contains(folder.id) {
            expandedFolders.remove(folder.id)
        } else {
            expandedFolders.insert(folder.id)
        }
    }
    
    func isExpanded(_ folder: MemoryFolder) -> Bool {
        expandedFolders.contains(folder.id)
    }
    
    // MARK: - Selection
    
    func selectPoint(_ pointId: String) {
        selectedPointId = pointId
        
        // Find and load the file for this point
        if let point = embeddingPoints.first(where: { $0.id == pointId }) {
            let file = MemoryFile(
                path: point.path,
                tier: MemoryTier(rawValue: point.tier) ?? .warm,
                tokens: point.tokens
            )
            Task {
                await loadFileContent(file: file)
            }
        }
    }
    
    func selectSearchResult(_ result: MemorySearchResult) {
        let file = MemoryFile(
            path: result.path,
            tier: .warm // Will be determined by actual content
        )
        Task {
            await loadFileContent(file: file)
        }
    }
    
    // MARK: - View Mode
    
    func setViewMode(_ mode: MemoryViewMode) {
        viewMode = mode
        
        if mode == .visualization && embeddingPoints.isEmpty {
            Task {
                await loadEmbeddings()
            }
        }
    }
}
