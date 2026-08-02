import AppKit

/// Optional "reliable hover" path (build-plan option B): a global + local
/// mouse-moved monitor tested against the silhouette's screen rect. Costs a
/// little idle CPU, catches the enter events tracking areas can miss at the
/// screen edge. Also owns the panel-dismissal monitors (click outside, Esc).
@MainActor
final class HoverController {
    private weak var window: NSWindow?
    private var silhouetteSize: @MainActor () -> CGSize
    private let onHoverRaw: @MainActor (Bool) -> Void
    private let onDismiss: @MainActor () -> Void

    private var mouseMonitors: [Any] = []
    private var dismissMonitors: [Any] = []
    private var lastInside = false

    init(
        window: NSWindow,
        silhouetteSize: @escaping @MainActor () -> CGSize,
        onHoverRaw: @escaping @MainActor (Bool) -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.window = window
        self.silhouetteSize = silhouetteSize
        self.onHoverRaw = onHoverRaw
        self.onDismiss = onDismiss
    }

    deinit {
        // Monitors are removed in stop()/setPanelDismissMonitoring(false);
        // the app never destroys this controller in practice.
    }

    // MARK: Global hover monitoring (option B)

    func setGlobalHoverMonitoring(_ enabled: Bool) {
        for monitor in mouseMonitors {
            NSEvent.removeMonitor(monitor)
        }
        mouseMonitors = []
        guard enabled else { return }

        let globalHandler: @Sendable (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluatePointer()
            }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: globalHandler) {
            mouseMonitors.append(global)
        }
        let localHandler: @Sendable (NSEvent) -> NSEvent? = { [weak self] event in
            MainActor.assumeIsolated {
                self?.evaluatePointer()
            }
            return event
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: localHandler) {
            mouseMonitors.append(local)
        }
    }

    private func evaluatePointer() {
        guard let window else { return }
        let size = silhouetteSize()
        let frame = window.frame
        let rect = NSRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height)
        let inside = rect.contains(NSEvent.mouseLocation)
        guard inside != lastInside else { return }
        lastInside = inside
        onHoverRaw(inside)
    }

    // MARK: Panel dismissal

    /// While the panel is open: any click outside our window collapses it,
    /// and Esc collapses it when the panel happens to be key.
    func setPanelDismissMonitoring(_ enabled: Bool) {
        for monitor in dismissMonitors {
            NSEvent.removeMonitor(monitor)
        }
        dismissMonitors = []
        guard enabled else { return }

        // Global monitors only see events delivered to other apps, so a
        // click inside our own panel never trips this.
        let outsideHandler: @Sendable (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onDismiss()
            }
        }
        if let outside = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown], handler: outsideHandler) {
            dismissMonitors.append(outside)
        }
        let escapeHandler: @Sendable (NSEvent) -> NSEvent? = { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated {
                self?.onDismiss()
            }
            return nil
        }
        if let escape = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: escapeHandler) {
            dismissMonitors.append(escape)
        }
    }
}
