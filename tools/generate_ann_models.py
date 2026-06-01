#!/usr/bin/env python3
"""Compile annunciator indicator models for VTF textures that are missing MDLs."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Optional


QC_NAME = "annui16x8_src.qc"
SMD_NAME = "annui16x8_src.smd"
SHARED_QCI_NAME = "annui16x8_src_shared.qci"
PHYS_SMD_NAME = "annui16x8_src_phys.smd"
MODEL_EXTENSIONS = (".mdl", ".dx80.vtx", ".dx90.vtx", ".phy", ".vvd")


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def replace_qc(source: str, name: str) -> str:
    lines = source.splitlines()
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("$definevariable NAME"):
            lines[index] = f'$definevariable NAME "{name}"'
        elif stripped.startswith("$modelname"):
            lines[index] = f'$modelname "luasquare/ann/{name}"'
    return "\n".join(lines) + "\n"


def replace_smd(source: str, name: str) -> str:
    lines = source.splitlines()
    for index, line in enumerate(lines):
        if line.strip() and " " not in line and line.strip() not in {"version", "nodes", "end", "skeleton", "time", "triangles"}:
            lines[index] = name
    return "\n".join(lines) + "\n"


def missing_model_names(materials_dir: Path, models_dir: Path, force: bool) -> list[str]:
    names = []
    for texture in sorted(materials_dir.glob("*.vtf")):
        model = models_dir / f"{texture.stem}.mdl"
        if force or not model.exists():
            names.append(texture.stem)
    return names


def copy_sources(src_dir: Path, tmp_dir: Path, name: str) -> Path:
    (tmp_dir / QC_NAME).write_text(replace_qc((src_dir / QC_NAME).read_text(encoding="utf-8"), name), encoding="utf-8")
    (tmp_dir / SMD_NAME).write_text(replace_smd((src_dir / SMD_NAME).read_text(encoding="utf-8"), name), encoding="utf-8")
    shutil.copy2(src_dir / SHARED_QCI_NAME, tmp_dir / SHARED_QCI_NAME)
    shutil.copy2(src_dir / PHYS_SMD_NAME, tmp_dir / PHYS_SMD_NAME)
    return tmp_dir / QC_NAME


def remove_existing_outputs(models_dir: Path, name: str) -> None:
    for extension in MODEL_EXTENSIONS:
        path = models_dir / f"{name}{extension}"
        if path.exists():
            path.unlink()


def write_gameinfo(game_dir: Path) -> None:
    game_dir.mkdir(parents=True, exist_ok=True)
    (game_dir / "gameinfo.txt").write_text(
        "\n".join(
            [
                '"GameInfo"',
                "{",
                '    game "Luasquare Model Compile"',
                '    FileSystem',
                "    {",
                '        SearchPaths',
                "        {",
                '            Game "."',
                "        }",
                "    }",
                "}",
                "",
            ]
        ),
        encoding="utf-8",
    )


def copy_outputs(game_dir: Path, models_dir: Path, name: str) -> None:
    output_dir = game_dir / "models" / "luasquare" / "ann"
    missing = []
    for extension in MODEL_EXTENSIONS:
        source = output_dir / f"{name}{extension}"
        if not source.exists():
            missing.append(source.name)
            continue
        shutil.copy2(source, models_dir / source.name)

    if missing:
        raise RuntimeError(f"studiomdl did not produce expected output(s) for {name}: {', '.join(missing)}")


def compile_model(studiomdl: Path, game_dir: Optional[Path], src_dir: Path, models_dir: Path, name: str, force: bool, dry_run: bool) -> None:
    game_preview = str(game_dir) if game_dir else "<temporary-gameinfo>"
    qc_preview = str(src_dir / QC_NAME) if dry_run else "<temporary-qc>"
    command_preview = [str(studiomdl), "-game", game_preview, qc_preview]
    if dry_run:
        print("would compile " + name + ": " + " ".join(f'"{part}"' if " " in part else part for part in command_preview))
        return

    with tempfile.TemporaryDirectory(prefix=f"ann_{name}_") as temp_name:
        temp_root = Path(temp_name)
        temp_src = temp_root / "src"
        temp_game = game_dir or (temp_root / "game")
        temp_src.mkdir(parents=True, exist_ok=True)
        if game_dir is None:
            write_gameinfo(temp_game)
        qc_path = copy_sources(src_dir, temp_src, name)
        if force:
            remove_existing_outputs(models_dir, name)

        command = [str(studiomdl), "-game", str(temp_game), str(qc_path)]
        print("compile " + name)
        result = subprocess.run(command, cwd=str(temp_src), text=True, capture_output=True)
        if result.stdout:
            print(result.stdout, end="")
        if result.stderr:
            print(result.stderr, end="")
        if result.returncode != 0:
            raise RuntimeError(f"studiomdl failed for {name} with exit code {result.returncode}")
        copy_outputs(temp_game, models_dir, name)


def main() -> int:
    root = repo_root()
    default_studiomdl = root.parents[2] / "bin" / "studiomdl.exe"
    parser = argparse.ArgumentParser(description="Compile annunciator models for VTF textures missing MDLs.")
    parser.add_argument("--studiomdl", type=Path, default=default_studiomdl, help="Path to studiomdl.exe.")
    parser.add_argument("--game", type=Path, help="Existing game path passed to studiomdl -game. Defaults to a temporary mini game folder.")
    parser.add_argument("--materials-dir", type=Path, default=root / "materials" / "models" / "luasquare" / "ann")
    parser.add_argument("--models-dir", type=Path, default=root / "models" / "luasquare" / "ann")
    parser.add_argument("--source-dir", type=Path, default=root / "models" / "luasquare")
    parser.add_argument("--force", action="store_true", help="Compile all textures and replace existing model outputs.")
    parser.add_argument("--dry-run", action="store_true", help="Print compile commands without compiling.")
    args = parser.parse_args()

    studiomdl = args.studiomdl.resolve()
    game_dir = args.game.resolve() if args.game else None
    materials_dir = args.materials_dir.resolve()
    models_dir = args.models_dir.resolve()
    source_dir = args.source_dir.resolve()

    if not studiomdl.exists():
        parser.error(f"studiomdl not found: {studiomdl}")
    for path in (materials_dir, models_dir, source_dir):
        if not path.exists():
            parser.error(f"path does not exist: {path}")
    if game_dir and not game_dir.exists():
        parser.error(f"game path does not exist: {game_dir}")

    names = missing_model_names(materials_dir, models_dir, args.force)
    if not names:
        print("all annunciator models are already present")
        return 0

    for name in names:
        compile_model(studiomdl, game_dir, source_dir, models_dir, name, args.force, args.dry_run)

    print(f"{'would compile' if args.dry_run else 'compiled'} {len(names)} model(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
