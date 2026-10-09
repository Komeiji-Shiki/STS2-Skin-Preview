# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Komeiji-Shiki and contributors

"""启动独立预览项目，复用本机杀戮尖塔 2 的引擎和 Spine 组件。"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from archives import ARCHIVE_SUFFIXES, import_archive, is_archive
from pck import make_catalog, write_pack

ROOT = Path(__file__).resolve().parent
SETTINGS = ROOT / "settings.json"


def select_path(title: str, folder: bool, initial: str = "") -> str:
    import tkinter as tk
    from tkinter import filedialog
    window = tk.Tk()
    window.withdraw()
    window.attributes("-topmost", True)
    options = {"title": title, "initialdir": initial or str(ROOT), "parent": window}
    result = filedialog.askdirectory(**options) if folder else filedialog.askopenfilename(
        **options, filetypes=[
            ("Mod 文件与压缩包", tuple(["*.pck", *["*" + suffix for suffix in ARCHIVE_SUFFIXES]])),
            ("Godot Mod 资源包", "*.pck"), ("ZIP 压缩包", "*.zip"),
            ("7Z 压缩包", "*.7z"), ("RAR 压缩包", "*.rar"),
        ]
    )
    window.destroy()
    return result


def choose_archive_entry(archive: Path, packs: list[str]) -> str | None:
    import tkinter as tk
    window = tk.Tk()
    window.title("选择压缩包内的角色 Mod")
    window.geometry("820x420")
    window.configure(bg="#141b21")
    window.attributes("-topmost", True)
    selected = None
    tk.Label(window, text=archive.name, bg="#141b21", fg="#ee775d",
             font=("Microsoft YaHei UI", 13), anchor="w").pack(fill="x", padx=18, pady=(18, 8))
    tk.Label(window, text=f"找到 {len(packs)} 个 PCK，请选择要预览的角色皮肤。",
             bg="#141b21", fg="#d4dde3", anchor="w").pack(fill="x", padx=18, pady=(0, 12))
    frame = tk.Frame(window, bg="#141b21")
    frame.pack(fill="both", expand=True, padx=18)
    listing = tk.Listbox(frame, bg="#10161c", fg="#d4dde3", selectbackground="#643c33",
                         selectforeground="#ffffff", font=("Microsoft YaHei UI", 11),
                         activestyle="none", highlightthickness=0, relief="flat", exportselection=False)
    vertical = tk.Scrollbar(frame, orient="vertical", command=listing.yview)
    horizontal = tk.Scrollbar(frame, orient="horizontal", command=listing.xview)
    listing.configure(yscrollcommand=vertical.set, xscrollcommand=horizontal.set)
    frame.rowconfigure(0, weight=1)
    frame.columnconfigure(0, weight=1)
    listing.grid(row=0, column=0, sticky="nsew")
    vertical.grid(row=0, column=1, sticky="ns")
    horizontal.grid(row=1, column=0, sticky="ew")
    for name in packs:
        listing.insert("end", name)
    listing.selection_set(0)
    listing.focus_set()

    def submit(_event=None):
        nonlocal selected
        selection = listing.curselection()
        if selection:
            selected = packs[selection[0]]
            window.destroy()

    buttons = tk.Frame(window, bg="#141b21")
    buttons.pack(fill="x", padx=18, pady=18)
    tk.Button(buttons, text="打开选中的皮肤", command=submit, bg="#7e473a", fg="white",
              activebackground="#9b5949", activeforeground="white", relief="flat", padx=18, pady=8).pack(side="right")
    tk.Button(buttons, text="取消", command=window.destroy, bg="#273039", fg="white",
              relief="flat", padx=18, pady=8).pack(side="right", padx=12)
    listing.bind("<Double-Button-1>", submit)
    window.bind("<Return>", submit)
    window.bind("<Escape>", lambda _event: window.destroy())
    window.mainloop()
    return selected


def resolve_mod(value: str, runtime: Path, archive_entry: str | None = None) -> tuple[Path, Path, str]:
    path = Path(value).expanduser().resolve()
    if path.is_dir():
        packs = sorted(path.glob("*.pck"))
        if not packs:
            raise ValueError("所选目录中没有 .pck 文件。")
        if len(packs) == 1:
            path = packs[0]
        else:
            chosen = select_path("目录中有多个资源包，请选择要预览的 PCK", False, str(path))
            if not chosen:
                raise InterruptedError
            path = Path(chosen).resolve()
    if path.is_file() and is_archive(path):
        pack, entry = import_archive(path, runtime, lambda packs: choose_archive_entry(path, packs), archive_entry)
        return pack, path, entry
    if not path.is_file() or path.suffix.lower() != ".pck":
        raise ValueError(f"请选择 PCK、Mod 文件夹或支持的压缩包：{path}")
    return path, path, ""


def build_viewer(game_dir: Path, runtime: Path) -> Path:
    files = {"res://project.godot": (ROOT / "viewer" / "project.godot").read_bytes()}
    for source in sorted((ROOT / "viewer").glob("*.gd")):
        files[f"res://_graywill_preview/{source.name}"] = source.read_bytes()
    extension = (
        '[configuration]\nentry_symbol="spine_godot_library_init"\ncompatibility_minimum="4.1"\n'
        '\n[libraries]\nwindows.x86_64=' + json.dumps(
            (game_dir / "libspine_godot.windows.template_release.x86_64.dll").as_posix(),
            ensure_ascii=False,
        ) + "\n"
    )
    files["res://_graywill_preview/spine.gdextension"] = extension.encode("utf-8")
    files["res://.godot/extension_list.cfg"] = b"res://_graywill_preview/spine.gdextension\n"
    files["res://.godot/global_script_class_cache.cfg"] = b"list=[]\n"
    digest = hashlib.sha256()
    for name, data in files.items():
        digest.update(name.encode("utf-8") + b"\0" + data)
    pack = runtime / f"viewer-{digest.hexdigest()[:16]}.pck"
    if not pack.exists():
        write_pack(pack, files)
    return pack


def main() -> int:
    parser = argparse.ArgumentParser(description="杀戮尖塔 2 角色皮肤预览器")
    parser.add_argument("path", nargs="?", help="Mod 文件夹、PCK 或压缩包，可拖到启动脚本上")
    parser.add_argument("--mod", help="Mod 文件夹、PCK 或 ZIP/7Z/RAR/TAR 压缩包")
    parser.add_argument("--archive-entry", help="指定压缩包内的 PCK 路径")
    parser.add_argument("--category", choices=("all", "animations", "images"), default="all", help="限定查看或批量导出的资源类别")
    parser.add_argument("--game", help="游戏安装目录")
    parser.add_argument("--choose", action="store_true", help="选择其他 Mod")
    parser.add_argument("--inspect", metavar="REPORT", help="输出实际资源和动画信息后退出")
    parser.add_argument("--capture", metavar="PNG", help="保存预览器窗口截图后退出")
    parser.add_argument("--capture-all", metavar="DIRECTORY", help="保存各场景的透明预览和资源报告后退出")
    args = parser.parse_args()
    settings = json.loads(SETTINGS.read_text(encoding="utf-8-sig")) if SETTINGS.exists() else {}
    game_value = args.game or settings.get("game_dir", "")
    if not game_value or not (Path(game_value) / "SlayTheSpire2.exe").is_file():
        game_value = select_path("选择杀戮尖塔 2 的游戏安装目录", True, game_value)
        if not game_value:
            return 0
    game_dir = Path(game_value).resolve()
    for filename in ("SlayTheSpire2.exe", "SlayTheSpire2.pck", "libspine_godot.windows.template_release.x86_64.dll"):
        if not (game_dir / filename).is_file():
            raise ValueError(f"游戏目录缺少 {filename}：{game_dir}")
    mod_value = args.mod or args.path or settings.get("last_mod", "")
    archive_entry = args.archive_entry
    if not args.choose and not args.mod and not args.path and not archive_entry:
        archive_entry = settings.get("archive_entry")
    if args.choose or not mod_value or not Path(mod_value).exists():
        archive_entry = args.archive_entry
        mod_value = select_path("选择角色皮肤 Mod 文件或压缩包", False, str(game_dir / "mods"))
        if not mod_value:
            return 0
    runtime = ROOT / ".runtime"
    runtime.mkdir(exist_ok=True)
    mod_path, source_path, selected_entry = resolve_mod(mod_value, runtime, archive_entry)
    catalog = make_catalog(mod_path, game_dir)
    catalog.update({"source_path": str(source_path), "archive_entry": selected_entry})
    if args.category != "all":
        catalog["assets"] = [asset for asset in catalog["assets"] if
                             (asset["kind"] != "image") == (args.category == "animations")]
        if not catalog["assets"]:
            raise ValueError("这个 Mod 没有找到所选类别的资源。")
    pack = build_viewer(game_dir, runtime)
    session_name = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    session = runtime / session_name
    session.mkdir()
    catalog.update({
        "tool_dir": str(ROOT), "python": sys.executable, "launcher": str(ROOT / "launcher.py"),
        "session_dir": str(session),
    })
    catalog_path = session / "catalog.json"
    catalog_path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2), encoding="utf-8")
    SETTINGS.write_text(json.dumps({"game_dir": str(game_dir), "last_mod": str(source_path),
                                   "archive_entry": selected_entry},
                                   ensure_ascii=False, indent=2), encoding="utf-8")
    command = [
        str(game_dir / "SlayTheSpire2.exe"), "--main-pack", str(pack),
        "--script", "res://_graywill_preview/main.gd", "--log-file", str(session / "viewer.log"),
        "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy", "--max-fps", "60",
    ]
    if args.inspect:
        command.append("--headless")
    command.extend(["--", "--catalog", str(catalog_path)])
    for flag, value in (("--inspect", args.inspect), ("--capture", args.capture), ("--capture-all", args.capture_all)):
        if value:
            target = Path(value).resolve()
            (target if flag == "--capture-all" else target.parent).mkdir(parents=True, exist_ok=True)
            command.extend([flag, str(target)])
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    with (session / "console.log").open("wb") as log:
        child = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=log, creationflags=flags)
    print(f"预览器已启动，PID {child.pid}。")
    print(f"运行记录：{session}")
    if args.inspect or args.capture or args.capture_all:
        result = child.wait()
        expected = []
        if args.inspect:
            expected.append(Path(args.inspect).resolve())
        if args.capture:
            expected.append(Path(args.capture).resolve())
        if args.capture_all:
            expected.append(Path(args.capture_all).resolve() / "resources.json")
        if result == 0 and not all(target.is_file() for target in expected):
            print(f"预览进程没有生成所需结果，请查看：{session / 'console.log'}", file=sys.stderr)
            return 1
        return result
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except InterruptedError:
        raise SystemExit(0)
    except (OSError, ValueError, KeyError) as error:
        print(f"无法启动预览器：{error}", file=sys.stderr)
        if not sys.stdout.isatty():
            import tkinter as tk
            from tkinter import messagebox
            window = tk.Tk()
            window.withdraw()
            messagebox.showerror("皮肤预览器", str(error), parent=window)
            window.destroy()
        raise SystemExit(1)
