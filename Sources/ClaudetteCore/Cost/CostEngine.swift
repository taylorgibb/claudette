import Foundation

public struct CostProgress: Sendable, Equatable {
    public let completedFiles: Int
    public let totalFiles: Int

    public init(completedFiles: Int, totalFiles: Int) {
        self.completedFiles = completedFiles
        self.totalFiles = totalFiles
    }

    public var completedFraction: Double {
        totalFiles > 0 ? Double(completedFiles) / Double(totalFiles) : 0
    }
}

public actor CostEngine {
    private let cacheURL: URL?
    private let analytics: any AnalyticsReporting
    private var logRoots: any LogRootResolving
    private var loadedCache: CostCache?
    private var progressContinuations: [UUID: AsyncStream<CostProgress>.Continuation] = [:]

    public init(
        cacheURL: URL?,
        logRoots: any LogRootResolving = ClaudeLogRoots(),
        analytics: any AnalyticsReporting = DisabledAnalytics()
    ) {
        self.cacheURL = cacheURL
        self.logRoots = logRoots
        self.analytics = analytics
    }

    private var cache: CostCache {
        get {
            if let loadedCache { return loadedCache }
            let loaded = cacheURL.flatMap(CostCache.load(from:)) ?? CostCache()
            loadedCache = loaded
            return loaded
        }
        set { loadedCache = newValue }
    }

    public func progressUpdates() -> AsyncStream<CostProgress> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: CostProgress.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        progressContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeProgressContinuation(id) }
        }
        return stream
    }

    private func removeProgressContinuation(_ id: UUID) {
        progressContinuations[id] = nil
    }

    private func publishProgress(_ progress: CostProgress) {
        for continuation in progressContinuations.values {
            continuation.yield(progress)
        }
    }

    public func setLogRoots(_ roots: any LogRootResolving) {
        logRoots = roots
    }

    public func refresh(prices: PriceTable, now: Date = Date()) async -> CostReport {
        let started = DispatchTime.now()
        let files = LogScanner.sessionFiles(in: logRoots.roots())
        let fresh = currentCursors(for: files)

        if fresh.contains(where: { path, cursor in
            cache.files[path]?.isInvalidated(by: cursor.cursor) ?? false
        }) {
            cache = CostCache()
        }

        var toScan: [(url: URL, from: UInt64, cursor: CostCache.FileCursor)] = []
        for (path, entry) in fresh {
            let offset = cache.files[path]?.offset ?? 0
            if entry.cursor.size > offset {
                toScan.append((entry.url, offset, entry.cursor))
            } else if cache.files[path] == nil {
                var cursor = entry.cursor
                cursor.offset = entry.cursor.size
                cache.files[path] = cursor
            }
        }
        toScan.sort { $0.url.path < $1.url.path }

        publishProgress(CostProgress(completedFiles: 0, totalFiles: toScan.count))
        for (index, job) in toScan.enumerated() {
            do {
                let result = try LogScanner.scanFile(at: job.url, from: job.from)
                for turn in result.turns {
                    cache.addIfUnseen(turn)
                }
                var cursor = job.cursor
                cursor.offset = result.consumedOffset
                cache.files[job.url.path] = cursor
            } catch {
                analytics.capture(.costScanFailed(failureKind: "read_error"))
            }
            publishProgress(CostProgress(completedFiles: index + 1, totalFiles: toScan.count))
            await Task.yield()
        }

        cache.prune(olderThanDays: Intervals.costRetentionDays, now: now)
        if let cacheURL {
            cache.save(to: cacheURL)
        }

        let elapsedMs = Int(
            Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000)
        let report = CostReport.build(
            dailyTallies: cache.days,
            prices: prices,
            now: now,
            scanDurationMs: elapsedMs,
            filesDiscovered: files.count)
        for model in report.unpricedModels {
            analytics.capture(.unpricedModelSeen(modelID: model))
        }
        return report
    }

    private func currentCursors(
        for files: [URL]
    ) -> [String: (cursor: CostCache.FileCursor, url: URL)] {
        let fm = FileManager.default
        var cursors: [String: (cursor: CostCache.FileCursor, url: URL)] = [:]
        for url in files {
            guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { continue }
            let cursor = CostCache.FileCursor(
                inode: (attrs[.systemFileNumber] as? UInt64) ?? 0,
                size: (attrs[.size] as? UInt64) ?? 0,
                modifiedAt: (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0,
                offset: 0)
            cursors[url.path] = (cursor, url)
        }
        return cursors
    }
}
