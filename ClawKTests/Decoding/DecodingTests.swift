import XCTest
@testable import ClawK

final class DecodingTests: XCTestCase {

    // MARK: - SessionInfo

    func testSessionInfoDecoding() throws {
        let json = """
        {
            "key": "agent:main:main",
            "kind": "session",
            "channel": null,
            "label": "My Session",
            "displayName": "Main",
            "updatedAt": 1707000000000,
            "sessionId": "abc-123",
            "model": "claude-sonnet-4-5",
            "contextTokens": 200000,
            "totalTokens": 50000,
            "systemSent": true,
            "abortedLastRun": false,
            "transcriptPath": "/path/to/transcript.jsonl"
        }
        """.data(using: .utf8)!

        let session = try JSONDecoder().decode(SessionInfo.self, from: json)
        XCTAssertEqual(session.key, "agent:main:main")
        XCTAssertEqual(session.sessionId, "abc-123")
        XCTAssertEqual(session.model, "claude-sonnet-4-5")
        XCTAssertEqual(session.contextTokens, 200_000)
        XCTAssertEqual(session.totalTokens, 50_000)
        XCTAssertEqual(session.label, "My Session")
        XCTAssertEqual(session.modelShortName, "Sonnet")
        XCTAssertEqual(session.sessionType, .main)
        XCTAssertEqual(session.contextUsagePercent, 25.0, accuracy: 0.01)
        XCTAssertNotNil(session.lastUpdatedDate)
    }

    func testSessionInfoDecodingMinimalFields() throws {
        let json = """
        {
            "key": "agent:main:subagent:xyz",
            "sessionId": "sub-123"
        }
        """.data(using: .utf8)!

        let session = try JSONDecoder().decode(SessionInfo.self, from: json)
        XCTAssertEqual(session.key, "agent:main:subagent:xyz")
        XCTAssertEqual(session.sessionId, "sub-123")
        XCTAssertNil(session.model)
        XCTAssertNil(session.totalTokens)
        XCTAssertEqual(session.modelShortName, "—")
        XCTAssertEqual(session.sessionType, .subagent)
    }

    // MARK: - CronJob

    func testCronJobDecoding() throws {
        let json = """
        {
            "id": "cron-1",
            "name": "Daily Check",
            "enabled": true,
            "schedule": {
                "kind": "every",
                "everyMs": 3600000
            },
            "state": {
                "nextRunAtMs": 1707000000000,
                "lastRunAtMs": 1706996400000,
                "lastStatus": "ok",
                "lastDurationMs": 5000
            }
        }
        """.data(using: .utf8)!

        let job = try JSONDecoder().decode(CronJob.self, from: json)
        XCTAssertEqual(job.id, "cron-1")
        XCTAssertEqual(job.name, "Daily Check")
        XCTAssertTrue(job.isEnabled)
        XCTAssertEqual(job.scheduleDescription, "1h")
        XCTAssertNotNil(job.nextRunDate)
        XCTAssertNotNil(job.lastRunDate)
    }

    // MARK: - ModelInfo

    func testModelInfoDecoding() throws {
        let json = """
        {
            "key": "claude-opus-4-6",
            "supportsVision": true,
            "supportsFunctionCalling": true,
            "tags": ["premium"]
        }
        """.data(using: .utf8)!

        let model = try JSONDecoder().decode(ModelInfo.self, from: json)
        XCTAssertEqual(model.id, "claude-opus-4-6")
        XCTAssertNil(model.contextWindow)
        XCTAssertEqual(model.effectiveContextWindow, 1_000_000) // opus-4-6 fallback
        XCTAssertEqual(model.supportsVision, true)
    }

    // MARK: - HeartbeatConfig

    func testHeartbeatConfigDecoding() throws {
        let json = """
        {
            "enabled": true,
            "every": "30m",
            "everyMs": 1800000,
            "model": "claude-haiku-4",
            "target": "main"
        }
        """.data(using: .utf8)!

        let config = try JSONDecoder().decode(HeartbeatConfig.self, from: json)
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.every, "30m")
        XCTAssertEqual(config.everyMs, 1_800_000)
        XCTAssertEqual(config.model, "claude-haiku-4")
    }

    // MARK: - GatewayError

    func testGatewayErrorDescriptions() {
        XCTAssertNotNil(GatewayError.invalidURL.errorDescription)
        XCTAssertNotNil(GatewayError.unauthorized.errorDescription)
        XCTAssertNotNil(GatewayError.notFound.errorDescription)
        XCTAssertNotNil(GatewayError.timeout.errorDescription)
        XCTAssertNotNil(GatewayError.noToken.errorDescription)
        XCTAssertNotNil(GatewayError.toolBlocked("test").errorDescription)
        XCTAssertNotNil(GatewayError.serverError("test").errorDescription)
    }

    func testGatewayErrorIsTimeout() {
        XCTAssertTrue(GatewayError.timeout.isTimeout)
        XCTAssertFalse(GatewayError.invalidURL.isTimeout)
        XCTAssertFalse(GatewayError.networkError(NSError(domain: "test", code: 0)).isTimeout)
    }

    func testGatewayErrorToolBlockedMessage() {
        let error = GatewayError.toolBlocked("bash")
        XCTAssertTrue(error.errorDescription!.contains("bash"))
    }

    func testGatewayErrorServerErrorMessage() {
        let error = GatewayError.serverError("Internal error")
        XCTAssertTrue(error.errorDescription!.contains("Internal error"))
    }

    // MARK: - ClaudeUsageResponse

    func testClaudeUsageResponseDecoding() throws {
        let json = """
        {
            "five_hour": {
                "utilization": 15.5,
                "resets_at": "2026-02-16T12:00:00Z"
            },
            "seven_day": {
                "utilization": 42.3,
                "resets_at": "2026-02-22T00:00:00Z"
            },
            "seven_day_opus": {
                "utilization": 30.0,
                "resets_at": "2026-02-22T00:00:00Z"
            }
        }
        """.data(using: .utf8)!

        let usage = try JSONDecoder().decode(ClaudeUsageResponse.self, from: json)
        XCTAssertEqual(usage.five_hour?.utilization, 15.5)
        XCTAssertEqual(usage.seven_day?.utilization, 42.3)
        XCTAssertEqual(usage.seven_day_opus?.utilization, 30.0)
        XCTAssertNil(usage.seven_day_sonnet)
        XCTAssertNil(usage.extra_usage)
    }

    // MARK: - EmbeddingPoint Encode/Decode

    func testEmbeddingPointRoundTrip() throws {
        let original = EmbeddingPoint(
            id: "point-1",
            path: "memory/notes.md",
            tier: "warm",
            tokens: 150,
            x: 1.5,
            y: -2.3,
            z: 0.7,
            cluster: "cluster-a",
            chunkIndex: 2,
            text: "Test content",
            similarityToMemory: 0.85,
            isMemoryMd: false
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(EmbeddingPoint.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.path, original.path)
        XCTAssertEqual(decoded.tier, original.tier)
        XCTAssertEqual(decoded.tokens, original.tokens)
        XCTAssertEqual(decoded.x, original.x, accuracy: 0.001)
        XCTAssertEqual(decoded.y, original.y, accuracy: 0.001)
        XCTAssertEqual(decoded.z, original.z, accuracy: 0.001)
        XCTAssertEqual(decoded.cluster, original.cluster)
        XCTAssertEqual(decoded.chunkIndex, original.chunkIndex)
        XCTAssertEqual(decoded.text, original.text)
        XCTAssertEqual(decoded.similarityToMemory, 0.85)
        XCTAssertEqual(decoded.isMemoryMd, false)
    }

    func testEmbeddingPointDecodingWithoutOptionalFields() throws {
        let json = """
        {
            "id": "p1",
            "path": "test.md",
            "tier": "hot",
            "tokens": 50,
            "x": 0.0,
            "y": 0.0,
            "z": 0.0,
            "chunkIndex": 0,
            "text": "hello"
        }
        """.data(using: .utf8)!

        let point = try JSONDecoder().decode(EmbeddingPoint.self, from: json)
        XCTAssertEqual(point.id, "p1")
        XCTAssertNil(point.cluster)
        XCTAssertNil(point.similarityToMemory)
        XCTAssertNil(point.isMemoryMd)
        XCTAssertEqual(point.similarity, 0.0) // default
    }

    // MARK: - SessionsListResponse

    func testSessionsListResponseDecoding() throws {
        let json = """
        {
            "count": 1,
            "sessions": [
                {
                    "key": "agent:main:main",
                    "sessionId": "sess-1",
                    "model": "claude-sonnet-4-5"
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(SessionsListResponse.self, from: json)
        XCTAssertEqual(response.count, 1)
        XCTAssertEqual(response.sessions.count, 1)
        XCTAssertEqual(response.sessions[0].sessionId, "sess-1")
    }

    // MARK: - CronListResponse

    func testCronListResponseDecoding() throws {
        let json = """
        {
            "jobs": [
                {
                    "id": "job-1",
                    "name": "Heartbeat",
                    "schedule": { "kind": "every", "everyMs": 1800000 }
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(CronListResponse.self, from: json)
        XCTAssertEqual(response.jobs.count, 1)
        XCTAssertEqual(response.jobs[0].name, "Heartbeat")
    }
}
