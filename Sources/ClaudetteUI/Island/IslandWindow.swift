import AppKit
import SwiftUI

/// Borderless, non-activating overlay pinned over the hardware notch. The
/// window rect is deliberately larger than the drawn silhouette so the panel
/// has room to animate; `HoverController` flips `ignoresMouseEvents` as the
/// pointer enters and leaves that silhouette, so everything else on screen
/// stays clickable.
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
        // Click-through until the pointer is proven to be over the silhouette.
        ignoresMouseEvents = true
        // The moment the pointer leaves the silhouette it is still inside this
        // window's much larger frame with `ignoresMouseEvents` off, so the exit
        // event targets us and the global monitor never sees it. Without this,
        // whether the panel ever notices the pointer left is down to luck.
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Only captures mouse events over the drawn silhouette; anywhere else in the
/// window's frame `hitTest` returns nil so clicks pass through.
///
/// This is necessary but *not* sufficient on its own — without the cursor
/// tracking in `HoverController` flipping `ignoresMouseEvents`, the window
/// still steals focus on click even when `hitTest` returns nil. hitTest stops
/// the steal during a click; the monitors stop it before the click arrives.
/// Concrete in its root view rather than `NSHostingView<AnyView>`: type
/// erasure at the root discards structural identity for the whole tree and
/// blocks SwiftUI's diffing fast paths.
final class IslandHostingView: NSHostingView<IslandRootView> {
    /// Returns the current silhouette size (top-center anchored in this view).
    var silhouetteSize: @MainActor () -> CGSize = { .zero }

    required init(rootView: IslandRootView) {
        super.init(rootView: rootView)
    }

    @MainActor @objc dynamic required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` arrives in the *superview's* space, which is bottom-left
        // origin, while this view is flipped. Comparing the raw point against
        // a bounds-derived rect silently misses by the full window height and
        // makes the whole panel unclickable — convert first.
        let local = convert(point, from: superview)
        let size = silhouetteSize()
        let rect = NSRect(
            x: (bounds.width - size.width) / 2,
            y: isFlipped ? 0 : bounds.maxY - size.height,
            width: size.width,
            height: size.height)
        // super.hitTest still wants the original, unconverted point.
        return rect.contains(local) ? super.hitTest(point) : nil
    }

    /// On a non-key window macOS swallows the first click just to focus it.
    /// The pointer is hovering the notch from whatever app the user is
    /// actually in, so the first click has to act.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
