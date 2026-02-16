import XCTest
@testable import ClawK

final class CronJobTests: XCTestCase {

    // MARK: - Helper

    private func makeJob(
        enabled: Bool? = true,
        schedule: CronSchedule = CronSchedule(kind: "every", expr: nil, tz: nil, everyMs: 3600000, atMs: nil),
        state: CronState? = nil
    ) -> CronJob {
        CronJob(
            id: "test-job-id",
            agentId: nil,
            name: "Test Job",
            enabled: enabled,
            createdAtMs: nil,
            updatedAtMs: nil,
            schedule: schedule,
            sessionTarget: nil,
            wakeMode: nil,
            payload: nil,
            state: state,
            isolation: nil,
            description: nil,
            deleteAfterRun: nil,
            delivery: nil
        )
    }

    // MARK: - isEnabled

    func testIsEnabledTrue() {
        let job = makeJob(enabled: true)
        XCTAssertTrue(job.isEnabled)
    }

    func testIsEnabledFalse() {
        let job = makeJob(enabled: false)
        XCTAssertFalse(job.isEnabled)
    }

    func testIsEnabledNilDefaultsToTrue() {
        let job = makeJob(enabled: nil)
        XCTAssertTrue(job.isEnabled)
    }

    // MARK: - scheduleDescription

    func testScheduleDescriptionEveryHours() {
        let schedule = CronSchedule(kind: "every", expr: nil, tz: nil, everyMs: 3600000, atMs: nil) // 1h
        let job = makeJob(schedule: schedule)
        XCTAssertEqual(job.scheduleDescription, "1h")
    }

    func testScheduleDescriptionEveryMinutes() {
        let schedule = CronSchedule(kind: "every", expr: nil, tz: nil, everyMs: 1800000, atMs: nil) // 30m
        let job = makeJob(schedule: schedule)
        XCTAssertEqual(job.scheduleDescription, "30m")
    }

    func testScheduleDescriptionEveryDays() {
        let schedule = CronSchedule(kind: "every", expr: nil, tz: nil, everyMs: 86400000, atMs: nil) // 1d
        let job = makeJob(schedule: schedule)
        XCTAssertEqual(job.scheduleDescription, "1d")
    }

    func testScheduleDescriptionCron() {
        let schedule = CronSchedule(kind: "cron", expr: "0 */6 * * *", tz: nil, everyMs: nil, atMs: nil)
        let job = makeJob(schedule: schedule)
        XCTAssertEqual(job.scheduleDescription, "0 */6 * * *")
    }

    func testScheduleDescriptionCronNilExpr() {
        let schedule = CronSchedule(kind: "cron", expr: nil, tz: nil, everyMs: nil, atMs: nil)
        let job = makeJob(schedule: schedule)
        XCTAssertEqual(job.scheduleDescription, "cron")
    }

    func testScheduleDescriptionAt() {
        let timestamp: Int64 = 1707000000000
        let schedule = CronSchedule(kind: "at", expr: nil, tz: nil, everyMs: nil, atMs: timestamp)
        let job = makeJob(schedule: schedule)
        // Should produce a formatted date string, just verify it's not "one-time"
        XCTAssertFalse(job.scheduleDescription.isEmpty)
        XCTAssertNotEqual(job.scheduleDescription, "one-time")
    }

    func testScheduleDescriptionAtNilMs() {
        let schedule = CronSchedule(kind: "at", expr: nil, tz: nil, everyMs: nil, atMs: nil)
        let job = makeJob(schedule: schedule)
        XCTAssertEqual(job.scheduleDescription, "one-time")
    }

    func testScheduleDescriptionEveryNilMs() {
        let schedule = CronSchedule(kind: "every", expr: nil, tz: nil, everyMs: nil, atMs: nil)
        let job = makeJob(schedule: schedule)
        XCTAssertEqual(job.scheduleDescription, "interval")
    }

    func testScheduleDescriptionUnknownKind() {
        let schedule = CronSchedule(kind: "manual", expr: nil, tz: nil, everyMs: nil, atMs: nil)
        let job = makeJob(schedule: schedule)
        XCTAssertEqual(job.scheduleDescription, "manual")
    }

    // MARK: - isRunning

    func testIsRunningNoState() {
        let job = makeJob(state: nil)
        XCTAssertFalse(job.isRunning)
    }

    func testIsRunningNoLastRun() {
        let state = CronState(nextRunAtMs: nil, lastRunAtMs: nil, lastStatus: nil, lastDurationMs: nil, consecutiveErrors: nil)
        let job = makeJob(state: state)
        XCTAssertFalse(job.isRunning)
    }

    // MARK: - nextRunDate / lastRunDate

    func testNextRunDate() {
        let state = CronState(nextRunAtMs: 1707000000000, lastRunAtMs: nil, lastStatus: nil, lastDurationMs: nil, consecutiveErrors: nil)
        let job = makeJob(state: state)
        let expected = Date(timeIntervalSince1970: 1707000000)
        XCTAssertEqual(job.nextRunDate, expected)
    }

    func testNextRunDateNil() {
        let job = makeJob(state: nil)
        XCTAssertNil(job.nextRunDate)
    }

    func testLastRunDate() {
        let state = CronState(nextRunAtMs: nil, lastRunAtMs: 1707000000000, lastStatus: nil, lastDurationMs: nil, consecutiveErrors: nil)
        let job = makeJob(state: state)
        let expected = Date(timeIntervalSince1970: 1707000000)
        XCTAssertEqual(job.lastRunDate, expected)
    }

    func testLastRunDateNil() {
        let job = makeJob(state: nil)
        XCTAssertNil(job.lastRunDate)
    }

    // MARK: - Duration formatting via scheduleDescription

    func testScheduleDescriptionEverySeconds() {
        let schedule = CronSchedule(kind: "every", expr: nil, tz: nil, everyMs: 30000, atMs: nil) // 30s
        let job = makeJob(schedule: schedule)
        XCTAssertEqual(job.scheduleDescription, "30s")
    }
}
