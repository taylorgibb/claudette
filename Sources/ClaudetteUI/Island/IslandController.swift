import AppKit
import SwiftUI

/// Owns the overlay window: creation, placement over the notch, hover
/// wiring, and repositioning on screen-parameter changes.
@MainActor
final class IslandController: NSObject {
    let viewModel: IslandViewModel
    private let window: IslandWindow
    private let hostingView: IslandHostingView
    private let hover: HoverController

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel

        let rect = NSRect(origin: .zero, size: Layout.hostWindowSize)
        window = IslandWindow(contentRect: rect)
        hostingView = IslandHostingView(rootView: IslandRootView(viewModel: viewModel))
        hostingView.silhouetteSize = { [weak viewModel] in
            viewModel?.silhouetteSize ?? .zero
        }
        window.contentView = hostingView

        hover = HoverController(
            window: window,
            silhouetteSize: { [weak viewModel] in viewModel?.silhouetteSize ?? .zero },
            onHoverChange: { [weak viewModel] inside in viewModel?.hoverChanged(isInside: inside) },
            onDismiss: { [weak viewModel] in viewModel?.collapse() })

        super.init()

        hostingView.menu = makeContextMenu()

        viewModel.onModeChange = { [weak self] mode in
            guard let self else { return }
            self.hover.setPanelDismissMonitoring(mode == .panel)
            // Key, but deliberately *not* active. `NSApp.activate` would
            // deactivate whatever the user is actually working in — closing
            // its menus and interrupting typing — and this fires on hover, not
            // on a click. Controls act on their first click because
            // `SymbolButton` answers `acceptsFirstMouse` for itself.
            if mode == .panel {
                self.window.makeKey()
            }
        }
    }

    /// The panel has no chrome by design, so these live on a right-click.
    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        // Sync state lost its header row; refreshed each time the menu opens.
        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh Now", action: #selector(refresh), keyEquivalent: "")
        menu.addItem(withTitle: "Cost Breakdown", action: #selector(showCost), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Claudette", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items where item.action != nil { item.target = self }
        return menu
    }

    @objc private func refresh() { viewModel.refreshUsage() }

    @objc private func showCost() {
        viewModel.expand()
        viewModel.showPage(.cost)
    }

    @objc private func showSettings() { viewModel.openSettings() }

    @objc private func quit() { NSApp.terminate(nil) }

    func show() {
        reposition()
        window.orderFrontRegardless()
    }

    func reposition() {
        guard let screen = NotchGeometry.selectScreen() else {
            window.orderOut(nil)
            return
        }
        viewModel.geometry = NotchGeometry.detect(screen: screen)
        let geometry = viewModel.geometry

        let size = Layout.hostWindowSize
        let frame = NSRect(
            x: geometry.notchCenterX - size.width / 2,
            y: geometry.screenFrame.maxY - size.height,
            width: size.width,
            height: size.height)
        window.setFrame(frame, display: true)
        if !window.isVisible {
            window.orderFrontRegardless()
        }
    }
}

extension IslandController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first?.title = viewModel.usagePresenter.syncStatusText
    }
}
