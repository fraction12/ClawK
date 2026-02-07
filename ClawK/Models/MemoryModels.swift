//
//  MemoryModels.swift
//  ClawK
//
//  Models for the Memory Browser
//

import Foundation

// MARK: - Memory File

struct MemoryFile: Identifiable, Hashable, Codable {
    let id: String
    let path: String
    let name: String
    let tier: MemoryTier
    let size: Int
    let tokens: Int
    let modified: Date?
    let chunkCount: Int
    
    init(path: String, tier: MemoryTier, size: Int = 0, tokens: Int = 0, modified: Date? = nil, chunkCount: Int = 0) {
        self.id = path
        self.path = path
        self.name = (path as NSString).lastPathComponent
        self.tier = tier
        self.size = size
        self.tokens = tokens
        self.modified = modified
        self.chunkCount = chunkCount
    }
}

// MARK: - Memory Tier

enum MemoryTier: String, Codable, CaseIterable {
    case hot = "hot"
    case warm = "warm"
    case cold = "cold"
    case archive = "archive"
    
    var displayName: String {
        switch self {
        case .hot: return "Hot"
        case .warm: return "Warm"
        case .cold: return "Cold"
        case .archive: return "Archive"
        }
    }
    
    var icon: String {
        switch self {
        case .hot: return "🔥"
        case .warm: return "🌡️"
        case .cold: return "❄️"
        case .archive: return "📦"
        }
    }
    
    var emoji: String { icon }
    
    var colorHex: String {
        switch self {
        case .hot: return "#ff4444"
        case .warm: return "#ffaa00"
        case .cold: return "#4488ff"
        case .archive: return "#888888"
        }
    }
}

// MARK: - Memory Folder

struct MemoryFolder: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let path: String
    let tier: MemoryTier
    var files: [MemoryFile]
    var subfolders: [MemoryFolder]
    var isExpanded: Bool = false
    
    var totalFiles: Int {
        files.count + subfolders.reduce(0) { $0 + $1.totalFiles }
    }
}

// MARK: - Memory Structure

struct MemoryStructure {
    var hot: [MemoryFile]
    var warm: [MemoryFolder]
    var cold: [MemoryFolder]
    var archive: [MemoryFile]
    
    var isEmpty: Bool {
        hot.isEmpty && warm.isEmpty && cold.isEmpty && archive.isEmpty
    }
    
    var allFiles: [MemoryFile] {
        var files = hot + archive
        for folder in warm {
            files += folder.files
            for subfolder in folder.subfolders {
                files += subfolder.files
            }
        }
        for folder in cold {
            files += folder.files
        }
        return files
    }
    
    static let empty = MemoryStructure(hot: [], warm: [], cold: [], archive: [])
}

// MARK: - Search Result

struct MemorySearchResult: Identifiable, Codable {
    let id: String
    let path: String
    let snippet: String
    let score: Double
    let startLine: Int
    let endLine: Int
    
    var filename: String {
        (path as NSString).lastPathComponent
    }
}

// MARK: - Embedding Point (for 3D visualization)

struct EmbeddingPoint: Identifiable, Codable {
    let id: String
    let path: String
    let tier: String
    let tokens: Int
    let x: Double
    let y: Double
    let z: Double
    let cluster: String?
    let chunkIndex: Int
    let text: String
    let similarityToMemory: Double?
    let isMemoryMd: Bool?
    
    var filename: String {
        (path as NSString).lastPathComponent
    }
    
    var isMemoryMdFile: Bool {
        isMemoryMd ?? (path == "MEMORY.md" || path.hasSuffix("/MEMORY.md"))
    }
    
    var similarity: Double {
        similarityToMemory ?? 0.0
    }
    
    // CodingKeys for backward compatibility
    enum CodingKeys: String, CodingKey {
        case id, path, tier, tokens, x, y, z, cluster, chunkIndex, text
        case similarityToMemory, isMemoryMd
    }
    
    // Memberwise initializer
    init(
        id: String,
        path: String,
        tier: String,
        tokens: Int,
        x: Double,
        y: Double,
        z: Double,
        cluster: String?,
        chunkIndex: Int,
        text: String,
        similarityToMemory: Double? = nil,
        isMemoryMd: Bool? = nil
    ) {
        self.id = id
        self.path = path
        self.tier = tier
        self.tokens = tokens
        self.x = x
        self.y = y
        self.z = z
        self.cluster = cluster
        self.chunkIndex = chunkIndex
        self.text = text
        self.similarityToMemory = similarityToMemory
        self.isMemoryMd = isMemoryMd
    }
    
    // Decoder initializer for JSON parsing
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        tier = try container.decode(String.self, forKey: .tier)
        tokens = try container.decode(Int.self, forKey: .tokens)
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        z = try container.decode(Double.self, forKey: .z)
        cluster = try container.decodeIfPresent(String.self, forKey: .cluster)
        chunkIndex = try container.decode(Int.self, forKey: .chunkIndex)
        text = try container.decode(String.self, forKey: .text)
        similarityToMemory = try container.decodeIfPresent(Double.self, forKey: .similarityToMemory)
        isMemoryMd = try container.decodeIfPresent(Bool.self, forKey: .isMemoryMd)
    }
}

// MARK: - Memory Stats

struct MemoryStats: Codable {
    let totalFiles: Int
    let totalChunks: Int
    let totalTokens: Int
    let tierCounts: [String: Int]
    let lastUpdated: Date?
}

// MARK: - Gateway Response Types

struct MemorySearchResponse: Codable {
    let results: [MemorySearchResult]
}

struct MemoryFileResponse: Codable {
    let path: String
    let content: String
    let tokens: Int
    let modified: Date?
}

struct EmbeddingsResponse: Codable {
    let points: [EmbeddingPoint]
    let stats: EmbeddingStats
}

struct EmbeddingStats: Codable {
    let totalPoints: Int
    let dimensions: Int
    let reductionMethod: String
}
