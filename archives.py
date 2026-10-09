# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Komeiji-Shiki and contributors

"""读取压缩包目录，提取选中的 PCK 和对应的描述及动画定义程序集。"""

from __future__ import annotations

import os
import shutil
import subprocess
import tarfile
import tempfile
import zipfile
from pathlib import Path
from typing import Callable

ARCHIVE_SUFFIXES = (
    ".zip", ".7z", ".rar", ".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tbz2", ".tar.xz", ".txz",
)
TAR_SUFFIXES = (".tar", ".tar.gz", ".tgz", ".tar.bz2", ".tbz2", ".tar.xz", ".txz")


def is_archive(path: Path) -> bool:
    return path.name.lower().endswith(ARCHIVE_SUFFIXES)


def find_7zip() -> str:
    candidates = [shutil.which("7z"), shutil.which("7zz")]
    for variable in ("ProgramFiles", "ProgramFiles(x86)"):
        directory = os.environ.get(variable)
        if directory:
            candidates.append(str(Path(directory) / "7-Zip" / "7z.exe"))
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return candidate
    raise ValueError("打开 7Z 或 RAR 需要本机安装 7-Zip，并将 7z 加入 PATH 或安装到默认目录。")


def check_7zip_result(result: subprocess.CompletedProcess, *, listing: bool = False) -> None:
    if result.returncode == 0:
        return
    detail = result.stderr.decode("utf-8", errors="replace").strip()
    if listing:
        detail = (detail + "\n" + result.stdout.decode("utf-8", errors="replace")).strip()
    if any(word in detail.lower() for word in ("password", "encrypted")):
        raise ValueError("压缩包需要密码，请先解密后再打开。")
    raise ValueError(f"无法读取压缩包：{detail[-1200:] or '7-Zip 返回错误'}")


class ModArchive:
    def __init__(self, path: Path):
        self.path = path
        self.handle = None
        self.members: dict[str, object] = {}
        self.binary = ""
        self.kind = "zip" if path.suffix.lower() == ".zip" else (
            "tar" if path.name.lower().endswith(TAR_SUFFIXES) else "7zip"
        )

    def __enter__(self):
        try:
            if self.kind == "zip":
                self.handle = zipfile.ZipFile(self.path)
                for member in self.handle.infolist():
                    if not member.is_dir():
                        self._add_member(member.filename, member)
            elif self.kind == "tar":
                self.handle = tarfile.open(self.path, "r:*")
                for member in self.handle.getmembers():
                    if member.isfile():
                        self._add_member(member.name, member)
            else:
                self.binary = find_7zip()
                result = subprocess.run(
                    [self.binary, "l", "-slt", "-sccUTF-8", "--", str(self.path)],
                    stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
                )
                check_7zip_result(result, listing=True)
                # 技术列表的分隔线前是压缩包信息，分隔线后才是文件条目。
                body = result.stdout.decode("utf-8").partition("----------")[2]
                fields = {}
                for line in [*body.splitlines(), ""]:
                    if not line.strip():
                        name = fields.get("Path")
                        directory = fields.get("Folder") == "+" or fields.get("Attributes", "").startswith("D")
                        if name and not directory:
                            self._add_member(name, fields)
                        fields = {}
                    elif " = " in line:
                        key, value = line.split(" = ", 1)
                        fields[key] = value
            return self
        except (zipfile.BadZipFile, tarfile.TarError) as error:
            self.close()
            raise ValueError(f"压缩包无法读取或已经损坏：{error}") from error
        except Exception:
            self.close()
            raise

    def _add_member(self, name: str, member: object) -> None:
        # 统一分隔符便于查找同目录的 JSON，读取时仍使用原始条目对象。
        normalized = name.replace("\\", "/")
        if normalized in self.members:
            raise ValueError(f"压缩包中存在重名文件，无法确定要读取的条目：{normalized}")
        self.members[normalized] = member

    def copy_to(self, name: str, target: Path) -> None:
        member = self.members[name]
        try:
            if self.kind == "zip":
                if member.flag_bits & 1:
                    raise ValueError("压缩包需要密码，请先解密后再打开。")
                with self.handle.open(member) as source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)
            elif self.kind == "tar":
                with self.handle.extractfile(member) as source, target.open("wb") as output:
                    shutil.copyfileobj(source, output)
            else:
                if member.get("Encrypted") == "+":
                    raise ValueError("压缩包需要密码，请先解密后再打开。")
                # 输出重定向到工具指定的文件，压缩包内的路径不会被用于写入磁盘。
                with target.open("wb") as output:
                    result = subprocess.run(
                        [self.binary, "e", "-so", "-spd", "-y", "-sccUTF-8", "--",
                         str(self.path), member["Path"]],
                        stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.PIPE,
                        creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
                    )
                check_7zip_result(result)
        except (zipfile.BadZipFile, tarfile.TarError, NotImplementedError, RuntimeError) as error:
            raise ValueError(f"无法提取压缩包内的 {name}：{error}") from error

    def close(self):
        if self.handle is not None:
            self.handle.close()

    def __exit__(self, *_args):
        self.close()


def import_archive(
    path: Path, runtime: Path, choose: Callable[[list[str]], str | None], entry: str | None = None,
) -> tuple[Path, str]:
    with ModArchive(path) as archive:
        packs = sorted(name for name in archive.members if name.lower().endswith(".pck"))
        if not packs:
            raise ValueError("这份压缩包中没有找到 .pck 资源包。")
        if entry:
            selected = entry.replace("\\", "/")
            if selected not in packs:
                raise ValueError(f"压缩包中找不到之前选择的 PCK：{selected}")
        elif len(packs) == 1:
            selected = packs[0]
        else:
            selected = choose(packs)
            if selected is None:
                raise InterruptedError
            if selected not in packs:
                raise ValueError("所选 PCK 不在当前压缩包中。")
        imports = runtime / "imports"
        imports.mkdir(parents=True, exist_ok=True)
        folder = Path(tempfile.mkdtemp(prefix="mod-", dir=imports))
        # 固定输出文件名，使 PCK 和 JSON 保持配对，也避免包内路径影响输出位置。
        pack_path = folder / "mod.pck"
        archive.copy_to(selected, pack_path)
        for suffix in (".json", ".dll"):
            companion_name = selected[:-4] + suffix
            matches = [name for name in archive.members if name.casefold() == companion_name.casefold()]
            if len(matches) == 1:
                archive.copy_to(matches[0], folder / ("mod" + suffix))
        return pack_path, selected
