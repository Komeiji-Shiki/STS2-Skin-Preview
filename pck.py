# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Komeiji-Shiki and contributors

"""只读取 Godot PCK 的目录和资源，不向游戏目录写入文件。"""

from __future__ import annotations

import hashlib
import json
import re
import struct
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

from animation_data import read_mod_animations

@dataclass(frozen=True)
class Entry:
    offset: int
    size: int
    flags: int


class PckArchive:
    def __init__(self, path: Path):
        self.path = path
        self.entries: dict[str, Entry] = {}
        with path.open("rb") as stream:
            length = path.stat().st_size
            header = stream.read(40)
            if len(header) < 40 or header[:4] != b"GDPC":
                raise ValueError(f"不是独立的 Godot PCK 文件：{path.name}")
            _, version, major, minor, patch, flags, base = struct.unpack_from("<6IQ", header)
            self.version = version
            self.engine = f"{major}.{minor}.{patch}"
            if version not in (2, 3, 4):
                raise ValueError(f"暂不支持 PCK {version}，目前支持格式 2、3、4。")
            if flags & 1:
                raise ValueError("资源包目录已加密，无法生成预览列表。")
            if flags & 4:
                raise ValueError("暂不支持 Godot sparse bundle 资源包。")
            directory = struct.unpack_from("<Q", header, 32)[0] if version >= 3 else 96
            if directory + 4 > length:
                raise ValueError("PCK 目录超出文件范围。")
            stream.seek(directory)
            count = struct.unpack("<I", stream.read(4))[0]
            if count > (length - directory) // 40:
                raise ValueError("PCK 文件数量无效。")
            for _ in range(count):
                size_bytes = stream.read(4)
                if len(size_bytes) != 4:
                    raise ValueError("PCK 目录不完整。")
                name_length = struct.unpack("<I", size_bytes)[0]
                if name_length > 65536 or stream.tell() + name_length + 36 > length:
                    raise ValueError("PCK 资源名称长度无效。")
                name = stream.read(name_length).rstrip(b"\0").decode("utf-8")
                offset, size, _, entry_flags = struct.unpack("<QQ16sI", stream.read(36))
                if entry_flags & 2:
                    continue
                absolute = base + offset
                if absolute + size > length:
                    raise ValueError(f"资源超出 PCK 文件范围：{name}")
                self.entries[name.removeprefix("res://")] = Entry(absolute, size, entry_flags)

    def read(self, name: str) -> bytes:
        entry = self.entries[name.removeprefix("res://")]
        if entry.flags & 1:
            raise ValueError(f"资源已加密：{name}")
        with self.path.open("rb") as stream:
            stream.seek(entry.offset)
            return stream.read(entry.size)

    def profiles(self) -> set[str]:
        # 游戏各角色沿用 skel_data 命名；原始 tres 和导出的 remap 均可识别。
        return {
            name.removesuffix(".remap")
            for name in self.entries
            if "skel_data" in name and name.endswith((".tres", ".tres.remap"))
        }

    def scenes(self) -> set[str]:
        logical = {
            name.removesuffix(".remap")
            for name in self.entries
            if not name.startswith(".godot/") and name.endswith((".tscn", ".tscn.remap", ".scn", ".scn.remap"))
        }
        remapped = {name + ".remap" for name in logical if name + ".remap" in self.entries}
        targets = set()
        for name in remapped:
            match = re.search(r'path\s*=\s*"([^"]+)"', self.read(name).decode("utf-8"))
            if match:
                targets.add(match.group(1).removeprefix("res://"))
        # 没有逻辑路径的二进制场景也可直接查看，已有 remap 的场景只显示一次。
        logical.update(name for name in self.entries if name.endswith(".scn") and name not in targets)
        return logical

    def resource_dependencies(self, name: str) -> set[str]:
        source = name
        if source not in self.entries and source + ".remap" in self.entries:
            remap = self.read(source + ".remap").decode("utf-8")
            match = re.search(r'path\s*=\s*"([^"]+)"', remap)
            if not match:
                return set()
            source = match.group(1).removeprefix("res://")
        if source not in self.entries:
            return set()
        dependencies = {
            match.decode("utf-8").removeprefix("res://")
            for match in re.findall(rb'res://[^\x00\r\n"]+', self.read(source))
        }
        for atlas in list(dependencies):
            if not atlas.endswith(".atlas"):
                continue
            atlas_source = atlas
            if atlas_source not in self.entries and atlas_source + ".import" in self.entries:
                remap = self.read(atlas_source + ".import").decode("utf-8").rstrip("\0")
                match = re.search(r'path\s*=\s*"([^"]+)"', remap)
                if match:
                    atlas_source = match.group(1).removeprefix("res://")
            if atlas_source not in self.entries:
                continue
            text = self.read(atlas_source).decode("utf-8").rstrip("\0")
            if atlas_source.endswith(".spatlas"):
                text = json.loads(text)["atlas_data"]
            pages = re.findall(r'^([^:\r\n]+\.(?:png|jpg|jpeg|webp))\s*$', text, re.MULTILINE)
            dependencies.update(str(PurePosixPath(atlas).parent / page.strip()) for page in pages)
        return dependencies


SCENES = {
    "characters": "战斗",
    "character_select": "角色选择",
    "merchant": "商店",
    "rest_site": "休息处",
}
CHARACTERS = {
    "necrobinder": "亡灵契约师",
    "ironclad": "铁甲战士",
    "silent": "静默猎手",
    "regent": "储君",
    "defect": "故障机器人",
}


def profile_label(name: str) -> tuple[str, str]:
    parts = PurePosixPath(name).parts
    group = SCENES.get(parts[1], parts[1]) if len(parts) > 1 else "角色"
    character = CHARACTERS.get(parts[2], parts[2]) if len(parts) > 2 else ""
    return f"{group} · {character}", group


def scene_label(name: str) -> tuple[str, str]:
    stem = PurePosixPath(name).stem
    for suffix, label in (
        ("_character_select_bg", "角色选择"), ("_character_select", "角色选择"),
        ("_rest_site", "休息处"), ("_merchant", "商店"),
        ("_character", "战斗"), ("_energy_counter", "能量面板"), ("_icon", "角色图标"),
    ):
        if stem.endswith(suffix):
            return f"{label} · {stem.removesuffix(suffix)}", label
    return stem, "场景"


def make_catalog(mod_path: Path, game_dir: Path) -> dict:
    mod = PckArchive(mod_path)
    base = PckArchive(game_dir / "SlayTheSpire2.pck")
    mod_profiles = mod.profiles()
    profiles = set(mod_profiles)
    changed_folders = {
        str(PurePosixPath(name).parent)
        for name in mod.entries
        if name.startswith("animations/") and not name.startswith(".godot/")
    }
    changed_resources = {
        name.removesuffix(".import").removesuffix(".remap")
        for name in mod.entries if not name.startswith(".godot/")
    }
    # 根据骨骼真正依赖的图集和贴图判断关联，避免同目录的原版伙伴混入列表。
    profiles.update(
        name for name in base.profiles()
        if str(PurePosixPath(name).parent) in changed_folders
        and base.resource_dependencies(name).intersection(changed_resources)
    )
    scene_order = {name: index for index, name in enumerate(SCENES.values())}
    assets = []
    for name in sorted(profiles):
        label, group = profile_label(name)
        assets.append({
            "kind": "spine", "path": f"res://{name}", "label": label,
            "group": group, "origin": "mod" if name in mod_profiles else "game",
        })
    scenes = mod.scenes()
    frame_animations = read_mod_animations(mod_path) if scenes else {}
    for name in sorted(scenes):
        label, group = scene_label(name)
        assets.append({
            "kind": "scene", "path": f"res://{name}", "label": label,
            "group": group, "origin": "mod",
            "frame_animations": frame_animations.get(f"res://{name}", []),
        })
    assets.sort(key=lambda asset: (scene_order.get(asset["group"], 99), asset["path"]))
    images: set[str] = set()
    for name in mod.entries:
        logical = name.removesuffix(".import")
        if logical.lower().endswith((".png", ".jpg", ".jpeg", ".webp", ".svg")):
            if not name.startswith(".godot/"):
                images.add(logical)
    for name in sorted(images):
        group = "贴图图集" if name.startswith("animations/") else "界面图片"
        assets.append({
            "kind": "image", "path": f"res://{name}",
            "label": PurePosixPath(name).stem, "group": group, "origin": "mod",
        })
    if not assets:
        raise ValueError("这份资源包中没有找到角色骨骼或可预览图片。")
    metadata = {}
    metadata_error = ""
    json_path = mod_path.with_suffix(".json")
    if json_path.exists():
        try:
            value = json.loads(json_path.read_text(encoding="utf-8-sig"))
            if isinstance(value, dict):
                metadata = value
        except (ValueError, UnicodeError) as error:
            metadata_error = f"Mod 描述文件未能读取：{error}"
    for asset in assets:
        if asset["kind"] == "scene" and metadata.get("id") and metadata.get("name"):
            group, separator, character = asset["label"].partition(" · ")
            if separator and character == metadata["id"]:
                asset["label"] = f"{group} · {metadata['name']}"
    return {
        "mod_path": str(mod_path), "game_dir": str(game_dir),
        "base_pack": str(game_dir / "SlayTheSpire2.pck"),
        "metadata": metadata, "metadata_error": metadata_error,
        "pack_version": mod.version, "engine_version": mod.engine,
        "file_count": len(mod.entries), "assets": assets,
    }


def write_pack(path: Path, files: dict[str, bytes]) -> None:
    """生成仅包含预览器自身代码的 PCK，明确指定独立的启动项目。"""
    directory = bytearray(struct.pack("<I", len(files)))
    payload = bytearray()
    for name, data in files.items():
        encoded = name.encode("utf-8")
        encoded += b"\0" * (-len(encoded) % 4)
        directory += struct.pack("<I", len(encoded)) + encoded
        directory += struct.pack("<QQ16sI", len(payload), len(data), hashlib.md5(data).digest(), 0)
        payload += data + b"\0" * (-len(data) % 16)
    base = (96 + len(directory) + 15) // 16 * 16
    header = struct.pack("<6IQ", 0x43504447, 2, 4, 1, 0, 2, base) + b"\0" * 64
    path.write_bytes(header + directory + b"\0" * (base - 96 - len(directory)) + payload)
