import XCTest
@testable import ClawK

final class CanvasStateTests: XCTestCase {

    // MARK: - Default State

    func testEmptyStateDefaults() {
        let state = CanvasState.empty
        XCTAssertFalse(state.isActive)
        XCTAssertEqual(state.target, "host")
        XCTAssertNil(state.currentURL)
        XCTAssertNil(state.windowSize)
        XCTAssertNil(state.snapshotData)
        XCTAssertNil(state.snapshotTimestamp)
        XCTAssertNil(state.error)
        XCTAssertFalse(state.isLoading)
        XCTAssertTrue(state.activityLog.isEmpty)
    }

    // MARK: - maxSnapshotSize

    func testMaxSnapshotSizeIsTwoMegabytes() {
        XCTAssertEqual(CanvasState.maxSnapshotSize, 2 * 1024 * 1024)
    }

    // MARK: - trimSnapshotIfNeeded

    func testTrimClearsOversizedSnapshot() {
        var state = CanvasState()
        // Create data larger than 2MB
        state.snapshotData = Data(repeating: 0xFF, count: 3 * 1024 * 1024)

        state.trimSnapshotIfNeeded()

        XCTAssertNil(state.snapshotData, "Oversized snapshot should be cleared")
    }

    func testTrimKeepsUndersizedSnapshot() {
        var state = CanvasState()
        let smallData = Data(repeating: 0xAA, count: 1024)
        state.snapshotData = smallData

        state.trimSnapshotIfNeeded()

        XCTAssertEqual(state.snapshotData, smallData, "Small snapshot should be preserved")
    }

    func testTrimKeepsExactlyMaxSizeSnapshot() {
        var state = CanvasState()
        let exactData = Data(repeating: 0xBB, count: CanvasState.maxSnapshotSize)
        state.snapshotData = exactData

        state.trimSnapshotIfNeeded()

        XCTAssertEqual(state.snapshotData, exactData, "Exact max size should be preserved")
    }

    func testTrimHandlesNilSnapshot() {
        var state = CanvasState()
        state.snapshotData = nil

        state.trimSnapshotIfNeeded()

        XCTAssertNil(state.snapshotData, "Nil snapshot should remain nil")
    }
}
