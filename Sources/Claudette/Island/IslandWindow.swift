import AppKit
import SwiftUI

/// Borderless, non-activating overlay pinned over the hardware notch. The
/// window rect is larger than the drawn silhouette; hit testing outside the
/// silhouette falls through so the menu bar stays clickable.
final class IslandWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view whose hit region is the current silhouette, not the window
/// rect. Also owns the `NSTrackingArea` hover path (build-plan option A).
final class IslandHostingView: NSHostingView<AnyView> {
    /// Returns the current silhouette size (top-center anchored in this view).
    var silhouetteSize: @MainActor () -> CGSize = { .zero }
    /// Raw hover signal; debouncing lives in the view model.
    var onHoverRaw: @MainActor (Bool) -> Void = { _ in }

    private var trackingArea: NSTrackingArea?

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    @MainActor @objc dynamic required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func silhouetteRect() -> NSRect {
        let size = silhouetteSize()
        let x = (bounds.width - size.width) / 2
        let y = isFlipped ? 0 : bounds.height - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func silhouetteContains(_ localPoint: NSPoint) -> Bool {
        silhouetteRect().contains(localPoint)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in the superview's coordinate space.
        let local = convert(point, from: superview)
        guard silhouetteContains(local) else { return nil }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        reportHover(event)
    }

    override func mouseMoved(with event: NSEvent) {
        reportHover(event)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverRaw(false)
    }

    private func reportHover(_ event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        onHoverRaw(silhouetteContains(local))
    }
}
