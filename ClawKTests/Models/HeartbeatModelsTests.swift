import XCTest
@testable import ClawK

final class HeartbeatModelsTests: XCTestCase {

    // MARK: - SystemStatus.lastActivityFormatted

    func testLastActivityFormattedJustNow() {
        let status = SystemStatus(
            gatewayConnected: true,
            gatewayLatencyMs: nil,
            nodeCount: 1,
            connectedNodes: 1,
            lastActivitySeconds: 30,
            lastHealthCheck: nil
        )
        XCTAssertEqual(status.lastActivityFormatted, "Just now")
    }

    func testLastActivityFormattedMinutes() {
        let status = SystemStatus(
            gatewayConnected: true,
            gatewayLatencyMs: nil,
            nodeCount: 1,
            connectedNodes: 1,
            lastActivitySeconds: 300, // 5 minutes
            lastHealthCheck: nil
        )
        XCTAssertEqual(status.lastActivityFormatted, "5m ago")
    }

    func testLastActivityFormattedHours() {
        let status = SystemStatus(
            gatewayConnected: true,
            gatewayLatencyMs: nil,
            nodeCount: 1,
            connectedNodes: 1,
            lastActivitySeconds: 7500, // 2h 5m
            lastHealthCheck: nil
        )
        XCTAssertEqual(status.lastActivityFormatted, "2h 5m ago")
    }

    func testLastActivityFormattedUnknown() {
        let status = SystemStatus(
            gatewayConnected: true,
            gatewayLatencyMs: nil,
            nodeCount: 1,
            connectedNodes: 1,
            lastActivitySeconds: nil,
            lastHealthCheck: nil
        )
        XCTAssertEqual(status.lastActivityFormatted, "Unknown")
    }

    // MARK: - ContextPressure

    func testUsagePercent() {
        let pressure = ContextPressure(currentTokens: 70_000, maxTokens: 200_000, lastFlush: nil)
        XCTAssertEqual(pressure.usagePercent, 35.0, accuracy: 0.01)
    }

    func testUsagePercentZeroMax() {
        let pressure = ContextPressure(currentTokens: 100, maxTokens: 0, lastFlush: nil)
        XCTAssertEqual(pressure.usagePercent, 0.0)
    }

    func testPressureLevelNormal() {
        let pressure = ContextPressure(currentTokens: 60_000, maxTokens: 200_000, lastFlush: nil) // 30%
        XCTAssertEqual(pressure.level, .normal)
    }

    func testPressureLevelWarning() {
        let pressure = ContextPressure(currentTokens: 150_000, maxTokens: 200_000, lastFlush: nil) // 75%
        XCTAssertEqual(pressure.level, .warning)
    }

    func testPressureLevelCritical() {
        let pressure = ContextPressure(currentTokens: 185_000, maxTokens: 200_000, lastFlush: nil) // 92.5%
        XCTAssertEqual(pressure.level, .critical)
    }

    func testPressureLevelBoundary70() {
        let pressure = ContextPressure(currentTokens: 140_000, maxTokens: 200_000, lastFlush: nil) // exactly 70%
        XCTAssertEqual(pressure.level, .warning)
    }

    func testPressureLevelBoundary90() {
        let pressure = ContextPressure(currentTokens: 180_000, maxTokens: 200_000, lastFlush: nil) // exactly 90%
        XCTAssertEqual(pressure.level, .critical)
    }

    func testPressureLevelJustBelow70() {
        let pressure = ContextPressure(currentTokens: 139_000, maxTokens: 200_000, lastFlush: nil) // 69.5%
        XCTAssertEqual(pressure.level, .normal)
    }

    // MARK: - HeartbeatState enum

    func testHeartbeatStateEmoji() {
        XCTAssertEqual(HeartbeatState.ok.emoji, "✓")
        XCTAssertEqual(HeartbeatState.alert.emoji, "⚠")
        XCTAssertEqual(HeartbeatState.critical.emoji, "❌")
        XCTAssertEqual(HeartbeatState.unknown.emoji, "?")
    }

    func testHeartbeatStateLabel() {
        XCTAssertEqual(HeartbeatState.ok.label, "OK")
        XCTAssertEqual(HeartbeatState.alert.label, "Alert")
        XCTAssertEqual(HeartbeatState.critical.label, "Critical")
        XCTAssertEqual(HeartbeatState.unknown.label, "Unknown")
    }

    // MARK: - FileHealthStatus enum

    func testFileHealthStatusEmoji() {
        XCTAssertEqual(FileHealthStatus.healthy.emoji, "✓")
        XCTAssertEqual(FileHealthStatus.needsAttention.emoji, "⚠")
        XCTAssertEqual(FileHealthStatus.stale.emoji, "🕐")
        XCTAssertEqual(FileHealthStatus.missing.emoji, "❌")
    }

    func testFileHealthStatusLabel() {
        XCTAssertEqual(FileHealthStatus.healthy.label, "Healthy")
        XCTAssertEqual(FileHealthStatus.needsAttention.label, "Needs Attention")
        XCTAssertEqual(FileHealthStatus.stale.label, "Stale")
        XCTAssertEqual(FileHealthStatus.missing.label, "Missing")
    }

    // MARK: - PressureLevel

    func testPressureLevelLabels() {
        XCTAssertEqual(PressureLevel.normal.label, "Healthy")
        XCTAssertEqual(PressureLevel.warning.label, "Warning")
        XCTAssertEqual(PressureLevel.critical.label, "Critical")
    }
}
