import AppKit
import SwiftUI
import ClaudetteCore

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
    @Published private(set) var displayTime = Date()
    @Published var geometry: NotchGeometry
    @Published var availableUpdateVersion: String?
    @Published var measuredPanelHeight: CGFloat?
    enum SignInPhase: Equatable {
        case idle
        case waiting
        case failed
    }

    @Published private(set) var isSignedIn: Bool
    @Published private(set) var signInPhase: SignInPhase = .idle

    let settings: AppSettings
    let analytics: any AnalyticsReporting
    private let usageService: UsageService
    private let costEngine: CostEngine
    private let priceLoader: PriceTableLoader
    private let oauthTokens: OAuthTokenStore
    private var signInTask: Task<Void, Never>?
    var onModeChange: (@MainActor (IslandMode) -> Void)?
    var onOpenSettings: (@MainActor () -> Void)?

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
        analytics: any AnalyticsReporting,
        oauthTokens: OAuthTokenStore = OAuthTokenStore()
    ) {
        self.settings = settings
        self.geometry = geometry
        self.usageService = usageService
        self.costEngine = costEngine
        self.priceLoader = priceLoader
        self.analytics = analytics
        self.oauthTokens = oauthTokens
        self.isSignedIn = oauthTokens.isSignedIn
    }

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
        signInTask?.cancel()
    }

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

    func hoverChanged(isInside: Bool) {
        if isInside {
            exitTask?.cancel()
            exitTask = nil
            guard mode == .collapsed, enterTask == nil else { return }
            enterTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled, let self else { return }
                self.enterTask = nil
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

    func signInWithClaude() {
        guard signInTask == nil else { return }
        signInPhase = .waiting
        let store = oauthTokens
        signInTask = Task { [weak self] in
            do {
                try await ClaudeOAuth.signIn(
                    store: store,
                    transport: URLSessionTransport(),
                    openBrowser: { NSWorkspace.shared.open($0) })
                guard let self else { return }
                self.isSignedIn = true
                self.signInPhase = .idle
                self.refreshUsage()
            } catch is CancellationError {
                self?.signInPhase = .idle
            } catch {
                self?.signInPhase = .failed
            }
            self?.signInTask = nil
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
    }

    func signOut() {
        oauthTokens.clear()
        isSignedIn = false
        refreshUsage()
    }

    func openSettings() {
        onOpenSettings?()
    }

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
