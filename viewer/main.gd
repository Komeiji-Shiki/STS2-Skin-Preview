# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Komeiji-Shiki and contributors

extends SceneTree

var catalog: Dictionary
var options: Dictionary = {}
var ui
var visible_assets: Array = []
var current_asset: Dictionary = {}
var scrubbing = false
var was_playing = true
var fatal = false


func _initialize():
	var args = OS.get_cmdline_user_args()
	for index in range(0, args.size() - 1, 2):
		options[args[index]] = args[index + 1]
	if not options.has("--catalog"):
		printerr("缺少资源目录参数，请通过启动脚本打开预览器。")
		quit(1)
		return
	var value = JSON.parse_string(FileAccess.get_file_as_string(options["--catalog"]))
	if not value is Dictionary:
		printerr("无法读取资源目录。")
		quit(1)
		return
	catalog = value
	root.title = "杀戮尖塔 2 · 皮肤预览 / Graywill"
	root.min_size = Vector2i(1080, 740)
	root.size = Vector2i(1360, 860)
	# 独立项目在挂载游戏包之前已经初始化，游戏启动场景不会参与预览。
	if not ClassDB.class_exists("SpineSprite"):
		printerr("未能加载游戏的 Spine 组件。")
		quit(1)
		return
	if not ProjectSettings.load_resource_pack(catalog.base_pack, false):
		printerr("无法读取游戏基础资源包。")
		quit(1)
		return
	if not ProjectSettings.load_resource_pack(catalog.mod_path, true):
		printerr("无法读取 Mod 资源包。")
		quit(1)
		return
	call_deferred("_start")


func _start():
	ui = load("res://_graywill_preview/ui.gd").new()
	ui.build(self, catalog)
	root.files_dropped.connect(_files_dropped)
	root.window_input.connect(_input)
	await process_frame
	await process_frame
	filter_assets("")
	if not visible_assets.is_empty():
		ui.assets.select(0)
		select_asset(0)
	if options.has("--inspect"):
		await inspect_resources()
	elif options.has("--capture-all"):
		await capture_resources()
	elif options.has("--capture"):
		await create_timer(0.8).timeout
		await capture_window(options["--capture"])
		quit(1 if fatal else 0)


func _process(_delta):
	if ui == null or ui.stage == null or not ui.stage.has_animation():
		return false
	var time = ui.stage.current_time()
	ui.time_label.text = "%.2f / %.2f 秒" % [time, ui.stage.duration]
	if not scrubbing:
		ui.timeline.set_value_no_signal(time)
	return false


func _input(event):
	if event is InputEventKey and event.pressed and not event.echo and ui != null:
		if root.gui_get_focus_owner() is LineEdit:
			return
		if event.keycode == KEY_SPACE:
			toggle_playing()
			root.set_input_as_handled()
		elif event.keycode == KEY_F:
			ui.stage.fit_view()
			root.set_input_as_handled()


func filter_assets(text: String):
	ui.assets.clear()
	visible_assets.clear()
	var category = ui.category.selected
	for asset in catalog.assets:
		if category == 1 and asset.kind == "image":
			continue
		if category == 2 and asset.group != "界面图片":
			continue
		if category == 3 and asset.group != "贴图图集":
			continue
		if text != "" and (asset.label + asset.path).to_lower().find(text.to_lower()) == -1:
			continue
		visible_assets.append(asset)
		ui.assets.add_item(("▧ " if asset.kind == "image" else "▸ ") + asset.label)
		var index = ui.assets.item_count - 1
		ui.assets.set_item_tooltip(index, asset.path)
		if current_asset.get("path", "") == asset.path:
			ui.assets.select(index)


func select_asset(index: int):
	if index < 0 or index >= visible_assets.size():
		return
	load_asset(visible_assets[index])


func load_asset(asset: Dictionary) -> Dictionary:
	current_asset = asset
	ui.title.text = asset.label
	ui.subtitle.text = asset.path.trim_prefix("res://")
	ui.subtitle.tooltip_text = asset.path
	ui.subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ui.animation.clear()
	ui.skin.clear()
	var info = ui.stage.load_asset(asset)
	if info.has("error"):
		ui.status.text = info.error
		ui.export_button.disabled = true
		return info
	ui.export_button.disabled = false
	ui.animation_section.visible = asset.kind == "spine" or not info.animations.is_empty()
	ui.skin.disabled = asset.kind != "spine"
	if asset.kind != "image":
		ui.animation.add_item("初始姿势")
		var default_index = 1 if info.animations.size() > 0 else 0
		for animation in info.animations:
			ui.animation.add_item(animation.name)
			if animation.name in ["idle", "idle_loop", "glory_loop"]:
				default_index = ui.animation.item_count - 1
		ui.animation.select(default_index)
		select_animation(default_index)
		if asset.kind == "spine":
			ui.skin.add_item("默认皮肤")
			for skin_name in info.skins:
				ui.skin.add_item(skin_name)
			ui.resource_info.text = "Spine %s\n%d 个动画 / %d 根骨骼 / %d 个槽位" % [info.version, info.animations.size(), info.bones, info.slots]
			if asset.origin == "game":
				ui.resource_info.text += "\n骨骼来自游戏，贴图由 Mod 替换"
		else:
			ui.skin.add_item("场景素材")
			ui.resource_info.text = "Godot 场景\n%d 个动画 / %d 个节点" % [info.animations.size(), info.nodes]
			if info.frame_sequences > 0:
				ui.resource_info.text += "\n帧顺序与时长读取自 Mod 定义"
	else:
		ui.skin.add_item("图片素材")
		ui.resource_info.text = "%d × %d 像素\n%s" % [info.width, info.height, asset.group]
	ui.status.text = "已载入 %s   ·   %s" % [asset.label, catalog.get("source_path", catalog.mod_path).get_file()]
	print("PREVIEW_LOADED ", asset.path, " ", JSON.stringify(info))
	return info


func select_animation(index: int):
	var name = "" if index == 0 else ui.animation.get_item_text(index)
	ui.stage.set_animation(name)
	ui.timeline.max_value = maxf(0.001, ui.stage.duration)
	ui.timeline.set_value_no_signal(0)
	ui.timeline.editable = ui.stage.duration > 0


func select_skin(index: int):
	ui.stage.set_skin("" if index == 0 else ui.skin.get_item_text(index))


func toggle_playing():
	ui.stage.playing = not ui.stage.playing
	ui.pause.text = "暂停" if ui.stage.playing else "播放"


func step_frame():
	ui.stage.playing = false
	ui.pause.text = "播放"
	var next_time = ui.stage.current_time() + 1.0 / 60.0
	if ui.stage.looping and next_time > ui.stage.duration and ui.stage.duration > 0:
		next_time = fmod(next_time, ui.stage.duration)
	ui.stage.seek(next_time)


func begin_scrub():
	scrubbing = true
	was_playing = ui.stage.playing
	ui.stage.playing = false


func end_scrub(_changed: bool):
	scrubbing = false
	ui.stage.playing = was_playing


func scrub_changed(value: float):
	ui.stage.seek(value)


func exports_dir() -> String:
	var path = catalog.tool_dir.path_join("exports")
	DirAccess.make_dir_recursive_absolute(path)
	return path


func open_exports():
	OS.shell_open(exports_dir())


func export_filename() -> String:
	var base = current_asset.path.get_file().get_basename()
	var name = ui.stage.animation_name.replace("/", "_")
	return base + ("_" + name if name != "" else "") + ".png"


func choose_export():
	ui.save_dialog.current_dir = exports_dir()
	ui.save_dialog.current_file = export_filename()
	ui.save_dialog.popup_centered_ratio(0.7)


func export_png(path: String):
	if path.get_extension().to_lower() != "png":
		path += ".png"
	var result = await ui.stage.export_image(path)
	ui.status.text = "已导出：" + path if result == OK else "导出失败：" + error_string(result)


func switch_mod(path: String):
	# 每个 Mod 使用新进程，Godot 已挂载资源和缓存不会混入下一份皮肤。
	var arguments = PackedStringArray(["-X", "utf8", catalog.launcher, "--game", catalog.game_dir, "--mod", path])
	var pid = OS.create_process(catalog.python, arguments, false)
	if pid == -1:
		ui.error_dialog.dialog_text = "未能启动新的预览窗口。"
		ui.error_dialog.popup_centered()
		return
	quit()


func _files_dropped(files: PackedStringArray):
	if files.size() > 0:
		switch_mod(files[0])


func resource_report(asset: Dictionary, info: Dictionary) -> Dictionary:
	var report = asset.duplicate()
	report.merge(info, true)
	if not info.has("error"):
		var rect = ui.stage.bounds
		report["bounds"] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	return report


func save_report(path: String, reports: Array):
	var output = {
		"mod": catalog.metadata, "mod_path": catalog.mod_path,
		"source_path": catalog.get("source_path", catalog.mod_path), "archive_entry": catalog.get("archive_entry", ""),
		"engine": Engine.get_version_info(), "assets": reports,
	}
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		fatal = true
		printerr("无法写入报告：", path)
		return
	file.store_string(JSON.stringify(output, "  "))
	file.close()


func inspect_resources():
	var reports = []
	for asset in catalog.assets:
		var info = load_asset(asset)
		reports.append(resource_report(asset, info))
		fatal = fatal or info.has("error")
	save_report(options["--inspect"], reports)
	quit(1 if fatal else 0)


func capture_window(path: String):
	await RenderingServer.frame_post_draw
	var result = root.get_texture().get_image().save_png(path)
	if result != OK:
		fatal = true
		printerr("无法导出窗口截图：", error_string(result))


func capture_resources():
	var output_dir: String = options["--capture-all"]
	var reports = []
	var asset_index = 0
	for asset in catalog.assets:
		var info = load_asset(asset)
		var report = resource_report(asset, info)
		if info.has("error"):
			fatal = true
		else:
			# 暂停后取确定的动画时间，批量导出的画面可重复选择。
			ui.stage.playing = false
			ui.pause.text = "播放"
			if ui.stage.duration > 0:
				ui.stage.seek(minf(0.7, ui.stage.duration * 0.25))
			for _frame in range(3):
				await process_frame
			var filename = "%02d_" % asset_index + export_filename()
			var result = await ui.stage.export_image(output_dir.path_join(filename))
			report["preview"] = filename
			report["export_result"] = result
			fatal = fatal or result != OK
		reports.append(report)
		asset_index += 1
	save_report(output_dir.path_join("resources.json"), reports)
	if options.has("--capture"):
		ui.assets.select(0)
		select_asset(0)
		ui.stage.playing = false
		ui.pause.text = "播放"
		ui.stage.seek(0.7)
		for _frame in range(3):
			await process_frame
		await capture_window(options["--capture"])
	quit(1 if fatal else 0)
