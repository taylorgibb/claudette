# claudette

Claude's top-notch supervisor.

Claudette pins a black-glass island over your Mac's notch showing your
Claude Code limits — percent remaining, one numeral on each side of the
camera. Hover and it expands in place to three gauge bars over a spend
sparkline. Nothing to click; swipe for the cost page — your last 30 days of
local session logs priced at pay-as-you-go API rates, next to what your
subscription actually costs.

Right-click the island for refresh, settings and quit.

- Swift 6, SwiftUI, macOS 14+. No dock icon, no external dependencies.
- Reads the token Claude Code already holds — no login flow of its own.
- The notch is detected automatically on every screen-parameter change;
  non-notched displays get an identical synthetic island. Nothing to
  configure.
- Gauge tint is a continuous Oklab ramp (calm → ember → flare), not
  traffic lights. Each bar carries a **pace tick**: the point usage would
  be at if you burned the window evenly. Fill past the tick means you'll
  hit the wall early.
- The cost page is entirely local: an incremental scanner over
  `~/.claude/projects/**/*.jsonl` with streaming-chunk dedup, priced from
  a bundled table that refreshes weekly from this repo.

## Install

```sh
brew tap taylorgibb/claudette https://github.com/taylorgibb/claudette.git
brew install --cask taylorgibb/claudette/claudette
```

Until releases are signed with a Developer ID and notarized, add
`--no-quarantine` to the install command (or right-click → Open).

On first refresh macOS asks for access to Claude Code's keychain item —
click **Always Allow** once.

## What it shows

Usage comes from the same OAuth endpoint Claude Code itself uses, which
returns a `limits[]` array. Which limits are in it depends on the plan, so
the panel always draws three rows and marks any the account doesn't have as
unavailable rather than moving the others:

| Row | Limit kind | Window |
| --- | --- | --- |
| Session | `session` | 5 hours |
| Week | `weekly_all` | 7 days |
| *Model name* | `weekly_scoped` | 7 days |

The collapsed bar shows the first two limits that actually exist, so an
account with no session cap promotes the next one up rather than showing a
blank.

Polling is jittered around the configured interval, with exponential backoff
on 429 and a slow retry lane on 401. The last good snapshot is persisted and
rendered dimmed ("synced 12m ago") when stale.

Settings is one screen: start at login, plan, and caffeine mode. Everything
else is automatic. Costs are shown in USD.

The dollar figure is an **estimate**: list API rates, cache writes at
1.25×/2× input for 5m/1h TTLs, cache reads at 0.1×. It excludes batch
discounts, long-context surcharges, and anything billed outside the
subscription. Models with no known price are counted in tokens but never
silently priced at zero — they're named in a footnote instead.

## Privacy

- The access token is read per poll, used for one request, and never written
  to disk or included in any event.
- Session log *contents* never leave the machine. Only aggregate token counts
  per model per day are cached, under `~/Library/Caches/Claudette`.
- Release builds send **anonymous usage analytics**, with no opt-out in the
  app. They are keyed to a random per-install UUID that is not derived from
  any hardware or account identifier, and are limited to a closed enum of
  eight event shapes with no free-form property — so there is no field
  arbitrary text could travel in. Error messages, the one free-form thing
  that can leave, go through a redactor first. Builds without a PostHog key,
  which includes anything you build yourself, send nothing at all.

See [SECURITY.md](SECURITY.md) for the full statement and how to report a
problem.

## Building from source

```sh
swift build          # debug build
swift test           # both test suites, offline, no external dependencies
scripts/package.sh 0.0.0-dev   # assemble dist/Claudette.app from a release build
```

`swift run Claudette` works but runs unbundled, so login-item registration and
the keychain prompt behave differently — package it for anything beyond a
smoke test.

### Layout

| Target | Contains |
| --- | --- |
| `ClaudetteCore` | Usage polling, credentials, cost engine, pricing, telemetry. No AppKit or SwiftUI. |
| `ClaudetteUI` | Views, view model, presenters, window and hover management. |
| `Claudette` | `Main.swift`, and nothing else. |

Both libraries have test targets. See [CONTRIBUTING.md](CONTRIBUTING.md) for
the rules that keep that split meaningful.

### Input handling

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

## Releasing

Tag `vX.Y.Z` (or run the Release workflow manually) and CI will: run tests,
build a universal binary, assemble and sign the app, create a DMG, notarize
it when secrets are present, publish a GitHub release, and bump
`Casks/claudette.rb` on `main` with the new version and SHA.

Repository secrets (all optional, features degrade gracefully):

| Secret | Purpose |
| --- | --- |
| `POSTHOG_API_KEY` | Bakes the (write-only) project key into release builds. Without it, no reporter is constructed and nothing is sent. |
| `POSTHOG_HOST` | Override ingestion host (default `https://eu.i.posthog.com`) |
| `MACOS_CERTIFICATE_P12` | Base64 Developer ID Application cert + key |
| `MACOS_CERTIFICATE_PASSWORD` | Password for the .p12 |
| `MACOS_SIGN_IDENTITY` | Identity name (auto-detected if omitted) |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | notarytool credentials |

Without signing secrets, releases are ad-hoc signed and need
`--no-quarantine`. Note that keychain "Always Allow" grants are tied to the
signing identity — ship a stable identity from the first signed release or
every update re-prompts.

## License

MIT — see [LICENSE](LICENSE).
