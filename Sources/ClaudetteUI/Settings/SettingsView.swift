import SwiftUI
import AppKit
import ClaudetteCore

/// One screen, three rows; everything else is automatic or on the context menu.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var viewModel: IslandViewModel
    @State private var loginItemNeedsApproval = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                settingRow("Start at Login") {
                    Toggle("", isOn: $settings.launchesAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                if loginItemNeedsApproval {
                    HStack(spacing: 4) {
                        Text("Waiting for approval in System Settings.")
                        Link("Open Login Items",
                             destination: URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
                        Spacer()
                    }
                    .font(Theme.SettingsFont.detail)
                    .foregroundStyle(Theme.settingsSecondaryText)
                }

                divider

                settingRow("Plan", detail: detectedPlanDetail) {
                    Picker("", selection: $settings.planTierOverride) {
                        Text("Automatic").tag(PlanTier.automaticID)
                        Divider()
                        ForEach(PlanTier.known) { tier in
                            Text(tier.displayName).tag(tier.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                divider

                settingRow("Caffeine Mode", detail: "Prevents Mac from going to sleep.") {
                    Toggle("", isOn: $settings.preventsSleep)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 26)

            Divider().overlay(Theme.hairline)

            Text(AppInfo.version)
                .font(Theme.SettingsFont.version)
                .foregroundStyle(Theme.settingsSecondaryText.opacity(0.8))
                .padding(.vertical, 13)
        }
        .frame(width: 520)
        .background(Theme.settingsSurface)
        .environment(\.colorScheme, .dark)
        .tint(Theme.accent)
        .onAppear { loginItemNeedsApproval = LoginItem.requiresApproval }
        .onChange(of: settings.launchesAtLogin) {
            loginItemNeedsApproval = LoginItem.requiresApproval
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
    }

    /// Title, optional sub-caption, trailing control.
    private func settingRow<Control: View>(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(Theme.SettingsFont.title)
                    .foregroundStyle(Theme.primaryText)
                if let detail {
                    Text(detail)
                        .font(Theme.SettingsFont.detail)
                        .foregroundStyle(Theme.settingsSecondaryText)
                }
            }
            Spacer(minLength: 16)
            control()
        }
    }

    /// The detected tier belongs in the caption, not as a picker row — naming
    /// it there duplicated whichever tier it matched.
    private var detectedPlanDetail: String {
        guard let detected = PlanTier.resolve(viewModel.usage.planTier) else {
            return "Nothing detected yet."
        }
        return "Detected from your account: \(detected.displayName)."
    }
}

/// Shows the one settings window.
///
/// The app is an `.accessory` — no Dock tile, no menu bar — so a plain
/// `makeKeyAndOrderFront` leaves the window behind whatever the user was in.
/// Switching to `.regular` for as long as it is open is what brings it
/// forward; `AppMenu` supplies the menu bar that then has to exist, which is
/// also where ⌘W, ⌘Q and the Edit-menu clipboard shortcuts come from.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(settings: AppSettings, viewModel: IslandViewModel) {
        if window == nil {
            let controller = NSHostingController(
                rootView: SettingsView(settings: settings, viewModel: viewModel))
            // The screen is fixed-width and self-sizing.
            controller.sizingOptions = [.preferredContentSize]
            let newWindow = NSWindow(contentViewController: controller)
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.title = "Claudette"
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            newWindow.center()
            window = newWindow
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        // Back to an accessory: no Dock tile, no app switcher entry.
        NSApp.setActivationPolicy(.accessory)
    }
}
