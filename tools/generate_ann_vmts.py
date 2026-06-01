#!/usr/bin/env python3
"""Generate annunciator VMT files for VTF textures."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Optional


VARIANTS = {
    "": {"frame": 0, "framerate": None},
    "1": {"frame": 0, "framerate": 4},
    "2": {"frame": 1, "framerate": None},
    "3": {"frame": 0, "framerate": 1},
}


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def material_path(texture: Path, materials_dir: Path) -> str:
    relative = texture.with_suffix("").relative_to(materials_dir)
    return relative.as_posix()


def render_vmt(base_texture: str, frame: int, framerate: Optional[int]) -> str:
    lines = [
        "UnlitGeneric",
        "{",
        f'    "$basetexture" "{base_texture}"',
        f'    "$frame" "{frame}"',
    ]

    if framerate is not None:
        lines.extend(
            [
                "",
                '    "Proxies"',
                "    {",
                '        "AnimatedTexture"',
                "        {",
                '            "animatedtexturevar" "$basetexture"',
                '            "animatedtextureframenumvar" "$frame"',
                f'            "animatedtextureframerate" "{framerate}"',
                "        }",
                "    }",
            ]
        )

    lines.append("}")
    return "\n".join(lines) + "\n"


def generate(directory: Path, materials_dir: Path, force: bool, dry_run: bool) -> tuple[int, int]:
    created = 0
    skipped = 0

    for texture in sorted(directory.glob("*.vtf")):
        base_texture = material_path(texture, materials_dir)
        for suffix, variant in VARIANTS.items():
            output = texture.with_name(f"{texture.stem}{suffix}.vmt")
            if output.exists() and not force:
                skipped += 1
                continue

            created += 1
            print(f"{'would write' if dry_run else 'write'} {output}")
            if not dry_run:
                output.write_text(render_vmt(base_texture, variant["frame"], variant["framerate"]), encoding="utf-8")

    return created, skipped


def main() -> int:
    root = repo_root()
    parser = argparse.ArgumentParser(description="Generate standard annunciator VMT files for each VTF texture.")
    parser.add_argument(
        "directory",
        nargs="?",
        default=root / "materials" / "models" / "luasquare" / "ann",
        type=Path,
        help="Directory containing annunciator .vtf files.",
    )
    parser.add_argument("--force", action="store_true", help="Overwrite existing .vmt files.")
    parser.add_argument("--dry-run", action="store_true", help="Print files that would be written without writing them.")
    args = parser.parse_args()

    directory = args.directory.resolve()
    materials_dir = (root / "materials").resolve()
    if not directory.is_dir():
        parser.error(f"directory does not exist: {directory}")
    if materials_dir not in directory.parents and directory != materials_dir:
        parser.error(f"directory must be inside {materials_dir}")

    created, skipped = generate(directory, materials_dir, args.force, args.dry_run)
    print(f"{'would create' if args.dry_run else 'created'} {created}, skipped {skipped}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
