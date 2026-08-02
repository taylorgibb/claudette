import AppKit
import ClaudetteUI

/// The whole executable: everything else lives in `ClaudetteUI`, which is a
/// library and therefore has somewhere to be tested from.
@main
enum ClaudetteMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        // `delegate` is kept alive by this frame for the app's lifetime
        // (NSApplication.delegate is not retained).
        withExtendedLifetime(delegate) {}
    }
}
