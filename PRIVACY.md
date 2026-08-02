# Claudette Privacy

Claudette can send anonymous usage and crash telemetry to PostHog
(EU-hosted, `eu.i.posthog.com`). This page is the complete list of what is
sent, when, and what categorically never leaves your machine.

## Identity

A random UUID minted on first launch, stored at
`~/Library/Application Support/Claudette/install-id`. It is never derived
from your hardware, network, or Anthropic account. Deleting the file (or
the app's data) resets it. No person profile is created in PostHog
(`personProfiles = .never`).

## Consent tiers

- **Essential** — on by default, disclosed inline the first time you open
  the panel, and switchable off in Settings → General (takes effect
  immediately via PostHog opt-out). Covers app launch, one daily
  heartbeat, and failure events.
- **Behavioral** — off by default, opt-in only. Covers panel opens,
  cost-screen views, and setting changes.

## The complete event list

| Event | When | Properties |
| --- | --- | --- |
| `app_launched` | cold start | app version, OS version, arch, notched-display bool, display count |
| `daily_heartbeat` | first successful refresh each day | app version, days-since-install (bucketed), plan tier |
| `usage_fetch_failed` | usage API non-200/decode failure | status code, failure kind, retry count |
| `credentials_unavailable` | credential resolution failed | reason enum (`no_keychain_item`, `mcp_only`, `scope_missing`, `expired`, `malformed`) |
| `cost_scan_failed` | log scanner error | failure kind, root kind |
| `unknown_model_priced` | model missing from price table | model ID |
| `panel_opened` *(behavioral)* | expanding the island | previous state |
| `cost_screen_viewed` *(behavioral)* | opening the cost page | scan duration (bucketed), model count |
| `setting_changed` *(behavioral)* | toggling a setting | key, value (enums/booleans only) |
| `$exception` | crash/uncaught exception | type, message and stack after redaction |

There are no per-poll events and no free-form string properties outside
the redacted exception fields.

## What never leaves the machine

Access and refresh tokens, your email or account identifiers, org IDs,
project directory names or any filesystem paths, prompt or response
content, absolute dollar figures, absolute token counts, and your
utilization percentages.

Anything free-form (crash messages, stack traces) passes through
[`Redactor`](Sources/ClaudetteCore/Telemetry/Redactor.swift) first, which
strips `sk-ant-*` tokens, email addresses, UUIDs, home-directory paths and
everything below `projects/`, then truncates to 2 KB. The redactor has its
own unit tests fed with realistic token and path strings.

## Verifying this

The entire telemetry surface is deliberately small:

- Event schema: `Sources/ClaudetteCore/Telemetry/AnalyticsEvent.swift`
- Redaction: `Sources/ClaudetteCore/Telemetry/Redactor.swift`
- The only file that talks to PostHog:
  `Sources/Claudette/Telemetry/PostHogAnalytics.swift`

Local builds (and any build without a `POSTHOG_API_KEY` supplied at
packaging time) contain no key and send nothing at all.
