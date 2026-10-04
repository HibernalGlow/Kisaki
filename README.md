<p>
  <img src="./assets/readme/hero.svg" width="100%" alt="Kisaki - a three-lane desktop frontend for the Czkawka cleaning engine">
</p>

<p align="right">English · <a href="./README_zh.md">简体中文</a></p>

**Kisaki is a new desktop frontend for the [Czkawka](https://github.com/qarmin/czkawka) cleaning
engine.** This repository is a fork of Czkawka: the scanning engine and every other frontend in it
are upstream's, and `kisaki/` and `kisaki_app/` are what this fork adds. They are one product in two
toolkits - a Slint shell and a Flutter shell - reaching the same engine the same way.

## What the fork adds

Two frontends, and eighteen lines outside them.

| | |
|:--|:--|
| `kisaki/` | 4 045 lines of Rust in 16 files, 2 260 lines of Slint in 12 files |
| `kisaki_app/` | 3 824 lines of Rust in the `kisaki_bridge` crate, 8 508 lines of Dart in 24 files, plus 2 963 lines of tests; generated bindings and `*.freezed.dart` are excluded |
| Outside the frontends | `+18 -6` across `Cargo.toml` (two workspace members), `justfile`, `misc/run_checks.sh`, `misc/change_version.py`, plus new files `.github/workflows/kisaki.yml`, `data/com.github.hibernerglow.kisaki.desktop` and `.metainfo.xml`, and `Cargo.lock` entries |
| Boundary | `czkawka_core` is never modified to make a UI feature easier, and upstream crates are never restyled - both would destroy future rebases |

Kisaki does not reuse Krokiet's UI. Its Rust side mirrors Krokiet's *mechanisms* (a worker thread per
scan, a `crossbeam` progress channel, an `Arc<AtomicBool>` stop flag, all Slint mutation pushed back
through `upgrade_in_event_loop`), while the layout, navigation, result table, progress display,
file-operation surface and theming are Kisaki's own.

## The board, measured

<p>
  <img src="./assets/readme/lane_board.svg" width="100%" alt="Dimensioned drawing of the Kisaki window: a header bar over a Source lane, a Results lane and an Analysis lane, with the measured minimums, clamps and the 48 pixel collapsed strip">
</p>

Two decisions are load-bearing:

- **Swiss / International Typographic Style.** Flat surfaces, one 8 px spacing unit, 1 px hairlines as
  the only ornament, hierarchy carried by type size and weight, and colour reserved for state -
  `primary` for selection and running, `danger` for destructive, `warn` and `ok` for outcomes. No
  shadows, no gradients, no icon artwork: markers are typographic until a real asset exists. Both
  palettes derive from a single `Theme.dark` flag.
- **Three swimlanes.** A header bar carries the scanner picker, scan/stop, the live progress rail, the
  theme toggle and the layout reset. Below it sit Source (paths plus schema-driven algorithm options),
  Results (the table) and Analysis (metrics, dry-run and trash toggles, delete, export). Lanes are
  drag-resizable, double-click resets to 300 px, and each collapses to a 48 px strip that shows a
  single letter.
- **Measured.** Window 1280 x 800 preferred and 940 x 560 minimum, 32 px lane headers, 6 px corners,
  Source clamped to 220..560, Analysis to 210..520, Results at least 360 wide, and the three overlays
  stacked at z 100, 200 and 300.

## Scanners

Fourteen, all of them the engine's:

duplicates · empty folders · big files · empty files · temporary files · similar images · similar
videos · same music · invalid symlinks · broken files · bad extensions · bad names · EXIF remover ·
video optimizer

## How a scan runs

<p>
  <img src="./assets/readme/dataflow.svg" width="100%" alt="Data flow diagram: the event-loop lane runs UI to Callabler to AppStore to results refresh back to the UI as a model, while the worker lane runs scan start to a czkawka_core scanner to a progress channel, crossing threads only via the spawned thread and upgrade_in_event_loop">
</p>

- `AppStore` behind an `Arc<Mutex<_>>` is the single source of truth; Slint models are projections of it.
- The table hands back a position in the **visible** model, and `store.visible` maps it to the
  canonical row - a UI index is never used to index `store.rows`.
- Selection is keyed by **path**, so it survives re-sorting and re-filtering.
- A `ModelRc` is never touched off the event loop.
- `Callabler` callbacks are registered exactly once each; `misc/find_unused_callbacks.py` fails on
  zero or duplicate registrations.

## Build

```sh
cargo build -p kisaki     # debug
just run kisaki           # debug run
just runr kisaki          # fast_release run
```

Default features are `winit_femtovg` and `winit_software`. Native-library features stay off by
default, exactly like Krokiet: `heif`, `libraw`, `libavif`, `xdg_portal_trash`. Renderer backends can
be swapped with `femtovg_wgpu`, `skia_opengl` or `skia_vulkan`.

Off is not harmless. With `heif` out, the engine leaves HEIC out of the extension list a scan
collects (`czkawka_core/src/common/image.rs`), so a folder of iPhone photos comes back looking clean.
The caption next to the version says which of the three decoders a binary was built with
(`heif+ raw- avif-`), and the bridge exposes the same facts through `codec_info()` in
`kisaki_app/rust/src/api/info.rs` - its Dart binding is still pending, so only the Slint caption shows
them today.

Requires Rust 1.94.1 or newer (edition 2024).

Before declaring any work on this crate done, run the per-package gates rather than the whole
workspace:

```sh
cargo clippy -p kisaki --all-targets -- -D warnings
python3 misc/find_unused_callbacks.py kisaki
python3 misc/find_unused_fluent_translations.py kisaki
python3 kisaki/tools/check_grid.py kisaki
```

CI adds `--all-features` to that first line, but only in the Linux job: on macOS the same command
stops inside `skia-bindings`, in its own generated `bindings.rs` (`E0425`, a missing template
parameter in a type alias it emits), with nothing in this crate involved. Run the
default-features gate locally and let the Linux job cover the feature union.

### The Flutter frontend

`kisaki_app/` talks to `czkawka_core` only through the generated `flutter_rust_bridge` surface, so
the bridge crate is built first and the bindings are regenerated whenever a bridge type changes:

```sh
cargo build -p kisaki_bridge          # the dylib the Dart loader opens
flutter_rust_bridge_codegen generate  # lives in ~/.cargo/bin, which is not on PATH by default
cd kisaki_app && flutter pub run build_runner build   # plain `dart run build_runner` cannot see flutter_test
flutter test
```

Run `flutter pub run build_runner build` without `--build-filter`: a filtered run deletes the `.g.dart`
and `.freezed.dart` files it was not asked to rebuild. The gates for this half are
`cargo test -p kisaki_bridge`, `cargo clippy -p kisaki_bridge --all-targets -- -D warnings` and
`flutter analyze`.

## Safety

Delete and export default to **dry run**, which produces a per-item plan and touches no files. Dry run
has to be turned off before anything is written, and the confirmation dialog states which mode is
active. Deletion goes through `czkawka_core`'s file operations, so "move to trash" behaves as it does
in every other Czkawka frontend.

## Not here yet

Result thumbnails and image preview, the four-mode image comparison dialog, the smart selection
assistant, the multi-dimensional filter panel (only the text filter is wired), the Simiu set mode, and
the video-optimize and EXIF execution dialogs. These are planned page-by-page additions, not gaps in
the scan engine.

## The rest of the family

| Crate | What it is | License | Docs |
|:--|:--|:--|:--|
| `czkawka_core` | scanning engine, used by every frontend | MIT | [README](czkawka_core/README.md) |
| `czkawka_cli` | command-line frontend | MIT | [README](czkawka_cli/README.md) |
| `czkawka_gui` | legacy GTK 4 frontend, maintenance only | MIT | [README](czkawka_gui/README.md) |
| `krokiet` | upstream Slint desktop frontend | GPL-3.0-only | [README](krokiet/README.md) |
| `cedinia` | Slint frontend for Android | GPL-3.0-only | [README](cedinia/README.md) |
| `kisaki` | this fork's Slint desktop frontend | GPL-3.0-only | [README](kisaki/README.md) |

## Translations

Strings use [Fluent](https://projectfluent.org/). Only `kisaki/i18n/en/kisaki.ftl` is authored by
hand; every other locale is generated and managed in Crowdin, and manual edits to non-English files
are overwritten by `just unpack_translations`. The FTL keys, the `Translations` Slint properties and
the generated `set_*` calls in `src/translations.rs` are one set - edit the `.slint` defaults and
regenerate, never hand-maintain two of the three.

## License

`czkawka_core`, `czkawka_cli` and `czkawka_gui` are MIT. `krokiet`, `cedinia` and `kisaki` are
GPL-3.0-only, because Slint requires it. Images and audio in this repository are CC BY 4.0.

## Credit

The engine and every frontend but `kisaki/` come from
[qarmin/czkawka](https://github.com/qarmin/czkawka), whose own homepage, feature list and comparison
against similar tools live upstream. Releases for the upstream project are published there; this fork
does not ship binaries.
