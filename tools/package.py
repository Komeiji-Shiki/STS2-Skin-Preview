# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Komeiji-Shiki and contributors

"""生成可公开分发的工具包，个人配置和导入素材保留在本机。"""

from __future__ import annotations

import argparse
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def package(output: Path) -> None:
    subprocess.run([
        "dotnet", "build", str(ROOT / "animation-reader" / "ModAnimationReader.csproj"),
        "-c", "Release", "-o", str(ROOT / "animation-reader" / "bin"), "--nologo",
    ], check=True)
    files = [
        *ROOT.glob("*.py"), *ROOT.glob("*.cmd"),
        *[ROOT / name for name in ("README.md", "LICENSE", "COPYRIGHT", "THIRD_PARTY_NOTICES.md", "settings.example.json")],
        *(ROOT / "viewer").glob("*.gd"), ROOT / "viewer" / "project.godot",
        *(ROOT / "licenses").glob("*.txt"), ROOT / "tools" / "package.py",
        ROOT / "animation-reader" / "Program.cs", ROOT / "animation-reader" / "ModAnimationReader.csproj",
    ]
    files.extend(ROOT / "animation-reader" / "bin" / name for name in (
        "ModAnimationReader.dll", "ModAnimationReader.deps.json", "ModAnimationReader.runtimeconfig.json",
    ))
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(files):
            archive.write(file, (Path("STS2-Skin-Preview") / file.relative_to(ROOT)).as_posix())
    print(f"已生成公开分发包：{output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="打包 STS2 Skin Preview")
    parser.add_argument("--output", type=Path, default=ROOT / "dist" / "STS2-Skin-Preview.zip")
    package(parser.parse_args().output.resolve())
