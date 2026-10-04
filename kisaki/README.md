# Kisaki

Kisaki is a modern desktop frontend for the [Czkawka](https://github.com/qarmin/czkawka) cleaning
engine. It is a third-party fork addition: `czkawka_core` keeps doing all the scanning, and Kisaki
only provides the interface.

```text
czkawka_core  ──>  krokiet   (official Slint GUI)
              └──>  kisaki    (this crate)
```

Kisaki deliberately does not reuse Krokiet's UI. Its Rust side mirrors Krokiet's mechanisms - a
worker thread per scan, a `crossbeam` progress channel, an `Arc<AtomicBool>` stop flag and all Slint
mutation pushed back through `upgrade_in_event_loop` - but the layout, navigation, result table,
progress display, file-operation surface and theming are Kisaki's own.

## Build

```sh
cargo build -p kisaki            # debug
just runr kisaki                 # fast_release
just run kisaki                  # debug run
```

Default features are `winit_femtovg` and `winit_software`. Optional native-library features are
off by default, exactly like Krokiet: `heif`, `libraw`, `libavif`, `xdg_portal_trash`. Renderer
backends can be selected with `femtovg_wgpu`, `skia_opengl`, `skia_vulkan`.

## Design language

Two decisions define the look, and both are load-bearing:

1. **Swiss / International Typographic Style.** Flat surfaces, a strict grid, hairline rules as the
   only ornament, hierarchy carried by type size and weight rather than colour, and an accent colour
   reserved for state (selection, running, destructive). No shadows, no gradients, no icon artwork -
   markers are typographic until a real asset exists.
2. **Three-lane swimlane board.** A header bar carries the scanner picker, the scan/stop action and
   the live progress rail; below it sit the Source lane (paths + per-tool algorithm options), the
   Results lane (the table) and the Analysis lane (metrics + file operations). Lanes collapse to a
   48px strip and are drag-resizable, double-click to reset.

The lane structure comes from the design the user prototyped in the `xiranite` czkawka node; the
typographic treatment comes from the Swiss style. Both dark and light palettes are derived from a
single `Theme.dark` flag in `ui/globals/theme.slint`.

## Layout

```text
kisaki/
├── build.rs              # compiles ui/main_window.slint
├── i18n/en/kisaki.ftl    # English strings, only this file is hand-edited
├── ui/
│   ├── main_window.slint # window, lane board, overlays, keyboard focus
│   ├── globals/          # common.slint, theme.slint, app_state.slint, callabler.slint, translations.slint
│   ├── components/       # atoms.slint (buttons, toggles, badges), lane.slint (swimlane chrome, progress)
│   └── screens/          # header_bar, source_lane, results_lane, analysis_lane
└── src/
    ├── main.rs           # bootstrap order, window creation, run loop
    ├── callbacks.rs      # every Callabler registration
    ├── scan.rs           # worker thread, common settings, ScanCtx and Outcome
    │   ├── scan_grouped.rs # duplicate / similar images / similar videos / music
    │   └── scan_flat.rs    # the other ten tools
    ├── results.rs        # filter, sort, metrics, model building
    ├── state.rs          # AppStore + SharedModels, the thread-safe source of truth
    ├── tools.rs          # 14-tool registry, column specs, option schemas
    ├── fields.rs         # per-tool option ids, defaults, enum mapping
    ├── paths.rs          # included / excluded / reference lists, rfd pickers
    ├── actions.rs        # delete, trash, dry run, export, open
    ├── settings.rs       # kisaki_settings.json
    ├── build_info.rs     # compiled-in codecs shown in the caption, runtime probes
    ├── common.rs         # byte, timestamp and sort-key formatting
    ├── progress.rs       # progress channel receiver
    ├── localizer_kisaki.rs # fli! macro, plus the runtime-key lookup for table-driven labels
    └── translations.rs   # Fluent wiring, generated Translations setters
```

## Scanned tools

Duplicate files, empty folders, big files, empty files, temporary files, similar images, similar
videos, same music, invalid symlinks, broken files, bad extensions, bad names, EXIF remover and
video optimizer.

## On disk

`main()` registers the engine's folders before anything else: `set_config_cache_path("Czkawka", "Kisaki")`.
The first argument names the **cache** folder, the second the **config** one, so on macOS the settings
land in `~/Library/Application Support/pl.Qarmin.Kisaki/kisaki_settings.json` while scan caches and the
thumbnail store land in `~/Library/Caches/pl.Qarmin.Czkawka`, next to the log file - `kisaki.log`, which
`czkawka_core/src/common/logger.rs:41` puts in the cache folder under the app name given to `setup_logger`.
Both folders were read back here after real runs: the config one holds `kisaki_settings.json`, the cache
one holds `kisaki.log`, `video_thumbnails/` and a `cache_duplicates_*_120.bin`.

That asymmetry is Krokiet's own (`krokiet/src/main.rs` passes `("Czkawka", "Krokiet")`): caches are shared
by the whole Czkawka family so a scan already done by any frontend can be reused, while each frontend keeps
its own settings. Sharing stays safe because the cache format version is part of the file name
(`cache_duplicates_{algo}_{VERSION}.bin`, `czkawka_core/src/tools/duplicate/core.rs:706`), so a reader only
ever opens files whose name carries the version its own core writes. `CZKAWKA_CONFIG_PATH` and
`CZKAWKA_CACHE_PATH` override either folder. The Flutter bridge registers the same pair in its
`#[frb(init)]`, so both Kisaki frontends use these two folders.

## Safety

Delete and export default to **dry run**, which only produces a per-item plan and touches no files.
Turning dry run off is required before anything is written, and the confirmation dialog states which
mode is active. Deletion goes through `czkawka_core`'s file operations so that "move to trash" keeps
working the same way as in every other Czkawka frontend.

## What is not here yet

Thumbnails and image preview, the image comparison dialog, the smart selection assistant, the
multi-dimensional filter panel (only the text filter is wired), the Simiu set mode, and video
optimize/EXIF execution dialogs. These are planned page-by-page replacements, not gaps in the scan
engine.

## Translations

Only `i18n/en/kisaki.ftl` is edited by hand. Every other locale is generated by AI translation and
managed in Crowdin; manual edits to non-English files are overwritten by `just unpack_translations`.
