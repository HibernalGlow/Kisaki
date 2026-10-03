# kisaki – Architecture Guide

Kisaki is a third-party Slint desktop frontend for `czkawka_core`. It reuses the engine and the
Rust/Slint technical route, but its UI is its own - Krokiet is a reference for *mechanisms*, not a
template for layout.

See also the root `AGENTS.md` (Rust style, `just fix`) and `krokiet/AGENTS.md` for the engine call
patterns this crate mirrors.

---

## Non-negotiable boundaries

1. **Never modify `czkawka_core` to make a UI feature easier.** If a core API is missing, work around
   it inside `kisaki/` and report the gap. `czkawka_core` is the stable boundary that keeps this fork
   rebaseable onto `upstream/master`.
2. **Keep the diff inside `kisaki/`.** Only workspace/build/registration files may be touched
   outside it, additively: root `Cargo.toml` members, `justfile`, `misc/run_checks.sh`,
   `misc/change_version.py`, `data/*.desktop`. Never reformat or restyle upstream crates - that
   destroys future rebases.
3. **Do not hand-edit non-English `.ftl`.** Only `i18n/en/kisaki.ftl` is authored here; other locales
   come from Crowdin and are overwritten by `just unpack_translations`.

---

## Visual language: Swiss / International Typographic Style

This is the product's design law. Structure comes from the three-lane board; style comes from Swiss
typography. Both are load-bearing.

- **Grid first.** One spacing unit (`Theme.gap`, 8px) and its half drive every margin. Lanes, cards
  and table rows align to it. No ad-hoc pixel values when the unit already covers the case.
- **Flat surfaces.** `Palette.bg` / `card` / `raised` / `sunken` are the only surface levels. No
  shadows, no gradients, no blur. Separation is done with 1px hairlines (`Palette.hairline`) and
  background steps.
- **Hierarchy through type, not decoration.** Size and weight carry meaning
  (`Theme.fs_caption` → `fs_metric`). Micro-headings are uppercase with letter-spacing
  (`MicroHeading`). Do not add an icon to explain something a label can say.
- **Colour is state, never ornament.** `Palette.primary` marks selection/active/running, `danger`
  marks destructive, `warn`/`ok` mark outcomes. Everything else stays neutral grey. Group identity
  uses the `chart_*` cycle plus a *printed group number* - colour is never the only signal.
- **Asymmetric, left-aligned.** Ragged-right text, left-anchored content, whitespace used as an
  active element.
- **No artwork.** Kisaki has no icon asset. Markers are typographic glyphs drawn with `Text`. Do not
  hand-draw an SVG to fill the gap; use a text button or a letter tile instead.
- **Both themes are first-class.** Every colour is derived from the single `Theme.dark` flag in
  `ui/globals/theme.slint`. Adding a hard-coded colour literal anywhere else breaks light mode.

---

## Layout contract

```
Window (min 940x560)
├── HeaderBar        scanner picker · scan/stop · progress rail · theme · reset layout
└── HorizontalBoard
    ├── Lane(Source)     tabs: Paths | Algorithm   (paths editor + schema-driven option fields)
    ├── DragHandle       clamp 220..560, double-click resets to 300
    ├── Lane(Results)    header strip · sticky column header · ListView rows · empty states
    ├── DragHandle       clamp 210..520, double-click resets to 300
    └── Lane(Analysis)   metric row · dry-run + trash toggles · delete · export
   Overlays (Window siblings, z-ordered): tool menu · confirm dialog · scan messages
```

Lanes collapse to a 48px strip. When collapsed the lane shows a single letter, not a rotated or
sliced title string - Slint has no vertical writing mode and `charAt` slicing is fragile.

---

## Slint rules that bite

- User identifiers are `snake_case`; only Slint built-ins are kebab-case (`min-width`,
  `current-index`, `placeholder-text`, `font-size`, `horizontal-alignment`, `mouse-cursor`).
  Mixing the two is the single most common failure here.
- `Text` is a built-in element - do **not** import it from `std-widgets.slint`.
- Anything beyond a few dozen rows must use `ListView`, never `ScrollView` + `for`
  (see `krokiet/AGENTS.md`).
- Font sizes must be `length`, not `int`.
- A global property cannot be bound from the window's own `width`; don't try to derive responsive
  state that way. Use `min-width` on the Window instead.

---

## Data flow

`Callabler` callbacks are registered exactly once each in `src/callbacks.rs` - the repo's
`misc/find_unused_callbacks.py` gate fails on zero or duplicate registrations.

```
UI event → Callabler → AppStore (Arc<Mutex<…>>, plain Rust, Send)
                         │
                         └→ results::refresh → VecModel<ResultRow> → AppState globals
```

- `src/state.rs` `AppStore` is the single source of truth. Slint models are projections of it.
- The table hands back a position in the **visible** model; `store.visible` maps it to a canonical
  row. Never index `store.rows` with a UI index directly.
- Selection is keyed by **path**, so it survives re-sorting and re-filtering.
- Scans run on a `thread::Builder` with `DEFAULT_THREAD_SIZE`; all Slint mutation returns via
  `Weak::upgrade_in_event_loop`. Never touch a `ModelRc` off the event loop.
- Progress arrives on a `crossbeam` channel and is rendered with `ProgressData::to_display()`; do
  not branch on the `ToolStage` enum.
- Delete and export are **dry run by default**; the plan path must not touch the filesystem, and
  deletion goes through `czkawka_core::common::fs_ops` so trash behaviour matches other frontends.

---

## Gates

Before declaring any Kisaki work done:

```
cargo build -p kisaki
cargo clippy -p kisaki --all-targets --all-features -- -D warnings
cargo test -p kisaki
cargo +nightly fmt -p kisaki && cargo fmt -p kisaki    # -p only, never --all
python3 misc/find_unused_callbacks.py kisaki
python3 misc/find_unused_slint_translations.py kisaki
python3 misc/find_unused_fluent_translations.py kisaki
python3 misc/find_unused_settings_properties.py kisaki
python3 misc/delete_unused_krokiet_slint_imports.py kisaki
```

`just fix` runs the whole workspace; prefer the per-package forms so unrelated upstream crates stay
untouched. A build reported as passing is not evidence - read the log, `build.rs` failures can be
swallowed by an exit-code-0 wrapper.

`src/translations.rs` has a `BEGIN/END GENERATED TRANSLATIONS` block: the FTL keys, the
`Translations` properties and the `set_*` calls are one set, derived from
`ui/globals/translations.slint`. Edit the `.slint` defaults and regenerate; never hand-maintain two
of the three.
