# Kisaki - Flutter desktop frontend

Kisaki is a third-party desktop GUI for the [Czkawka](https://github.com/qarmin/czkawka) engine,
maintained in this fork beside the Slint frontend in `../kisaki`. The scanning work stays in
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

`lib/util/rust_lib.dart` resolves the dylib by trying candidates and keeping the newest: the
`Contents/Frameworks` copy inside a packaged `.app` first, then the workspace `target/<profile>`
directory, so a development run picks up `cargo build` without a reinstall.

## Gates

Every one of these is part of CI (`.github/workflows/kisaki.yml`, jobs `bridge` and `dart`).

```bash
cargo test -p kisaki_bridge                                     # 114 tests
cargo clippy -p kisaki_bridge --all-targets -- -D warnings
cargo fmt -p kisaki_bridge -- --check                           # stable, as CI runs it
flutter analyze
flutter test                                                      # 132 tests
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
cargo build -p kisaki_bridge
flutter pub run build_runner build                   # never with --build-filter
```

`build_runner` deletes outputs it was not asked to regenerate, so a filtered run removes committed
`.g.dart` and `.freezed.dart` files.

## Not here on purpose

No scanning algorithm, no duplicate or similarity logic, no cache format in Dart - those are the
engine's. The app is a Flutter frontend of this fork; the Slint frontend in `../kisaki` is the
separate, engine-direct implementation.
