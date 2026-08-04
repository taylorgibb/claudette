import CoreGraphics
import ClaudetteCore

struct IslandLayout: Equatable {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let measuredPanelHeight: CGFloat?

    init(geometry: NotchGeometry, measuredPanelHeight: CGFloat? = nil) {
        self.notchWidth = geometry.notchWidth
        self.notchHeight = geometry.notchHeight
        self.measuredPanelHeight = measuredPanelHeight
    }

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

enum IslandMode: String, Equatable, Sendable {
    case collapsed
    case panel
}
