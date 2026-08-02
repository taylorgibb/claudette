import AppKit
import SwiftUI
import ClaudetteCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings!
    private var analytics: any Analytics = NoopAnalytics()
    private var usageService: UsageService!
    private var costEngine: CostEngine!
    private var priceLoader: PriceTableLoader!
    private var islandController: IslandController!
    private var viewModel: IslandViewModel!
    private var sleepWake: SleepWakeObserver?
    private var powerManager = PowerAssertionManager()
    private var updateChecker = UpdateChecker()
    private var settingsWindow = SettingsWindowController()
    private var screenObserver: NSObjectProtocol?

    static let priceTableURL = URL(
        string: "https://raw.githubusercontent.com/taylorgibb/claudette/main/Sources/ClaudetteCore/Resources/prices.json")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Claudette")
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Claudette")
        try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try? fm.createDirectory(at: caches, withIntermediateDirectories: true)

        settings = AppSettings()
        analytics = makeAnalytics(appSupport: appSupport)
        ExceptionReporter.install(analytics)

        usageService = UsageService(
            persistenceURL: appSupport.appendingPathComponent("snapshot.json"),
            analytics: analytics)
        costEngine = CostEngine(
            cacheURL: caches.appendingPathComponent("cost-v1.json"),
            extraRoots: settings.extraLogRoots,
            analytics: analytics)
        priceLoader = PriceTableLoader(remoteURL: Self.priceTableURL, cacheDirectory: caches)

        let screen = NotchGeometry.selectScreen(selection: settings.displaySelection)
        let geometry = screen.map {
            NotchGeometry.detect(screen: $0, compactSynthetic: settings.syntheticNotchCompact)
        } ?? NotchGeometry(
            screenFrame: .zero, notchMinX: 0,
            notchWidth: NotchGeometry.syntheticStandardWidth, notchHeight: 24, isSynthetic: true)

        viewModel = IslandViewModel(
            settings: settings,
            geometry: geometry,
            usageService: usageService,
            costEngine: costEngine,
            priceLoader: priceLoader,
            analytics: analytics)
        viewModel.onOpenSettings = { [weak self] in
            guard let self else { return }
            self.settingsWindow.show(settings: self.settings, vm: self.viewModel, updater: self.updateChecker)
        }

        islandController = IslandController(viewModel: viewModel)
        islandController.show()
        viewModel.start()

        wireSettingChanges()
        wireSystemObservers()
        powerManager.apply(
            preventSystemSleep: settings.preventSystemSleep,
            preventDisplaySleep: settings.preventDisplaySleep)

        Task { [usageService, settings] in
            await usageService?.start(pollInterval: settings?.pollIntervalSeconds ?? 300)
        }

        analytics.capture(.appLaunched(
            appVersion: AppInfo.version,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            arch: AppInfo.arch,
            isNotchedDisplay: NotchGeometry.hasNotchedDisplay,
            displayCount: NSScreen.screens.count))

        // Surface update availability in the panel.
        updateChecker.onAvailableChange = { [weak self] version in
            self?.viewModel.updateAvailable = version
        }
        updateChecker.startDaily { [weak self] in
            self?.settings.autoCheckUpdates ?? false
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        powerManager.releaseAll()
        analytics.flush()
    }

    // MARK: Wiring

    private func makeAnalytics(appSupport: URL) -> any Analytics {
        let apiKey = (Bundle.main.object(forInfoDictionaryKey: "ClaudettePostHogAPIKey") as? String) ?? ""
        let host = (Bundle.main.object(forInfoDictionaryKey: "ClaudettePostHogHost") as? String)
            ?? "https://eu.i.posthog.com"
        guard !apiKey.isEmpty else {
            // Dev builds and forks without a key: telemetry is fully off.
            return NoopAnalytics()
        }
        return PostHogAnalytics(
            apiKey: apiKey,
            host: host,
            distinctID: InstallID.get(appSupportDirectory: appSupport),
            policy: settings.telemetryPolicy)
    }

    private func wireSettingChanges() {
        settings.onChange = { [weak self] key, value in
            guard let self else { return }
            self.analytics.capture(.settingChanged(key: key, value: value))

            switch key {
            case "pollIntervalMinutes":
                Task { [usageService = self.usageService, seconds = self.settings.pollIntervalSeconds] in
                    await usageService?.setPollInterval(seconds)
                }
            case "telemetryEssential", "telemetryBehavioral":
                self.analytics.setPolicy(self.settings.telemetryPolicy)
            case "launchAtLogin":
                LoginItem.set(enabled: self.settings.launchAtLogin)
            case "preventSystemSleep", "preventDisplaySleep":
                self.powerManager.apply(
                    preventSystemSleep: self.settings.preventSystemSleep,
                    preventDisplaySleep: self.settings.preventDisplaySleep)
            case "displaySelection", "syntheticNotchCompact":
                self.islandController.reposition()
            case "reliableHover":
                self.islandController.applyHoverStrategy()
            case "extraLogRoots":
                self.viewModel.refreshCost()
            default:
                break
            }
        }
    }

    private func wireSystemObservers() {
        sleepWake = SleepWakeObserver(
            onSleep: { [weak self] in
                guard let self else { return }
                Task { await self.usageService.suspend() }
            },
            onWake: { [weak self] in
                guard let self else { return }
                Task { await self.usageService.resume() }
                self.islandController.reposition()
                // Assertions don't always survive sleep; re-apply.
                self.powerManager.apply(
                    preventSystemSleep: self.settings.preventSystemSleep,
                    preventDisplaySleep: self.settings.preventDisplaySleep)
            })

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.islandController.reposition()
            }
        }
    }
}
