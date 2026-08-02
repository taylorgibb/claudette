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
        XCTAssertEqual(result.turns.count, 4)
        XCTAssertEqual(result.turns[0].model, "claude-opus-4-5")
        XCTAssertEqual(result.turns[0].tally.input, 100)
        XCTAssertEqual(result.turns[0].tally.output, 50)
        XCTAssertEqual(result.turns[0].tally.cacheWrite5m, 1000)
        XCTAssertEqual(result.turns[0].tally.cacheRead, 2000)
    }

    func testDuplicateStreamingChunksShareDedupHash() throws {
        let url = try fixture("dup-stream")
        let result = try LogScanner.scanFile(at: url, from: 0)
        let hashes = Set(result.turns.compactMap(\.dedupHash))
        // 3 chunks of msg_01 collapse to one hash; msg_02 is distinct.
        XCTAssertEqual(hashes.count, 2)
    }

    /// A turn with no identity at all gets no hash. Hashing the empty pair
    /// would give every such turn the same key, so all but the first would be
    /// discarded as duplicates.
    func testMissingIDsProduceNoDedupHash() {
        XCTAssertNil(LogScanner.dedupHash(messageID: nil, requestID: nil))
        XCTAssertNil(LogScanner.dedupHash(messageID: "", requestID: ""))
        XCTAssertNotNil(LogScanner.dedupHash(messageID: "m", requestID: nil))
        XCTAssertNotNil(LogScanner.dedupHash(messageID: nil, requestID: "r"))
        XCTAssertNotEqual(
            LogScanner.dedupHash(messageID: "m1", requestID: nil),
            LogScanner.dedupHash(messageID: "m2", requestID: nil))
    }

    func testCacheTTLBreakdownPricedSeparately() throws {
        let url = try fixture("cache-ttls")
        let result = try LogScanner.scanFile(at: url, from: 0)
        let turn = try XCTUnwrap(result.turns.first)
        XCTAssertEqual(turn.tally.cacheWrite5m, 800)
        XCTAssertEqual(turn.tally.cacheWrite1h, 200)
        // The aggregate cache_creation_input_tokens must not be double counted.
        XCTAssertEqual(turn.tally.total, 800 + 200 + 10 + 5 + 300)
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
        XCTAssertEqual(result.turns.count, 1)
        XCTAssertEqual(result.consumedOffset, UInt64(head.count))

        // Once the line completes, an incremental pass from the stored
        // offset picks it up.
        let rest = #"age":{"id":"m2","model":"claude-opus-4-5","usage":{"input_tokens":9,"output_tokens":1}}}"#
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((rest + "\n").utf8))
        try handle.close()

        let tail = try LogScanner.scanFile(at: url, from: result.consumedOffset)
        XCTAssertEqual(tail.turns.count, 1)
        XCTAssertEqual(tail.turns[0].tally.input, 9)
    }

    func testUnpricedModelStillCounted() throws {
        let url = try fixture("unknown-model")
        let result = try LogScanner.scanFile(at: url, from: 0)
        XCTAssertEqual(result.turns.count, 1)
        XCTAssertEqual(result.turns[0].model, "totally-future-model")
    }

    func testDayUsesLocalCalendar() throws {
        let line = """
        {"type":"assistant","requestId":"r1","timestamp":"2026-07-30T10:00:00.123456Z",\
        "message":{"id":"m1","model":"claude-opus-4-5","usage":{"input_tokens":1,"output_tokens":1}}}
        """
        let parsed = try XCTUnwrap(LogScanner.parseLine(Data(line.utf8)))
        let expected = DayKey(ISO8601.parse("2026-07-30T10:00:00.123456Z")!)
        XCTAssertEqual(parsed.day, expected)
    }

    func testFNV1aIsStable() {
        // Persisted dedup depends on this value never changing.
        XCTAssertEqual(Hash.fnv1a64(""), 0xcbf2_9ce4_8422_2325)
        XCTAssertEqual(Hash.fnv1a64("a"), 0xaf63_dc4c_8601_ec8c)
    }
}

final class DayKeyTests: XCTestCase {
    func testRoundTripsThroughItsRawValue() throws {
        let key = DayKey(year: 2026, month: 8, day: 2)
        XCTAssertEqual(key.rawValue, "2026-08-02")
        XCTAssertEqual(DayKey(rawValue: "2026-08-02"), key)
        XCTAssertNil(DayKey(rawValue: "not-a-day"))
        XCTAssertNil(DayKey(rawValue: "2026-08"))
    }

    func testOrdersChronologically() {
        XCTAssertLessThan(DayKey(year: 2025, month: 12, day: 31), DayKey(year: 2026, month: 1, day: 1))
        XCTAssertLessThan(DayKey(year: 2026, month: 1, day: 9), DayKey(year: 2026, month: 1, day: 10))
        XCTAssertLessThan(DayKey(year: 2026, month: 9, day: 1), DayKey(year: 2026, month: 10, day: 1))
    }

    /// The formatter used to be a static that captured `TimeZone.current`
    /// once. This app runs for weeks, so a frozen zone silently mis-files
    /// spend across the day boundary after travel or a DST change.
    func testResolvesAgainstTheCurrentTimeZoneNotAFrozenOne() {
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        let previous = NSTimeZone.default
        defer { NSTimeZone.default = previous }

        NSTimeZone.default = TimeZone(identifier: "Pacific/Kiritimati")!  // UTC+14
        let east = DayKey(instant)
        NSTimeZone.default = TimeZone(identifier: "Pacific/Midway")!      // UTC-11
        let west = DayKey(instant)

        XCTAssertNotEqual(east, west, "the same instant falls on different local days")
    }

    func testEncodesAsAPlainString() throws {
        let data = try JSONEncoder().encode([DayKey(year: 2026, month: 8, day: 2)])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), #"["2026-08-02"]"#)
    }
}
