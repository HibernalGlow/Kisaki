#!/usr/bin/env bash
# Build a macOS Kisaki.app that actually carries the Rust bridge inside it.
#
# `flutter build macos` knows nothing about the `kisaki_bridge` cargo member, so the dylib has to
# be copied into Contents/Frameworks afterwards - which is also where lib/util/rust_lib.dart looks
# for it. Re-signing happens after the copy, because injecting a file into an already signed
# bundle is exactly what makes Gatekeeper report "file modified".
#
# Usage: bash kisaki_app/packaging/macos_bundle.sh [debug|release]
set -euo pipefail

profile="${1:-release}"
if [ "$profile" != release ] && [ "$profile" != debug ]; then
  echo "error: profile must be 'debug' or 'release', got '$profile'" >&2
  exit 2
fi

app_profile="$(tr '[:lower:]' '[:upper:]' <<<"${profile:0:1}")${profile:1}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(cd "$here/.." && pwd)"
bridge="target/$profile/libkisaki_bridge.dylib"
app="$here/build/macos/Build/Products/$app_profile/Kisaki.app"

# The bridge lives in the shared workspace target dir, and Cocoapods is invoked by flutter here.
build_bridge() { (cd "$repo" && cargo build -p kisaki_bridge "$@"); }
build_flutter() { (cd "$here" && flutter build macos "$@"); }

# Cocoapods dies on a non-UTF-8 locale on this toolchain, so pin it before flutter shells out.
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

if [ "$profile" = release ]; then
  echo "== cargo build -p kisaki_bridge --release"
  build_bridge --release
  echo "== flutter build macos --release"
  build_flutter --release
else
  echo "== cargo build -p kisaki_bridge (debug)"
  build_bridge
  echo "== flutter build macos --debug"
  build_flutter --debug
fi

if [ ! -f "$repo/$bridge" ]; then
  echo "error: cargo produced no $bridge" >&2
  exit 1
fi
if [ ! -d "$app" ]; then
  echo "error: flutter produced no $app" >&2
  exit 1
fi

echo "== bundling the bridge into Contents/Frameworks"
/bin/mkdir -p "$app/Contents/Frameworks"
/bin/cp -f "$repo/$bridge" "$app/Contents/Frameworks/libkisaki_bridge.dylib"

echo "== ad-hoc re-sign, nested library before the bundle"
codesign --force --sign - "$app/Contents/Frameworks/libkisaki_bridge.dylib"
codesign --force --sign - "$app"

echo "== verifying"
codesign --verify --deep --strict --verbose=2 "$app"

echo
echo "Kisaki.app is at: $app"
echo "Run it with:      open \"$app\""
echo "Or with a terminal to see its stdout: \"$app/Contents/MacOS/Kisaki\""
