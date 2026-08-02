import SwiftUI
import AppKit
import ClaudetteCore

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var vm: IslandViewModel
    @ObservedObject var updater: UpdateChecker

    var body: some View {
        TabView {
            GeneralSettingsTab(settings: settings, updater: updater)
                .tabItem { Label("General", systemImage: "gearshape") }
            DisplaySettingsTab(settings: settings)
                .tabItem { Label("Display", systemImage: "display") }
            DataSettingsTab(settings: settings, vm: vm)
                .tabItem { Label("Data", systemImage: "externaldrive") }
        }
        .frame(width: 520, height: 500)
    }
}

struct GeneralSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updater: UpdateChecker
    @State private var loginItemNeedsApproval = false

    var body: some View {
        Form {
            Section {
                Toggle("Start Claudette at login", isOn: $settings.launchAtLogin)
                if loginItemNeedsApproval {
                    HStack(spacing: 4) {
                        Text("Waiting for approval in System Settings.")
                            .foregroundStyle(.secondary)
                        Link("Open Login Items",
                             destination: URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                    }
                    .font(.callout)
                }
            }

            Section("Keep this Mac awake") {
                Toggle("Prevent system sleep", isOn: $settings.preventSystemSleep)
                Text("The machine keeps running; the display may still sleep. Right for long agent runs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Prevent display sleep", isOn: $settings.preventDisplaySleep)
                Text("The screen stays lit. An indicator shows in the panel while either is active.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Refresh") {
                Picker("Usage refresh interval", selection: $settings.pollIntervalMinutes) {
                    Text("5 minutes").tag(5)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                }
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $settings.autoCheckUpdates)
                HStack {
                    Text("Version \(AppInfo.version)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let available = updater.availableVersion {
                        Link("v\(available) available", destination: AppSettings.releasesURL)
                    }
                    Button("Check Now") {
                        Task { await updater.checkNow() }
                    }
                }
            }

            Section("Privacy") {
                Toggle("Share anonymous usage and crash data", isOn: $settings.telemetryEssential)
                Text("Launch, daily heartbeat, and failure events only. Redacted; never prompts, tokens, paths, or usage numbers.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Also share interaction analytics", isOn: $settings.telemetryBehavioral)
                Text("Panel opens, cost-screen views, and setting toggles. Off by default.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { refreshLoginStatus() }
        .onChange(of: settings.launchAtLogin) {
            refreshLoginStatus()
        }
    }

    private func refreshLoginStatus() {
        loginItemNeedsApproval = LoginItem.requiresApproval
    }
}

struct DisplaySettingsTab: View {
    @ObservedObject var settings: AppSettings
    @State private var screens: [(id: String, name: String)] = []

    var body: some View {
        Form {
            Section("Screen") {
                Picker("Show on", selection: $settings.displaySelection) {
                    Text("Auto (notched display)").tag("auto")
                    ForEach(screens, id: \.id) { screen in
                        Text(screen.name).tag(screen.id)
                    }
                }
                Toggle("Compact width on non-notched displays", isOn: $settings.syntheticNotchCompact)
            }

            Section("Numbers") {
                Picker("Show percentages as", selection: $settings.displayRemaining) {
                    Text("Used (matches the API)").tag(false)
                    Text("Remaining").tag(true)
                }
                .pickerStyle(.radioGroup)
            }

            Section("Hover") {
                Toggle("Reliable hover (global mouse monitor)", isOn: $settings.reliableHover)
                Text("Turn on if hovering from the top screen edge sometimes fails to open the island. Costs a small amount of idle CPU.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            screens = NSScreen.screens.map {
                (NotchGeometry.screenID(for: $0), $0.localizedName)
            }
        }
    }
}

struct DataSettingsTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var vm: IslandViewModel
    @State private var rootsText = ""

    var body: some View {
        Form {
            Section("Plan for cost comparison") {
                Picker("Plan", selection: $settings.planTierOverride) {
                    Text(autoLabel).tag("auto")
                    ForEach(PlanTier.known, id: \.id) { tier in
                        Text("\(tier.displayName) — $\(Int(tier.monthlyUSD))/mo").tag(tier.id)
                    }
                    Text("Custom").tag("custom")
                }
                if settings.planTierOverride == "custom" {
                    TextField(
                        "Monthly cost (USD)",
                        value: $settings.customMonthlyPrice,
                        format: .number)
                }
                Text("Cost figures are USD at list API rates.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Extra Claude log roots") {
                TextEditor(text: $rootsText)
                    .font(.system(.callout, design: .monospaced))
                    .frame(height: 56)
                HStack {
                    Text("One path per line, scanned in addition to the standard locations.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Apply") {
                        settings.extraLogRoots = rootsText
                            .split(separator: "\n")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        vm.refreshCost()
                    }
                }
            }

            Section("Cost cache") {
                HStack {
                    if let report = vm.costReport {
                        Text("\(report.filesScanned) files · last scan \(report.scanDurationMs) ms")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No scan yet").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Rebuild Cost Cache") {
                        vm.rebuildCostCache()
                    }
                }
            }

            Section("Usage source diagnostics") {
                LabeledContent("Credentials") {
                    Text(vm.usage.credentialSource.map { $0 == .keychain ? "Keychain" : "~/.claude/.credentials.json" } ?? "Not found")
                }
                LabeledContent("Last HTTP status") {
                    Text(vm.usage.lastHTTPStatus.map(String.init) ?? "—")
                }
                LabeledContent("Last successful sync") {
                    Text(vm.usage.syncedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                }
                LabeledContent("Detected plan tier") {
                    Text(vm.usage.planTier ?? "—")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            rootsText = settings.extraLogRoots.joined(separator: "\n")
        }
    }

    private var autoLabel: String {
        if let detected = PlanTier.resolve(vm.usage.planTier) {
            return "Auto-detected (\(detected.displayName) — $\(Int(detected.monthlyUSD))/mo)"
        }
        return "Auto-detected (nothing detected yet)"
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(settings: AppSettings, vm: IslandViewModel, updater: UpdateChecker) {
        if window == nil {
            let view = SettingsView(settings: settings, vm: vm, updater: updater)
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false)
            newWindow.title = "Claudette Settings"
            newWindow.contentView = NSHostingView(rootView: view)
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
