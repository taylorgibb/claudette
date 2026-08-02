import Foundation

/// Persistent incremental scan state. Session JSONL files are append-only,
/// so per-file byte offsets let each rescan read only the tail. Totals are
/// global (day → model → tally) because resumed sessions copy history across
/// files, which makes cross-file dedup necessary; any file that shrinks,
/// changes inode, or moves backwards in time forces a full rebuild.
public struct CostCache: Codable, Sendable, Equatable {
    /// Bumped whenever the shape changes; a mismatched file is discarded,
    /// which costs one full rescan and nothing else.
    public static let currentVersion = 1

    /// Where a file was last read up to, and the identity it had at the time.
    public struct FileCursor: Codable, Sendable, Equatable {
        public var inode: UInt64
        public var size: UInt64
        public var modifiedAt: Double
        public var offset: UInt64

        public init(inode: UInt64, size: UInt64, modifiedAt: Double, offset: UInt64) {
            self.inode = inode
            self.size = size
            self.modifiedAt = modifiedAt
            self.offset = offset
        }

        /// True when this file can no longer be resumed from `offset` and the
        /// whole cache has to be rebuilt — totals are global, so one file's
        /// contribution can't be subtracted.
        public func isInvalidated(by fresh: FileCursor) -> Bool {
            fresh.size < offset
                || (inode != 0 && fresh.inode != inode)
                // Rewritten in place: same inode, but time moved backwards, so
                // the bytes at `offset` are no longer the ones we consumed.
                || fresh.modifiedAt < modifiedAt
        }
    }

    public var version: Int = currentVersion
    public var files: [String: FileCursor] = [:]
    /// Bucketed by day so `prune` drops hashes together with the tallies they
    /// belong to. A flat set would grow for the lifetime of the install.
    public var seenHashes: [DayKey: Set<UInt64>] = [:]
    public var days: [DayKey: [ModelID: TokenTally]] = [:]

    public init() {}

    /// Records a turn unless an identical one was already counted. Returns
    /// false when it was a duplicate, so callers can't accidentally add twice.
    @discardableResult
    public mutating func addIfUnseen(_ turn: LoggedTurn) -> Bool {
        if let hash = turn.dedupHash {
            guard seenHashes[turn.day, default: []].insert(hash).inserted else { return false }
        }
        days[turn.day, default: [:]][turn.model, default: TokenTally()] += turn.tally
        return true
    }

    /// Drops day buckets, and their dedup hashes, older than the horizon.
    public mutating func prune(olderThanDays retention: Int, now: Date = Date()) {
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -retention, to: now)
        else { return }
        let cutoff = DayKey(cutoffDate)
        days = days.filter { $0.key >= cutoff }
        seenHashes = seenHashes.filter { $0.key >= cutoff }
    }

    public static func load(from url: URL) -> CostCache? {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(CostCache.self, from: data),
              cache.version == currentVersion
        else { return nil }
        return cache
    }

    public func save(to url: URL) {
        guard let data = try? ISO8601.encoder().encode(self) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Codable

    // `seenHashes` is held decoded in memory — it is consulted once per log
    // line — and packed to base64 only when persisted. A JSON array of
    // `UInt64` would be roughly 3× the bytes.
    private enum CodingKeys: String, CodingKey {
        case version, files, days
        case seenHashBlobs = "seenHashes"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        files = try container.decodeIfPresent([String: FileCursor].self, forKey: .files) ?? [:]
        days = try container.decodeIfPresent([DayKey: [ModelID: TokenTally]].self, forKey: .days) ?? [:]
        let blobs = try container.decodeIfPresent([DayKey: String].self, forKey: .seenHashBlobs) ?? [:]
        seenHashes = blobs.compactMapValues(Self.unpack)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(files, forKey: .files)
        try container.encode(days, forKey: .days)
        try container.encode(seenHashes.mapValues(Self.pack), forKey: .seenHashBlobs)
    }

    private static func pack(_ hashes: Set<UInt64>) -> String {
        var data = Data(capacity: hashes.count * 8)
        for hash in hashes {
            withUnsafeBytes(of: hash.littleEndian) { data.append(contentsOf: $0) }
        }
        return data.base64EncodedString()
    }

    private static func unpack(_ blob: String) -> Set<UInt64>? {
        guard let data = Data(base64Encoded: blob), !data.isEmpty else { return nil }
        var result = Set<UInt64>(minimumCapacity: data.count / 8)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<(raw.count / 8) {
                let value = raw.loadUnaligned(fromByteOffset: i * 8, as: UInt64.self)
                result.insert(UInt64(littleEndian: value))
            }
        }
        return result
    }
}
