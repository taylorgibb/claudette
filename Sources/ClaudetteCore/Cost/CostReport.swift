import Foundation

/// The 30-day API-equivalent cost picture, entirely from local logs.
public struct CostReport: Sendable, Equatable {
    public struct Day: Sendable, Equatable, Identifiable {
        public let dayKey: String
        public let dollars: Double
        public var id: String { dayKey }

        public init(dayKey: String, dollars: Double) {
            self.dayKey = dayKey
            self.dollars = dollars
        }
    }

    public struct ModelLine: Sendable, Equatable, Identifiable {
        public let model: String
        public let tally: TokenTally
        /// nil = unknown model: tokens counted, excluded from the dollar figure.
        public let dollars: Double?
        public let share: Double
        public var id: String { model }

        public init(model: String, tally: TokenTally, dollars: Double?, share: Double) {
            self.model = model
            self.tally = tally
            self.dollars = dollars
            self.share = share
        }
    }

    public let windowDays: Int
    /// Oldest → newest, one entry per calendar day, zero-filled.
    public let days: [Day]
    public let totalDollars: Double
    /// Sorted by dollars descending, unknown models last.
    public let models: [ModelLine]
    public let unknownModels: [String]
    public let generatedAt: Date
    public let scanDurationMs: Int
    public let filesScanned: Int

    public init(
        windowDays: Int,
        days: [Day],
        totalDollars: Double,
        models: [ModelLine],
        unknownModels: [String],
        generatedAt: Date,
        scanDurationMs: Int,
        filesScanned: Int
    ) {
        self.windowDays = windowDays
        self.days = days
        self.totalDollars = totalDollars
        self.models = models
        self.unknownModels = unknownModels
        self.generatedAt = generatedAt
        self.scanDurationMs = scanDurationMs
        self.filesScanned = filesScanned
    }

    /// Builds the report from cached day/model tallies.
    public static func build(
        from days: [String: [String: TokenTally]],
        prices: PriceTable,
        windowDays: Int = 30,
        now: Date = Date(),
        scanDurationMs: Int = 0,
        filesScanned: Int = 0
    ) -> CostReport {
        let calendar = Calendar.current
        var dayKeys: [String] = []
        for back in stride(from: windowDays - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -back, to: now) else { continue }
            dayKeys.append(DayKey.from(date))
        }
        let window = Set(dayKeys)

        var perModel: [String: TokenTally] = [:]
        var perDayDollars: [String: Double] = [:]
        for (dayKey, modelTallies) in days where window.contains(dayKey) {
            for (model, tally) in modelTallies {
                perModel[model, default: TokenTally()] += tally
                if let dollars = prices.dollars(for: tally, model: model) {
                    perDayDollars[dayKey, default: 0] += dollars
                }
            }
        }

        var lines: [ModelLine] = []
        var unknown: [String] = []
        var total = 0.0
        for (model, tally) in perModel {
            let dollars = prices.dollars(for: tally, model: model)
            if let dollars {
                total += dollars
            } else {
                unknown.append(model)
            }
            lines.append(ModelLine(model: model, tally: tally, dollars: dollars, share: 0))
        }
        lines = lines.map { line in
            ModelLine(
                model: line.model,
                tally: line.tally,
                dollars: line.dollars,
                share: total > 0 ? (line.dollars ?? 0) / total : 0)
        }
        lines.sort { ($0.dollars ?? -1) > ($1.dollars ?? -1) }

        return CostReport(
            windowDays: windowDays,
            days: dayKeys.map { Day(dayKey: $0, dollars: perDayDollars[$0] ?? 0) },
            totalDollars: total,
            models: lines,
            unknownModels: unknown.sorted(),
            generatedAt: now,
            scanDurationMs: scanDurationMs,
            filesScanned: filesScanned)
    }
}

/// API-equivalent vs subscription comparison.
public struct CostComparison: Sendable, Equatable {
    /// API equivalent divided by subscription cost, e.g. 4.7.
    public let effectiveMultiple: Double?
    /// Day of month when accumulated API-equivalent spend crossed the
    /// subscription cost, nil if it never did in the window.
    public let breakEvenDayKey: String?
    public let monthlyPrice: Double

    public init(report: CostReport, monthlyPrice: Double) {
        self.monthlyPrice = monthlyPrice
        if monthlyPrice > 0 {
            effectiveMultiple = report.totalDollars / monthlyPrice
            var accumulated = 0.0
            var crossed: String?
            for day in report.days {
                accumulated += day.dollars
                if accumulated >= monthlyPrice {
                    crossed = day.dayKey
                    break
                }
            }
            breakEvenDayKey = crossed
        } else {
            effectiveMultiple = nil
            breakEvenDayKey = nil
        }
    }
}

/// Maps plan tier identifiers to display names and list prices (USD/month).
public enum PlanTier {
    public struct Info: Sendable, Equatable {
        public let id: String
        public let displayName: String
        public let monthlyUSD: Double
    }

    public static let known: [Info] = [
        Info(id: "pro", displayName: "Pro", monthlyUSD: 20),
        Info(id: "max_5x", displayName: "Max 5x", monthlyUSD: 100),
        Info(id: "max_20x", displayName: "Max 20x", monthlyUSD: 200),
        Info(id: "team", displayName: "Team", monthlyUSD: 30),
    ]

    /// Accepts `default_claude_max_5x`-style tier IDs from the usage response
    /// or `max` / `pro` subscription types from the credential store.
    public static func resolve(_ raw: String?) -> Info? {
        guard let raw = raw?.lowercased(), !raw.isEmpty else { return nil }
        if raw.contains("max_20x") || raw.contains("20x") {
            return known.first { $0.id == "max_20x" }
        }
        if raw.contains("max_5x") || raw.contains("5x") || raw.contains("max") {
            return known.first { $0.id == "max_5x" }
        }
        if raw.contains("team") {
            return known.first { $0.id == "team" }
        }
        if raw.contains("pro") {
            return known.first { $0.id == "pro" }
        }
        return nil
    }
}
