//
//  MemoryService.swift
//  ClawK
//
//  Service for accessing memory data from OpenClaw's SQLite database
//

import Foundation
import SQLite3

// SQLite destructor constant - SQLITE_TRANSIENT (-1) tells SQLite to make its own copy of the string
private let SQLITE_TRANSIENT: sqlite3_destructor_type = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor MemoryService {
    private let memoryPath: String
    private let dbPath: String
    private var db: OpaquePointer?
    
    init() {
        let config = AppConfiguration.shared
        self.memoryPath = config.memoryPath
        self.dbPath = config.memoryDbPath
    }
    
    // MARK: - Database Connection
    
    private func openDatabase() throws {
        guard db == nil else { return }
        
        if sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            throw MemoryServiceError.databaseOpenFailed
        }
    }
    
    private func closeDatabase() {
        if let db = db {
            sqlite3_close(db)
            self.db = nil
        }
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
    
    // MARK: - Memory Structure
    
    func loadMemoryStructure() async throws -> MemoryStructure {
        let fm = FileManager.default
        var hot: [MemoryFile] = []
        var warm: [MemoryFolder] = []
        var cold: [MemoryFolder] = []
        var archive: [MemoryFile] = []
        
        // Get chunk counts from database
        let chunkCounts = try await getChunkCounts()
        
        // CRITICAL: MEMORY.md is at workspace root, not in memory folder!
        let workspaceRoot = (memoryPath as NSString).deletingLastPathComponent
        let memoryMdPath = "\(workspaceRoot)/MEMORY.md"
        
        if fm.fileExists(atPath: memoryMdPath),
           let attrs = try? fm.attributesOfItem(atPath: memoryMdPath),
           let modified = attrs[.modificationDate] as? Date,
           let size = attrs[.size] as? Int {
            let tokens = size / 4
            let chunks = chunkCounts["MEMORY.md"] ?? 0  // SQLite stores as "MEMORY.md"
            
            debugLog("📝 Found MEMORY.md at workspace root: \(memoryMdPath)")
            debugLog("   - Size: \(size) bytes, Tokens: \(tokens), Chunks: \(chunks)")
            
            hot.append(MemoryFile(
                path: "MEMORY.md",  // Keep path consistent with SQLite
                tier: .hot,
                size: size,
                tokens: tokens,
                modified: modified,
                chunkCount: chunks
            ))
        } else {
            debugLog("⚠️ MEMORY.md NOT FOUND at: \(memoryMdPath)")
        }
        
        // Scan memory directory
        guard let enumerator = fm.enumerator(atPath: memoryPath) else {
            throw MemoryServiceError.memoryPathNotFound
        }
        
        var folders: [String: [MemoryFile]] = [:]
        let calendar = Calendar.current
        let now = Date()
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        
        while let file = enumerator.nextObject() as? String {
            // Skip hidden files and non-markdown files
            if file.hasPrefix(".") || (!file.hasSuffix(".md") && !file.hasSuffix(".json")) {
                continue
            }
            
            let fullPath = "\(memoryPath)/\(file)"
            guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                  let modified = attrs[.modificationDate] as? Date,
                  let size = attrs[.size] as? Int else {
                continue
            }
            
            // Determine tier based on path and date
            let tier: MemoryTier
            let relativePath = "memory/\(file)"
            
            if file.contains("archive/") {
                if file.contains("-Q") {
                    tier = .archive
                } else {
                    tier = .cold
                }
            } else if file == "MEMORY.md" || (modified >= sevenDaysAgo && !file.contains("/")) {
                tier = .hot
            } else {
                tier = .warm
            }
            
            // Estimate tokens (roughly 4 chars per token)
            let tokens = size / 4
            let chunks = chunkCounts[relativePath] ?? 0
            
            let memFile = MemoryFile(
                path: relativePath,
                tier: tier,
                size: size,
                tokens: tokens,
                modified: modified,
                chunkCount: chunks
            )
            
            // Group files
            if tier == .hot {
                hot.append(memFile)
            } else if tier == .archive {
                archive.append(memFile)
            } else {
                // Group by folder
                let components = file.components(separatedBy: "/")
                if components.count > 1 {
                    let folderName = components[0]
                    if folders[folderName] == nil {
                        folders[folderName] = []
                    }
                    folders[folderName]?.append(memFile)
                } else {
                    // Root level warm files
                    if folders["_root"] == nil {
                        folders["_root"] = []
                    }
                    folders["_root"]?.append(memFile)
                }
            }
        }
        
        // Sort hot files (MEMORY.md first, then by date)
        hot.sort { file1, file2 in
            if file1.name == "MEMORY.md" { return true }
            if file2.name == "MEMORY.md" { return false }
            return (file1.modified ?? .distantPast) > (file2.modified ?? .distantPast)
        }
        
        // Convert folders to MemoryFolder structures
        for (name, files) in folders {
            if name == "_root" { continue }
            
            let tier: MemoryTier = name.contains("archive") ? .cold : .warm
            let folder = MemoryFolder(
                id: name,
                name: name,
                path: "memory/\(name)",
                tier: tier,
                files: files.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) },
                subfolders: []
            )
            
            if tier == .cold {
                cold.append(folder)
            } else {
                warm.append(folder)
            }
        }
        
        // Add root level warm files
        if let rootFiles = folders["_root"], !rootFiles.isEmpty {
            // These are actually displayed at the tier level, not in a folder
            // But based on our tier logic, they should already be in hot
        }
        
        // Sort folders by name (reverse chronological for date-based folders)
        warm.sort { $0.name > $1.name }
        cold.sort { $0.name > $1.name }
        archive.sort { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        
        return MemoryStructure(hot: hot, warm: warm, cold: cold, archive: archive)
    }
    
    private func getChunkCounts() async throws -> [String: Int] {
        try openDatabase()
        
        var counts: [String: Int] = [:]
        let query = "SELECT path, COUNT(*) as count FROM chunks GROUP BY path"
        var stmt: OpaquePointer?
        
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let pathCStr = sqlite3_column_text(stmt, 0) {
                    let path = String(cString: pathCStr)
                    let count = Int(sqlite3_column_int(stmt, 1))
                    counts[path] = count
                }
            }
        }
        sqlite3_finalize(stmt)
        
        return counts
    }
    
    // MARK: - File Content
    
    func loadFileContent(path: String) async throws -> String {
        let fm = FileManager.default
        let workspaceRoot = (memoryPath as NSString).deletingLastPathComponent
        var fullPath: String
        
        // Handle MEMORY.md specially - it's at workspace root
        if path == "MEMORY.md" {
            fullPath = "\(workspaceRoot)/MEMORY.md"
        } else if path.hasPrefix("memory/") {
            let relativePath = String(path.dropFirst("memory/".count))
            fullPath = "\(memoryPath)/\(relativePath)"
        } else {
            fullPath = "\(memoryPath)/\(path)"
        }
        
        debugLog("📖 Loading file: \(path) -> \(fullPath)")
        
        guard fm.fileExists(atPath: fullPath) else {
            debugLog("❌ File not found: \(fullPath)")
            throw MemoryServiceError.fileNotFound
        }
        
        return try String(contentsOfFile: fullPath, encoding: .utf8)
    }
    
    // MARK: - Search (via OpenClaw's memory index)
    
    func search(query: String, limit: Int = 20) async throws -> [MemorySearchResult] {
        try openDatabase()
        
        var results: [MemorySearchResult] = []
        
        // FTS5 search - use proper query syntax
        // Split query into words and search for any of them
        let searchTerms = query
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .map { term -> String in
                // Escape special FTS5 characters and wrap each term
                let escaped = term
                    .replacingOccurrences(of: "\"", with: "\"\"")
                    .replacingOccurrences(of: "*", with: "")
                return "\"\(escaped)\"*"  // Prefix matching
            }
            .joined(separator: " OR ")
        
        let ftsSearchTerm = searchTerms.isEmpty ? "\"\(query)\"*" : searchTerms
        
        let ftsQuery = """
            SELECT id, path, text, start_line, end_line 
            FROM chunks 
            WHERE id IN (
                SELECT id FROM chunks_fts 
                WHERE chunks_fts MATCH ?
            )
            LIMIT ?
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, ftsQuery, -1, &stmt, nil) == SQLITE_OK {
            // Use withCString to properly pass the string to SQLite
            let bindResult = ftsSearchTerm.withCString { cString in
                sqlite3_bind_text(stmt, 1, cString, -1, SQLITE_TRANSIENT)
            }
            
            if bindResult == SQLITE_OK {
                sqlite3_bind_int(stmt, 2, Int32(limit))
                
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let idCStr = sqlite3_column_text(stmt, 0),
                       let pathCStr = sqlite3_column_text(stmt, 1),
                       let textCStr = sqlite3_column_text(stmt, 2) {
                        let result = MemorySearchResult(
                            id: String(cString: idCStr),
                            path: String(cString: pathCStr),
                            snippet: createSnippet(text: String(cString: textCStr), query: query),
                            score: 0.9, // FTS match
                            startLine: Int(sqlite3_column_int(stmt, 3)),
                            endLine: Int(sqlite3_column_int(stmt, 4))
                        )
                        results.append(result)
                    }
                }
            } else {
                debugLog("⚠️ FTS bind failed, falling back to LIKE search")
            }
        }
        sqlite3_finalize(stmt)
        
        // If FTS didn't find much, fall back to LIKE search
        if results.count < 5 {
            let likePattern = "%\(query)%"
            let likeQuery = """
                SELECT id, path, text, start_line, end_line 
                FROM chunks 
                WHERE text LIKE ? COLLATE NOCASE
                LIMIT ?
            """
            
            if sqlite3_prepare_v2(db, likeQuery, -1, &stmt, nil) == SQLITE_OK {
                _ = likePattern.withCString { cString in
                    sqlite3_bind_text(stmt, 1, cString, -1, SQLITE_TRANSIENT)
                }
                sqlite3_bind_int(stmt, 2, Int32(limit - results.count))
                
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let idCStr = sqlite3_column_text(stmt, 0),
                       let pathCStr = sqlite3_column_text(stmt, 1),
                       let textCStr = sqlite3_column_text(stmt, 2) {
                        let id = String(cString: idCStr)
                        // Skip duplicates
                        if results.contains(where: { $0.id == id }) { continue }
                        
                        let result = MemorySearchResult(
                            id: id,
                            path: String(cString: pathCStr),
                            snippet: createSnippet(text: String(cString: textCStr), query: query),
                            score: 0.7, // LIKE match
                            startLine: Int(sqlite3_column_int(stmt, 3)),
                            endLine: Int(sqlite3_column_int(stmt, 4))
                        )
                        results.append(result)
                    }
                }
            }
            sqlite3_finalize(stmt)
        }
        
        // Log search results for debugging
        debugLog("🔍 Search for '\(query)': \(results.count) results found")
        
        closeDatabase()
        return results
    }
    
    private func createSnippet(text: String, query: String, maxLength: Int = 200) -> String {
        let lowercaseText = text.lowercased()
        let lowercaseQuery = query.lowercased()
        
        guard let range = lowercaseText.range(of: lowercaseQuery) else {
            // No match found, return beginning of text
            let endIndex = text.index(text.startIndex, offsetBy: min(maxLength, text.count))
            return String(text[..<endIndex]) + "..."
        }
        
        // Find the position in the original text
        let matchStart = text.distance(from: text.startIndex, to: range.lowerBound)
        let contextStart = max(0, matchStart - 50)
        let contextEnd = min(text.count, matchStart + query.count + 100)
        
        let startIndex = text.index(text.startIndex, offsetBy: contextStart)
        let endIndex = text.index(text.startIndex, offsetBy: contextEnd)
        
        var snippet = String(text[startIndex..<endIndex])
        if contextStart > 0 { snippet = "..." + snippet }
        if contextEnd < text.count { snippet = snippet + "..." }
        
        return snippet
    }
    
    // MARK: - Embeddings for 3D Visualization
    
    func loadEmbeddings() async throws -> [EmbeddingPoint] {
        debugLog("📊 Loading embeddings for 3D visualization...")
        
        // Try to use Python UMAP script first for better visualization
        do {
            let points = try await loadEmbeddingsWithUMAP()
            debugLog("✅ Loaded \(points.count) points via Python UMAP script")
            return points
        } catch {
            debugLog("⚠️ Python UMAP failed: \(error), falling back to Swift PCA")
        }
        
        // Fall back to Swift PCA implementation
        let points = try await loadEmbeddingsWithPCA()
        debugLog("✅ Loaded \(points.count) points via Swift PCA")
        return points
    }
    
    /// Load embeddings using Python UMAP script (better clustering)
    private func loadEmbeddingsWithUMAP() async throws -> [EmbeddingPoint] {
        let config = AppConfiguration.shared
        let scriptPath = config.embeddingsScriptPath
        let venvPath = config.pythonVenvPath
        
        // Check if script and venv exist
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            debugLog("❌ Python script not found at: \(scriptPath)")
            throw MemoryServiceError.noEmbeddings
        }
        
        guard FileManager.default.fileExists(atPath: venvPath) else {
            debugLog("❌ Python venv not found at: \(venvPath)")
            throw MemoryServiceError.noEmbeddings
        }
        
        debugLog("🐍 Running Python UMAP script...")
        
        // Run the process on a background thread with timeout
        // Python UMAP normally takes ~3s for 228 embeddings.
        // 15s is generous but safe — the ViewModel has a 30s outer timeout.
        let processTimeout: TimeInterval = 15.0
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hasResumed = false
                let resumeLock = NSLock()
                
                func safeResume(with result: Result<[EmbeddingPoint], Error>) {
                    resumeLock.lock()
                    defer { resumeLock.unlock() }
                    guard !hasResumed else { return }
                    hasResumed = true
                    switch result {
                    case .success(let points):
                        continuation.resume(returning: points)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                
                let process = Process()
                process.executableURL = URL(fileURLWithPath: venvPath)
                process.arguments = [scriptPath, "--db", self.dbPath]
                
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                
                // Set up timeout
                let timeoutWorkItem = DispatchWorkItem {
                    if process.isRunning {
                        debugLog("⏱️ Python script timed out, terminating...")
                        process.terminate()
                    }
                    safeResume(with: .failure(MemoryServiceError.timeout))
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + processTimeout, execute: timeoutWorkItem)
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    // Cancel timeout if process finished
                    timeoutWorkItem.cancel()
                    
                    // Read stderr for debugging
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    if let stderrStr = String(data: stderrData, encoding: .utf8), !stderrStr.isEmpty {
                        debugLog("🐍 Python stderr: \(stderrStr)")
                    }
                    
                    guard process.terminationStatus == 0 else {
                        debugLog("❌ Python script exited with status: \(process.terminationStatus)")
                        safeResume(with: .failure(MemoryServiceError.noEmbeddings))
                        return
                    }
                    
                    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    
                    guard !data.isEmpty else {
                        debugLog("❌ Python script produced no output")
                        safeResume(with: .failure(MemoryServiceError.noEmbeddings))
                        return
                    }
                    
                    let response = try JSONDecoder().decode(EmbeddingsResponse.self, from: data)
                    debugLog("✅ Python script returned \(response.points.count) points")
                    safeResume(with: .success(response.points))
                } catch {
                    timeoutWorkItem.cancel()
                    debugLog("❌ Python execution error: \(error)")
                    safeResume(with: .failure(error))
                }
            }
        }
    }
    
    /// Load embeddings using Swift PCA implementation (fallback)
    private func loadEmbeddingsWithPCA() async throws -> [EmbeddingPoint] {
        // Check for cancellation early
        try Task.checkCancellation()
        
        try openDatabase()
        
        var embeddings: [[Double]] = []
        var metadata: [(id: String, path: String, text: String, chunkIndex: Int)] = []
        var chunkIndices: [String: Int] = [:]
        
        let query = """
            SELECT id, path, text, embedding 
            FROM chunks 
            ORDER BY path, start_line
            LIMIT 500
        """
        
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let idCStr = sqlite3_column_text(stmt, 0),
                      let pathCStr = sqlite3_column_text(stmt, 1),
                      let textCStr = sqlite3_column_text(stmt, 2),
                      let embeddingCStr = sqlite3_column_text(stmt, 3) else {
                    continue
                }
                
                let id = String(cString: idCStr)
                let path = String(cString: pathCStr)
                let text = String(cString: textCStr)
                let embeddingJson = String(cString: embeddingCStr)
                
                // Parse embedding JSON
                if let data = embeddingJson.data(using: .utf8),
                   let embedding = try? JSONDecoder().decode([Double].self, from: data) {
                    embeddings.append(embedding)
                    
                    // Track chunk index per file
                    let idx = chunkIndices[path] ?? 0
                    chunkIndices[path] = idx + 1
                    
                    metadata.append((id: id, path: path, text: text, chunkIndex: idx))
                }
            }
        }
        sqlite3_finalize(stmt)
        
        guard !embeddings.isEmpty else {
            throw MemoryServiceError.noEmbeddings
        }
        
        // Check for cancellation before heavy computation
        try Task.checkCancellation()
        
        debugLog("📊 Running PCA on \(embeddings.count) embeddings...")
        
        // Perform dimensionality reduction using PCA
        let reduced = pca3D(embeddings: embeddings)
        
        // Calculate cosine similarity to MEMORY.md using original high-dimensional embeddings
        let similarities = calculateSimilaritiesToMemoryMd(
            embeddings: embeddings,
            metadata: metadata
        )
        debugLog("📊 Calculated \(similarities.count) similarity scores")
        
        // Determine tiers and create points
        var points: [EmbeddingPoint] = []
        let calendar = Calendar.current
        let now = Date()
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now)!
        
        for (i, meta) in metadata.enumerated() {
            let tier = determineTier(path: meta.path, sevenDaysAgo: sevenDaysAgo)
            let tokens = meta.text.count / 4 // Rough estimate
            let isMemoryMd = meta.path == "MEMORY.md"
            let similarity = i < similarities.count ? similarities[i] : 0.0
            
            let point = EmbeddingPoint(
                id: meta.id,
                path: meta.path,
                tier: tier.rawValue,
                tokens: tokens,
                x: reduced[i].0,
                y: reduced[i].1,
                z: reduced[i].2,
                cluster: nil,
                chunkIndex: meta.chunkIndex,
                text: String(meta.text.prefix(200)),
                similarityToMemory: similarity,
                isMemoryMd: isMemoryMd
            )
            points.append(point)
        }
        
        closeDatabase()
        return points
    }
    
    // MARK: - Cosine Similarity Calculation
    
    /// Calculate cosine similarity of each embedding to the average MEMORY.md embedding
    private func calculateSimilaritiesToMemoryMd(
        embeddings: [[Double]],
        metadata: [(id: String, path: String, text: String, chunkIndex: Int)]
    ) -> [Double] {
        guard !embeddings.isEmpty else { return [] }
        
        // Find MEMORY.md embedding indices
        let memoryMdIndices = metadata.enumerated()
            .filter { $0.element.path == "MEMORY.md" }
            .map { $0.offset }
        
        guard !memoryMdIndices.isEmpty else {
            debugLog("⚠️ MEMORY.md not found in embeddings, cannot calculate similarities")
            return Array(repeating: 0.0, count: embeddings.count)
        }
        
        // Calculate average MEMORY.md embedding
        let d = embeddings[0].count
        var memoryMdAvg = [Double](repeating: 0, count: d)
        
        for idx in memoryMdIndices {
            for j in 0..<d {
                memoryMdAvg[j] += embeddings[idx][j]
            }
        }
        
        let count = Double(memoryMdIndices.count)
        for j in 0..<d {
            memoryMdAvg[j] /= count
        }
        
        // Calculate cosine similarity for each embedding
        var similarities: [Double] = []
        
        for embedding in embeddings {
            let similarity = cosineSimilarity(embedding, memoryMdAvg)
            // Cosine similarity is in [-1, 1], normalize to [0, 1]
            // Most embeddings will be positive (similar direction), so this is reasonable
            let normalized = (similarity + 1.0) / 2.0
            similarities.append(normalized)
        }
        
        // Debug: log some similarity stats
        let minSim = similarities.min() ?? 0
        let maxSim = similarities.max() ?? 0
        let avgSim = similarities.reduce(0, +) / Double(similarities.count)
        debugLog("📊 Similarity stats - min: \(String(format: "%.2f", minSim)), max: \(String(format: "%.2f", maxSim)), avg: \(String(format: "%.2f", avgSim))")
        
        return similarities
    }
    
    /// Calculate cosine similarity between two vectors
    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dotProduct: Double = 0
        var magA: Double = 0
        var magB: Double = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        
        let magnitude = sqrt(magA) * sqrt(magB)
        guard magnitude > 0 else { return 0 }
        
        return dotProduct / magnitude
    }
    
    private func determineTier(path: String, sevenDaysAgo: Date) -> MemoryTier {
        if path.contains("archive/") {
            if path.contains("-Q") {
                return .archive
            }
            return .cold
        }
        
        if path == "MEMORY.md" || path == "memory/MEMORY.md" {
            return .hot
        }
        
        // Check if it's a recent daily log
        let filename = (path as NSString).lastPathComponent
        if let dateMatch = filename.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) {
            let dateStr = String(filename[dateMatch])
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            if let fileDate = formatter.date(from: dateStr) {
                if fileDate >= sevenDaysAgo {
                    return .hot
                }
            }
        }
        
        return .warm
    }
    
    // MARK: - PCA Implementation (Simple 3D reduction)
    
    private func pca3D(embeddings: [[Double]]) -> [(Double, Double, Double)] {
        guard !embeddings.isEmpty else { return [] }
        
        let n = embeddings.count
        let d = embeddings[0].count
        
        // Step 1: Center the data
        var mean = [Double](repeating: 0, count: d)
        for embedding in embeddings {
            for j in 0..<d {
                mean[j] += embedding[j]
            }
        }
        for j in 0..<d {
            mean[j] /= Double(n)
        }
        
        var centered = embeddings.map { embedding in
            zip(embedding, mean).map { $0 - $1 }
        }
        
        // Step 2: Use power iteration to find top 3 principal components
        // This is a simplified approach - for production, use Accelerate framework
        var components: [[Double]] = []
        
        for _ in 0..<3 {
            var v = (0..<d).map { _ in Double.random(in: -1...1) }
            let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
            v = v.map { $0 / norm }
            
            // Power iteration (20 iterations)
            for _ in 0..<20 {
                // Compute A^T A v
                var av = [Double](repeating: 0, count: d)
                for row in centered {
                    let dot = zip(row, v).reduce(0) { $0 + $1.0 * $1.1 }
                    for j in 0..<d {
                        av[j] += row[j] * dot
                    }
                }
                
                let avNorm = sqrt(av.reduce(0) { $0 + $1 * $1 })
                v = av.map { $0 / max(avNorm, 1e-10) }
            }
            
            components.append(v)
            
            // Deflate - remove this component from the data
            for i in 0..<n {
                let proj = zip(centered[i], v).reduce(0) { $0 + $1.0 * $1.1 }
                for j in 0..<d {
                    centered[i][j] -= proj * v[j]
                }
            }
        }
        
        // Step 3: Project original data onto components
        let originalCentered = embeddings.map { embedding in
            zip(embedding, mean).map { $0 - $1 }
        }
        
        var result: [(Double, Double, Double)] = []
        for row in originalCentered {
            let x = zip(row, components[0]).reduce(0) { $0 + $1.0 * $1.1 }
            let y = zip(row, components[1]).reduce(0) { $0 + $1.0 * $1.1 }
            let z = zip(row, components[2]).reduce(0) { $0 + $1.0 * $1.1 }
            result.append((x, y, z))
        }
        
        // Normalize to [-2, 2] range for better visual spread
        let maxVal = result.reduce(0) { max($0, max(abs($1.0), max(abs($1.1), abs($1.2)))) }
        if maxVal > 0 {
            // Scale to [-2, 2] range for more visual separation
            let scale = 2.0 / maxVal
            result = result.map { (x: $0.0 * scale, y: $0.1 * scale, z: $0.2 * scale) }
        }
        
        return result
    }
    
    // MARK: - Stats
    
    func loadStats() async throws -> MemoryStats {
        try openDatabase()
        
        var totalChunks = 0
        var tierCounts: [String: Int] = ["hot": 0, "warm": 0, "cold": 0, "archive": 0]
        
        let query = "SELECT COUNT(*) FROM chunks"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            if sqlite3_step(stmt) == SQLITE_ROW {
                totalChunks = Int(sqlite3_column_int(stmt, 0))
            }
        }
        sqlite3_finalize(stmt)
        
        let structure = try await loadMemoryStructure()
        tierCounts["hot"] = structure.hot.count
        tierCounts["warm"] = structure.warm.reduce(0) { $0 + $1.files.count }
        tierCounts["cold"] = structure.cold.reduce(0) { $0 + $1.files.count }
        tierCounts["archive"] = structure.archive.count
        
        let totalFiles = tierCounts.values.reduce(0, +)
        let totalTokens = structure.allFiles.reduce(0) { $0 + $1.tokens }
        
        closeDatabase()
        return MemoryStats(
            totalFiles: totalFiles,
            totalChunks: totalChunks,
            totalTokens: totalTokens,
            tierCounts: tierCounts,
            lastUpdated: Date()
        )
    }
    
    // MARK: - Verification
    
    func verifyMemoryData() async {
        debugLog("\n" + String(repeating: "=", count: 60))
        debugLog("🔍 MEMORY DATA VERIFICATION")
        debugLog(String(repeating: "=", count: 60))
        
        do {
            let structure = try await loadMemoryStructure()
            
            // Hot tier
            debugLog("\n🔥 HOT TIER (\(structure.hot.count) files):")
            for file in structure.hot {
                let memoryIndicator = file.name == "MEMORY.md" ? " ⭐" : ""
                debugLog("   • \(file.path) (\(file.tokens) tok, \(file.chunkCount) chunks)\(memoryIndicator)")
            }
            
            // Check MEMORY.md specifically
            if structure.hot.contains(where: { $0.name == "MEMORY.md" }) {
                debugLog("   ✅ MEMORY.md is present in hot tier")
            } else {
                debugLog("   ❌ MEMORY.md MISSING from hot tier!")
            }
            
            // Warm tier
            let warmFileCount = structure.warm.reduce(0) { $0 + $1.files.count }
            debugLog("\n🌡️ WARM TIER (\(structure.warm.count) folders, \(warmFileCount) files):")
            for folder in structure.warm {
                debugLog("   📁 \(folder.name)/ (\(folder.files.count) files)")
            }
            
            // Cold tier
            let coldFileCount = structure.cold.reduce(0) { $0 + $1.files.count }
            debugLog("\n❄️ COLD TIER (\(structure.cold.count) folders, \(coldFileCount) files):")
            for folder in structure.cold {
                debugLog("   📁 \(folder.name)/ (\(folder.files.count) files)")
            }
            
            // Archive tier
            debugLog("\n📦 ARCHIVE TIER (\(structure.archive.count) files):")
            for file in structure.archive {
                debugLog("   • \(file.path)")
            }
            
            // Database check
            try openDatabase()
            let countQuery = "SELECT COUNT(DISTINCT path) FROM chunks"
            var stmt: OpaquePointer?
            var dbFileCount = 0
            if sqlite3_prepare_v2(db, countQuery, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    dbFileCount = Int(sqlite3_column_int(stmt, 0))
                }
            }
            sqlite3_finalize(stmt)
            
            // Check for MEMORY.md in database
            var memoryMdInDb = false
            let memoryQuery = "SELECT COUNT(*) FROM chunks WHERE path = 'MEMORY.md'"
            if sqlite3_prepare_v2(db, memoryQuery, -1, &stmt, nil) == SQLITE_OK {
                if sqlite3_step(stmt) == SQLITE_ROW {
                    memoryMdInDb = sqlite3_column_int(stmt, 0) > 0
                }
            }
            sqlite3_finalize(stmt)
            
            debugLog("\n📊 DATABASE STATS:")
            debugLog("   Files in SQLite: \(dbFileCount)")
            debugLog("   MEMORY.md in DB: \(memoryMdInDb ? "✅ Yes" : "❌ No")")
            
            // Summary
            let totalFiles = structure.allFiles.count
            let totalTokens = structure.allFiles.reduce(0) { $0 + $1.tokens }
            
            debugLog("\n📈 TOTALS:")
            debugLog("   Total files: \(totalFiles)")
            debugLog("   Total tokens: \(totalTokens)")
            debugLog(String(repeating: "=", count: 60) + "\n")
            
        } catch {
            debugLog("❌ Verification error: \(error)")
        }
    }
}

// MARK: - Errors

enum MemoryServiceError: LocalizedError {
    case databaseOpenFailed
    case memoryPathNotFound
    case fileNotFound
    case noEmbeddings
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .databaseOpenFailed:
            return "Failed to open memory database"
        case .memoryPathNotFound:
            return "Memory path not found"
        case .fileNotFound:
            return "File not found"
        case .noEmbeddings:
            return "No embeddings found in database"
        case .timeout:
            return "Operation timed out"
        }
    }
}
