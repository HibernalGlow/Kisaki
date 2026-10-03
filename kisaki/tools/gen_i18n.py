"""Regenerates kisaki/i18n/en/kisaki.ftl and the translate_items body.

Three places must stay one set: the Slint Translations global, the literal fli!("key")
calls in Rust, and the tool/column registry keys in Rust. Run from the repo root.
Throwaway dev tool - delete it when the crate is green.
"""

import pathlib
import re
import sys

ROOT = pathlib.Path("kisaki")
TRANSLATIONS_SLINT = ROOT / "ui/globals/translations.slint"
FTL = ROOT / "i18n/en/kisaki.ftl"
RUST = ROOT / "src/translations.rs"

PROPERTY = re.compile(r'^\s*in-out property <string> (\w+): "(.*)";', re.MULTILINE)
USE = re.compile(r"Translations\.(\w+)")
FLI = re.compile(r'fli!\(\s*"([^"]+)"')
REGISTRY = re.compile(r'"((?:tool_|col_|field_|option_|status_|plan_|confirm_|rust_)[a-z0-9_]+)"')

# Keys requested from Rust rather than from the Slint global. Fluent placeholders
# are written as { $count } etc.
EXTRA = {
    "rust_init_error_title": "Kisaki failed to start",
    "rust_no_included_paths": "Add at least one included directory before scanning",
    "status_scanning": "Scanning...",
    "status_stopping": "Requesting stop...",
    "status_cancelled": "Scan stopped",
    "status_stopped": "Scan stopped - results found so far are kept",
    "status_nothing_found": "Scan finished, nothing found",
    "status_found": "Found { $files } files in { $groups } groups ({ $size })",
    "status_paths_updated": "Path list updated",
    "status_nothing_selected": "Select at least one result first",
    "status_nothing_to_export": "There are no results to export",
    "status_dry_run_only": "Dry run only - no files were changed",
    "status_deleting": "Applying file operations...",
    "status_removed_all": "Removed { $count } paths",
    "status_removed_partial": "Removed { $removed } paths, { $failed } failed",
    "status_open_failed": "Cannot open { $path }: { $error }",
    "status_exported": "Results written to { $folder }",
    "status_export_failed": "Export failed: { $error }",
    "confirm_delete_title": "Delete the selected files?",
    "confirm_delete_body": "This will remove { $count } paths ({ $size }) for real.",
    "confirm_dry_run_body": "Dry run: plans { $count } paths ({ $size }) and changes nothing.",
    "plan_header": "Plan for { $count } paths ({ $size }): { $verb }",
    "plan_more": "... and { $count } more",
    "plan_files_to_trash": "move to trash",
    "plan_files_to_delete": "delete permanently",
    "plan_folders_to_trash": "move folders to trash",
    "plan_folders_to_delete": "delete folders permanently",
    "tool_duplicate_files": "Duplicate files",
    "tool_empty_folders": "Empty folders",
    "tool_big_files": "Big files",
    "tool_empty_files": "Empty files",
    "tool_temporary_files": "Temporary files",
    "tool_similar_images": "Similar images",
    "tool_similar_videos": "Similar videos",
    "tool_duplicate_music": "Same music",
    "tool_invalid_symlinks": "Invalid symlinks",
    "tool_broken_files": "Broken files",
    "tool_bad_extensions": "Bad extensions",
    "tool_bad_names": "Bad names",
    "tool_exif_remover": "EXIF remover",
    "tool_video_optimizer": "Video optimizer",
    "col_size": "Size",
    "col_modified": "Modified",
    "col_difference": "Difference",
    "col_resolution": "Resolution",
    "col_duration": "Duration",
    "col_codec": "Codec",
    "col_bitrate": "Bitrate",
    "col_title": "Title",
    "col_artist": "Artist",
    "col_year": "Year",
    "col_length": "Length",
    "col_genre": "Genre",
    "col_destination": "Destination",
    "col_error": "Error",
    "col_errors": "Errors",
    "col_current_extension": "Current extension",
    "col_proper_group": "Proper group",
    "col_proper_extension": "Proper extension",
    "col_new_name": "New name",
    "col_tags": "Tags",
    "col_info": "Info",
    "option_check_method_hash": "Hash",
    "option_check_method_size": "Size",
    "option_check_method_name": "Name",
    "option_check_method_size_and_name": "Size and name",
    "option_similarity_original": "Original",
    "option_similarity_very_high": "Very high",
    "option_similarity_high": "High",
    "option_similarity_medium": "Medium",
    "option_similarity_small": "Small",
    "option_similarity_very_small": "Very small",
    "option_similarity_minimal": "Minimal",
    "option_geometric_invariance_off": "Off",
    "option_geometric_invariance_mirror_flip": "Mirror and flip",
    "option_geometric_invariance_mirror_flip_rotate90": "Mirror, flip and rotate 90",
    "option_music_method_tags": "Tags",
    "option_music_method_fingerprint": "Fingerprint",
    "option_video_optimizer_mode_crop": "Crop",
    "option_video_optimizer_mode_transcode": "Transcode",
    "field_dup_check_method": "Checking method",
    "field_dup_hash_type": "Hash algorithm",
    "field_dup_case_sensitive_names": "Case sensitive names",
    "field_dup_ignore_hard_links": "Ignore hard links",
    "field_dup_use_prehash": "Use prehash",
    "field_dup_hash_cache_size": "Minimal cache file size - hash (KiB)",
    "field_dup_prehash_cache_size": "Minimal cache file size - prehash (KiB)",
    "field_img_similarity": "Maximum similarity",
    "field_img_hash_size": "Hash size",
    "field_img_hash_algorithm": "Hash algorithm",
    "field_img_resize_algorithm": "Resize algorithm",
    "field_img_ignore_same_size": "Ignore same size",
    "field_img_ignore_same_resolution": "Ignore same resolution",
    "field_img_geometric_invariance": "Geometric invariance",
    "field_vid_tolerance": "Similarity tolerance",
    "field_vid_ignore_same_size": "Ignore same size",
    "field_vid_skip_forward": "Skip forward (s)",
    "field_vid_hash_duration": "Hash duration (s)",
    "field_vid_letterbox_crop": "Detect letterboxing",
    "field_mus_check_type": "Comparing method",
    "field_mus_approximate": "Approximate comparison",
    "field_mus_title": "Compare title",
    "field_mus_artist": "Compare artist",
    "field_mus_bitrate": "Compare bitrate",
    "field_mus_genre": "Compare genre",
    "field_mus_year": "Compare year",
    "field_mus_length": "Compare length",
    "field_mus_max_difference": "Maximum difference",
    "field_mus_min_fragment_duration": "Minimum fragment duration (s)",
    "field_big_number_of_files": "Number of files",
    "field_big_biggest_first": "Show biggest files first",
    "field_emp_zero_byte_content": "Zero byte content",
    "field_emp_non_printable_content": "Non printable content",
    "field_temp_extension_list": "Temporary extensions",
    "field_bro_audio": "Check audio",
    "field_bro_pdf": "Check PDF",
    "field_bro_archive": "Check archives",
    "field_bro_image": "Check images",
    "field_bro_video_ffprobe": "Check videos with ffprobe",
    "field_bro_video_ffmpeg": "Check videos with ffmpeg",
    "field_bro_font": "Check fonts",
    "field_bro_markup": "Check markup",
    "field_exif_ignored_tags": "Ignored EXIF tags",
    "field_vidopt_mode": "Operation",
    "field_vidopt_excluded_codecs": "Excluded codecs",
    "field_vidopt_black_pixel_threshold": "Black pixel threshold",
    "field_vidopt_black_bar_min_percentage": "Minimum black bar percentage",
    "field_vidopt_max_samples": "Maximum samples",
    "field_vidopt_min_crop_size": "Minimum crop size",
}


def kebab(name: str) -> str:
    return name.replace("_", "-")


def collect_rust_keys() -> set[str]:
    keys: set[str] = set()
    for path in ROOT.rglob("*.rs"):
        source = path.read_text(encoding="utf-8")
        keys.update(FLI.findall(source))
        keys.update(REGISTRY.findall(source))
        keys.update(match for match in FLI.findall(source) if not match.startswith(("tool_", "col_", "field_", "option_", "status_", "plan_", "confirm_", "rust_")))
    return keys


def main() -> int:
    declared = dict(PROPERTY.findall(TRANSLATIONS_SLINT.read_text(encoding="utf-8")))

    referenced: set[str] = set()
    for path in ROOT.rglob("*.slint"):
        if path != TRANSLATIONS_SLINT:
            referenced.update(USE.findall(path.read_text(encoding="utf-8")))

    unused_globals = sorted(set(declared) - referenced)
    if unused_globals:
        print("Translations properties nobody reads (remove them from translations.slint):")
        for name in unused_globals:
            print(f"  - {name}")
        return 1

    rust_keys = collect_rust_keys()
    global_keys = {kebab(name) for name in declared}
    # translate_items() requests the global keys as literals, so they are already
    # covered by the values declared in translations.slint.
    missing_values = sorted(key for key in rust_keys if key not in EXTRA and key not in global_keys)
    if missing_values:
        print("Rust requests these keys but no English value exists (add to EXTRA):")
        for key in missing_values:
            print(f"  - {key}")
        return 1

    # Only emit Rust keys that are genuinely requested, so the unused-translation
    # gate cannot trip over a stale entry.
    used_extra = sorted(key for key in rust_keys if key in EXTRA)
    stale = sorted(set(EXTRA) - rust_keys)
    if stale:
        print(f"note: dropping {len(stale)} unused EXTRA entries: {', '.join(stale)}")

    FTL.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Kisaki English strings.",
        "# The block below mirrors ui/globals/translations.slint; the rest are Rust-only keys.",
        "# Only i18n/en/kisaki.ftl is authored by hand - other locales come from Crowdin.",
        "",
    ]
    lines += [f"{kebab(name)} = {value(declared[name])}" for name in sorted(declared)]
    lines.append("")
    lines += [f"{key} = {value(EXTRA[key])}" for key in used_extra]
    FTL.write_text("\n".join(lines) + "\n", encoding="utf-8")

    setters = [f'    translation.set_{name}(fli!("{kebab(name)}").into());' for name in sorted(declared)]
    body = ["    let translation = app.global::<Translations>();"] + setters

    rust = RUST.read_text(encoding="utf-8")
    start = "// BEGIN GENERATED TRANSLATIONS"
    end = "// END GENERATED TRANSLATIONS"
    if start not in rust or end not in rust:
        print("translations.rs is missing the generated markers")
        return 1
    head, rest = rust.split(start, 1)
    _old, tail = rest.split(end, 1)
    if "Translations" not in head:
        patched = head.replace(
            "use crate::{AppState, MainWindow, ToolId, fli};",
            "use crate::{AppState, MainWindow, ToolId, Translations, fli};",
            1,
        )
        if "Translations" not in patched:
            print("could not add the Translations import - fix the use line in translations.rs by hand")
            return 1
        head = patched
    block = f"{start}\nfn translate_items(app: &MainWindow) {{\n" + "\n".join(body) + f"\n}}\n{end}"
    RUST.write_text(head + block + tail, encoding="utf-8")

    print(f"wrote {FTL}: {len(declared)} global keys + {len(used_extra)} rust keys; translate_items has {len(declared)} setters")
    return 0


def value(text: str) -> str:
    """Fluent message values are bare text, not quoted strings (see upstream
    krokiet/i18n/en/krokiet.ftl), so `{ $count }` stays a real placeable."""
    return text.replace("\\", "").replace('"', "")


if __name__ == "__main__":
    sys.exit(main())
