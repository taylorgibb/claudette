import AppKit
import SwiftUI
import ClaudetteCore

@MainActor
final class IslandViewModel: ObservableObject {
    enum Mode: String, Equatable {
        case collapsed
        case peek
        case panel
    }

    enum Page: Equatable {
        case usage
        case cost
    }

    @Published private(set) var mode: Mode = .collapsed
    @Published var page: Page = .usage
    @Published var usage = UsageState()
    @Published var costReport: CostReport?
    @Published var costProgress: CostProgress?
    @Published var now = Date()
    @Published var geometry: NotchGeometry
    @Published var showConsent = false
    @Published var updateAvailable: String?

    let settings: AppSettings
    let analytics: any Analytics
    private let usageService: UsageService
    private let costEngine: CostEngine
    private let priceLoader: PriceTableLoader
    var onModeChange: (@MainActor (Mode) -> Void)?
    var onOpenSettings: (@MainActor () -> Void)?

    private var enterTask: Task<Void, Never>?
    private var exitTask: Task<Void, Never>?
    private var tickerTask: Task<Void, Never>?
    private var costTimerTask: Task<Void, Never>?
    private var costRefreshInFlight = false

    init(
        settings: AppSettings,
        geometry: NotchGeometry,
        usageService: UsageService,
        costEngine: CostEngine,
        priceLoader: PriceTableLoader,
        analytics: any Analytics
    ) {
        self.settings = settings
        self.geometry = geometry
        self.usageService = usageService
        self.costEngine = costEngine
        self.priceLoader = priceLoader
        self.analytics = analytics
    }

    // MARK: Geometry

    var collapsedSize: CGSize {
        CGSize(
            width: geometry.notchWidth + Layout.pillWidth * 2,
            height: geometry.notchHeight + Layout.collapsedDrop)
    }

    func size(for mode: Mode) -> CGSize {
        switch mode {
        case .collapsed:
            return collapsedSize
        case .peek:
            return CGSize(
                width: max(collapsedSize.width, Layout.peekWidth),
                height: geometry.notchHeight + Layout.peekDrop)
        case .panel:
            return CGSize(
                width: max(collapsedSize.width, Layout.panelWidth),
                height: geometry.notchHeight + Layout.panelDrop)
        }
    }

    var silhouetteSize: CGSize { size(for: mode) }

    // MARK: Lifecycle

    func start() {
        tickerTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval: UInt64 = (self?.mode == .collapsed) ? 30_000_000_000 : 1_000_000_000
                try? await Task.sleep(nanoseconds: interval)
                guard let self else { return }
                self.now = Date()
            }
        }
        Task { [weak self] in
            guard let service = self?.usageService else { return }
            for await state in await service.states() {
                guard let self else { return }
                self.usage = state
                self.heartbeatIfNeeded(state)
            }
        }
        Task { [weak self] in
            guard let engine = self?.costEngine else { return }
            for await progress in await engine.progress() {
                guard let self else { return }
                self.costProgress = progress.filesDone < progress.filesTotal ? progress : nil
            }
        }
        // Rescan on a 15-minute timer; also kicked on panel open.
        costTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshCost()
                try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
            }
        }
    }

    func stop() {
        tickerTask?.cancel()
        costTimerTask?.cancel()
        enterTask?.cancel()
        exitTask?.cancel()
    }

    // MARK: Hover / click state machine

    /// Debounce: 60ms in, 180ms out (400ms grace from the panel).
    func hoverRaw(_ inside: Bool) {
        if inside {
            exitTask?.cancel()
            exitTask = nil
            guard mode == .collapsed, enterTask == nil else { return }
            enterTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000)
                guard !Task.isCancelled, let self else { return }
                self.enterTask = nil
                // Never expand while a drag is in progress.
                guard self.mode == .collapsed, NSEvent.pressedMouseButtons == 0 else { return }
                self.setMode(.peek)
            }
        } else {
            enterTask?.cancel()
            enterTask = nil
            guard mode != .collapsed, exitTask == nil else { return }
            let grace: UInt64 = mode == .panel ? 400_000_000 : 180_000_000
            exitTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: grace)
                guard !Task.isCancelled, let self else { return }
                self.exitTask = nil
                self.collapse()
            }
        }
    }

    func clicked() {
        switch mode {
        case .collapsed, .peek:
            openPanel(from: mode)
        case .panel:
            break
        }
    }

    func openPanel(from previous: Mode) {
        analytics.capture(.panelOpened(fromState: previous.rawValue))
        setMode(.panel)
        if !settings.consentShown {
            showConsent = true
        }
        refreshCost()
    }

    func collapse() {
        guard mode != .collapsed else { return }
        setMode(.collapsed)
        page = .usage
    }

    private func setMode(_ newMode: Mode) {
        guard mode != newMode else { return }
        mode = newMode
        onModeChange?(newMode)
    }

    func goToCostPage() {
        guard page != .cost else { return }
        page = .cost
        let bucket = AnalyticsBuckets.scanDurationMs(costReport?.scanDurationMs ?? 0)
        analytics.capture(.costScreenViewed(
            scanDurationBucket: bucket,
            modelCount: costReport?.models.count ?? 0))
    }

    func acknowledgeConsent() {
        settings.consentShown = true
        showConsent = false
    }

    func refreshTapped() {
        Task { await usageService.refreshNow() }
    }

    func openSettings() {
        onOpenSettings?()
    }

    // MARK: Data

    func refreshCost() {
        guard !costRefreshInFlight else { return }
        costRefreshInFlight = true
        Task { [weak self] in
            guard let self else { return }
            await self.priceLoader.refreshIfStale()
            let table = await self.priceLoader.current()
            await self.costEngine.setExtraRoots(self.settings.extraLogRoots)
            let report = await self.costEngine.refresh(prices: table)
            self.costReport = report
            self.costRefreshInFlight = false
        }
    }

    func rebuildCostCache() {
        Task { [weak self] in
            guard let self else { return }
            let table = await self.priceLoader.current()
            let report = await self.costEngine.rebuild(prices: table)
            self.costReport = report
        }
    }

    private func heartbeatIfNeeded(_ state: UsageState) {
        guard case .ok = state.phase else { return }
        let today = DayKey.from(Date())
        guard settings.lastHeartbeatDay != today else { return }
        settings.lastHeartbeatDay = today
        analytics.capture(.dailyHeartbeat(
            appVersion: AppInfo.version,
            daysSinceInstallBucket: AnalyticsBuckets.daysSinceInstall(settings.daysSinceInstall),
            planTier: PlanTier.resolve(state.planTier)?.id ?? (state.planTier == nil ? "unknown" : "other")))
    }

    // MARK: Derived display state

    var isStale: Bool {
        usage.isStale(now: now)
    }

    var syncStatusText: String {
        if usage.isRefreshing { return "SYNCING…" }
        switch usage.phase {
        case .ok, .initializing:
            return Format.ago(usage.syncedAt, from: now)
        case .credentialsUnavailable:
            return "NO CREDENTIALS"
        case .unauthorized:
            return "SIGNED OUT"
        case .scopeMissing:
            return "TOKEN LACKS SCOPE"
        case .rateLimited:
            return "RATE LIMITED"
        case .offline:
            return Format.ago(usage.syncedAt, from: now)
        }
    }

    var problemText: String? {
        switch usage.phase {
        case .ok, .initializing:
            return nil
        case .credentialsUnavailable(let reason):
            return reason.guidance
        case .unauthorized:
            return "Session expired. Run `claude login`, Claudette will pick it up."
        case .scopeMissing:
            return CredentialFailureReason.scopeMissing.guidance
        case .rateLimited(let until):
            if let until {
                return "Usage API rate limited. Retrying \(Format.countdown(to: until, from: now).lowercased())."
            }
            return "Usage API rate limited. Backing off."
        case .offline(let message):
            return usage.syncedAt == nil ? "Can't reach the usage API (\(message))." : nil
        }
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
