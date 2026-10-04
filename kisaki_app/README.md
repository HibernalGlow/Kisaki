# Kisaki - Flutter desktop frontend

Kisaki is a third-party desktop GUI for the [Czkawka](https://github.com/qarmin/czkawka) engine.
This is the frontend the project ships: the Slint one in `../kisaki` was shelved on 2026-10-04, so new
UI work belongs here and not there. The scanning work stays in
`czkawka_core`: this app never re-implements hashing, traversal, dedup or comparison. It renders a
three-lane board (sources, results, analysis) in a Swiss/International visual language with dark and
light themes, and it talks to the engine through one Rust crate.

```text
czkawka_core  ->  kisaki_app/rust (kisaki_bridge, flutter_rust_bridge)  ->  kisaki_app/lib (Dart board)
```

## Layout

| Path | Owns |
|---|---|
| `rust/src/api` | the FFI surface: requests, outcomes, and one async function per verb |
| `rust/src/engine` | the ported tool registry, scan plumbing, and the mutating verbs |
| `lib/src/rust` | **generated** Dart bindings - never edit by hand |
| `lib/engine` | `KisakiEngine` seam, its FRB adapter, and a seed adapter for tests and demos |
| `lib/state` | board controller, selection and filter rules, row projection |
| `lib/ui` | the board, lanes, panels, dialogs and overlays |
| `lib/l10n` | every label the board paints, so a missing string is a test failure |
| `packaging/macos_bundle.sh` | builds the app and carries the bridge dylib inside it |

## Running it

Prerequisites: Rust 1.94.1 or newer, a stable Flutter SDK, and `ffmpeg` plus `ffprobe` (the video
optimizer probes and re-encodes real clips, and its tests do too).

```bash
cargo build -p kisaki_bridge          # from the repository root, writes target/debug
cd kisaki_app
flutter pub get
flutter run -d macos                  # or: linux, windows
```

`lib/main.dart` asks the platform window for 1280 x 800 with a minimum of 940 x 560, and the minimum
comes from `BoardTokens.minWindowWidth/minWindowHeight` - the same numbers the lane layout degrades
against - so the narrow-window arrangement is reachable by resizing rather than only by a test fixture.

`lib/util/rust_lib.dart` resolves the dylib by trying candidates and keeping the newest: the
`Contents/Frameworks` copy inside a packaged `.app` first, then the workspace `target/<profile>`
directory, so a development run picks up `cargo build` without a reinstall.

## Platform builds and version

The six `CMakeLists.txt` files under `linux/` and `windows/` are tracked, which needed an explicit
exception in the root `.gitignore` (its blanket `*.txt` rule hid them, so a clone could not build
either platform). Names are the product's: the Linux executable is `kisaki` with GTK application id
`com.github.hibernerglow.kisaki`, matching the desktop entry and the AppStream id, the Windows
executable is `kisaki.exe`, and the macOS bundle is `Kisaki.app`.

`pubspec.yaml` carries the engine's version (`12.0.2+1202`) because build-name becomes
`CFBundleShortVersionString` on macOS and the file version on Windows. `misc/change_version.py`
rewrites it along with `rust/Cargo.toml` and the AppStream release entry, so no release number can
drift on its own. `packaging/linux_bundle.sh` builds the Linux bundle and puts
`libkisaki_bridge.so` next to the `kisaki` executable, which is the first directory
`lib/util/rust_lib.dart` searches; CI runs that script (job `flutter-linux`) because no machine in
this workspace has a Linux toolchain, and uploads the finished bundle as artifact
`linux_kisaki_flutter_x86_64` on the default branch. `packaging/windows_bundle.sh` is the Windows
counterpart: it copies `kisaki_bridge.dll` into `build/windows/x64/runner/Release`, the directory the
Flutter tool itself reports as its output. Neither script can be proven from this machine - a Windows
cross check of the bridge gets as far as `blake3` (needs `ml64.exe`; the engine's `blake_pure` feature
avoids it) and then stops in `dart-sys`, whose build script hands a C file to the host compiler, so
MSVC is genuinely required. The `flutter-windows` job therefore exists but runs only on `workflow_dispatch`
and on the default branch: it needs one green run on a real runner before it is safe to gate pull
requests with, and until then the script's guards are verified only against a stub toolchain.

## Codec support

The bridge builds against `czkawka_core` with **no** native codec features by default, and that is not
a harmless omission: with `heif` off, `check_if_can_display_image` (core `common/image.rs:271`) leaves
HEIC out of the allowed extension list, so a scan of an iPhone photo folder simply sees fewer files -
no error, no row, no message. Measured here, both directions: `cargo test -p kisaki_bridge` passes the
equivalence test with `heif_build == check_if_can_display_image("photo.HEIC")`, and the same test
passes under `cargo test -p kisaki_bridge --features heif` (124 tests either way, libheif compiling
cleanly on this machine).

`rust/Cargo.toml` therefore forwards the same four optional features the Slint frontend exposes -
`heif`, `libraw`, `libavif`, `xdg_portal_trash` - so one build flag decides both frontends, and
`codec_info()` returns the compiled-in set plus the engine's own diagnostic text. That text is now on
screen: `flutter_rust_bridge_codegen generate` exposes `codecInfo()` to Dart, `KisakiEngine.codecInfo()`
carries it across the seam, and the statistics card ends with `heif+ raw- avif-`, the engine's build
line, and the core version, OS and thread limit. `test/codec_readback_widget_test.dart` flips the three
flags in the stub engine and asserts the caption changes with them, so the line cannot quietly become a
string. Note the CI asymmetry this
exposes: the Linux job builds the Slint crate
`--features heif,libraw,libavif` while the macOS and Windows jobs build it plain, so today only the
Linux frontend binary can hash HEIC.

## Gates

Every one of these is part of CI (`.github/workflows/kisaki.yml`, jobs `bridge` and `dart`).

```bash
cargo test -p kisaki_bridge                                     # 125 tests
cargo test -p kisaki_bridge --features heif,libraw,libavif       # same 125, native codecs compiled in
cargo clippy -p kisaki_bridge --all-targets -- -D warnings
cargo fmt -p kisaki_bridge -- --check                           # stable, as CI runs it
flutter analyze
flutter test                                                      # 375 tests, measured 2026-10-04
```

`test/bridge_smoke_test.dart` loads the compiled dylib and drives real work through it: scans a temp
tree, renames misnamed files, moves and copies a selection, strips EXIF into a side file, sorts a
similar-images set into folders and undoes it, and transcodes an mpeg4 clip to h264. The counts above
were measured on 2026-10-04; re-run them rather than trusting the numbers.

## File operations

Every mutating call takes an explicit `dryRun`. A dry run performs nothing: it reserves target names
the same way a real run would, so the plan it reports is the plan that would happen. Deletions and
cleanup go through `czkawka_core::common::fs_ops`, which is what gives trash behaviour identical to
the other frontends.

`requestStop` interrupts whichever job is in flight - a scan or one file operation - and only one file
operation runs at a time, so a stop signal can never land on the wrong batch. Delete, rename, move,
EXIF and video optimize each stop between files, and what they never attempted is reported as stopped
rather than as removed or failed, so an interrupted run can never overstate reclaimed bytes.
`applySimiuSet` still runs to completion: its undo journal has to describe exactly the operations that
happened.

| Verb | What it does |
|---|---|
| `deleteFiles` | trash or delete selected rows |
| `exportResults` | write the current result set as JSON or CSV |
| `renameFiles` | apply the names the engine wants for bad names and bad extensions |
| `moveFiles` | move or copy into a folder, with skip / overwrite / rename / error conflict policy |
| `cleanExif` | strip metadata with the engine's remover, into a side file by default |
| `applySimiuSet` | move, copy or hard-link files into set folders, one undo journal per root |
| `undoSimiuSet` | replay one journal newest-first; refuses a journal it cannot describe exactly |
| `optimizeVideos` | transcode or crop with the engine's own ffmpeg commands, per selected file |

A fix never silently overwrites: an occupied target name is skipped, refused or suffixed
(`name (1).ext`, `name_01.ext`) depending on the policy in the request, and a file the engine no
longer flags is reported as skipped with the engine's own reason when it has one.

## Changing the bridge API

Bindings are committed, so CI does not run codegen. After editing `rust/src/api`:

```bash
~/.cargo/bin/flutter_rust_bridge_codegen generate    # from kisaki_app
"$(rustup which --toolchain nightly rustfmt)" --edition 2024 --config-path .rustfmt.toml \
  rust/src/frb_generated.rs                          # from kisaki_app, sorts the generated imports
cargo fmt -p kisaki_bridge                           # the stable check CI runs
cargo build -p kisaki_bridge
flutter pub run build_runner build                   # never with --build-filter
```

Codegen writes `frb_generated.rs` with its own import order, which the repository's rustfmt config
sorts back. Skipping that pass leaves a formatting-only diff in a generated file - measured on
2026-10-04, where the round trip is clean only after formatting. `rustup run nightly cargo fmt` is
not a substitute: on this machine it still executes the stable binary.

`build_runner` deletes outputs it was not asked to regenerate, so a filtered run removes committed
`.g.dart` and `.freezed.dart` files.

## Not here on purpose

No scanning algorithm, no duplicate or similarity logic, no cache format in Dart - those are the
engine's. The app is a Flutter frontend of this fork; the Slint frontend in `../kisaki` is the
separate, engine-direct implementation.

No icon art either, and none is invented: `windows/runner/Runner.rc` deliberately carries no ICON
resource because the `flutter create` icon is the Flutter logo (its `app_icon.ico` hash-matches the
template), and `data/com.github.hibernerglow.kisaki.desktop` names an Icon id no file provides. The
macOS project is in the same state on purpose: the `AppIcon.appiconset` with the seven template pngs is
gone from `Runner/Assets.xcassets`, and so are the three `ASSETCATALOG_COMPILER_APPICON_NAME` settings
that asked Xcode to compile it, because the catalog was only half-tracked anyway (the `Contents.json`
binding those pngs is swallowed by the root `.gitignore` rule for json files). `Kisaki.app` therefore
launches with the system generic icon on all three platforms. Adding Kisaki art later means an appiconset
plus its descriptor, the setting restored, and an `app_icon.ico`.

Brand text is checked rather than assumed. `flutter create` does not substitute the `APP_NAME` literal it
writes into `macos/Runner/Base.lproj/MainMenu.xib` - generating a fresh project with this toolchain leaves
all six occurrences in place - so the application menu and its About, Hide and Quit items would ship that
token. `misc/check_brand_tokens.py` greps the app's tracked text files for it and for `com.example`, and
runs under `just fix` and in CI. The compiled nib is readable without launching anything: `ibtool --compile
out.nib MainMenu.xib` then `strings out.nib` lists `About Kisaki`, `Hide Kisaki`, `Quit Kisaki`.

