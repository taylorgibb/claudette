# claudette

Claude's top-notch supervisor.

Claudette pins a black-glass island over your Mac's notch showing your
Claude Code **session** and **weekly** limits. Hover to reveal three gauge
bars, click for the full panel, swipe for the cost screen — your last 30
days of local session logs priced at pay-as-you-go API rates, next to what
your subscription actually costs.

- Swift 6, SwiftUI, macOS 14+. No dock icon.
- Reads the token Claude Code already holds — no login flow of its own.
- Gauge tint is a continuous Oklab ramp (calm → ember → flare), not
  traffic lights. Each bar carries a **pace tick**: the point usage would
  be at if you burned the window evenly. Fill past the tick means you'll
  hit the wall early.
- The cost screen is entirely local: an incremental scanner over
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

| Row | Source | Fallback |
| --- | --- | --- |
| Session | `five_hour` window | hidden; weekly promoted to primary |
| Weekly | `seven_day` window | — |
| Weekly (model) | `seven_day_opus` | `seven_day_sonnet`, else a ghost row |

Usage comes from the same OAuth endpoint Claude Code itself uses, polled
every 5/15/30 minutes with jitter, exponential backoff on 429, and a slow
retry lane on 401. The last good snapshot is persisted and rendered dimmed
("synced 12m ago") when stale.

The dollar figure is an **estimate**: list API rates (USD), cache writes at
1.25×/2× input for 5m/1h TTLs, cache reads at 0.1×. It excludes batch
discounts, long-context surcharges, and anything billed outside the
subscription. Unknown models are counted in tokens but never silently
priced — they're named in a footnote instead.

## Building from source

```sh
swift build            # debug build
swift test             # ClaudetteCore test suite
swift run Claudette    # run the island (no bundle: login item + keychain prompts differ)
./scripts/package.sh 0.0.0-dev   # assemble dist/Claudette.app from a release build
```

The package has two targets: `ClaudetteCore` (no AppKit — usage polling,
credentials, cost engine, telemetry primitives; fully unit-tested) and the
`Claudette` app (island shell, views, settings, PostHog).

## Releasing

Tag `vX.Y.Z` (or run the Release workflow manually) and CI will: run tests,
build a universal binary, assemble and sign the app, create a DMG, notarize
it when secrets are present, publish a GitHub release, and bump
`Casks/claudette.rb` on `main` with the new version and SHA.

Repository secrets (all optional, features degrade gracefully):

| Secret | Purpose |
| --- | --- |
| `POSTHOG_API_KEY` | Bakes the (write-only) project key into release builds |
| `POSTHOG_HOST` | Override ingestion host (default `https://eu.i.posthog.com`) |
| `MACOS_CERTIFICATE_P12` | Base64 Developer ID Application cert + key |
| `MACOS_CERTIFICATE_PASSWORD` | Password for the .p12 |
| `MACOS_SIGN_IDENTITY` | Identity name (auto-detected if omitted) |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | notarytool credentials |

Without signing secrets, releases are ad-hoc signed and need
`--no-quarantine`. Note that keychain "Always Allow" grants are tied to the
signing identity — ship a stable identity from the first signed release or
every update re-prompts.
