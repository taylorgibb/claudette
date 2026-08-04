# Input handling

The island is a borderless, non-activating `NSPanel` that has to sit over the
notch without stealing clicks from the app underneath. That takes six
cooperating mechanisms, and removing any one of them breaks something
non-obvious:

1. **An oversized host window.** The panel's frame is fixed at the largest
   extent the island can ever reach (`Layout.hostWindowSize`) so the silhouette
   can animate inside it without the window resizing.
2. **`ignoresMouseEvents`, flipped on the edge crossing.** The window server
   honours this unconditionally, which is what actually makes the rest of the
   frame click-through. Setting it is an IPC round trip, so `HoverController`
   only touches it when the pointer crosses the silhouette boundary.
3. **`hitTest` restricted to the silhouette.** Necessary but not sufficient on
   its own: it stops the window stealing a click in flight, while the monitors
   above stop the click arriving at all. It must convert the incoming point
   from the superview's bottom-left space, because the hosting view is flipped
   — comparing the raw point against a bounds-derived rect misses by the full
   window height and makes the whole panel unclickable.
4. **Global *and* local `.mouseMoved` monitors.** Tracking areas miss enter
   events at the top screen edge. The global monitor covers the pointer being
   over another app's window; the local one covers it being over ours.
   `acceptsMouseMovedEvents` has to be on, or the exit event goes to a window
   that never asked for it.
5. **A launch watchdog.** If the pointer is already inside the silhouette when
   the app starts, no `.mouseMoved` ever fires. A 10 Hz timer covers that,
   and self-invalidates on the first real event or after two seconds.
6. **`SymbolButton`.** `acceptsFirstMouse` is asked of the view `hitTest`
   returns — a SwiftUI descendant we don't own — so overriding it on the
   hosting view does nothing. An AppKit button answers for itself, which is
   what lets the gear act on the first click without the app activating and
   deactivating whatever the user was working in.
