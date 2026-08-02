# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for a security problem.

Use GitHub's [private vulnerability reporting](https://github.com/taylorgibb/claudette/security/advisories/new),
or email **taylor@developerhut.co.za**. You should get an acknowledgement
within 72 hours, and a fix or a plan within 14 days.

## What is in scope

Claudette reads your Claude Code OAuth token and your local session logs, so
the things worth reporting are:

- Any path by which the access token, or part of it, could leave the machine
  other than in the `Authorization` header to `api.anthropic.com`.
- Any path by which prompt text, file paths, project names, or usage figures
  could reach the analytics endpoint. Everything that leaves goes through
  [`Redactor`](Sources/ClaudetteCore/Telemetry/Redactor.swift) and the closed
  [`AnalyticsEvent`](Sources/ClaudetteCore/Telemetry/AnalyticsEvent.swift)
  enum; a way around either is a vulnerability.
- Anything that lets another local process read the token through Claudette
  that could not read it directly from the keychain.

## What is not in scope

- The keychain prompt on first launch. That is macOS asking whether Claudette
  may read the item Claude Code owns; answering "Always Allow" is bound to
  Claudette's signing identity and is revoked if that identity changes.
- Cost figures being wrong. They are an estimate at list rates from local
  logs — a bug, but not a security one.

## What Claudette does with your data

- **The token** is read from the keychain (or `~/.claude/.credentials.json`)
  on each poll and used for exactly one request. It is never written to disk,
  never logged, and never included in an analytics event.
- **Session logs** are read to count tokens. Contents are never transmitted;
  only aggregate token counts per model per day are kept, in
  `~/Library/Caches/Claudette`.
- **Analytics** are on in release builds and have no in-app opt-out. They are
  anonymous — keyed to a random per-install UUID, never to your hardware or
  your Anthropic account — and limited to the fixed event list in
  `AnalyticsEvent`. There is no free-form property, so there is no field that
  arbitrary text could travel in. A build without a PostHog project key,
  which includes any build you make yourself, constructs no reporter and
  sends nothing. To opt out of a release build, delete
  `~/Library/Application Support/Claudette/install-id` and build from source.
