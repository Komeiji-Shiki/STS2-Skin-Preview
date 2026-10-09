# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Komeiji-Shiki and contributors

"""读取代码中声明的帧动画，供独立场景预览使用。"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path


def read_mod_animations(mod_path: Path) -> dict:
    assembly = mod_path.with_suffix(".dll")
    reader = Path(__file__).parent / "animation-reader" / "bin" / "ModAnimationReader.dll"
    if not assembly.exists():
        return {}
    if b"VisualFrameSequenceBuilder" not in assembly.read_bytes():
        return {}
    dotnet = shutil.which("dotnet")
    if dotnet is None:
        raise ValueError("预览代码声明的角色帧动画需要 .NET 9。请安装 .NET 9 运行时，或使用包含它的 SDK。")
    if not reader.exists():
        # 源码下载包在首次使用帧动画时生成读取器，普通皮肤预览无需这一步。
        build = subprocess.run(
            [dotnet, "build", str(reader.parent.parent / "ModAnimationReader.csproj"),
             "-c", "Release", "-o", str(reader.parent), "--nologo"],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8",
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
        if build.returncode != 0:
            detail = (build.stdout + build.stderr).strip()[-1500:]
            raise ValueError("从源码首次运行帧动画需要 .NET 9 SDK，读取模块生成失败：\n" + detail)
    result = subprocess.run(
        [dotnet, str(reader), str(assembly)], stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, encoding="utf-8",
        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
    )
    if result.returncode != 0:
        raise ValueError(f"无法读取 Mod 中的帧动画定义：{result.stderr.strip()[-1000:]}")
    return json.loads(result.stdout)
