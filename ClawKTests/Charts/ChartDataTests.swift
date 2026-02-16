import XCTest
import CoreGraphics
@testable import ClawK

final class ChartDataTests: XCTestCase {

    // MARK: - roundUpToNiceNumber

    func testRoundUpToNiceNumber7() {
        XCTAssertEqual(roundUpToNiceNumber(7), 10)
    }

    func testRoundUpToNiceNumber12() {
        XCTAssertEqual(roundUpToNiceNumber(12), 15)
    }

    func testRoundUpToNiceNumber23() {
        XCTAssertEqual(roundUpToNiceNumber(23), 25)
    }

    func testRoundUpToNiceNumber35() {
        XCTAssertEqual(roundUpToNiceNumber(35), 35)
    }

    func testRoundUpToNiceNumber75() {
        XCTAssertEqual(roundUpToNiceNumber(75), 75)
    }

    func testRoundUpToNiceNumber36() {
        XCTAssertEqual(roundUpToNiceNumber(36), 40)
    }

    func testRoundUpToNiceNumber76() {
        XCTAssertEqual(roundUpToNiceNumber(76), 80)
    }

    func testRoundUpToNiceNumber101() {
        // 101 rounds up to next multiple of 5 = 105
        XCTAssertEqual(roundUpToNiceNumber(101), 105)
    }

    func testRoundUpToNiceNumberZero() {
        XCTAssertEqual(roundUpToNiceNumber(0), 10)
    }

    func testRoundUpToNiceNumberExact() {
        XCTAssertEqual(roundUpToNiceNumber(50), 50)
        XCTAssertEqual(roundUpToNiceNumber(100), 100)
        XCTAssertEqual(roundUpToNiceNumber(25), 25)
    }

    func testRoundUpToNiceNumber5() {
        XCTAssertEqual(roundUpToNiceNumber(5), 5)
    }

    // MARK: - transformToChartPoints

    func testTransformToChartPointsEmpty() {
        let result = transformToChartPoints(from: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testTransformToChartPointsDeltaCalculation() {
        let now = Date()
        let history = [
            HeartbeatHistory(timestamp: now.addingTimeInterval(-3600), status: "HEARTBEAT_OK", contextPercent: 50, sessionsChecked: 1, sessionsActive: 1, memoryEventsLogged: 5, statusDescription: "ok"),
            HeartbeatHistory(timestamp: now.addingTimeInterval(-1800), status: "HEARTBEAT_OK", contextPercent: 55, sessionsChecked: 1, sessionsActive: 1, memoryEventsLogged: 8, statusDescription: "ok"),
            HeartbeatHistory(timestamp: now.addingTimeInterval(-600), status: "HEARTBEAT_OK", contextPercent: 60, sessionsChecked: 1, sessionsActive: 1, memoryEventsLogged: 12, statusDescription: "ok"),
        ]

        let points = transformToChartPoints(from: history)
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[0].value, 5) // First: 5 - 0 = 5
        XCTAssertEqual(points[1].value, 3) // 8 - 5 = 3
        XCTAssertEqual(points[2].value, 4) // 12 - 8 = 4
    }

    func testTransformToChartPointsNegativeDeltaClamped() {
        let now = Date()
        let history = [
            HeartbeatHistory(timestamp: now.addingTimeInterval(-3600), status: "HEARTBEAT_OK", contextPercent: 50, sessionsChecked: 1, sessionsActive: 1, memoryEventsLogged: 10, statusDescription: "ok"),
            HeartbeatHistory(timestamp: now.addingTimeInterval(-1800), status: "HEARTBEAT_OK", contextPercent: 55, sessionsChecked: 1, sessionsActive: 1, memoryEventsLogged: 5, statusDescription: "ok"),
        ]

        let points = transformToChartPoints(from: history)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(points[1].value, 0) // Negative clamped to 0
    }

    func testTransformToChartPointsFilters24Hours() {
        let now = Date()
        let history = [
            // Old data (>24h ago) — should be filtered out
            HeartbeatHistory(timestamp: now.addingTimeInterval(-90000), status: "HEARTBEAT_OK", contextPercent: 50, sessionsChecked: 1, sessionsActive: 1, memoryEventsLogged: 100, statusDescription: "ok"),
            // Recent data
            HeartbeatHistory(timestamp: now.addingTimeInterval(-3600), status: "HEARTBEAT_OK", contextPercent: 50, sessionsChecked: 1, sessionsActive: 1, memoryEventsLogged: 5, statusDescription: "ok"),
        ]

        let points = transformToChartPoints(from: history)
        XCTAssertEqual(points.count, 1) // Only recent data
    }

    // MARK: - Edge Case Helpers

    func testIsChartEmpty() {
        XCTAssertTrue(isChartEmpty([]))
        XCTAssertFalse(isChartEmpty([ChartPoint(timestamp: Date(), value: 1, status: "HEARTBEAT_OK")]))
    }

    func testIsCollectingState() {
        XCTAssertFalse(isCollectingState([]))
        XCTAssertTrue(isCollectingState([ChartPoint(timestamp: Date(), value: 1, status: "HEARTBEAT_OK")]))
        XCTAssertTrue(isCollectingState([
            ChartPoint(timestamp: Date(), value: 1, status: "HEARTBEAT_OK"),
            ChartPoint(timestamp: Date(), value: 2, status: "HEARTBEAT_OK"),
        ]))
        XCTAssertFalse(isCollectingState([
            ChartPoint(timestamp: Date(), value: 1, status: "HEARTBEAT_OK"),
            ChartPoint(timestamp: Date(), value: 2, status: "HEARTBEAT_OK"),
            ChartPoint(timestamp: Date(), value: 3, status: "HEARTBEAT_OK"),
        ]))
    }

    func testIsFlatLine() {
        let points = [
            ChartPoint(timestamp: Date(), value: 5, status: "HEARTBEAT_OK"),
            ChartPoint(timestamp: Date(), value: 5, status: "HEARTBEAT_OK"),
            ChartPoint(timestamp: Date(), value: 5, status: "HEARTBEAT_OK"),
        ]
        XCTAssertTrue(isFlatLine(points))
    }

    func testIsFlatLineFalse() {
        let points = [
            ChartPoint(timestamp: Date(), value: 5, status: "HEARTBEAT_OK"),
            ChartPoint(timestamp: Date(), value: 6, status: "HEARTBEAT_OK"),
        ]
        XCTAssertFalse(isFlatLine(points))
    }

    func testIsFlatLineSinglePoint() {
        XCTAssertFalse(isFlatLine([ChartPoint(timestamp: Date(), value: 5, status: "HEARTBEAT_OK")]))
    }

    func testIsSinglePoint() {
        XCTAssertTrue(isSinglePoint([ChartPoint(timestamp: Date(), value: 1, status: "HEARTBEAT_OK")]))
        XCTAssertFalse(isSinglePoint([]))
        XCTAssertFalse(isSinglePoint([
            ChartPoint(timestamp: Date(), value: 1, status: "HEARTBEAT_OK"),
            ChartPoint(timestamp: Date(), value: 2, status: "HEARTBEAT_OK"),
        ]))
    }

    // MARK: - ChartScale

    func testChartScaleXPositionMidpoint() {
        let now = Date()
        let start = now.addingTimeInterval(-3600)
        let scale = ChartScale(xMin: start, xMax: now, yMax: 100)
        let dims = ChartDimensions(width: 400, height: 200)

        let midDate = now.addingTimeInterval(-1800) // halfway
        let pos = scale.xPosition(for: midDate, in: dims)
        let expectedMid = dims.marginLeft + dims.plotWidth / 2
        XCTAssertEqual(pos, expectedMid, accuracy: 1.0)
    }

    func testChartScaleYPositionInversion() {
        let now = Date()
        let scale = ChartScale(xMin: now, xMax: now.addingTimeInterval(3600), yMax: 100)
        let dims = ChartDimensions(width: 400, height: 200)

        // yMax should be at the top (marginTop)
        let topPos = scale.yPosition(for: 100, in: dims)
        XCTAssertEqual(topPos, dims.marginTop, accuracy: 1.0)

        // yMin (0) should be at the bottom
        let bottomPos = scale.yPosition(for: 0, in: dims)
        XCTAssertEqual(bottomPos, dims.marginTop + dims.plotHeight, accuracy: 1.0)
    }

    func testChartScaleSinglePointEdgeCase() {
        let now = Date()
        let scale = ChartScale(xMin: now, xMax: now, yMax: 10)
        let dims = ChartDimensions(width: 400, height: 200)

        // When xMin == xMax, should return center
        let pos = scale.xPosition(for: now, in: dims)
        let expectedCenter = dims.marginLeft + dims.plotWidth / 2
        XCTAssertEqual(pos, expectedCenter, accuracy: 0.1)
    }

    func testChartScaleYMinEqualsYMax() {
        let now = Date()
        // yMin=0 and yMax=0 → constructor forces yMax = max(0, 0+1) = 1
        let scale = ChartScale(xMin: now, xMax: now.addingTimeInterval(3600), yMin: 0, yMax: 0)
        let dims = ChartDimensions(width: 400, height: 200)

        // Should not crash; yMax is forced to at least 1
        let pos = scale.yPosition(for: 0, in: dims)
        XCTAssertFalse(pos.isNaN)
    }

    // MARK: - pointColorComponents

    func testPointColorAlertIsRed() {
        let point = ChartPoint(timestamp: Date(), value: 5, status: "HEARTBEAT_ALERT")
        let color = pointColorComponents(for: point)
        XCTAssertGreaterThan(color.red, 0.8)
        XCTAssertLessThan(color.green, 0.3)
    }

    func testPointColorHighActivity() {
        let point = ChartPoint(timestamp: Date(), value: 15, status: "HEARTBEAT_OK")
        let color = pointColorComponents(for: point)
        // High activity = purple (red ~0.5, green 0, blue ~0.5)
        XCTAssertEqual(color.red, 0.5, accuracy: 0.01)
        XCTAssertEqual(color.blue, 0.5, accuracy: 0.01)
    }

    func testPointColorMediumActivity() {
        let point = ChartPoint(timestamp: Date(), value: 10, status: "HEARTBEAT_OK")
        let color = pointColorComponents(for: point)
        // Medium activity = blue
        XCTAssertLessThan(color.red, 0.1)
        XCTAssertGreaterThan(color.blue, 0.9)
    }

    func testPointColorLowActivity() {
        let point = ChartPoint(timestamp: Date(), value: 3, status: "HEARTBEAT_OK")
        let color = pointColorComponents(for: point)
        // Low activity = indigo
        XCTAssertGreaterThan(color.red, 0.2)
        XCTAssertGreaterThan(color.blue, 0.4)
        XCTAssertLessThan(color.alpha, 1.0) // slight transparency
    }
}
