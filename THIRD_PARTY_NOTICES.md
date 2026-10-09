# 第三方组件与素材

本项目提供预览器自身的 Python、GDScript 和 C# 代码。游戏引擎及 Spine GDExtension 从使用者的《杀戮尖塔 2》安装目录读取。

## Godot

Godot Engine 采用 MIT 许可，许可原文保存在 [licenses/Godot.txt](licenses/Godot.txt)。[官方许可说明](https://godotengine.org/license/)介绍了引擎与用户内容的许可范围。

PCK 格式参考 [Godot 4.5 的文件读取实现](https://github.com/godotengine/godot/blob/4.5/core/io/file_access_pack.cpp)。

## Spine

Spine Runtimes 的版权归 Esoteric Software LLC 所有，许可原文保存在 [licenses/Spine-Runtimes.txt](licenses/Spine-Runtimes.txt)。运行库的使用、集成和分发适用该许可及 [Spine Editor License Agreement](https://esotericsoftware.com/spine-editor-license)。预览器自身的开源许可不替代这些条款。

接口说明见 [spine-godot 官方文档](https://esotericsoftware.com/spine-godot)。

## 7-Zip 与 .NET

7Z、RAR 的读取由本机安装的 7-Zip 提供。程序和许可由 [7-Zip 项目](https://www.7-zip.org/)提供。

程序集动画读取器使用 .NET 9 标准库。分发包包含本项目自行编译的读取器，运行环境由使用者安装的 .NET 提供。

## 游戏与 Mod 素材

《杀戮尖塔 2》的程序及素材由 Mega Crit 和相关权利人所有。导入的角色、图片、动画与声音属于其原作者或相关权利人。

仓库与公开分发包提供预览工具。用户导入的素材、预览图和本机资源报告由用户自行保存。
