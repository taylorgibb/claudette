# Contributing to Claudette

## Getting set up

```sh
git clone https://github.com/taylorgibb/claudette.git
cd claudette
swift test
```

That is the whole setup. Claudette has **no external dependencies**, so a
clean clone builds and tests with nothing but a Swift 6 toolchain and Xcode's
command line tools. If `swift test` does anything other than pass on a fresh
clone, that is a bug — please report it.

To run the app:

```sh
swift build -c release
scripts/package.sh 0.0.0-dev
open dist/Claudette.app
```

The first launch asks for keychain access. That is macOS asking whether
Claudette may read the credential item Claude Code owns; there is no way to
read your usage without it.

## How the code is laid out

Three targets, and the boundaries between them are load-bearing:

| Target | Contains | Rule |
|---|---|---|
| `ClaudetteCore` | Usage polling, cost scanning, pricing, telemetry | **No AppKit, no SwiftUI.** Pure logic and Foundation. Fully unit tested. |
| `ClaudetteUI` | Views, view model, presenters, window and hover management | AppKit and SwiftUI live here. Has its own test target. |
| `Claudette` | `Main.swift` | Nothing else. If you are adding a file here, it probably belongs in `ClaudetteUI`. |

Two rules follow from that table, and reviews will hold you to them:

- **Decisions belong in Core or in a presenter, not in a `View`.** If a change
  decides *what* to show — which rows a plan has, what a failure reads like,
  whether a model is priced — it goes in `ClaudetteCore` or in
  `UsagePresenter`/`CostPresenter`, where it can be tested. Views decide only
  how things look.
- **Anything that touches the network goes through `HTTPTransport`.** That is
  what lets every network path be tested with `StubTransport` and no network.

## Privacy constraints

These are not style preferences. A change that breaks one of them will be
rejected regardless of how useful it is.

- `AnalyticsEvent` is a closed enum with fixed associated values. **Do not add
  a free-form `String` property to an event.** If arbitrary text can reach an
  event, it can reach the wire.
- Anything free-form that does leave — error messages, stack traces — goes
  through `Redactor`. There is exactly one egress path and it stays that way.
- Never capture a usage percentage, a dollar figure, a file path, a project
  name, or anything derived from prompt text.
- The install ID is a random UUID minted on first launch. It must never be
  derived from a hardware serial, a MAC address, or the Anthropic account.

## Tests

- Core logic needs a test. `ClaudetteCoreTests` and `ClaudetteUITests` both
  run offline and touch no real user data — `CostEngine` takes a
  `LogRootResolving`, so use `FixedLogRoots([fixtureDirectory])` rather than
  letting a scan reach `~/.claude`.
- Fixtures live in `Tests/ClaudetteCoreTests/Fixtures`.
- A test that only passes on a machine with no Claude Code history is not a
  test; it is a coin flip.

## Comments

Comments explain **why**, not what. The AppKit corners of this app —
`IslandWindow.hitTest`, `SymbolButton`, `HoverController` — are held together
by non-obvious platform behaviour, and the comments recording *why* each
workaround exists are the most valuable prose in the repo. If you change that
code, keep the reasoning current; if you find reasoning that is now wrong,
deleting it is a real contribution.

## Pull requests

- Branch from `main`, keep the change focused.
- `swift build && swift test` must pass. CI runs the same two commands.
- Describe what you changed and why. Screenshots or a short screen recording
  for anything visual — the island is 33 points tall and the difference
  between right and wrong is often two of them.

## Pricing data

`Sources/ClaudetteCore/Resources/prices.json` is the bundled floor; the app
also fetches the same file from `main` at runtime so prices can be corrected
without shipping a release. Adding a model there is a genuinely useful, small
first contribution — include a link to the published rates in the PR.
