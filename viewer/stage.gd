# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Komeiji-Shiki and contributors

extends Control

signal zoom_changed(value)

var viewport: SubViewport
var viewport_container: SubViewportContainer
var canvas: Node2D
var content: Node2D
var spine_data
var scene_controller
var bounds = Rect2(-100, -100, 200, 200)
var base_scale = 1.0
var zoom = 1.0
var pan = Vector2.ZERO
var flipped = false
var background_mode = 0
var dragging = false
var playing = true
var playback_speed = 1.0
var looping = true
var animation_name = ""
var duration = 0.0
var debug_bones = false


func _ready():
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	viewport_container = SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(viewport_container)
	viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(viewport)
	canvas = Node2D.new()
	viewport.add_child(canvas)
	resized.connect(_on_resize)
	gui_input.connect(_on_input)
	queue_redraw()


func _process(delta):
	if content != null and spine_data != null and playing:
		content.update_skeleton(delta * playback_speed)
	elif scene_controller != null:
		scene_controller.set_playback(playing, playback_speed)
		if playing:
			scene_controller.advance(delta * playback_speed)


func clear_content():
	if content != null:
		content.free()
	content = null
	spine_data = null
	scene_controller = null
	animation_name = ""
	duration = 0.0


func load_asset(asset: Dictionary) -> Dictionary:
	clear_content()
	var resource = ResourceLoader.load(asset.path)
	if resource == null:
		return {"error": "无法读取素材，请查看运行记录。"}
	var result = {"animations": [], "skins": []}
	if asset.kind == "spine":
		if not resource.is_class("SpineSkeletonDataResource"):
			return {"error": "该资源不是角色骨骼数据。"}
		spine_data = resource
		content = ClassDB.instantiate("SpineSprite")
		content.set_skeleton_data_res(resource)
		# 手动更新使暂停、变速和时间轴使用同一条播放路径。
		content.set_update_mode(2)
		canvas.add_child(content)
		if not resource.is_skeleton_data_loaded():
			clear_content()
			return {"error": "骨骼与贴图未能匹配，或 Spine 版本不兼容。"}
		for animation in resource.get_animations():
			result.animations.append({"name": animation.get_name(), "duration": animation.get_duration()})
		for skin in resource.get_skins():
			result.skins.append(skin.get_name())
		result["version"] = resource.get_version()
		result["bones"] = resource.get_bones().size()
		result["slots"] = resource.get_slots().size()
		content.set_debug_bones(debug_bones)
		content.update_skeleton(0.0)
		bounds = content.get_skeleton().get_bounds()
		if bounds.size.x < 1 or bounds.size.y < 1:
			bounds = Rect2(resource.get_x(), -resource.get_y() - resource.get_height(), resource.get_width(), resource.get_height())
	elif asset.kind == "scene":
		if not resource is PackedScene:
			return {"error": "该资源不是 Godot 场景。"}
		content = Node2D.new()
		canvas.add_child(content)
		scene_controller = load("res://_graywill_preview/scene_preview.gd").new()
		result = scene_controller.load_scene(resource, asset.get("frame_animations", []), content)
		if result.has("error"):
			clear_content()
			return result
		bounds = scene_controller.get_bounds(content)
		if not bounds.has_area():
			bounds = Rect2(-100, -100, 200, 200)
	else:
		if not resource is Texture2D:
			return {"error": "该资源不是二维图片。"}
		content = Sprite2D.new()
		content.texture = resource
		canvas.add_child(content)
		bounds = Rect2(-resource.get_size() / 2.0, resource.get_size())
		result["width"] = resource.get_width()
		result["height"] = resource.get_height()
	fit_view()
	return result


func set_animation(value: String):
	if scene_controller != null:
		animation_name = value
		scene_controller.looping = looping
		scene_controller.set_animation(value)
		duration = scene_controller.duration
		bounds = scene_controller.get_bounds(content)
		fit_view()
		return
	if spine_data == null:
		return
	animation_name = value
	var state = content.get_animation_state()
	state.clear_tracks()
	content.get_skeleton().set_to_setup_pose()
	duration = 0.0
	if value != "":
		var animation = spine_data.find_animation(value)
		if animation == null:
			return
		duration = animation.get_duration()
		var entry = state.set_animation(value, looping, 0)
		entry.set_mix_duration(0.0)
	content.update_skeleton(0.0)
	bounds = content.get_skeleton().get_bounds()
	fit_view()


func set_skin(value: String):
	if spine_data == null:
		return
	if value == "":
		content.get_skeleton().set_skin(null)
	else:
		content.get_skeleton().set_skin_by_name(value)
	content.get_skeleton().set_slots_to_setup_pose()
	content.update_skeleton(0.0)


func set_loop(value: bool):
	looping = value
	if scene_controller != null:
		scene_controller.looping = value
	if spine_data != null:
		var entry = content.get_animation_state().get_current(0)
		if entry != null:
			entry.set_loop(value)


func seek(time: float):
	if scene_controller != null:
		scene_controller.seek(clampf(time, 0, duration))
		return
	if spine_data == null or animation_name == "":
		return
	# 每次取当前轨道对象，避免持有运行时可能重新使用的 TrackEntry。
	var entry = content.get_animation_state().get_current(0)
	if entry != null:
		entry.set_track_time(clampf(time, 0.0, duration))
		content.update_skeleton(0.0)


func current_time() -> float:
	if scene_controller != null:
		return scene_controller.elapsed
	if spine_data == null or animation_name == "":
		return 0.0
	var entry = content.get_animation_state().get_current(0)
	return entry.get_animation_time() if entry != null else 0.0


func has_animation() -> bool:
	return spine_data != null or scene_controller != null


func set_bones(value: bool):
	debug_bones = value
	if spine_data != null:
		content.set_debug_bones(value)


func fit_view():
	zoom = 1.0
	pan = Vector2.ZERO
	_recalculate_scale()
	_update_transform()
	zoom_changed.emit(zoom)


func _recalculate_scale():
	var available = Vector2(maxf(100, size.x - 110), maxf(100, size.y - 100))
	base_scale = minf(available.x / maxf(1, bounds.size.x), available.y / maxf(1, bounds.size.y))


func set_zoom(value: float):
	zoom = clampf(value, 0.1, 8.0)
	_update_transform()
	zoom_changed.emit(zoom)


func set_flip(value: bool):
	flipped = value
	_update_transform()


func _update_transform():
	if canvas == null:
		return
	var factor = base_scale * zoom
	canvas.scale = Vector2(-factor if flipped else factor, factor)
	canvas.position = size / 2.0 + pan - bounds.get_center() * canvas.scale


func _on_resize():
	_recalculate_scale()
	_update_transform()
	queue_redraw()


func _on_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_MIDDLE:
			dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_zoom(zoom * 1.1)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_zoom(zoom / 1.1)
	elif event is InputEventMouseMotion and dragging:
		pan += event.relative
		_update_transform()


func _draw():
	var color = Color("11171b")
	if background_mode == 1:
		color = Color("e4e2de")
	elif background_mode == 2:
		color = Color("255944")
	draw_rect(Rect2(Vector2.ZERO, size), color)
	if background_mode == 0:
		for x in range(0, int(size.x), 32):
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.28, 0.35, 0.39, 0.15))
		for y in range(0, int(size.y), 32):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.28, 0.35, 0.39, 0.15))
		draw_line(Vector2(size.x / 2, 0), Vector2(size.x / 2, size.y), Color(0.6, 0.65, 0.68, 0.12))
		draw_line(Vector2(0, size.y / 2), Vector2(size.x, size.y / 2), Color(0.6, 0.65, 0.68, 0.12))


func export_image(path: String) -> int:
	await RenderingServer.frame_post_draw
	var image = viewport.get_texture().get_image()
	# PNG 只含素材；背景网格和界面控件位于另一个视口。
	var used = image.get_used_rect()
	if used.size.x > 0 and used.size.y > 0:
		var padded = used.grow(16).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		image = image.get_region(padded)
	return image.save_png(path)
