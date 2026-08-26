import XCTest
@testable import QuotaPulse

final class CodexEquivalentValueIndexerTests: XCTestCase {
    func testOfficialPriceFormulaIncludesCacheWriteAndLongContextMultipliers() throws {
        let value = try XCTUnwrap(
            CodexEquivalentValuePricing.valueUSD(
                model: "gpt-5.6-sol",
                input: 300_000,
                cachedInput: 100_000,
                cacheWriteInput: 50_000,
                output: 10_000
            )
        )
        XCTAssertEqual(value, 2.08, accuracy: 0.000_001)
    }

    func testSkipsForkReplayAndRepeatedTokenBroadcasts() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = root.appendingPathComponent("cache/index.json")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let now = Date()
        let rootID = "11111111-1111-1111-1111-111111111111"
        let forkID = "22222222-2222-2222-2222-222222222222"
        let normalForkID = "33333333-3333-3333-3333-333333333333"
        let rootFile = root.appendingPathComponent("rollout-2026-08-14T00-00-00-\(rootID).jsonl")
        let forkFile = root.appendingPathComponent("rollout-2026-08-14T00-01-00-\(forkID).jsonl")
        let normalForkFile = root.appendingPathComponent("rollout-2026-08-14T00-02-00-\(normalForkID).jsonl")
        let rootStart = now.addingTimeInterval(-3_600)
        let forkStart = now.addingTimeInterval(-1_800)

        try writeLines([
            meta(id: rootID, timestamp: rootStart, source: "vscode"),
            taskStarted(timestamp: rootStart, startedAt: rootStart, turnID: rootID),
            turnContext(timestamp: rootStart, model: "gpt-5.3-codex"),
            tokenCount(timestamp: rootStart.addingTimeInterval(10), input: 1_000, output: 100, plan: "plus"),
            tokenCount(timestamp: rootStart.addingTimeInterval(11), input: 1_000, output: 100, plan: "plus"),
            tokenCount(timestamp: rootStart.addingTimeInterval(20), input: 2_000, output: 200, plan: "plus")
        ], to: rootFile)

        try writeLines([
            meta(id: forkID, timestamp: forkStart, source: ["subagent": ["thread_spawn": [:]]], sessionID: rootID),
            taskStarted(timestamp: forkStart, startedAt: rootStart, turnID: rootID),
            turnContext(timestamp: forkStart, model: "gpt-5.3-codex"),
            tokenCount(timestamp: forkStart, input: 1_000, output: 100, plan: "plus"),
            tokenCount(timestamp: forkStart, input: 2_000, output: 200, plan: "plus"),
            taskStarted(timestamp: forkStart, startedAt: forkStart, turnID: forkID),
            turnContext(timestamp: forkStart.addingTimeInterval(1), model: "gpt-5.3-codex"),
            tokenCount(timestamp: forkStart.addingTimeInterval(10), input: 3_000, output: 300, plan: "plus"),
            tokenCount(timestamp: forkStart.addingTimeInterval(20), input: 4_000, output: 400, plan: nil)
        ], to: forkFile)

        try writeLines([
            meta(id: normalForkID, timestamp: forkStart, source: "vscode", forkedFromID: rootID),
            taskStarted(timestamp: forkStart, startedAt: rootStart, turnID: rootID),
            turnContext(timestamp: forkStart, model: "gpt-5.3-codex"),
            tokenCount(timestamp: forkStart, input: 2_000, output: 200, plan: "plus"),
            taskStarted(timestamp: forkStart, startedAt: forkStart, turnID: normalForkID),
            turnContext(timestamp: forkStart.addingTimeInterval(1), model: "gpt-5.3-codex"),
            tokenCount(timestamp: forkStart.addingTimeInterval(12), input: 3_000, output: 300, plan: "plus")
        ], to: normalForkFile)

        let indexer = CodexEquivalentValueIndexer(fileManager: fileManager, roots: [root], cacheURL: cache)
        let snapshot = await indexer.refresh(now: now, minimumInterval: 0)
        let total = snapshot.dailyValues.reduce(0) { $0 + $1.valueUSD }

        // Root 2k/200 + two fork suffixes of 1k/100. Replayed and duplicate states are not counted.
        XCTAssertEqual(total, 0.0126, accuracy: 0.000_000_1)
        XCTAssertEqual(snapshot.excludedUnverifiedRequestCount, 1)
        XCTAssertTrue(snapshot.isLowerBound)

        try appendLines([
            tokenCount(timestamp: now, input: 5_000, output: 500, plan: "plus")
        ], to: forkFile)
        let updated = await indexer.refresh(now: now.addingTimeInterval(1), minimumInterval: 0)
        let updatedTotal = updated.dailyValues.reduce(0) { $0 + $1.valueUSD }
        XCTAssertEqual(updatedTotal, 0.01575, accuracy: 0.000_000_1)
    }

    func testUnverifiedOrMismatchedSessionIdentityNeverCreatesValue() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = root.appendingPathComponent("cache/index.json")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let now = Date()
        let missingMetaID = "44444444-4444-4444-4444-444444444444"
        let mismatchedMetaID = "55555555-5555-5555-5555-555555555555"
        let missingMetaFile = root.appendingPathComponent("rollout-2026-08-14T00-03-00-\(missingMetaID).jsonl")
        let mismatchedMetaFile = root.appendingPathComponent("rollout-2026-08-14T00-04-00-\(mismatchedMetaID).jsonl")

        try writeLines([
            turnContext(timestamp: now, model: "gpt-5.3-codex"),
            tokenCount(timestamp: now, input: 2_000_000, output: 200_000, plan: "plus")
        ], to: missingMetaFile)
        try writeLines([
            meta(id: "66666666-6666-6666-6666-666666666666", timestamp: now, source: "vscode"),
            turnContext(timestamp: now, model: "gpt-5.3-codex"),
            tokenCount(timestamp: now, input: 2_000_000, output: 200_000, plan: "plus")
        ], to: mismatchedMetaFile)

        let indexer = CodexEquivalentValueIndexer(fileManager: fileManager, roots: [root], cacheURL: cache)
        let snapshot = await indexer.refresh(now: now, minimumInterval: 0)
        XCTAssertEqual(snapshot.dailyValues.reduce(0) { $0 + $1.valueUSD }, 0)
        XCTAssertTrue(snapshot.isLowerBound)
    }

    private func meta(
        id: String,
        timestamp: Date,
        source: Any,
        sessionID: String? = nil,
        forkedFromID: String? = nil
    ) -> [String: Any] {
        var payload: [String: Any] = ["id": id, "source": source]
        if let sessionID { payload["session_id"] = sessionID }
        if let forkedFromID { payload["forked_from_id"] = forkedFromID }
        return ["timestamp": iso(timestamp), "type": "session_meta", "payload": payload]
    }

    private func taskStarted(timestamp: Date, startedAt: Date, turnID: String) -> [String: Any] {
        [
            "timestamp": iso(timestamp),
            "type": "event_msg",
            "payload": [
                "type": "task_started",
                "started_at": startedAt.timeIntervalSince1970,
                "turn_id": turnID
            ]
        ]
    }

    private func turnContext(timestamp: Date, model: String) -> [String: Any] {
        ["timestamp": iso(timestamp), "type": "turn_context", "payload": ["model": model]]
    }

    private func tokenCount(timestamp: Date, input: Int, output: Int, plan: String?) -> [String: Any] {
        var rateLimits: [String: Any] = [:]
        if let plan { rateLimits["plan_type"] = plan }
        return [
            "timestamp": iso(timestamp),
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "info": [
                    "total_token_usage": [
                        "input_tokens": input,
                        "cached_input_tokens": 0,
                        "output_tokens": output
                    ]
                ],
                "rate_limits": rateLimits
            ]
        ]
    }

    private func writeLines(_ objects: [[String: Any]], to url: URL) throws {
        let data = try encodedLines(objects)
        try data.write(to: url)
    }

    private func appendLines(_ objects: [[String: Any]], to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: encodedLines(objects))
    }

    private func encodedLines(_ objects: [[String: Any]]) throws -> Data {
        var data = Data()
        for object in objects {
            data.append(try JSONSerialization.data(withJSONObject: object))
            data.append(0x0A)
        }
        return data
    }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
