import AppKit
import SwiftUI
import ClaudetteCore

/// Drives one island: what mode it is in, what data it holds, and when to go
/// and get more. The rendering decisions live in `UsagePresenter` and
/// `CostPresenter`; the pixel arithmetic lives in `IslandLayout`.
@MainActor
final class IslandViewModel: ObservableObject {
    enum Page: Equatable {
        case usage
        case cost
    }

    @Published private(set) var mode: IslandMode = .collapsed
    @Published var page: Page = .usage
    @Published var usage = UsageState()
    @Published var costReport: CostReport?
    @Published var costProgress: CostProgress?
    /// Re-published on the ticker so countdowns and "synced Nm ago" advance.
    @Published private(set) var displayTime = Date()
    @Published var geometry: NotchGeometry
    @Published var availableUpdateVersion: String?
    /// Reported by the panel once laid out, so the silhouette tracks what the
    /// content actually needs.
    @Published var measuredPanelHeight: CGFloat?

    let settings: AppSettings
    let analytics: any AnalyticsReporting
    private let usageService: UsageService
    private let costEngine: CostEngine
    private let priceLoader: PriceTableLoader
    var onModeChange: (@MainActor (IslandMode) -> Void)?
    var onOpenSettings: (@MainActor () -> Void)?

    /// Every long-lived task this object owns. `stop()` can only be honest if
    /// it can reach all of them, so they all go in here.
    private var runningTasks: [Task<Void, Never>] = []
    private var enterTask: Task<Void, Never>?
    private var exitTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?
    private var costRefreshInFlight = false

    init(
        settings: AppSettings,
        geometry: NotchGeometry,
        usageService: UsageService,
        costEngine: CostEngine,
        priceLoader: PriceTableLoader,
        analytics: any AnalyticsReporting
    ) {
        self.settings = settings
        self.geometry = geometry
        self.usageService = usageService
        self.costEngine = costEngine
        self.priceLoader = priceLoader
        self.analytics = analytics
    }

    // MARK: Derived state

    var layout: IslandLayout {
        IslandLayout(geometry: geometry, measuredPanelHeight: measuredPanelHeight)
    }

    var silhouetteSize: CGSize { layout.size(for: mode) }

    var usagePresenter: UsagePresenter {
        UsagePresenter(state: usage, now: displayTime)
    }

    var costPresenter: CostPresenter? {
        costReport.map {
            CostPresenter(
                report: $0,
                plan: settings.billingTier(detected: usage.planTier))
        }
    }

    // MARK: Lifecycle

    func start() {
        restartTicker()
        runningTasks.append(Task { [weak self] in
            guard let service = self?.usageService else { return }
            for await state in await service.stateUpdates() {
                guard let self else { return }
                self.usage = state
                self.heartbeatIfNeeded(state)
            }
        })
        runningTasks.append(Task { [weak self] in
            guard let engine = self?.costEngine else { return }
            for await progress in await engine.progressUpdates() {
                guard let self else { return }
                let isRunning = progress.completedFiles < progress.totalFiles
                self.costProgress = isRunning ? progress : nil
            }
        })
        runningTasks.append(Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshCost()
                try? await Task.sleep(for: .seconds(Intervals.costRescan))
            }
        })
    }

    func stop() {
        runningTasks.forEach { $0.cancel() }
        runningTasks.removeAll()
        tickerTask?.cancel()
        enterTask?.cancel()
        exitTask?.cancel()
    }

    /// Collapsed, nothing on screen reads `displayTime` more than once every
    /// half minute. Re-armed on every mode change rather than sampling the
    /// interval once per iteration — otherwise expanding mid-sleep leaves the
    /// countdowns frozen for up to 30 seconds, which is exactly the moment
    /// they are being looked at.
    private func restartTicker() {
        tickerTask?.cancel()
        let interval: Duration = mode == .collapsed ? .seconds(30) : .seconds(1)
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.displayTime = Date()
            }
        }
    }

    // MARK: Hover state machine

    /// Debounced in both directions: 60ms of hover before expanding, so
    /// crossing the notch on the way somewhere else does nothing; 400ms of
    /// grace before collapsing, so clipping a corner doesn't dismiss it.
    func hoverChanged(isInside: Bool) {
        if isInside {
            exitTask?.cancel()
            exitTask = nil
            guard mode == .collapsed, enterTask == nil else { return }
            enterTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled, let self else { return }
                self.enterTask = nil
                // Never expand into the middle of a drag.
                guard self.mode == .collapsed, NSEvent.pressedMouseButtons == 0 else { return }
                self.expand()
            }
        } else {
            enterTask?.cancel()
            enterTask = nil
            guard mode != .collapsed, exitTask == nil else { return }
            exitTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, let self else { return }
                self.exitTask = nil
                self.collapse()
            }
        }
    }

    func expand() {
        guard mode != .panel else { return }
        analytics.capture(.panelOpened)
        setMode(.panel)
        refreshCostIfStale()
    }

    func collapse() {
        guard mode != .collapsed else { return }
        setMode(.collapsed)
        page = .usage
    }

    private func setMode(_ newMode: IslandMode) {
        guard mode != newMode else { return }
        mode = newMode
        restartTicker()
        onModeChange?(newMode)
    }

    /// One entry point for both directions, so the analytics can't be
    /// attached to only one of them.
    func showPage(_ newPage: Page) {
        guard page != newPage else { return }
        page = newPage
        guard newPage == .cost else { return }
        analytics.capture(.costPageViewed(
            scanDurationBucket: AnalyticsBuckets.scanDurationBucket(
                ms: costReport?.scanDurationMs ?? 0),
            modelCount: costReport?.models.count ?? 0))
    }

    func refreshUsage() {
        Task { await usageService.refreshNow() }
    }

    func openSettings() {
        onOpenSettings?()
    }

    // MARK: Data

    /// A scan walks every Claude log root, and hover is cheap to trigger.
    /// Compares against the wall clock, not `displayTime`, which is up to 30
    /// seconds stale in exactly the state this is called from.
    func refreshCostIfStale() {
        guard let report = costReport else { return refreshCost() }
        guard Date().timeIntervalSince(report.generatedAt) > Intervals.costFreshness else { return }
        refreshCost()
    }

    func refreshCost() {
        guard !costRefreshInFlight else { return }
        costRefreshInFlight = true
        let roots = ClaudeLogRoots(extraRoots: settings.extraLogRoots)
        Task { [weak self] in
            guard let self else { return }
            await self.priceLoader.refreshIfStale()
            let table = await self.priceLoader.current()
            await self.costEngine.setLogRoots(roots)
            self.costReport = await self.costEngine.refresh(prices: table)
            self.costRefreshInFlight = false
        }
    }

    private func heartbeatIfNeeded(_ state: UsageState) {
        guard case .ok = state.phase else { return }
        let today = DayKey(Date()).rawValue
        guard settings.lastHeartbeatDay != today else { return }
        settings.lastHeartbeatDay = today
        let tier = PlanTier.resolve(state.planTier)?.id
            ?? (state.planTier == nil ? "unknown" : "other")
        analytics.capture(.dailyHeartbeat(
            appVersion: AppInfo.version,
            daysSinceInstallBucket: AnalyticsBuckets.daysSinceInstallBucket(settings.daysSinceInstall),
            planTier: tier))
    }
}

enum AppInfo {
    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }

    static var arch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}
