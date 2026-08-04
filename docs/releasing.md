# Releasing

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
