#!/usr/bin/env bash
# Build a Linux Kisaki bundle that actually carries the Rust bridge.
#
# The bridge is opened by path rather than linked, so a bundle without it starts and then reports
# that it could not find the library. lib/util/rust_lib.dart tries the executable's own directory
# first, which is why the copy lands beside `kisaki` and not inside `lib/` - the loader has no
# candidate for that directory yet.
#
# Usage: bash kisaki_app/packaging/linux_bundle.sh [debug|release]
set -euo pipefail

profile="${1:-release}"
if [ "$profile" != release ] && [ "$profile" != debug ]; then
  echo "error: profile must be 'debug' or 'release', got '$profile'" >&2
  exit 2
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo="$(cd "$here/.." && pwd)"
bridge="target/$profile/libkisaki_bridge.so"
bundle="$here/build/linux/x64/$profile/bundle"

(cd "$repo" && cargo build -p kisaki_bridge "--$profile")
(cd "$here" && flutter build linux "--$profile")

if [ ! -x "$bundle/kisaki" ]; then
  echo "error: flutter produced no $bundle/kisaki" >&2
  exit 1
fi
if [ ! -f "$repo/$bridge" ]; then
  echo "error: cargo produced no $repo/$bridge" >&2
  exit 1
fi

/bin/cp -f "$repo/$bridge" "$bundle/libkisaki_bridge.so"
# The loader keeps the newest of its candidates, so prove the copy is the library this run built.
cmp "$repo/$bridge" "$bundle/libkisaki_bridge.so"

echo "Kisaki is bundled at: $bundle/kisaki"
echo "Run it with:          \"$bundle/kisaki\""
