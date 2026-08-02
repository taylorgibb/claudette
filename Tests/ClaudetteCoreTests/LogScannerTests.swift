import XCTest
@testable import ClaudetteCore

final class LogScannerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudette-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func fixture(_ name: String) throws -> URL {
        try XCTUnwrap(Bundle.module.url(
            forResource: name, withExtension: "jsonl", subdirectory: "Fixtures"))
    }

    func testParsesAssistantLinesOnly() throws {
        let url = try fixture("dup-stream")
        let result = try LogScanner.scanFile(at: url, from: 0)
        // 3 duplicate streaming chunks + 1 distinct message; user/junk lines skipped.
        XCTAssertEqual(result.entries.count, 4)
        XCTAssertEqual(result.entries[0].model, "claude-opus-4-5")
        XCTAssertEqual(result.entries[0].tally.input, 100)
        XCTAssertEqual(result.entries[0].tally.output, 50)
        XCTAssertEqual(result.entries[0].tally.cacheWrite5m, 1000)
        XCTAssertEqual(result.entries[0].tally.cacheRead, 2000)
    }

    func testDuplicateStreamingChunksShareDedupHash() throws {
        let url = try fixture("dup-stream")
        let result = try LogScanner.scanFile(at: url, from: 0)
        let hashes = Set(result.entries.map(\.dedupHash))
        // 3 chunks of msg_01 collapse to one hash; msg_02 is distinct.
        XCTAssertEqual(hashes.count, 2)
    }

    func testCacheTTLBreakdownPricedSeparately() throws {
        let url = try fixture("cache-ttls")
        let result = try LogScanner.scanFile(at: url, from: 0)
        let entry = try XCTUnwrap(result.entries.first)
        XCTAssertEqual(entry.tally.cacheWrite5m, 800)
        XCTAssertEqual(entry.tally.cacheWrite1h, 200)
        // The aggregate cache_creation_input_tokens must not be double counted.
        XCTAssertEqual(entry.tally.total, 800 + 200 + 10 + 5 + 300)
    }

    func testNoBreakdownAssumesFiveMinuteTTL() throws {
        let line = """
        {"type":"assistant","requestId":"r1","timestamp":"2026-07-30T10:00:00Z",\
        "message":{"id":"m1","model":"claude-sonnet-4-5",\
        "usage":{"input_tokens":1,"output_tokens":2,"cache_creation_input_tokens":500}}}
        """
        let parsed = try XCTUnwrap(LogScanner.parseLine(Data(line.utf8)))
        XCTAssertEqual(parsed.tally.cacheWrite5m, 500)
        XCTAssertEqual(parsed.tally.cacheWrite1h, 0)
    }

    func testSyntheticModelSkipped() {
        let line = """
        {"type":"assistant","message":{"id":"m","model":"<synthetic>",\
        "usage":{"input_tokens":5,"output_tokens":5}}}
        """
        XCTAssertNil(LogScanner.parseLine(Data(line.utf8)))
    }

    func testTruncatedFinalLineIsNotConsumed() throws {
        let complete = """
        {"type":"assistant","requestId":"r1","timestamp":"2026-07-30T10:00:00Z",\
        "message":{"id":"m1","model":"claude-opus-4-5","usage":{"input_tokens":7,"output_tokens":3}}}
        """
        let partial = #"{"type":"assistant","requestId":"r2","mess"#
        let url = tempDir.appendingPathComponent("truncated.jsonl")
        let head = Data((complete + "\n").utf8)
        try (head + Data(partial.utf8)).write(to: url)

        let result = try LogScanner.scanFile(at: url, from: 0)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.consumedOffset, UInt64(head.count))

        // Once the line completes, an incremental pass from the stored
        // offset picks it up.
        let rest = #"age":{"id":"m2","model":"claude-opus-4-5","usage":{"input_tokens":9,"output_tokens":1}}}"#
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((rest + "\n").utf8))
        try handle.close()

        let tail = try LogScanner.scanFile(at: url, from: result.consumedOffset)
        XCTAssertEqual(tail.entries.count, 1)
        XCTAssertEqual(tail.entries[0].tally.input, 9)
    }

    func testUnknownModelStillCounted() throws {
        let url = try fixture("unknown-model")
        let result = try LogScanner.scanFile(at: url, from: 0)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].model, "totally-future-model")
    }

    func testDayKeyUsesLocalCalendar() throws {
        let line = """
        {"type":"assistant","requestId":"r1","timestamp":"2026-07-30T10:00:00.123456Z",\
        "message":{"id":"m1","model":"claude-opus-4-5","usage":{"input_tokens":1,"output_tokens":1}}}
        """
        let parsed = try XCTUnwrap(LogScanner.parseLine(Data(line.utf8)))
        let expected = DayKey.from(ISO8601.parse("2026-07-30T10:00:00.123456Z")!)
        XCTAssertEqual(parsed.dayKey, expected)
    }

    func testSeenHashesBlobRoundTrip() {
        var cache = CostCache()
        let hashes: Set<UInt64> = [0, 1, 42, .max, 0xdead_beef_cafe_f00d]
        cache.seenHashes = hashes
        XCTAssertEqual(cache.seenHashes, hashes)
    }

    func testFNV1aIsStable() {
        // Persisted dedup depends on this value never changing.
        XCTAssertEqual(fnv1a64(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(fnv1a64("a"), 0xaf63_dc4c_8601_ec8c)
    }
}
