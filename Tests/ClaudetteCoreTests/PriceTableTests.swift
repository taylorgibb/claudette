import XCTest
@testable import ClaudetteCore

final class PriceTableTests: XCTestCase {
    func testBundledTableLoads() {
        let table = PriceTable.bundled()
        XCTAssertFalse(table.models.isEmpty)
        XCTAssertNotNil(table.price(forModel: "claude-opus-4-5"))
    }

    func testExactMatch() {
        let table = PriceTable(models: ["claude-opus-4-5": ModelPrice(inputPerMillion: 5, outputPerMillion: 25)])
        XCTAssertEqual(table.price(forModel: "claude-opus-4-5")?.inputPerMillion, 5)
    }

    func testDatedVariantPrefixMatch() {
        let table = PriceTable(models: ["claude-sonnet-4-6": ModelPrice(inputPerMillion: 3, outputPerMillion: 15)])
        XCTAssertEqual(table.price(forModel: "claude-sonnet-4-6-20260514")?.inputPerMillion, 3)
        XCTAssertEqual(table.price(forModel: "claude-sonnet-4-6-latest")?.inputPerMillion, 3)
    }

    func testProviderPrefixIsStripped() {
        let table = PriceTable(models: ["claude-opus-4-5": ModelPrice(inputPerMillion: 5, outputPerMillion: 25)])
        XCTAssertEqual(table.price(forModel: "anthropic/claude-opus-4-5-20260114")?.inputPerMillion, 5)
    }

    func testDifferentModelNeverBleedsThroughPrefix() {
        // claude-opus-4-5 must NOT inherit claude-opus-4 pricing.
        let table = PriceTable(models: ["claude-opus-4": ModelPrice(inputPerMillion: 15, outputPerMillion: 75)])
        XCTAssertNil(table.price(forModel: "claude-opus-4-5"))
        XCTAssertNil(table.price(forModel: "claude-opus-4-5-20260114"))
        // But a real dated variant of opus-4 still matches.
        XCTAssertEqual(table.price(forModel: "claude-opus-4-20250514")?.inputPerMillion, 15)
    }

    func testUnknownModelReturnsNilNotZero() {
        let table = PriceTable.bundled()
        XCTAssertNil(table.price(forModel: "future-model-x"))
        XCTAssertNil(table.dollars(for: TokenTally(input: 1000), model: "future-model-x"))
    }

    func testDollarMathWithDerivedCacheRates() {
        let table = PriceTable(models: ["m": ModelPrice(inputPerMillion: 10, outputPerMillion: 20)])
        let tally = TokenTally(
            input: 1_000_000,
            output: 1_000_000,
            cacheWrite5m: 1_000_000,
            cacheWrite1h: 1_000_000,
            cacheRead: 1_000_000)
        // 10 + 20 + 12.5 (1.25x) + 20 (2x) + 1 (0.1x)
        XCTAssertEqual(table.dollars(for: tally, model: "m")!, 63.5, accuracy: 1e-9)
    }

    func testExplicitCacheRatesOverrideDerived() {
        let price = ModelPrice(
            inputPerMillion: 10, outputPerMillion: 20,
            cacheReadPerMillion: 2, cacheWrite5mPerMillion: 11, cacheWrite1hPerMillion: 30)
        XCTAssertEqual(price.cacheReadPerMillion, 2)
        XCTAssertEqual(price.cacheWrite5mPerMillion, 11)
        XCTAssertEqual(price.cacheWrite1hPerMillion, 30)
    }

    /// Rates omitted by the table are filled in at decode time, so a
    /// `ModelPrice` in hand always has all five.
    func testDerivedCacheRatesSurviveDecoding() throws {
        let json = #"{"version":1,"models":{"m":{"input":10,"output":20}}}"#
        let table = try PriceTable.load(from: Data(json.utf8))
        let price = try XCTUnwrap(table.price(forModel: "m"))
        XCTAssertEqual(price.cacheReadPerMillion, 1, accuracy: 1e-9)
        XCTAssertEqual(price.cacheWrite5mPerMillion, 12.5, accuracy: 1e-9)
        XCTAssertEqual(price.cacheWrite1hPerMillion, 20, accuracy: 1e-9)
    }

    func testModelDisplayNames() {
        XCTAssertEqual(ModelNaming.displayName(for: "claude-opus-4-5-20260114"), "Opus 4.5")
        XCTAssertEqual(ModelNaming.displayName(for: "anthropic/claude-sonnet-5"), "Sonnet 5")
        XCTAssertEqual(ModelNaming.displayName(for: "claude-3-5-sonnet"), "Sonnet 3.5")
        XCTAssertEqual(ModelNaming.displayName(for: "claude-fable-5"), "Fable 5")
        // Nothing recognisable: echo the ID whole rather than truncating it
        // to its first word — unpriced models are named in a footnote.
        XCTAssertEqual(ModelNaming.displayName(for: "mystery"), "Mystery")
        XCTAssertEqual(
            ModelNaming.displayName(for: "totally-future-model"), "totally-future-model")
    }

    func testMergeOverridesByModelID() {
        let base = PriceTable(models: [
            "a": ModelPrice(inputPerMillion: 1, outputPerMillion: 2),
            "b": ModelPrice(inputPerMillion: 3, outputPerMillion: 4),
        ])
        let remote = PriceTable(models: [
            "b": ModelPrice(inputPerMillion: 30, outputPerMillion: 40),
            "c": ModelPrice(inputPerMillion: 5, outputPerMillion: 6),
        ])
        let merged = base.merging(remote)
        XCTAssertEqual(merged.price(forModel: "a")?.inputPerMillion, 1)
        XCTAssertEqual(merged.price(forModel: "b")?.inputPerMillion, 30)
        XCTAssertEqual(merged.price(forModel: "c")?.inputPerMillion, 5)
    }

    func testLoadFromJSON() throws {
        let json = """
        {"version": 2, "updated_at": "2026-08-01", "models": {
            "claude-x": {"input": 1.5, "output": 7.5, "cache_read": 0.15}
        }}
        """
        let table = try PriceTable.load(from: Data(json.utf8))
        XCTAssertEqual(table.version, 2)
        XCTAssertEqual(table.price(forModel: "claude-x")?.cacheReadPerMillion, 0.15)
    }
}
