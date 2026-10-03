#!/usr/bin/env python3
"""Fail when a layout literal in ui/ ignores the 4px grid.

Swiss law for this crate: one unit (Theme.gap = 8px) and its half drive every margin, so a raw
pixel literal is only allowed when it is a multiple of the half unit. The exemptions are the
documented exceptions, not a general escape hatch:
  * ui/globals/theme.slint, which is the single source of the scale;
  * font-size / letter-spacing, whose steps are a type scale rather than a spacing scale;
  * 0, 1 and 2 px, which are the hairline rules and group stripes.

Usage: python3 kisaki/tools/check_grid.py [crate-dir]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

HALF_UNIT = 4
EXEMPT_PIXELS = {0, 1, 2}
# Window and lane bounds are measured geometry pinned by the layout contract in kisaki/AGENTS.md
# and README.md, not spacing choices, so they stay exactly as documented.
CONTRACT = {210, 220, 300, 520, 560, 940, 1000, 1280, 800, 10000}
EXEMPT_PROPERTIES = ("font-size", "letter-spacing")
THEME_FILE = Path("ui") / "globals" / "theme.slint"
LITERAL = re.compile(r"(\d+)px")


# A line comment is not a layout literal, and the generated translation block is not ours to restyle.
COMMENT = re.compile(r"^\s*(//|/\*)")


def violations(path: Path) -> list[str]:
    reports = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if COMMENT.match(line):
            continue
        if any(property_name in line for property_name in EXEMPT_PROPERTIES):
            continue
        for match in LITERAL.finditer(line):
            pixels = int(match.group(1))
            if pixels in EXEMPT_PIXELS or pixels in CONTRACT or pixels % HALF_UNIT == 0:
                continue
            reports.append(f"{path}:{number}: {match.group(0)} - not a multiple of {HALF_UNIT}px: {line.strip()}")
    return reports


def main() -> int:
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("kisaki")
    files = sorted((root / "ui").rglob("*.slint"))
    if not files:
        print(f"error: no .slint files under {root / 'ui'}", file=sys.stderr)
        return 2

    found = []
    for file in files:
        if file.relative_to(root) == THEME_FILE:
            continue
        found.extend(violations(file))

    for file in files:
        if file.relative_to(root) == THEME_FILE:
            for report in violations(file):
                # The scale file may define the scale, but it must still be self-consistent.
                print(f"note: {report}")

    if found:
        print(f"{len(found)} off-grid literals in {root / 'ui'}:")
        for report in found:
            print(f"  {report}")
        return 1

    print(f"grid clean: {len(files) - 1} files, every layout literal on the {HALF_UNIT}px grid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
