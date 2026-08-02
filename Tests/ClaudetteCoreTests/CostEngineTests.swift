import XCTest
@testable import ClaudetteCore

final class CostEngineTests: XCTestCase {
    private var tempDir: URL!
    private var logsDir: URL!
    private var cacheURL: URL!
    private let prices = PriceTable(models: [
        "claude-opus-4-5": ModelPrice(inputPerMillion: 5, outputPerMillion: 25),
    ])

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudette-engine-\(UUID().uuidString)")
        logsDir = tempDir.appendingPathComponent("logs")
        cacheURL = tempDir.appendingPathComponent("cost.json")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func line(id: String?, request: String?, input: Int, output: Int,
                      cacheWrite: Int = 0, cacheRead: Int = 0,
                      model: String = "claude-opus-4-5",
                      timestamp: String) -> String {
        let idField = id.map { #""id":"\#($0)","# } ?? ""
        let requestField = request.map { #""requestId":"\#($0)","# } ?? ""
        return """
        {"type":"assistant",\(requestField)"timestamp":"\(timestamp)",\
        "message":{\(idField)"model":"\(model)","usage":{"input_tokens":\(input),\
        "output_tokens":\(output),"cache_creation_input_tokens":\(cacheWrite),\
        "cache_read_input_tokens":\(cacheRead)}}}
        """
    }

    private func recentTimestamp() -> String {
        ISO8601.format(Date().addingTimeInterval(-3600))
    }

    /// Scan only the fixture tree. Without the injected resolver the engine
    /// also walks the developer's real `~/.claude` logs, and every assertion
    /// below becomes a property of whoever is running the suite.
    private func makeEngine() -> CostEngine {
        CostEngine(cacheURL: cacheURL, logRoots: FixedLogRoots([logsDir]))
    }

    func testDeduplicatesStreamingChunks() async throws {
        let ts = recentTimestamp()
        let content = [
            line(id: "m1", request: "r1", input: 100, output: 50, cacheWrite: 1000, cacheRead: 2000, timestamp: ts),
            line(id: "m1", request: "r1", input: 100, output: 50, cacheWrite: 1000, cacheRead: 2000, timestamp: ts),
            line(id: "m1", request: "r1", input: 100, output: 50, cacheWrite: 1000, cacheRead: 2000, timestamp: ts),
            line(id: "m2", request: "r2", input: 10, output: 5, timestamp: ts),
        ].joined(separator: "\n") + "\n"
        try Data(content.utf8).write(to: logsDir.appendingPathComponent("a.jsonl"))

        let report = await makeEngine().refresh(prices: prices)
        // Dedup keeps one copy of m1: input 110, output 55, cw5m 1000, read 2000.
        let inputDollars: Double = 110.0 * 5.0
        let outputDollars: Double = 55.0 * 25.0
        let cacheWriteDollars: Double = 1000.0 * 6.25
        let cacheReadDollars: Double = 2000.0 * 0.5
        let expected: Double = (inputDollars + outputDollars + cacheWriteDollars + cacheReadDollars) / 1_000_000.0
        XCTAssertEqual(report.totalDollars, expected, accuracy: 1e-12)
        XCTAssertEqual(report.models.count, 1)
        XCTAssertEqual(report.models[0].tally.input, 110)
    }

    func testCrossFileDuplicatesRemoved() async throws {
        // Resumed sessions copy history into a new file; dedup must be global.
        let ts = recentTimestamp()
        let entry = line(id: "m1", request: "r1", input: 100, output: 100, timestamp: ts)
        try Data((entry + "\n").utf8).write(to: logsDir.appendingPathComponent("a.jsonl"))
        try Data((entry + "\n").utf8).write(to: logsDir.appendingPathComponent("b.jsonl"))

        let report = await makeEngine().refresh(prices: prices)
        XCTAssertEqual(report.models.first?.tally.input, 100)
    }

    /// Turns with neither a message ID nor a request ID have no identity to
    /// dedup on. Hashing the empty pair would fold every one of them into a
    /// single entry and silently drop the rest.
    func testTurnsWithoutAnyIDAreAllCounted() async throws {
        let ts = recentTimestamp()
        let content = [
            line(id: nil, request: nil, input: 10, output: 0, timestamp: ts),
            line(id: nil, request: nil, input: 20, output: 0, timestamp: ts),
            line(id: nil, request: nil, input: 30, output: 0, timestamp: ts),
        ].joined(separator: "\n") + "\n"
        try Data(content.utf8).write(to: logsDir.appendingPathComponent("a.jsonl"))

        let report = await makeEngine().refresh(prices: prices)
        XCTAssertEqual(report.models.first?.tally.input, 60)
    }

    func testIncrementalRescanReadsOnlyTheTail() async throws {
        let ts = recentTimestamp()
        let fileURL = logsDir.appendingPathComponent("a.jsonl")
        let first = line(id: "m1", request: "r1", input: 100, output: 0, timestamp: ts) + "\n"
        try Data(first.utf8).write(to: fileURL)

        let engine = makeEngine()
        _ = await engine.refresh(prices: prices)

        // Corrupt the already-consumed head, and append a new line, both
        // through the same handle so the inode is preserved — replacing the
        // file would trip the rebuild check and prove nothing. If the engine
        // re-read from zero this garbage would change the totals; a true tail
        // read never sees it.
        let second = line(id: "m2", request: "r2", input: 7, output: 0, timestamp: ts) + "\n"
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data("XXXX".utf8))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(second.utf8))
        try handle.close()

        let report = await engine.refresh(prices: prices)
        XCTAssertEqual(report.models.first?.tally.input, 107)
    }

    func testShrunkFileForcesCleanRebuild() async throws {
        let ts = recentTimestamp()
        let fileURL = logsDir.appendingPathComponent("a.jsonl")
        let two = [
            line(id: "m1", request: "r1", input: 100, output: 0, timestamp: ts),
            line(id: "m2", request: "r2", input: 50, output: 0, timestamp: ts),
        ].joined(separator: "\n") + "\n"
        try Data(two.utf8).write(to: fileURL)

        let engine = makeEngine()
        let before = await engine.refresh(prices: prices)
        XCTAssertEqual(before.models.first?.tally.input, 150)

        let one = line(id: "m1", request: "r1", input: 100, output: 0, timestamp: ts) + "\n"
        try Data(one.utf8).write(to: fileURL)

        let after = await engine.refresh(prices: prices)
        XCTAssertEqual(after.models.first?.tally.input, 100)
    }

    /// A file rewritten in place to a *larger* size keeps its inode and passes
    /// the size check, so only the timestamp reveals that resuming from the
    /// stored offset would parse unrelated bytes.
    func testFileRewrittenBackwardsInTimeForcesRebuild() async throws {
        let ts = recentTimestamp()
        let fileURL = logsDir.appendingPathComponent("a.jsonl")
        try Data((line(id: "m1", request: "r1", input: 100, output: 0, timestamp: ts) + "\n").utf8)
            .write(to: fileURL)

        let engine = makeEngine()
        _ = await engine.refresh(prices: prices)

        let replacement = [
            line(id: "m9", request: "r9", input: 5, output: 0, timestamp: ts),
            line(id: "m8", request: "r8", input: 5, output: 0, timestamp: ts),
        ].joined(separator: "\n") + "\n"
        try Data(replacement.utf8).write(to: fileURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: fileURL.path)

        let report = await engine.refresh(prices: prices)
        XCTAssertEqual(report.models.first?.tally.input, 10)
    }

    func testCachePersistsAcrossEngineInstances() async throws {
        let ts = recentTimestamp()
        let fileURL = logsDir.appendingPathComponent("a.jsonl")
        try Data((line(id: "m1", request: "r1", input: 42, output: 0, timestamp: ts) + "\n").utf8)
            .write(to: fileURL)

        _ = await makeEngine().refresh(prices: prices)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheURL.path))

        // A fresh engine loads the cache; with no file growth it re-reads nothing.
        let report = await makeEngine().refresh(prices: prices)
        XCTAssertEqual(report.models.first?.tally.input, 42)
    }

    func testUnpricedModelExcludedFromDollarsButCounted() async throws {
        let ts = recentTimestamp()
        let content = [
            line(id: "m1", request: "r1", input: 100, output: 0, timestamp: ts),
            line(id: "m2", request: "r2", input: 999, output: 0, model: "totally-future-model", timestamp: ts),
        ].joined(separator: "\n") + "\n"
        try Data(content.utf8).write(to: logsDir.appendingPathComponent("a.jsonl"))

        let report = await makeEngine().refresh(prices: prices)
        XCTAssertEqual(report.unpricedModels, ["totally-future-model"])
        let expected: Double = 500.0 / 1_000_000.0
        XCTAssertEqual(report.totalDollars, expected, accuracy: 1e-12)
        let unpriced = try XCTUnwrap(report.models.first { $0.model == "totally-future-model" })
        XCTAssertNil(unpriced.dollars)
        XCTAssertEqual(unpriced.tally.input, 999)
    }
}

final class CostCacheTests: XCTestCase {
    private func turn(_ hash: UInt64?, day: DayKey, input: Int64 = 1) -> LoggedTurn {
        LoggedTurn(dedupHash: hash, model: "m", day: day, tally: TokenTally(input: input))
    }

    /// The dedup set used to be a single flat blob that `prune` never touched,
    /// so it grew for the life of the install and was re-encoded every refresh.
    func testPruneDropsDedupHashesWithTheirDay() {
        var cache = CostCache()
        let old = DayKey(Date(timeIntervalSinceNow: -200 * 86_400))
        let recent = DayKey(Date())
        cache.addIfUnseen(turn(1, day: old))
        cache.addIfUnseen(turn(2, day: recent))

        cache.prune(olderThanDays: 90)

        XCTAssertNil(cache.days[old])
        XCTAssertNil(cache.seenHashes[old])
        XCTAssertNotNil(cache.seenHashes[recent])
    }

    func testAddIfUnseenReportsDuplicates() {
        var cache = CostCache()
        let day = DayKey(Date())
        XCTAssertTrue(cache.addIfUnseen(turn(7, day: day)))
        XCTAssertFalse(cache.addIfUnseen(turn(7, day: day)))
        XCTAssertEqual(cache.days[day]?["m"]?.input, 1)
    }

    func testTurnsWithoutHashesAreNeverFoldedTogether() {
        var cache = CostCache()
        let day = DayKey(Date())
        XCTAssertTrue(cache.addIfUnseen(turn(nil, day: day)))
        XCTAssertTrue(cache.addIfUnseen(turn(nil, day: day)))
        XCTAssertEqual(cache.days[day]?["m"]?.input, 2)
    }

    func testRoundTripsThroughJSON() throws {
        var cache = CostCache()
        let day = DayKey(Date())
        for hash in [UInt64(0), 1, 42, .max, 0xdead_beef_cafe_f00d] {
            cache.addIfUnseen(turn(hash, day: day))
        }
        cache.files["/a.jsonl"] = CostCache.FileCursor(
            inode: 9, size: 100, modifiedAt: 1234, offset: 50)

        let data = try ISO8601.encoder().encode(cache)
        let decoded = try JSONDecoder().decode(CostCache.self, from: data)
        XCTAssertEqual(decoded, cache)
        XCTAssertEqual(decoded.seenHashes[day]?.count, 5)
    }

    /// A day bucket is keyed by the readable `2026-08-02` string, not by the
    /// alternating array Codable falls back to for non-String keys.
    func testDaysEncodeAsAJSONObject() throws {
        var cache = CostCache()
        cache.addIfUnseen(turn(1, day: DayKey(year: 2026, month: 8, day: 2)))
        let json = String(decoding: try ISO8601.encoder().encode(cache), as: UTF8.self)
        XCTAssertTrue(json.contains(#""2026-08-02""#))
    }

    func testInvalidationRules() {
        let stored = CostCache.FileCursor(inode: 5, size: 100, modifiedAt: 1000, offset: 100)
        func fresh(inode: UInt64 = 5, size: UInt64 = 100, modifiedAt: Double = 1000) -> CostCache.FileCursor {
            CostCache.FileCursor(inode: inode, size: size, modifiedAt: modifiedAt, offset: 0)
        }
        XCTAssertFalse(stored.isInvalidated(by: fresh()))
        XCTAssertFalse(stored.isInvalidated(by: fresh(size: 200, modifiedAt: 2000)))
        XCTAssertTrue(stored.isInvalidated(by: fresh(size: 40)), "shrunk")
        XCTAssertTrue(stored.isInvalidated(by: fresh(inode: 6)), "replaced")
        XCTAssertTrue(stored.isInvalidated(by: fresh(size: 200, modifiedAt: 5)), "rewritten in place")
    }
}
