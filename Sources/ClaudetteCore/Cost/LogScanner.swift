import Foundation

/// One assistant turn's token usage, parsed from a session JSONL line.
public struct LoggedTurn: Sendable, Equatable {
    /// Stable across launches and files, so a turn copied into a resumed
    /// session is counted once. Nil when the line carried neither a message ID
    /// nor a request ID — such a turn is counted without dedup rather than
    /// being folded together with every other ID-less turn.
    public let dedupHash: UInt64?
    public let model: ModelID
    public let day: DayKey
    public let tally: TokenTally

    public init(dedupHash: UInt64?, model: ModelID, day: DayKey, tally: TokenTally) {
        self.dedupHash = dedupHash
        self.model = model
        self.day = day
        self.tally = tally
    }
}

/// Where Claude Code keeps its session logs. Injected into `CostEngine` so a
/// test can scan a fixture tree without also picking up the real ones.
public protocol LogRootResolving: Sendable {
    func roots() -> [URL]
}

/// The shipping policy: the documented Claude Code locations, plus whatever
/// extra directories the user configured.
public struct ClaudeLogRoots: LogRootResolving {
    private let environment: [String: String]
    private let home: URL
    private let extraRoots: [String]

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        extraRoots: [String] = []
    ) {
        self.environment = environment
        self.home = home
        self.extraRoots = extraRoots
    }

    public func roots() -> [URL] {
        LogScanner.existingDirectories(among: candidates())
    }

    private func candidates() -> [URL] {
        var candidates: [URL] = []

        if let configDir = environment["CLAUDE_CONFIG_DIR"] {
            for part in configDir.split(separator: ",") {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                candidates.append(URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
                    .appendingPathComponent("projects"))
            }
        }
        candidates.append(home.appendingPathComponent(".config/claude/projects"))
        candidates.append(home.appendingPathComponent(".claude/projects"))

        // Claude desktop app session containers: <base>/**/.claude/projects
        let appSupport = home.appendingPathComponent("Library/Application Support/Claude")
        for container in ["claude-code-sessions", "local-agent-mode-sessions"] {
            candidates.append(contentsOf: LogScanner.nestedProjectRoots(
                under: appSupport.appendingPathComponent(container)))
        }

        for extra in extraRoots {
            let trimmed = extra.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            candidates.append(URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath))
        }
        return candidates
    }
}

/// An explicit list, for tests and for anyone embedding the engine.
public struct FixedLogRoots: LogRootResolving {
    private let urls: [URL]

    public init(_ urls: [URL]) {
        self.urls = urls
    }

    public func roots() -> [URL] {
        LogScanner.existingDirectories(among: urls)
    }
}

/// Pure log-scanning machinery: file listing, line parsing, chunked
/// incremental reads. No state and no opinion about where logs live —
/// `LogRootResolving` owns that, `CostEngine` owns the cache.
public enum LogScanner {

    // MARK: - Directory walking

    /// Keeps the directories that exist, in order, deduplicated by resolved
    /// path so a symlinked root isn't scanned twice.
    static func existingDirectories(among candidates: [URL]) -> [URL] {
        var seen = Set<String>()
        var roots: [URL] = []
        let fm = FileManager.default
        for candidate in candidates {
            let resolved = candidate.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  seen.insert(resolved.path).inserted
            else { continue }
            roots.append(resolved)
        }
        return roots
    }

    /// Finds `**/.claude/projects` under a base directory, bounded depth.
    static func nestedProjectRoots(under base: URL, maxDepth: Int = 5) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        let baseDepth = base.pathComponents.count
        var found: [URL] = []
        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - baseDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if url.lastPathComponent == "projects",
               url.deletingLastPathComponent().lastPathComponent == ".claude" {
                found.append(url)
                enumerator.skipDescendants()
            }
        }
        return found
    }

    /// All `.jsonl` files below the given roots.
    public static func sessionFiles(in roots: [URL]) -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: []
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    // MARK: - Line parsing

    struct LogLine: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                struct CacheCreation: Decodable {
                    let ephemeral5m: Int64?
                    let ephemeral1h: Int64?

                    enum CodingKeys: String, CodingKey {
                        case ephemeral5m = "ephemeral_5m_input_tokens"
                        case ephemeral1h = "ephemeral_1h_input_tokens"
                    }
                }

                let inputTokens: Int64?
                let outputTokens: Int64?
                let cacheCreationInputTokens: Int64?
                let cacheReadInputTokens: Int64?
                let cacheCreation: CacheCreation?

                enum CodingKeys: String, CodingKey {
                    case inputTokens = "input_tokens"
                    case outputTokens = "output_tokens"
                    case cacheCreationInputTokens = "cache_creation_input_tokens"
                    case cacheReadInputTokens = "cache_read_input_tokens"
                    case cacheCreation = "cache_creation"
                }
            }

            let id: String?
            let model: String?
            let usage: Usage?
        }

        let type: String?
        let message: Message?
        let requestId: String?
        let timestamp: String?
    }

    /// Parses one JSONL line into usage, or nil for anything that isn't an
    /// assistant turn with usage attached. The decoder is a parameter rather
    /// than a shared static: `JSONDecoder` is not `Sendable` on this
    /// deployment target, and this is a `public static` entry point.
    public static func parseLine(_ line: Data, decoder: JSONDecoder = JSONDecoder()) -> LoggedTurn? {
        guard !line.isEmpty else { return nil }
        guard let parsed = try? decoder.decode(LogLine.self, from: line) else { return nil }
        guard parsed.type == "assistant",
              let message = parsed.message,
              let usage = message.usage,
              let model = message.model,
              !model.isEmpty,
              model != "<synthetic>"
        else { return nil }

        var tally = TokenTally()
        tally.input = usage.inputTokens ?? 0
        tally.output = usage.outputTokens ?? 0
        tally.cacheRead = usage.cacheReadInputTokens ?? 0
        if let breakdown = usage.cacheCreation,
           breakdown.ephemeral5m != nil || breakdown.ephemeral1h != nil {
            tally.cacheWrite5m = breakdown.ephemeral5m ?? 0
            tally.cacheWrite1h = breakdown.ephemeral1h ?? 0
        } else {
            // No TTL breakdown: assume 5m.
            tally.cacheWrite5m = usage.cacheCreationInputTokens ?? 0
        }
        guard !tally.isEmpty else { return nil }

        let date = parsed.timestamp.flatMap(ISO8601.parse) ?? Date()
        return LoggedTurn(
            dedupHash: dedupHash(messageID: message.id, requestID: parsed.requestId),
            model: model.lowercased(),
            day: DayKey(date),
            tally: tally)
    }

    /// Streaming chunks repeat usage for the same message; without this key
    /// the totals overcount badly. Nil when the line has no identity at all —
    /// hashing the empty pair would collapse every such turn into one and
    /// silently drop the rest.
    static func dedupHash(messageID: String?, requestID: String?) -> UInt64? {
        let message = messageID ?? ""
        let request = requestID ?? ""
        guard !message.isEmpty || !request.isEmpty else { return nil }
        return Hash.fnv1a64("\(message):\(request)")
    }

    // MARK: - File scanning

    public struct FileScanResult: Sendable {
        public var consumedOffset: UInt64
        public var turns: [LoggedTurn]

        public init(consumedOffset: UInt64, turns: [LoggedTurn]) {
            self.consumedOffset = consumedOffset
            self.turns = turns
        }
    }

    /// Reads a session file from `offset`, in 1 MB chunks, splitting lines
    /// manually. A truncated final line (no trailing newline) is left
    /// unconsumed so the next incremental pass picks it up once complete.
    public static func scanFile(at url: URL, from offset: UInt64) throws -> FileScanResult {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)

        let decoder = JSONDecoder()
        let chunkSize = 1 << 20
        var carry = Data()
        var consumed = offset
        var turns: [LoggedTurn] = []
        let newline = UInt8(ascii: "\n")

        while true {
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            carry.append(chunk)

            var searchStart = carry.startIndex
            while let newlineIndex = carry[searchStart...].firstIndex(of: newline) {
                let lineData = carry.subdata(in: searchStart..<newlineIndex)
                consumed += UInt64(newlineIndex - searchStart) + 1
                if let parsed = parseLine(lineData, decoder: decoder) {
                    turns.append(parsed)
                }
                searchStart = carry.index(after: newlineIndex)
            }
            carry.removeSubrange(carry.startIndex..<searchStart)
        }

        return FileScanResult(consumedOffset: consumed, turns: turns)
    }
}
