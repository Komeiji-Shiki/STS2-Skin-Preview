# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (C) 2026 Komeiji-Shiki and contributors

extends RefCounted

var scene: Node
var players: Array = []
var sprites: Array = []
var particles: Array = []
var frame_cues: Array = []
var frame_target: Sprite2D
var textures: Dictionary = {}
var animation_name = ""
var elapsed = 0.0
var duration = 0.0
var looping = true


func load_scene(resource: PackedScene, cues: Array, parent: Node2D) -> Dictionary:
	scene = resource.instantiate()
	parent.add_child(scene)
	_collect(scene)
	frame_cues = cues
	if not cues.is_empty():
		frame_target = scene.find_child("Visuals", true, false) as Sprite2D
		if frame_target == null:
			return {"error": "场景没有找到帧动画使用的 Visuals 节点。"}
		set_animation(cues[0].name)
	var clips: Dictionary = {}
	for player in players:
		for name in player.get_animation_list():
			if name != "RESET":
				clips[name] = maxf(clips.get(name, 0), player.get_animation(name).length)
	for sprite in sprites:
		for name in sprite.sprite_frames.get_animation_names():
			clips[name] = maxf(clips.get(name, 0), _sprite_duration(sprite, name))
	for cue in cues:
		var seconds = 0.0
		for frame in cue.frames:
			seconds += frame.seconds
		clips[cue.name] = seconds
	var animations = []
	for name in clips:
		animations.append({"name": name, "duration": clips[name]})
	return {"animations": animations, "skins": [], "renderer": "Godot 场景",
		"nodes": _node_count(scene), "frame_sequences": cues.size(),
		"animated_sprites": sprites.size(), "animation_players": players.size()}


func _collect(node: Node):
	if node is AnimationPlayer:
		node.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		players.append(node)
	elif node is AnimationTree:
		node.active = false
	elif node is AnimatedSprite2D and node.sprite_frames != null:
		node.pause()
		sprites.append(node)
	elif node is TextureRect and node.texture != null and not node.size.x > 0:
		# 游戏界面通常由父容器提供尺寸，独立预览时使用图片的原始尺寸。
		node.size = node.texture.get_size()
	elif node is GPUParticles2D or node is CPUParticles2D:
		particles.append({"node": node, "speed": node.speed_scale})
	for child in node.get_children():
		_collect(child)


func _node_count(node: Node) -> int:
	var count = 1
	for child in node.get_children():
		count += _node_count(child)
	return count


func _sprite_duration(sprite: AnimatedSprite2D, name: String) -> float:
	var frames = sprite.sprite_frames
	var seconds = 0.0
	var fps = frames.get_animation_speed(name)
	if fps <= 0:
		return 0.0
	for index in range(frames.get_frame_count(name)):
		seconds += frames.get_frame_duration(name, index) / fps
	return seconds


func set_animation(name: String):
	animation_name = name
	elapsed = 0.0
	duration = 0.0
	for player in players:
		player.stop()
		if player.has_animation("RESET"):
			player.play("RESET")
			player.advance(0)
			player.stop()
		if name != "" and player.has_animation(name):
			player.play(name)
			player.advance(0)
			duration = maxf(duration, player.get_animation(name).length)
	for sprite in sprites:
		sprite.pause()
		if sprite.sprite_frames.has_animation(name):
			sprite.animation = name
			duration = maxf(duration, _sprite_duration(sprite, name))
	for cue in frame_cues:
		if cue.name == name:
			var seconds = 0.0
			for frame in cue.frames:
				seconds += frame.seconds
			duration = maxf(duration, seconds)
	seek(0.0)


func advance(delta: float):
	if animation_name == "":
		return
	seek(elapsed + delta)


func set_playback(playing: bool, speed: float):
	for particle in particles:
		particle.node.speed_scale = particle.speed * speed if playing else 0.0


func seek(time: float):
	elapsed = time
	if duration > 0:
		elapsed = fmod(time, duration) if looping else clampf(time, 0, duration)
	for player in players:
		if animation_name != "" and player.has_animation(animation_name):
			var length = player.get_animation(animation_name).length
			var position = fmod(elapsed, length) if looping and length > 0 else minf(elapsed, length)
			player.seek(position, true)
	for sprite in sprites:
		if not sprite.sprite_frames.has_animation(sprite.animation):
			continue
		var seconds = _sprite_duration(sprite, sprite.animation)
		var position = fmod(elapsed, seconds) if looping and seconds > 0 else minf(elapsed, seconds)
		var frames = sprite.sprite_frames
		var fps = frames.get_animation_speed(sprite.animation)
		if fps <= 0:
			continue
		for index in range(frames.get_frame_count(sprite.animation)):
			var frame_time = frames.get_frame_duration(sprite.animation, index) / fps
			if position < frame_time or index == frames.get_frame_count(sprite.animation) - 1:
				sprite.set_frame_and_progress(index, minf(1, position / frame_time))
				break
			position -= frame_time
	for cue in frame_cues:
		if cue.name != animation_name:
			continue
		var position = elapsed
		for index in range(cue.frames.size()):
			var frame = cue.frames[index]
			if position < frame.seconds or index == cue.frames.size() - 1:
				if not textures.has(frame.path):
					textures[frame.path] = ResourceLoader.load(frame.path)
				frame_target.texture = textures[frame.path]
				break
			position -= frame.seconds


func get_bounds(parent: Node2D) -> Rect2:
	return _bounds(scene, parent)


func _bounds(node: Node, parent: Node2D) -> Rect2:
	var result = Rect2()
	var local = Rect2()
	if node is Sprite2D and node.texture != null:
		local = node.get_rect()
	elif node is AnimatedSprite2D and node.sprite_frames != null:
		var texture = node.sprite_frames.get_frame_texture(node.animation, node.frame)
		if texture != null:
			local = Rect2(node.offset - texture.get_size() / 2 if node.centered else node.offset, texture.get_size())
	elif node is TextureRect and node.texture != null:
		local = Rect2(Vector2.ZERO, node.size)
	if local.has_area() and node is CanvasItem and node.is_visible_in_tree():
		var transform = parent.get_global_transform().affine_inverse() * node.get_global_transform()
		result = transform * local
	for child in node.get_children():
		var child_bounds = _bounds(child, parent)
		if child_bounds.has_area():
			result = result.merge(child_bounds) if result.has_area() else child_bounds
	return result
