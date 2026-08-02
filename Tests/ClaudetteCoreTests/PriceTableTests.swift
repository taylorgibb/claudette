import XCTest
@testable import ClaudetteCore

final class PriceTableTests: XCTestCase {
    func testBundledTableLoads() {
        let table = PriceTable.bundled()
        XCTAssertFalse(table.models.isEmpty)
        XCTAssertNotNil(table.price(forModel: "claude-opus-4-5"))
    }

    func testExactMatch() {
        let table = PriceTable(models: ["claude-opus-4-5": ModelPrice(input: 5, output: 25)])
        XCTAssertEqual(table.price(forModel: "claude-opus-4-5")?.input, 5)
    }

    func testDatedVariantPrefixMatch() {
        let table = PriceTable(models: ["claude-sonnet-4-6": ModelPrice(input: 3, output: 15)])
        XCTAssertEqual(table.price(forModel: "claude-sonnet-4-6-20260514")?.input, 3)
        XCTAssertEqual(table.price(forModel: "claude-sonnet-4-6-latest")?.input, 3)
    }

    func testProviderPrefixIsStripped() {
        let table = PriceTable(models: ["claude-opus-4-5": ModelPrice(input: 5, output: 25)])
        XCTAssertEqual(table.price(forModel: "anthropic/claude-opus-4-5-20260114")?.input, 5)
    }

    func testDifferentModelNeverBleedsThroughPrefix() {
        // claude-opus-4-5 must NOT inherit claude-opus-4 pricing.
        let table = PriceTable(models: ["claude-opus-4": ModelPrice(input: 15, output: 75)])
        XCTAssertNil(table.price(forModel: "claude-opus-4-5"))
        XCTAssertNil(table.price(forModel: "claude-opus-4-5-20260114"))
        // But a real dated variant of opus-4 still matches.
        XCTAssertEqual(table.price(forModel: "claude-opus-4-20250514")?.input, 15)
    }

    func testUnknownModelReturnsNilNotZero() {
        let table = PriceTable.bundled()
        XCTAssertNil(table.price(forModel: "future-model-x"))
        XCTAssertNil(table.dollars(for: TokenTally(input: 1000), model: "future-model-x"))
    }

    func testDollarMathWithDerivedCacheRates() {
        let table = PriceTable(models: ["m": ModelPrice(input: 10, output: 20)])
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
        let price = ModelPrice(input: 10, output: 20, cacheRead: 2, cacheWrite5m: 11, cacheWrite1h: 30)
        XCTAssertEqual(price.effectiveCacheRead, 2)
        XCTAssertEqual(price.effectiveCacheWrite5m, 11)
        XCTAssertEqual(price.effectiveCacheWrite1h, 30)
    }

    func testMergeOverridesByModelID() {
        let base = PriceTable(models: [
            "a": ModelPrice(input: 1, output: 2),
            "b": ModelPrice(input: 3, output: 4),
        ])
        let remote = PriceTable(models: [
            "b": ModelPrice(input: 30, output: 40),
            "c": ModelPrice(input: 5, output: 6),
        ])
        let merged = base.merging(remote)
        XCTAssertEqual(merged.price(forModel: "a")?.input, 1)
        XCTAssertEqual(merged.price(forModel: "b")?.input, 30)
        XCTAssertEqual(merged.price(forModel: "c")?.input, 5)
    }

    func testLoadFromJSON() throws {
        let json = """
        {"version": 2, "updated_at": "2026-08-01", "models": {
            "claude-x": {"input": 1.5, "output": 7.5, "cache_read": 0.15}
        }}
        """
        let table = try PriceTable.load(from: Data(json.utf8))
        XCTAssertEqual(table.version, 2)
        XCTAssertEqual(table.price(forModel: "claude-x")?.cacheRead, 0.15)
    }
}
