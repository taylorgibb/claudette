import AppKit
import Combine
import SwiftUI
import ClaudetteCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    private struct Services {
        let settings: AppSettings
        let analytics: any AnalyticsReporting
        let usage: UsageService
        let cost: CostEngine
        let prices: PriceTableLoader
        let viewModel: IslandViewModel
        let island: IslandController
    }

    private var services: Services?
    private var sleepWake: SleepWakeObserver?
    private let power = PowerAssertionManager()
    private let updates = UpdateChecker()
    private let settingsWindow = SettingsWindowController()
    private let screenObservers = RegistrationBag.observers(of: .default)
    private var subscriptions = Set<AnyCancellable>()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppMenu.install()

        let directories = Directories()
        let settings = AppSettings()
        let analytics = makeAnalytics(appSupport: directories.appSupport)
        ExceptionReporter.install(analytics)

        let usage = UsageService(
            persistenceURL: directories.appSupport.appendingPathComponent("snapshot.json"),
            analytics: analytics)
        let cost = CostEngine(
            cacheURL: directories.caches.appendingPathComponent("cost.json"),
            logRoots: ClaudeLogRoots(extraRoots: settings.extraLogRoots),
            analytics: analytics)
        let prices = PriceTableLoader(cacheDirectory: directories.caches)

        let viewModel = IslandViewModel(
            settings: settings,
            geometry: NotchGeometry.current(),
            usageService: usage,
            costEngine: cost,
            priceLoader: prices,
            analytics: analytics)
        viewModel.onOpenSettings = { [weak self] in
            guard let self, let services = self.services else { return }
            self.settingsWindow.show(
                settings: services.settings, viewModel: services.viewModel)
        }

        let island = IslandController(viewModel: viewModel)
        services = Services(
            settings: settings, analytics: analytics, usage: usage, cost: cost,
            prices: prices, viewModel: viewModel, island: island)

        island.show()
        viewModel.start()

        observeSettings(settings)
        observeSystem()
        power.setPreventsSleep(settings.preventsSleep)

        Task { await usage.start(pollInterval: settings.pollIntervalSeconds) }

        analytics.capture(.appLaunched(
            appVersion: AppInfo.version,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            arch: AppInfo.arch,
            isNotchedDisplay: NotchGeometry.hasNotchedDisplay,
            displayCount: NSScreen.screens.count))

        updates.onAvailableVersionChange = { [weak viewModel] version in
            viewModel?.availableUpdateVersion = version
        }
        updates.startDaily { [weak settings] in
            settings?.checksForUpdatesAutomatically ?? false
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        services?.viewModel.stop()
        power.release()
        services?.analytics.flush()
    }

    private func makeAnalytics(appSupport: URL) -> any AnalyticsReporting {
        let token = (Bundle.main.object(forInfoDictionaryKey: "ClaudettePostHogAPIKey") as? String) ?? ""
        let host = (Bundle.main.object(forInfoDictionaryKey: "ClaudettePostHogHost") as? String)
            .flatMap(URL.init(string:)) ?? URL(string: "https://eu.i.posthog.com")!
        guard !token.isEmpty else { return DisabledAnalytics() }
        return PostHogReporter(
            projectToken: token,
            host: host,
            installID: InstallID.get(appSupportDirectory: appSupport))
    }

    private func observeSettings(_ settings: AppSettings) {
        settings.changes
            .sink { [weak self] change in
                guard let self, let services = self.services else { return }
                if let value = change.reportedValue {
                    services.analytics.capture(
                        .settingChanged(key: change.key.rawValue, value: value))
                }

                switch change.key {
                case .pollIntervalMinutes:
                    let seconds = settings.pollIntervalSeconds
                    Task { await services.usage.setPollInterval(seconds) }
                case .launchesAtLogin:
                    LoginItem.set(enabled: settings.launchesAtLogin)
                case .preventsSleep:
                    self.power.setPreventsSleep(settings.preventsSleep)
                case .extraLogRoots:
                    services.viewModel.refreshCost()
                case .planTierOverride, .lastHeartbeatDay, .checksForUpdatesAutomatically:
                    break
                }
            }
            .store(in: &subscriptions)
    }

    private func observeSystem() {
        sleepWake = SleepWakeObserver(
            onSleep: { [weak self] in
                guard let services = self?.services else { return }
                Task { await services.usage.suspend() }
            },
            onWake: { [weak self] in
                guard let self, let services = self.services else { return }
                Task { await services.usage.resume() }
                services.island.reposition()
                self.power.renew(preventsSleep: services.settings.preventsSleep)
            })

        screenObservers.add(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.services?.island.reposition()
            }
        })
    }
}

private struct Directories {
    let appSupport: URL
    let caches: URL

    init() {
        let fm = FileManager.default
        appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Claudette")
        caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Claudette")
        try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try? fm.createDirectory(at: caches, withIntermediateDirectories: true)
    }
}
