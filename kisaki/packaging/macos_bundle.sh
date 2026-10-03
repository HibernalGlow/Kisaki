#!/usr/bin/env bash
# Wraps a built kisaki binary into a macOS .app bundle so it gets proper
# application metadata (name, identifier, icon) instead of showing up as a
# bare executable. Upstream Czkawka ships mac binaries unpacked; doing the
# bundling here keeps kisaki identifiable in the Dock and in Cmd-Tab.
#
# Usage: kisaki/packaging/macos_bundle.sh [target/debug|target/release]
set -euo pipefail

if [ $# -gt 1 ]; then
    echo "usage: $0 [profile dir, default target/release]" >&2
    exit 2
fi

PROFILE="${1:-target/release}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BINARY="$REPO_ROOT/$PROFILE/kisaki"
APP="$REPO_ROOT/$PROFILE/Kisaki.app"
IDENTIFIER="com.github.hibernerglow.kisaki"
VERSION="$(sed -n 's/^version = "\(.*\)"/\1/p' "$REPO_ROOT/kisaki/Cargo.toml" | head -1)"

if [ ! -x "$BINARY" ]; then
    echo "no binary at $BINARY - run: cargo build --profile ${PROFILE#target/} -p kisaki" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/kisaki"

# No icon asset exists for Kisaki yet, so Info.plist deliberately omits
# CFBundleIconFile rather than pointing at a missing or hand-invented file.
cat >"$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>Kisaki</string>
    <key>CFBundleDisplayName</key>       <string>Kisaki</string>
    <key>CFBundleExecutable</key>        <string>kisaki</string>
    <key>CFBundleIdentifier</key>        <string>$IDENTIFIER</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key>    <string>11.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSHumanReadableCopyright</key>  <string>GPL-3.0-only</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
</dict>
</plist>
PLIST

# An ad-hoc signature is enough for a locally built bundle; a hardened runtime
# entitlements file would be needed for distribution.
codesign --force --deep --sign - "$APP" 2>/dev/null || \
    echo "warning: ad-hoc codesign failed, the bundle still runs locally" >&2

echo "built $APP (kisaki $VERSION, identifier $IDENTIFIER)"
