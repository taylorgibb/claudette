import Foundation

/// Per-model rates in USD per million tokens. Cache dimensions default to the
/// standard multipliers when the table omits them: write 1.25× input at 5m
/// TTL, 2× input at 1h TTL, read 0.1× input.
///
/// Every property is a *rate*, unlike the same-named counts on `TokenTally` —
/// hence the `PerMillion` suffix on all of them.
public struct ModelPrice: Codable, Sendable, Equatable {
    public var inputPerMillion: Double
    public var outputPerMillion: Double
    public var cacheReadPerMillion: Double
    public var cacheWrite5mPerMillion: Double
    public var cacheWrite1hPerMillion: Double

    private enum CodingKeys: String, CodingKey {
        case inputPerMillion = "input"
        case outputPerMillion = "output"
        case cacheReadPerMillion = "cache_read"
        case cacheWrite5mPerMillion = "cache_write_5m"
        case cacheWrite1hPerMillion = "cache_write_1h"
    }

    public init(
        inputPerMillion: Double,
        outputPerMillion: Double,
        cacheReadPerMillion: Double? = nil,
        cacheWrite5mPerMillion: Double? = nil,
        cacheWrite1hPerMillion: Double? = nil
    ) {
        self.inputPerMillion = inputPerMillion
        self.outputPerMillion = outputPerMillion
        self.cacheReadPerMillion = cacheReadPerMillion ?? inputPerMillion * 0.1
        self.cacheWrite5mPerMillion = cacheWrite5mPerMillion ?? inputPerMillion * 1.25
        self.cacheWrite1hPerMillion = cacheWrite1hPerMillion ?? inputPerMillion * 2.0
    }

    // The defaults are applied at decode time rather than through `effective*`
    // accessors, so a `ModelPrice` in hand always has all five rates.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            inputPerMillion: try container.decode(Double.self, forKey: .inputPerMillion),
            outputPerMillion: try container.decode(Double.self, forKey: .outputPerMillion),
            cacheReadPerMillion: try container.decodeIfPresent(
                Double.self, forKey: .cacheReadPerMillion),
            cacheWrite5mPerMillion: try container.decodeIfPresent(
                Double.self, forKey: .cacheWrite5mPerMillion),
            cacheWrite1hPerMillion: try container.decodeIfPresent(
                Double.self, forKey: .cacheWrite1hPerMillion))
    }
}

public struct PriceTable: Sendable, Equatable {
    public private(set) var models: [ModelID: ModelPrice]
    public let version: Int
    public let updatedAt: String?

    struct FileFormat: Codable {
        var version: Int
        var updatedAt: String?
        var models: [ModelID: ModelPrice]

        enum CodingKeys: String, CodingKey {
            case version
            case updatedAt = "updated_at"
            case models
        }
    }

    public init(models: [ModelID: ModelPrice], version: Int = 1, updatedAt: String? = nil) {
        self.models = Dictionary(uniqueKeysWithValues: models.map { ($0.key.lowercased(), $0.value) })
        self.version = version
        self.updatedAt = updatedAt
    }

    public static func load(from data: Data) throws -> PriceTable {
        let file = try JSONDecoder().decode(FileFormat.self, from: data)
        return PriceTable(models: file.models, version: file.version, updatedAt: file.updatedAt)
    }

    /// Ships in the app bundle; the floor that remote refreshes override.
    public static func bundled() -> PriceTable {
        guard
            let url = Bundle.module.url(forResource: "prices", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let table = try? load(from: data)
        else {
            return PriceTable(models: [:])
        }
        return table
    }

    /// Remote overrides by model ID; bundled entries survive unless overridden.
    public func merging(_ override: PriceTable) -> PriceTable {
        var merged = models
        for (key, value) in override.models {
            merged[key] = value
        }
        return PriceTable(
            models: merged,
            version: max(version, override.version),
            updatedAt: override.updatedAt ?? updatedAt)
    }

    /// Exact match first, then prefix matching for dated variants:
    /// `claude-sonnet-4-6-20260514` matches `claude-sonnet-4-6`. The suffix
    /// after a prefix match must look like a date/`latest`/revision so
    /// `claude-opus-4-5` never silently picks up `claude-opus-4` pricing.
    public func price(forModel modelID: ModelID) -> ModelPrice? {
        let id = ModelNaming.canonical(modelID)
        if let exact = models[id] {
            return exact
        }
        var best: (key: ModelID, price: ModelPrice)?
        for (key, price) in models {
            guard id.hasPrefix(key), id.count > key.count else { continue }
            guard Self.isVariantSuffix(String(id.dropFirst(key.count))) else { continue }
            if best == nil || key.count > best!.key.count {
                best = (key, price)
            }
        }
        return best?.price
    }

    static func isVariantSuffix(_ suffix: String) -> Bool {
        guard suffix.hasPrefix("-") else { return false }
        let tail = String(suffix.dropFirst())
        if tail == "latest" { return true }
        // Date stamp: 20250514 etc.
        if tail.count == 8, tail.allSatisfy(\.isNumber), tail.hasPrefix("20") { return true }
        // Bedrock-style revision: v2:0, v1
        if tail.hasPrefix("v"), tail.dropFirst().first?.isNumber == true { return true }
        return false
    }

    /// Dollar cost of a tally, or nil for a model with no price. Never
    /// silently price an unknown model at zero.
    public func dollars(for tally: TokenTally, model: ModelID) -> Double? {
        guard let price = price(forModel: model) else { return nil }
        let million = 1_000_000.0
        return Double(tally.input) / million * price.inputPerMillion
            + Double(tally.output) / million * price.outputPerMillion
            + Double(tally.cacheWrite5m) / million * price.cacheWrite5mPerMillion
            + Double(tally.cacheWrite1h) / million * price.cacheWrite1hPerMillion
            + Double(tally.cacheRead) / million * price.cacheReadPerMillion
    }
}

/// Reading model identifiers. Both halves — matching a price and naming a row
/// in the UI — parse the same ID shapes, so they live together.
public enum ModelNaming {
    /// Lowercased, provider prefix stripped: `anthropic/Claude-Opus-5` →
    /// `claude-opus-5`.
    public static func canonical(_ id: ModelID) -> ModelID {
        let lowered = id.lowercased()
        guard let slash = lowered.lastIndex(of: "/") else { return lowered }
        return String(lowered[lowered.index(after: slash)...])
    }

    /// Short display name: `claude-opus-4-5-20260114` → `Opus 4.5`. Falls
    /// back to the raw ID rather than inventing a name.
    public static func displayName(for id: ModelID) -> String {
        var parts = canonical(id).split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) {
            parts.removeLast()
        }
        guard !parts.isEmpty else { return id }
        var family = parts.removeFirst()
        // "3-5-sonnet" style: family digits before the name.
        if family.allSatisfy(\.isNumber),
           let nameIndex = parts.firstIndex(where: { !$0.allSatisfy(\.isNumber) }) {
            let version = ([family] + parts[..<nameIndex]).joined(separator: ".")
            return "\(parts[nameIndex].capitalized) \(version)"
        }
        // Anything left that isn't a version number means this ID is not
        // `claude-<family>-<version>` at all. Echo it whole rather than
        // truncating it to its first word — an unpriced model is named in the
        // footnote, and a half-name there is worse than a long one.
        guard parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return id }
        let version = parts.joined(separator: ".")
        family = family.capitalized
        return version.isEmpty ? family : "\(family) \(version)"
    }
}

/// Keeps the price table fresh: bundled floor, remote overrides, weekly check.
public actor PriceTableLoader {
    private let remoteURL: URL?
    private let cacheDirectory: URL?
    private let transport: any HTTPTransport
    private var loadedTable: PriceTable?

    public init(
        remoteURL: URL? = Endpoints.priceTable,
        cacheDirectory: URL?,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.remoteURL = remoteURL
        self.cacheDirectory = cacheDirectory
        self.transport = transport
    }

    /// Deferred for the same reason as `CostEngine`'s cache: an actor's `init`
    /// runs on the caller, and this one reads the bundle and the disk cache.
    public func current() -> PriceTable {
        if let loadedTable { return loadedTable }
        var table = PriceTable.bundled()
        if let dir = cacheDirectory,
           let data = try? Data(contentsOf: dir.appendingPathComponent("prices-remote.json")),
           let cached = try? PriceTable.load(from: data) {
            table = table.merging(cached)
        }
        loadedTable = table
        return table
    }

    public func refreshIfStale(now: Date = Date()) async {
        guard let remoteURL, let cacheDirectory else { return }
        let stampURL = cacheDirectory.appendingPathComponent("prices-last-check")
        if let stampData = try? Data(contentsOf: stampURL),
           let stamp = TimeInterval(String(decoding: stampData, as: UTF8.self)),
           now.timeIntervalSince1970 - stamp < Intervals.priceTableCheck {
            return
        }
        try? FileManager.default.createDirectory(
            at: cacheDirectory, withIntermediateDirectories: true)

        // The stamp is written whether or not the fetch works. Stamping only
        // on success makes an offline machine re-attempt on every cost
        // refresh forever; backdating a failure means it retries in hours
        // rather than sitting out the full week.
        func stamp(nextCheckIn delay: TimeInterval) {
            let value = now.timeIntervalSince1970 - (Intervals.priceTableCheck - delay)
            try? Data(String(value).utf8).write(to: stampURL, options: .atomic)
        }

        guard let reply = try? await transport.get(remoteURL, headers: [:]),
              reply.status == 200,
              let remote = try? PriceTable.load(from: reply.data)
        else {
            stamp(nextCheckIn: Intervals.priceTableRetry)
            return
        }
        stamp(nextCheckIn: Intervals.priceTableCheck)
        loadedTable = PriceTable.bundled().merging(remote)
        try? reply.data.write(
            to: cacheDirectory.appendingPathComponent("prices-remote.json"), options: .atomic)
    }
}
