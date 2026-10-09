# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Komeiji-Shiki and contributors

extends RefCounted

const ACCENT = Color("ee775d")
const MUTED = Color("8d9da8")

var root: Control
var assets: ItemList
var filter: LineEdit
var category: OptionButton
var title: Label
var subtitle: Label
var resource_info: Label
var status: Label
var animation: OptionButton
var skin: OptionButton
var pause: Button
var step: Button
var loop: CheckBox
var speed: HSlider
var speed_label: Label
var timeline: HSlider
var time_label: Label
var zoom: HSlider
var zoom_label: Label
var stage
var export_button: Button
var mod_dialog: FileDialog
var folder_dialog: FileDialog
var save_dialog: FileDialog
var error_dialog: AcceptDialog
var animation_section: VBoxContainer


func make_style(color: Color, border = Color("2b343b"), padding = 10) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style


func make_theme() -> Theme:
	var theme = Theme.new()
	var font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI"])
	theme.default_font = font
	theme.default_font_size = 14
	for type_name in ["Button", "OptionButton", "LineEdit"]:
		theme.set_stylebox("normal", type_name, make_style(Color("1a2229")))
		theme.set_stylebox("hover", type_name, make_style(Color("273039"), Color("55636e")))
		theme.set_stylebox("pressed", type_name, make_style(Color("643c33"), ACCENT))
		theme.set_stylebox("focus", type_name, make_style(Color(0, 0, 0, 0), ACCENT))
		theme.set_stylebox("disabled", type_name, make_style(Color("141a20"), Color("242b31")))
		theme.set_color("font_color", type_name, Color("e7edf1"))
		theme.set_color("font_disabled_color", type_name, Color("58636c"))
	theme.set_stylebox("panel", "PanelContainer", make_style(Color("141b21"), Color("2b343b"), 16))
	theme.set_stylebox("panel", "PopupMenu", make_style(Color("1b252d")))
	theme.set_stylebox("hover", "PopupMenu", make_style(Color("50342d"), ACCENT))
	theme.set_stylebox("panel", "ItemList", make_style(Color("10161c"), Color("29323a"), 4))
	theme.set_stylebox("selected", "ItemList", make_style(Color("5b3931"), ACCENT, 6))
	theme.set_stylebox("selected_focus", "ItemList", make_style(Color("5b3931"), ACCENT, 6))
	theme.set_stylebox("cursor", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("cursor_unfocused", "ItemList", StyleBoxEmpty.new())
	theme.set_constant("v_separation", "ItemList", 12)
	theme.set_constant("h_separation", "HBoxContainer", 12)
	theme.set_constant("separation", "VBoxContainer", 12)
	theme.set_color("font_color", "Label", Color("e4eaee"))
	theme.set_color("font_color", "ItemList", Color("cbd6dd"))
	return theme


func label(parent: Node, text: String, font_size = 14, color = Color("d4dde3")) -> Label:
	var node = Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	return node


func button(parent: Node, text: String, callback: Callable) -> Button:
	var node = Button.new()
	node.text = text
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.pressed.connect(callback)
	parent.add_child(node)
	return node


func row(parent: Node) -> HBoxContainer:
	var node = HBoxContainer.new()
	parent.add_child(node)
	return node


func section(parent: Node, text: String) -> VBoxContainer:
	var column = VBoxContainer.new()
	parent.add_child(column)
	label(column, text, 12, ACCENT)
	return column


func slider(parent: Node, minimum: float, maximum: float, value: float, interval: float) -> HSlider:
	var node = HSlider.new()
	node.min_value = minimum
	node.max_value = maximum
	node.step = interval
	node.value = value
	node.custom_minimum_size.y = 24
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node


func build(app, catalog: Dictionary):
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = make_theme()
	app.root.add_child(root)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	root.add_child(margin)
	var layout = VBoxContainer.new()
	margin.add_child(layout)
	var header = row(layout)
	var brand = VBoxContainer.new()
	brand.add_theme_constant_override("separation", 2)
	header.add_child(brand)
	label(brand, "SKIN / STUDIO", 30, Color("edf2f5"))
	label(brand, "杀戮尖塔 2   ·   角色皮肤预览", 13, MUTED)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	button(header, "选择 Mod 文件", func(): mod_dialog.popup_centered_ratio(0.75))
	button(header, "选择 Mod 文件夹", func(): folder_dialog.popup_centered_ratio(0.75))
	button(header, "打开导出目录", app.open_exports)
	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	var sidebar = PanelContainer.new()
	sidebar.custom_minimum_size.x = 280
	body.add_child(sidebar)
	var side = VBoxContainer.new()
	sidebar.add_child(side)
	label(side, "01 / MOD 资源", 12, ACCENT)
	var metadata = catalog.get("metadata", {})
	var fallback_name: String = catalog.get("archive_entry", "")
	if fallback_name == "":
		fallback_name = catalog.mod_path
	var name_label = label(side, str(metadata.get("name", fallback_name.get_file().get_basename())), 20)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = 245
	label(side, "v%s   /   %s" % [metadata.get("version", "?"), metadata.get("author", "未知作者")], 12, MUTED)
	var source_path: String = catalog.get("source_path", catalog.mod_path)
	var path_label = label(side, source_path.get_file(), 12, MUTED)
	path_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	path_label.tooltip_text = source_path + ("\n" + catalog.archive_entry if catalog.get("archive_entry", "") != "" else "")
	filter = LineEdit.new()
	filter.placeholder_text = "搜索场景、图片或资源名"
	filter.text_changed.connect(app.filter_assets)
	side.add_child(filter)
	category = OptionButton.new()
	for text in ["全部资源", "角色动画", "界面图片", "贴图图集"]:
		category.add_item(text)
	category.item_selected.connect(func(_index): app.filter_assets(filter.text))
	side.add_child(category)
	assets = ItemList.new()
	assets.size_flags_vertical = Control.SIZE_EXPAND_FILL
	assets.item_selected.connect(app.select_asset)
	side.add_child(assets)
	label(side, "%d 个文件   ·   PCK %s   ·   Godot %s" % [catalog.file_count, catalog.pack_version, catalog.engine_version], 11, MUTED)
	var center = VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(center)
	var title_box = VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 2)
	center.add_child(title_box)
	title = label(title_box, "载入素材", 24)
	subtitle = label(title_box, "", 12, MUTED)
	stage = load("res://_graywill_preview/stage.gd").new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size = Vector2(260, 260)
	center.add_child(stage)
	var stage_hint = row(center)
	label(stage_hint, "鼠标拖动平移 / 滚轮缩放 / 空格暂停 / F 适应窗口", 11, MUTED)
	var inspector_panel = PanelContainer.new()
	inspector_panel.custom_minimum_size.x = 270
	body.add_child(inspector_panel)
	var inspector_layout = VBoxContainer.new()
	inspector_panel.add_child(inspector_layout)
	var inspector_scroll = ScrollContainer.new()
	inspector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inspector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inspector_layout.add_child(inspector_scroll)
	var inspector = VBoxContainer.new()
	inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inspector_scroll.add_child(inspector)
	label(inspector, "02 / 预览控制", 12, ACCENT)
	animation_section = section(inspector, "动画")
	animation = OptionButton.new()
	animation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	animation.clip_text = true
	animation.custom_minimum_size.x = 225
	animation.item_selected.connect(app.select_animation)
	animation_section.add_child(animation)
	var playback = row(animation_section)
	pause = button(playback, "暂停", app.toggle_playing)
	pause.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step = button(playback, "下一帧", app.step_frame)
	loop = CheckBox.new()
	loop.text = "循环播放"
	loop.button_pressed = true
	loop.toggled.connect(func(value): stage.set_loop(value))
	animation_section.add_child(loop)
	var speed_row = row(animation_section)
	label(speed_row, "播放速度", 12, MUTED)
	speed_label = label(speed_row, "1.00×", 12)
	speed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed = slider(animation_section, 0.1, 3.0, 1.0, 0.05)
	speed.value_changed.connect(func(value): stage.playback_speed = value; speed_label.text = "%.2f×" % value)
	time_label = label(animation_section, "0.00 / 0.00 秒", 12, MUTED)
	timeline = slider(animation_section, 0.0, 1.0, 0.0, 0.001)
	timeline.drag_started.connect(app.begin_scrub)
	timeline.drag_ended.connect(app.end_scrub)
	timeline.value_changed.connect(app.scrub_changed)
	var skin_section = section(inspector, "骨骼内的皮肤")
	skin = OptionButton.new()
	skin.item_selected.connect(app.select_skin)
	skin_section.add_child(skin)
	var view_section = section(inspector, "画面")
	var zoom_row = row(view_section)
	label(zoom_row, "缩放", 12, MUTED)
	zoom_label = label(zoom_row, "100%", 12)
	zoom_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	zoom = slider(view_section, 0.1, 8.0, 1.0, 0.05)
	zoom.value_changed.connect(func(value): stage.set_zoom(value))
	stage.zoom_changed.connect(func(value): zoom.set_value_no_signal(value); zoom_label.text = "%d%%" % roundi(value * 100))
	button(view_section, "适应窗口", func(): stage.fit_view())
	var flip = CheckBox.new()
	flip.text = "水平翻转"
	flip.toggled.connect(func(value): stage.set_flip(value))
	view_section.add_child(flip)
	var bones = CheckBox.new()
	bones.text = "显示骨骼"
	bones.toggled.connect(func(value): stage.set_bones(value))
	view_section.add_child(bones)
	var background = OptionButton.new()
	for text in ["暗色网格", "浅色背景", "绿幕背景"]:
		background.add_item(text)
	background.item_selected.connect(func(index): stage.background_mode = index; stage.queue_redraw())
	view_section.add_child(background)
	resource_info = label(inspector_layout, "", 11, MUTED)
	resource_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	resource_info.custom_minimum_size.x = 225
	export_button = button(inspector_layout, "导出透明 PNG", app.choose_export)
	export_button.add_theme_stylebox_override("normal", make_style(Color("7e473a"), ACCENT))
	var footer = row(layout)
	status = label(footer, "正在载入资源…", 12, MUTED)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label(footer, "GRAYWILL / 本地预览", 11, ACCENT)
	mod_dialog = FileDialog.new()
	mod_dialog.title = "选择角色皮肤 Mod 文件或压缩包"
	mod_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	mod_dialog.access = FileDialog.ACCESS_FILESYSTEM
	mod_dialog.use_native_dialog = true
	mod_dialog.filters = PackedStringArray([
		"*.pck,*.zip,*.7z,*.rar,*.tar,*.tar.gz,*.tgz,*.tar.bz2,*.tbz2,*.tar.xz,*.txz ; Mod 文件与压缩包",
		"*.pck ; Godot Mod 资源包", "*.zip ; ZIP 压缩包", "*.7z ; 7Z 压缩包", "*.rar ; RAR 压缩包",
	])
	mod_dialog.current_dir = source_path.get_base_dir()
	mod_dialog.file_selected.connect(app.switch_mod)
	root.add_child(mod_dialog)
	folder_dialog = FileDialog.new()
	folder_dialog.title = "选择角色皮肤 Mod 文件夹"
	folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	folder_dialog.use_native_dialog = true
	folder_dialog.current_dir = source_path.get_base_dir()
	folder_dialog.dir_selected.connect(app.switch_mod)
	root.add_child(folder_dialog)
	save_dialog = FileDialog.new()
	save_dialog.title = "导出透明 PNG"
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_FILESYSTEM
	save_dialog.use_native_dialog = true
	save_dialog.filters = PackedStringArray(["*.png ; PNG 图片"])
	save_dialog.file_selected.connect(app.export_png)
	root.add_child(save_dialog)
	error_dialog = AcceptDialog.new()
	error_dialog.title = "皮肤预览器"
	root.add_child(error_dialog)
