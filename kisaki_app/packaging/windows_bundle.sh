#!/usr/bin/env bash
# Build a Windows Kisaki bundle that actually carries the Rust bridge.
#
# Same shape as linux_bundle.sh: the bridge is opened by path, not linked, so the app starts and then
# reports that it could not find the library unless the DLL sits beside the executable. The first
# candidate in lib/util/rust_lib.dart is the executable's own directory on every platform, so this
# needs no loader change.
#
# Run this from Git Bash on a Windows machine (the flutter and cargo lines are the native ones there).
# It has not been executed on Windows yet: the guards, paths and the copy are what a stub tree proves,
# everything else is the toolchain's behaviour.
#
# Usage: bash kisaki_app/packaging/windows_bundle.sh [debug|release]
set -euo pipefail

profile="${1:-release}"
if [ "$profile" != release ] && [ "$profile" != debug ]; then
  echo "error: profile must be 'debug' or 'release', got '$profile'" >&2
  exit 2
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(cd "$here/.." && pwd)"
bridge="target/$profile/kisaki_bridge.dll"
# Flutter capitalizes the runner mode directory.
case "$profile" in
  release) runner="Release" ;;
  debug) runner="Debug" ;;
esac
bundle="$here/build/windows/x64/runner/$runner"

(cd "$repo" && cargo build -p kisaki_bridge "--$profile")
(cd "$here" && flutter build windows "--$profile")

if [ ! -f "$bundle/kisaki.exe" ]; then
  echo "error: flutter produced no $bundle/kisaki.exe" >&2
  exit 1
fi
if [ ! -f "$repo/$bridge" ]; then
  echo "error: cargo produced no $repo/$bridge" >&2
  exit 1
fi

/bin/cp -f "$repo/$bridge" "$bundle/kisaki_bridge.dll"
# The loader keeps the newest of its candidates, so prove the copy is the library this run built.
cmp "$repo/$bridge" "$bundle/kisaki_bridge.dll"

echo "Kisaki is bundled at: $bundle/kisaki.exe"
echo "Run it from:          \"$bundle\""
