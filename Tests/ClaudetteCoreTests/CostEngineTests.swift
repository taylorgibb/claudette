import XCTest
@testable import ClaudetteCore

final class CostEngineTests: XCTestCase {
    private var tempDir: URL!
    private var logsDir: URL!
    private var cacheURL: URL!
    private let prices = PriceTable(models: [
        "claude-opus-4-5": ModelPrice(input: 5, output: 25),
    ])

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudette-engine-\(UUID().uuidString)")
        logsDir = tempDir.appendingPathComponent("logs")
        cacheURL = tempDir.appendingPathComponent("cost-v1.json")
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func line(id: String, request: String, input: Int, output: Int,
                      cacheWrite: Int = 0, cacheRead: Int = 0,
                      model: String = "claude-opus-4-5",
                      timestamp: String) -> String {
        """
        {"type":"assistant","requestId":"\(request)","timestamp":"\(timestamp)",\
        "message":{"id":"\(id)","model":"\(model)","usage":{"input_tokens":\(input),\
        "output_tokens":\(output),"cache_creation_input_tokens":\(cacheWrite),\
        "cache_read_input_tokens":\(cacheRead)}}}
        """
    }

    private func recentTimestamp() -> String {
        ISO8601.format(Date().addingTimeInterval(-3600))
    }

    private func makeEngine() -> CostEngine {
        CostEngine(cacheURL: cacheURL, extraRoots: [logsDir.path])
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
        let expected = (110.0 * 5 + 55.0 * 25 + 1000.0 * 6.25 + 2000.0 * 0.5) / 1_000_000
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

    func testIncrementalRescanReadsOnlyTheTail() async throws {
        let ts = recentTimestamp()
        let fileURL = logsDir.appendingPathComponent("a.jsonl")
        let first = line(id: "m1", request: "r1", input: 100, output: 0, timestamp: ts) + "\n"
        try Data(first.utf8).write(to: fileURL)

        let engine = makeEngine()
        _ = await engine.refresh(prices: prices)

        // Corrupt the already-consumed head in place (same byte count). If the
        // engine re-read from zero this garbage would change the totals; a
        // true tail read never sees it.
        var bytes = try Data(contentsOf: fileURL)
        bytes.replaceSubrange(0..<4, with: Data("XXXX".utf8))
        try bytes.write(to: fileURL)

        let second = line(id: "m2", request: "r2", input: 7, output: 0, timestamp: ts) + "\n"
        let handle = try FileHandle(forWritingTo: fileURL)
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

    func testUnknownModelExcludedFromDollarsButCounted() async throws {
        let ts = recentTimestamp()
        let content = [
            line(id: "m1", request: "r1", input: 100, output: 0, timestamp: ts),
            line(id: "m2", request: "r2", input: 999, output: 0, model: "totally-future-model", timestamp: ts),
        ].joined(separator: "\n") + "\n"
        try Data(content.utf8).write(to: logsDir.appendingPathComponent("a.jsonl"))

        let report = await makeEngine().refresh(prices: prices)
        XCTAssertEqual(report.unknownModels, ["totally-future-model"])
        XCTAssertEqual(report.totalDollars, 100.0 * 5 / 1_000_000, accuracy: 1e-12)
        let unknownLine = try XCTUnwrap(report.models.first { $0.model == "totally-future-model" })
        XCTAssertNil(unknownLine.dollars)
        XCTAssertEqual(unknownLine.tally.input, 999)
    }
}
