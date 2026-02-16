import XCTest
@testable import ClawK

final class DeepLinkTests: XCTestCase {

    // MARK: - Valid Destinations

    func testMissionControlFromURL() {
        let url = URL(string: "clawk://mission-control")!
        XCTAssertEqual(DeepLinkDestination.from(url: url), .missionControl)
    }

    func testMemoryFromURL() {
        let url = URL(string: "clawk://memory")!
        XCTAssertEqual(DeepLinkDestination.from(url: url), .memory)
    }

    func testCanvasFromURL() {
        let url = URL(string: "clawk://canvas")!
        XCTAssertEqual(DeepLinkDestination.from(url: url), .canvas)
    }

    func testSettingsFromURL() {
        let url = URL(string: "clawk://settings")!
        XCTAssertEqual(DeepLinkDestination.from(url: url), .settings)
    }

    // MARK: - Invalid URLs

    func testWrongSchemeReturnsNil() {
        let url = URL(string: "https://mission-control")!
        XCTAssertNil(DeepLinkDestination.from(url: url))
    }

    func testUnknownHostReturnsNil() {
        let url = URL(string: "clawk://unknown-page")!
        XCTAssertNil(DeepLinkDestination.from(url: url))
    }

    func testEmptyHostReturnsNil() {
        let url = URL(string: "clawk://")!
        XCTAssertNil(DeepLinkDestination.from(url: url))
    }

    // MARK: - Raw Values

    func testRawValueMissionControl() {
        XCTAssertEqual(DeepLinkDestination.missionControl.rawValue, "mission-control")
    }

    func testRawValueMemory() {
        XCTAssertEqual(DeepLinkDestination.memory.rawValue, "memory")
    }

    func testRawValueCanvas() {
        XCTAssertEqual(DeepLinkDestination.canvas.rawValue, "canvas")
    }

    func testRawValueSettings() {
        XCTAssertEqual(DeepLinkDestination.settings.rawValue, "settings")
    }
}
