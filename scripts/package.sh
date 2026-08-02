#!/usr/bin/env bash
# Assembles dist/Claudette.app from a `swift build -c release` output.
# Usage: scripts/package.sh <version>
# Env:   POSTHOG_API_KEY (optional; telemetry is a no-op without it)
#        POSTHOG_HOST    (optional; defaults to the EU ingestion host)
set -euo pipefail

VERSION="${1:?usage: package.sh <version>}"

# Universal builds land in .build/apple/Products/Release; single-arch in .build/release.
BUILD_DIR=".build/apple/Products/Release"
if [[ ! -x "$BUILD_DIR/Claudette" ]]; then
  BUILD_DIR=".build/release"
fi
if [[ ! -x "$BUILD_DIR/Claudette" ]]; then
  echo "error: no release binary found; run swift build -c release first" >&2
  exit 1
fi

APP="dist/Claudette.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/Claudette" "$APP/Contents/MacOS/Claudette"

# SPM resource bundles (ClaudetteCore prices.json, PostHog privacy manifest)
# must sit in Contents/Resources for Bundle.module to resolve them.
find "$BUILD_DIR" -maxdepth 1 -name "*.bundle" -print0 | while IFS= read -r -d '' bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

sed -e "s/__VERSION__/${VERSION}/g" \
    -e "s/__POSTHOG_API_KEY__/${POSTHOG_API_KEY:-}/g" \
    -e "s#__POSTHOG_HOST__#${POSTHOG_HOST:-https://eu.i.posthog.com}#g" \
    packaging/Info.plist > "$APP/Contents/Info.plist"

printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "Built $APP (version $VERSION)"
lipo -archs "$APP/Contents/MacOS/Claudette" 2>/dev/null || true
