"""Fail when a `flutter create` brand token is living in the shipped app again.

The template writes the literal string `APP_NAME` into `macos/Runner/Base.lproj/MainMenu.xib` and
never substitutes it: creating a fresh project with this toolchain leaves all six occurrences in
place. Kisaki edits them out, so a regenerated or re-synced platform folder silently puts a foreign
name back into the menu bar, the About panel, and the window title.
"""

import sys
from pathlib import Path
from typing import Iterator, List, Tuple

TOKENS = ("APP_NAME", "com.example")
SKIPPED_DIRS = {".dart_tool", ".symlinks", "build", "ephemeral"}
TEXT_SUFFIXES = {
    ".cc",
    ".cmake",
    ".cpp",
    ".dart",
    ".entitlements",
    ".h",
    ".md",
    ".manifest",
    ".plist",
    ".rc",
    ".swift",
    ".xib",
    ".yaml",
    ".yml",
}
TEXT_NAMES = {"CMakeLists.txt"}


def text_files(app_root: Path) -> Iterator[Path]:
    for path in app_root.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIPPED_DIRS for part in path.parts):
            continue
        if path.suffix in TEXT_SUFFIXES or path.name in TEXT_NAMES:
            yield path


def hits_for(path: Path) -> List[str]:
    content = path.read_text(encoding="utf-8", errors="ignore")
    return [token for token in TOKENS if token in content]


def main() -> int:
    app_root = Path(__file__).resolve().parent.parent / "kisaki_app"
    if not app_root.is_dir():
        print(f"Error: {app_root} is not a directory")
        return 1

    # A check that scanned nothing would report success forever, which is the failure mode this
    # script exists to catch.
    scanned = list(text_files(app_root))
    if not scanned:
        print(f"Error: found no text files under {app_root}")
        return 1

    found: List[Tuple[Path, List[str]]] = []
    for path in scanned:
        tokens = hits_for(path)
        if tokens:
            found.append((path, tokens))

    if found:
        print(f"Template brand tokens in {len(found)} of {len(scanned)} scanned files:")
        for path, tokens in found:
            print(f"  {path.relative_to(app_root.parent)}: {', '.join(tokens)}")
        return 1

    print(f"No template brand tokens in {len(scanned)} scanned files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
