import SwiftUI
import AppKit
import ClaudetteCore

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

                divider

                settingRow("Claude Account", detail: accountDetail) {
                    if viewModel.isSignedIn {
                        Button("Sign Out") { viewModel.signOut() }
                    } else if viewModel.signInPhase == .waiting {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Button("Cancel") { viewModel.cancelSignIn() }
                        }
                    } else {
                        Button("Sign In with Claude") { viewModel.signInWithClaude() }
                    }
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

    private var accountDetail: String {
        if viewModel.isSignedIn {
            return "Signed in. Claudette keeps its own token — no more keychain prompts."
        }
        switch viewModel.signInPhase {
        case .waiting: return "Finish signing in from your browser."
        case .failed: return "Sign-in didn't complete. Try again."
        case .idle: return "One-time browser sign-in that replaces the keychain prompts."
        }
    }

    private var detectedPlanDetail: String {
        guard let detected = PlanTier.resolve(viewModel.usage.planTier) else {
            return "Nothing detected yet."
        }
        return "Detected from your account: \(detected.displayName)."
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(settings: AppSettings, viewModel: IslandViewModel) {
        if window == nil {
            let controller = NSHostingController(
                rootView: SettingsView(settings: settings, viewModel: viewModel))
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
        NSApp.setActivationPolicy(.accessory)
    }
}
