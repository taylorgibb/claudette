import AppKit
import SwiftUI

/// Owns the overlay window: creation, placement over the notch, hover
/// wiring, and repositioning on screen-parameter changes.
@MainActor
final class IslandController {
    let viewModel: IslandViewModel
    private let window: IslandWindow
    private let hostingView: IslandHostingView
    private let hover: HoverController

    init(viewModel: IslandViewModel) {
        self.viewModel = viewModel

        let rect = NSRect(origin: .zero, size: Layout.windowSize)
        window = IslandWindow(contentRect: rect)
        hostingView = IslandHostingView(rootView: AnyView(IslandRootView(vm: viewModel)))
        hostingView.silhouetteSize = { [weak viewModel] in
            viewModel?.silhouetteSize ?? .zero
        }
        window.contentView = hostingView

        hover = HoverController(
            window: window,
            silhouetteSize: { [weak viewModel] in viewModel?.silhouetteSize ?? .zero },
            onHoverRaw: { [weak viewModel] inside in viewModel?.hoverRaw(inside) },
            onDismiss: { [weak viewModel] in viewModel?.collapse() })

        hostingView.onHoverRaw = { [weak self] inside in
            // Tracking-area path is only authoritative when the global
            // monitor is off; both feed the same debounced state machine.
            guard let self, !self.viewModel.settings.reliableHover else { return }
            self.viewModel.hoverRaw(inside)
        }

        viewModel.onModeChange = { [weak self] mode in
            self?.hover.setPanelDismissMonitoring(mode == .panel)
        }

        applyHoverStrategy()
    }

    func applyHoverStrategy() {
        hover.setGlobalHoverMonitoring(viewModel.settings.reliableHover)
    }

    func show() {
        reposition()
        window.orderFrontRegardless()
    }

    func reposition() {
        guard let screen = NotchGeometry.selectScreen(selection: viewModel.settings.displaySelection) else {
            window.orderOut(nil)
            return
        }
        let geometry = NotchGeometry.detect(
            screen: screen,
            compactSynthetic: viewModel.settings.syntheticNotchCompact)
        viewModel.geometry = geometry

        let size = Layout.windowSize
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
