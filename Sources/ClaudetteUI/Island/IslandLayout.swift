import CoreGraphics
import ClaudetteCore

/// How big the drawn silhouette is in each state.
///
/// A value type computed from the notch geometry rather than state on the view
/// model: these are pixel facts, they change only when the display or the
/// panel's content does, and nothing about them needs to be published.
struct IslandLayout: Equatable {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    /// What the panel measured itself at, once it has been laid out. Nil for
    /// the first frame, which falls back to an estimate.
    let measuredPanelHeight: CGFloat?

    init(geometry: NotchGeometry, measuredPanelHeight: CGFloat? = nil) {
        self.notchWidth = geometry.notchWidth
        self.notchHeight = geometry.notchHeight
        self.measuredPanelHeight = measuredPanelHeight
    }

    /// A fixed height independent of the menu bar, so the bar reads the same
    /// on notched and synthetic displays.
    var collapsedSize: CGSize {
        CGSize(width: notchWidth + Layout.pillWidth * 2, height: Layout.collapsedHeight)
    }

    var expandedSize: CGSize {
        CGSize(
            width: max(collapsedSize.width, Layout.panelWidth),
            height: measuredPanelHeight ?? notchHeight + Layout.estimatedPanelBodyHeight)
    }

    func size(for mode: IslandMode) -> CGSize {
        switch mode {
        case .collapsed: return collapsedSize
        case .panel: return expandedSize
        }
    }
}

/// Collapsed is the bar beside the notch; panel is the full hover surface.
enum IslandMode: String, Equatable, Sendable {
    case collapsed
    case panel
}
