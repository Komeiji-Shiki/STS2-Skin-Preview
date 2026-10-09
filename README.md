# STS2 Skin Preview

《杀戮尖塔 2》角色皮肤与动画的本地预览工具。

直接打开 Mod 的 PCK、文件夹或压缩包，查看 Spine 骨骼、Godot 场景、角色帧动画和图片素材。预览窗口使用本机游戏引擎渲染，提供动画选择、时间轴、变速、缩放和透明 PNG 导出。

界面采用暗色、直角和平面布局。左侧选择资源，中间查看画面，右侧调整播放与显示参数。

## 功能

| 功能 | 支持内容 |
| --- | --- |
| 文件导入 | PCK、Mod 文件夹、ZIP、7Z、RAR、TAR 及常见 TAR 压缩格式；支持拖入窗口和启动脚本 |
| 资源识别 | Spine 骨骼、Godot 场景、贴图图集、角色头像、卡牌及其他图片 |
| Spine 预览 | 动画与皮肤切换、骨骼显示；可关联只替换贴图的 Mod 与游戏骨骼 |
| 原生场景 | `.tscn`、`.scn` 和导出后的 `.remap`；播放 `AnimatedSprite2D`、`AnimationPlayer` 动画 |
| 代码帧动画 | 读取 STS2RitsuLib 明确声明的帧顺序、重复帧和逐帧时长 |
| 播放控制 | 播放、暂停、逐帧、循环、时间轴和 0.10～3.00 倍速度 |
| 画面控制 | 平移、缩放、适应窗口、水平翻转、暗色网格、浅色与绿幕背景 |
| 导出 | 当前素材的透明 PNG、批量预览图、资源及动画信息报告 |

压缩包中只有一个 PCK 时直接打开；有多个时显示列表供用户选择。工具会识别多层文件夹，并读取选中 PCK 对应的 JSON 与同名 DLL。

## 运行环境

- Windows。
- Python 3.10 或更高版本，包含 Tkinter。Python 代码使用标准库。
- 本机安装的《杀戮尖塔 2》，包含 `SlayTheSpire2.exe`、`SlayTheSpire2.pck` 和 `libspine_godot.windows.template_release.x86_64.dll`。
- 打开 7Z、RAR 时需要安装 7-Zip，并将 `7z` 加入 PATH，或安装到默认目录。
- 读取 DLL 中声明的角色帧动画时需要 .NET 9。预编译包使用 .NET 9 运行时；从源码首次运行这项功能需要 .NET 9 SDK，启动器会自动生成读取模块。

当前实际适配与验证的游戏版本是 **v0.107.1**，游戏引擎为 **4.5.1.m.12.mono.custom_build**。其他版本是否可用，取决于其资源格式及运行库接口。

## 快速开始

1. 下载项目文件并解压到一个独立目录。
2. 双击 `启动预览.cmd`。
3. 首次运行时选择游戏安装目录，再选择角色 Mod 的 PCK 或压缩包。
4. 在左侧选择角色场景或图片，在右侧选择动画并调整画面。

也可以把 PCK、压缩包或包含 PCK 的文件夹拖到预览窗口，或拖到 `启动预览.cmd` 上。`选择其他Mod.cmd` 会先显示文件选择窗口。

游戏位置和最近打开的 Mod 保存在本机 `settings.json` 中。这个文件在首次运行后自动创建，格式可参考 [settings.example.json](settings.example.json)。

## 预览与导出

- 空格切换播放与暂停。
- “下一帧”暂停并前进 1/60 秒。
- 拖动时间轴查看指定时刻，释放后恢复此前的播放状态。
- 鼠标左键或中键拖动画面，滚轮调整缩放。
- F 键或“适应窗口”重新居中。缩放百分比相对于适应窗口后的大小。
- “导出透明 PNG”保存当前可见素材，裁去透明边缘并保留 16 像素留白。

PNG 导出不包含背景网格与界面控件。默认保存到工具旁边的 `exports`，也可以在保存窗口中选择其他位置。放大到预览窗口之外的部分会被裁剪。

每次切换 Mod 都会启动新的预览进程，以清除上一份资源的挂载与缓存。运行记录和导入缓存保存在 `.runtime`。

## 支持范围

PCK 读取支持未加密、非 sparse bundle 的 Godot 格式 2、3、4，实际验证的是格式 3。Spine 骨骼按照游戏的 `skel_data` 资源命名识别；场景按照 `.tscn`、`.scn` 及其 remap 识别。

代码帧动画支持 STS2RitsuLib 的 `VisualCueSetBuilder.Sequence` 和 `VisualFrameSequenceBuilder.Frame` 常量声明，并应用到场景中的 `Visuals` 图片节点。读取器只分析程序集元数据与 IL 常量。通过任意代码动态计算的动画逻辑仍由游戏运行。

预览按素材和场景独立显示。完整游戏中的玩法状态、角色脚本、动画混合和特效触发，可能与独立预览不同。加密压缩包需要先解密。

已实际使用以下 Mod 确认资源加载、场景渲染和 PNG 导出：

| Mod | 确认结果 |
| --- | --- |
| Nekobinder 0.9.2 | 四组 Spine 场景及 14 张图片；战斗与商店各 35 个动画 |
| 邪神巫女 0.1.0 | 六个 Godot 场景；五个战斗帧动作和选人场景内的原生动画 |

这些 Mod 的素材由原作者提供。公开仓库与发行包提供预览工具，示例数据由使用者自行导入。

## 命令行

```powershell
python -X utf8 launcher.py --mod "角色皮肤.pck"
python -X utf8 launcher.py --mod "角色皮肤.zip"
python -X utf8 launcher.py --mod "皮肤合集.7z" --archive-entry "角色/Nekobinder.pck"
python -X utf8 launcher.py --game "游戏安装目录" --mod "Mod文件夹"
python -X utf8 launcher.py --inspect "resources.json"
python -X utf8 launcher.py --capture "viewer.png"
python -X utf8 launcher.py --capture-all "previews"
python -X utf8 launcher.py --mod "Mod文件夹" --category animations --capture-all "场景预览"
```

`--inspect` 输出实际加载的资源、骨骼、皮肤和动画信息；`--capture` 保存窗口截图；`--capture-all` 导出每项素材的透明 PNG 与 `resources.json`。

`--category animations` 只选择骨骼和场景，`--category images` 只选择图片；默认显示全部资源。

## 开发与打包

项目由 Python 启动器、Godot GDScript 预览界面及一个小型 .NET 数据读取器组成。

```text
launcher.py                 启动、输入选择与独立预览项目生成
pck.py                      PCK 索引、资源依赖与项目打包
archives.py                 压缩包目录读取与所选资源提取
animation_data.py           帧动画读取模块调用
animation-reader/           .NET 程序集元数据读取器源码
viewer/                     Godot 界面、场景与动画播放
tools/package.py            生成公开分发包
licenses/                   第三方许可说明
```

生成程序集读取器：

```powershell
dotnet build animation-reader/ModAnimationReader.csproj -c Release -o animation-reader/bin
```

生成包含预编译读取器的公开分发包：

```powershell
python -X utf8 tools/package.py
```

输出文件位于 `dist/STS2-Skin-Preview.zip`。打包脚本会编译读取器并收集项目自身的程序和说明，个人配置、缓存、导出图片及第三方 Mod 素材保留在本机。

## 问题反馈

请在 Issue 中说明游戏版本、Mod 名称与版本、导入格式、期望结果和实际表现。加载问题通常可在 `.runtime` 最近一次运行目录的 `console.log` 与 `viewer.log` 中找到原因。

## 许可

项目自身代码采用 **GNU Affero General Public License v3.0（AGPL-3.0-only）**，版权归 Komeiji-Shiki 与相关贡献者所有。完整许可见 [LICENSE](LICENSE)。游戏程序、Godot、Spine 与使用者导入的 Mod 素材保持各自许可，相关说明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
