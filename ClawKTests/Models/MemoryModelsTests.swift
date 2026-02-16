import XCTest
@testable import ClawK

final class MemoryModelsTests: XCTestCase {

    // MARK: - MemoryFile

    func testMemoryFileNameDerivation() {
        let file = MemoryFile(path: "/home/user/.openclaw/workspace/memory/MEMORY.md", tier: .hot)
        XCTAssertEqual(file.name, "MEMORY.md")
    }

    func testMemoryFileId() {
        let path = "/some/path/file.md"
        let file = MemoryFile(path: path, tier: .warm)
        XCTAssertEqual(file.id, path)
    }

    func testMemoryFileDefaults() {
        let file = MemoryFile(path: "test.md", tier: .cold)
        XCTAssertEqual(file.size, 0)
        XCTAssertEqual(file.tokens, 0)
        XCTAssertNil(file.modified)
        XCTAssertEqual(file.chunkCount, 0)
    }

    // MARK: - MemoryTier

    func testMemoryTierDisplayName() {
        XCTAssertEqual(MemoryTier.hot.displayName, "Hot")
        XCTAssertEqual(MemoryTier.warm.displayName, "Warm")
        XCTAssertEqual(MemoryTier.cold.displayName, "Cold")
        XCTAssertEqual(MemoryTier.archive.displayName, "Archive")
    }

    func testMemoryTierIcon() {
        XCTAssertEqual(MemoryTier.hot.icon, "🔥")
        XCTAssertEqual(MemoryTier.warm.icon, "🌡️")
        XCTAssertEqual(MemoryTier.cold.icon, "❄️")
        XCTAssertEqual(MemoryTier.archive.icon, "📦")
    }

    func testMemoryTierEmojiMatchesIcon() {
        for tier in MemoryTier.allCases {
            XCTAssertEqual(tier.emoji, tier.icon)
        }
    }

    func testMemoryTierCaseIterable() {
        XCTAssertEqual(MemoryTier.allCases.count, 4)
    }

    // MARK: - MemoryStructure

    func testMemoryStructureIsEmpty() {
        let structure = MemoryStructure.empty
        XCTAssertTrue(structure.isEmpty)
    }

    func testMemoryStructureIsNotEmpty() {
        let file = MemoryFile(path: "test.md", tier: .hot, size: 100)
        let structure = MemoryStructure(hot: [file], warm: [], cold: [], archive: [])
        XCTAssertFalse(structure.isEmpty)
    }

    func testMemoryStructureAllFilesFlat() {
        let hot1 = MemoryFile(path: "hot1.md", tier: .hot)
        let hot2 = MemoryFile(path: "hot2.md", tier: .hot)
        let archive1 = MemoryFile(path: "archive1.md", tier: .archive)
        let structure = MemoryStructure(hot: [hot1, hot2], warm: [], cold: [], archive: [archive1])
        XCTAssertEqual(structure.allFiles.count, 3)
    }

    func testMemoryStructureAllFilesRecursive() {
        let hotFile = MemoryFile(path: "hot.md", tier: .hot)
        let warmFile = MemoryFile(path: "warm/file.md", tier: .warm)
        let subfolderFile = MemoryFile(path: "warm/sub/file.md", tier: .warm)
        let coldFile = MemoryFile(path: "cold/file.md", tier: .cold)

        let subfolder = MemoryFolder(id: "sub", name: "sub", path: "warm/sub", tier: .warm, files: [subfolderFile], subfolders: [])
        let warmFolder = MemoryFolder(id: "warm", name: "warm", path: "warm", tier: .warm, files: [warmFile], subfolders: [subfolder])
        let coldFolder = MemoryFolder(id: "cold", name: "cold", path: "cold", tier: .cold, files: [coldFile], subfolders: [])

        let structure = MemoryStructure(hot: [hotFile], warm: [warmFolder], cold: [coldFolder], archive: [])
        let allFiles = structure.allFiles
        XCTAssertEqual(allFiles.count, 4)
    }

    // MARK: - MemorySearchResult

    func testMemorySearchResultFilename() {
        let result = MemorySearchResult(id: "1", path: "/path/to/MEMORY.md", snippet: "test", score: 0.9, startLine: 1, endLine: 5)
        XCTAssertEqual(result.filename, "MEMORY.md")
    }

    // MARK: - EmbeddingPoint

    func testIsMemoryMdFileExplicitFlag() {
        let point = EmbeddingPoint(id: "1", path: "some/other/file.md", tier: "hot", tokens: 100, x: 0, y: 0, z: 0, cluster: nil, chunkIndex: 0, text: "", isMemoryMd: true)
        XCTAssertTrue(point.isMemoryMdFile)
    }

    func testIsMemoryMdFileExplicitFlagFalse() {
        let point = EmbeddingPoint(id: "1", path: "MEMORY.md", tier: "hot", tokens: 100, x: 0, y: 0, z: 0, cluster: nil, chunkIndex: 0, text: "", isMemoryMd: false)
        XCTAssertFalse(point.isMemoryMdFile)
    }

    func testIsMemoryMdFilePathFallback() {
        let point = EmbeddingPoint(id: "1", path: "MEMORY.md", tier: "hot", tokens: 100, x: 0, y: 0, z: 0, cluster: nil, chunkIndex: 0, text: "", isMemoryMd: nil)
        XCTAssertTrue(point.isMemoryMdFile)
    }

    func testIsMemoryMdFilePathFallbackWithDirectory() {
        let point = EmbeddingPoint(id: "1", path: "workspace/MEMORY.md", tier: "hot", tokens: 100, x: 0, y: 0, z: 0, cluster: nil, chunkIndex: 0, text: "", isMemoryMd: nil)
        XCTAssertTrue(point.isMemoryMdFile)
    }

    func testIsMemoryMdFilePathFallbackNotMemory() {
        let point = EmbeddingPoint(id: "1", path: "other.md", tier: "hot", tokens: 100, x: 0, y: 0, z: 0, cluster: nil, chunkIndex: 0, text: "", isMemoryMd: nil)
        XCTAssertFalse(point.isMemoryMdFile)
    }

    func testSimilarityDefault() {
        let point = EmbeddingPoint(id: "1", path: "test", tier: "hot", tokens: 100, x: 0, y: 0, z: 0, cluster: nil, chunkIndex: 0, text: "", similarityToMemory: nil)
        XCTAssertEqual(point.similarity, 0.0)
    }

    func testSimilarityWithValue() {
        let point = EmbeddingPoint(id: "1", path: "test", tier: "hot", tokens: 100, x: 0, y: 0, z: 0, cluster: nil, chunkIndex: 0, text: "", similarityToMemory: 0.85)
        XCTAssertEqual(point.similarity, 0.85, accuracy: 0.001)
    }

    func testEmbeddingPointFilename() {
        let point = EmbeddingPoint(id: "1", path: "/workspace/memory/notes.md", tier: "warm", tokens: 50, x: 1, y: 2, z: 3, cluster: "cluster-1", chunkIndex: 0, text: "hello")
        XCTAssertEqual(point.filename, "notes.md")
    }

    // MARK: - MemoryFolder

    func testMemoryFolderTotalFiles() {
        let file1 = MemoryFile(path: "a.md", tier: .warm)
        let file2 = MemoryFile(path: "b.md", tier: .warm)
        let subfolder = MemoryFolder(id: "sub", name: "sub", path: "sub", tier: .warm, files: [file2], subfolders: [])
        let folder = MemoryFolder(id: "root", name: "root", path: "root", tier: .warm, files: [file1], subfolders: [subfolder])
        XCTAssertEqual(folder.totalFiles, 2)
    }
}
