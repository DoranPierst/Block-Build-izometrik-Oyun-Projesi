extends Node2D

## Karakter görseli: SubViewport → Sprite2D.
## Varsayılan model: assets/characters/roblox.blend (8 yön grid facing).

enum CharacterMode { ROBLOX, FBX, CAPSULE, HABBO_2D }

const ROBLOX_MODEL := "res://assets/characters/roblox.blend"
const VOXEL_MODEL  := "res://assets/characters/Meshy_AI_voxel_base_mesh_karak_0608092123_texture.fbx"

@export var character_mode: CharacterMode = CharacterMode.ROBLOX

@export var cam_ortho_size: float    = 1.7
@export var vp_size:        Vector2i = Vector2i(96, 128)
@export_range(1, 4, 1) var render_scale: int = 3
@export var ground_offset:  Vector2  = Vector2.ZERO

@export var model_path: String = ROBLOX_MODEL
@export var model_correction_rotation: Vector3 = Vector3.ZERO
@export var model_facing_offset_deg: float = 90.0
@export var model_extra_scale:    float   = 1.0
@export var model_extra_position: Vector3 = Vector3.ZERO

@export var skin_color:  Color = Color(0.96, 0.82, 0.68)
@export var hair_color:  Color = Color(0.36, 0.22, 0.10)
@export var shirt_color: Color = Color(0.18, 0.55, 0.92)
@export var pants_color: Color = Color(0.20, 0.26, 0.42)
@export var shoes_color: Color = Color(0.12, 0.12, 0.14)
@export var body_color: Color = Color(0.25, 0.45, 0.80)
@export var head_color: Color = Color(0.88, 0.72, 0.58)

## 2 birim yükseklik ≈ 1.1 world birimi (izometrik kamera).
const TARGET_HEIGHT := 1.1
const MODEL_FALLBACKS: Array[String] = [
	ROBLOX_MODEL,
	VOXEL_MODEL,
]

var _vp:           SubViewport
var _sprite:       Sprite2D
var _root:         Node3D
var _model_body:   Node3D
var _current_dir:  int = HabboIsoFacing.DEFAULT_DIR
var _walk_phase:   float = 0.0
var _is_moving:    bool  = false
var _facing_badge: Label
var _show_facing_badge: bool = false

func _ready() -> void:
	add_to_group("character_view")
	match character_mode:
		CharacterMode.ROBLOX, CharacterMode.FBX:
			set_process(true)
			_build_viewport()
			_load_model_when_ready()
		CharacterMode.CAPSULE:
			set_process(true)
			_build_viewport()
			_build_capsule_character()
			_align_sprite_to_feet()
			_build_facing_badge()
			_apply_facing_dir(HabboIsoFacing.DEFAULT_DIR)
		CharacterMode.HABBO_2D:
			set_process(true)
			_build_facing_badge()
			_apply_facing_dir(HabboIsoFacing.DEFAULT_DIR)

func _process(delta: float) -> void:
	if _is_moving:
		_walk_phase += delta * 9.0
	else:
		_walk_phase = 0.0

	if character_mode == CharacterMode.HABBO_2D:
		queue_redraw()
		return

	if _model_body == null:
		return
	var bob := sin(_walk_phase) * 0.014 if _is_moving else 0.0
	_model_body.position.y = bob

func _draw() -> void:
	if character_mode != CharacterMode.HABBO_2D:
		return
	var colors := HabboCharacter2D.Colors.new()
	colors.skin  = skin_color
	colors.hair  = hair_color
	colors.shirt = shirt_color
	colors.pants = pants_color
	colors.shoes = shoes_color
	var phase := _walk_phase if _is_moving else 0.0
	HabboCharacter2D.draw_character(self, _current_dir, phase, colors, ground_offset)

func _load_model_when_ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if await _try_load_models():
		return
	push_warning("CharacterView: model yüklenemedi → kapsül yedek.")
	character_mode = CharacterMode.CAPSULE
	_build_capsule_character()
	_align_sprite_to_feet()
	_build_facing_badge()
	_apply_facing_dir(HabboIsoFacing.DEFAULT_DIR)

func _build_viewport() -> void:
	var scale_i := maxi(render_scale, 1)
	_vp = SubViewport.new()
	_vp.size = vp_size * scale_i
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.anisotropic_filtering_level = Viewport.ANISOTROPY_4X
	add_child(_vp)

	var wenv := WorldEnvironment.new()
	var env  := Environment.new()
	env.background_mode      = Environment.BG_COLOR
	env.background_color     = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color  = Color(1, 1, 1)
	env.ambient_light_energy = 0.80
	wenv.environment = env
	_vp.add_child(wenv)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 45, 0)
	sun.light_energy     = 0.90
	_vp.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -135, 0)
	fill.light_energy     = 0.45
	_vp.add_child(fill)

	var cam := Camera3D.new()
	cam.projection       = Camera3D.PROJECTION_ORTHOGONAL
	cam.size             = cam_ortho_size
	cam.position         = Vector3(0.0, TARGET_HEIGHT * 0.5, 0.0)
	cam.rotation_degrees = Vector3(-26.565, 45.0, 0.0)
	_vp.add_child(cam)
	cam.translate_object_local(Vector3(0, 0, 12))

	_sprite                = Sprite2D.new()
	_sprite.texture        = _vp.get_texture()
	_sprite.centered       = true
	_sprite.z_index        = 0
	_sprite.scale          = Vector2(1.0 / scale_i, 1.0 / scale_i)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	_sprite.position       = Vector2(
		ground_offset.x, -float(vp_size.y) * 0.5 + ground_offset.y)
	add_child(_sprite)

func _get_viewport_camera() -> Camera3D:
	if _vp == null:
		return null
	for child in _vp.get_children():
		if child is Camera3D:
			return child as Camera3D
	return null

func _align_sprite_to_feet() -> void:
	var cam := _get_viewport_camera()
	if cam == null or _sprite == null or _root == null:
		return
	var scale_i := float(maxi(render_scale, 1))
	var feet_vp := cam.unproject_position(_root.to_global(Vector3.ZERO))
	var fx := feet_vp.x / scale_i
	var fy := feet_vp.y / scale_i
	_sprite.position = Vector2(
		ground_offset.x + float(vp_size.x) * 0.5 - fx,
		ground_offset.y + float(vp_size.y) * 0.5 - fy
	)

func _create_character_root() -> void:
	_root = Node3D.new()
	_root.position = Vector3.ZERO
	_vp.add_child(_root)

func _try_load_models() -> bool:
	var paths: Array[String] = []
	if not model_path.is_empty():
		paths.append(model_path)
	for fb in MODEL_FALLBACKS:
		if fb not in paths:
			paths.append(fb)
	for path in paths:
		if await _load_single_model(path):
			print("CharacterView: model yüklendi → ", path)
			return true
	return false

func _cleanup_failed_model_load() -> void:
	if _root and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_model_body = null

func _load_single_model(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return false
	_create_character_root()

	_model_body = Node3D.new()
	_model_body.name = "ModelBody"
	_root.add_child(_model_body)

	var pivot := Node3D.new()
	pivot.name = "ModelPivot"
	_model_body.add_child(pivot)

	var instance: Node = packed.instantiate()
	if instance == null:
		_cleanup_failed_model_load()
		return false

	var content: Node3D
	if instance is Node3D:
		content = instance as Node3D
		pivot.add_child(content)
	else:
		content = Node3D.new()
		content.name = "ModelWrapper"
		pivot.add_child(content)
		content.add_child(instance)

	await _deferred_fit(pivot, content, path)

	_build_facing_badge()
	_apply_facing_dir(HabboIsoFacing.DEFAULT_DIR)
	return true

func _deferred_fit(pivot: Node3D, content: Node3D, path: String) -> void:
	var oriented := false
	for _i in 6:
		var aabb := _combined_aabb(pivot)
		if not oriented and aabb.size.length() >= 0.001:
			_orient_content(pivot, content, path)
			oriented = true
			await get_tree().process_frame
		if oriented and _try_fit_content(pivot, content):
			_align_sprite_to_feet()
			return
		await get_tree().process_frame
	content.scale    = Vector3.ONE * 0.25 * model_extra_scale
	content.position = model_extra_position

func _orient_content(pivot: Node3D, content: Node3D, _path: String) -> void:
	if model_correction_rotation != Vector3.ZERO:
		content.rotation_degrees = model_correction_rotation
		return
	content.rotation_degrees = _best_upright_rotation(pivot, content)

func _best_upright_rotation(pivot: Node3D, content: Node3D) -> Vector3:
	content.rotation_degrees = Vector3.ZERO
	var s := _combined_aabb(pivot).size
	if s.length() < 0.001:
		return Vector3.ZERO
	# glTF/Blender Y-up: T-pose'da kollar X'te genişler, Y yine boy ekseni.
	if s.y >= s.z * 1.15 and s.y >= s.x * 0.55:
		return Vector3.ZERO
	var candidates: Array[Vector3] = [
		Vector3(90.0, 0.0, 0.0), Vector3(-90.0, 0.0, 0.0),
		Vector3(0.0, 90.0, 0.0), Vector3(0.0, -90.0, 0.0),
		Vector3(0.0, 0.0, 90.0), Vector3(0.0, 0.0, -90.0),
	]
	var best := Vector3.ZERO
	var best_y := s.y
	for rot in candidates:
		content.rotation_degrees = rot
		var ss := _combined_aabb(pivot).size
		if ss.y < ss.x or ss.y < ss.z:
			continue
		if ss.y > best_y:
			best_y = ss.y
			best = rot
	content.rotation_degrees = best
	return best

func _combined_aabb(root: Node3D) -> AABB:
	var mins := Vector3(INF, INF, INF)
	var maxs := Vector3(-INF, -INF, -INF)
	var found := false
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mi as MeshInstance3D
		if mesh_inst.mesh == null:
			continue
		var ab  := mesh_inst.get_aabb()
		var rel := root.global_transform.affine_inverse() * mesh_inst.global_transform
		for i in 8:
			var pt := rel * ab.get_endpoint(i)
			mins  = mins.min(pt)
			maxs  = maxs.max(pt)
			found = true
	if not found:
		return AABB()
	return AABB(mins, maxs - mins)

func _try_fit_content(pivot: Node3D, content: Node3D) -> bool:
	content.scale    = Vector3.ONE
	content.position = Vector3.ZERO
	var aabb := _combined_aabb(pivot)
	if aabb.size.y < 0.001:
		return false
	var s := (TARGET_HEIGHT / aabb.size.y) * model_extra_scale
	content.scale    = Vector3.ONE * s
	var foot_x := (aabb.position.x + aabb.size.x * 0.5) * s
	var foot_z := (aabb.position.z + aabb.size.z * 0.5) * s
	var foot_y := aabb.position.y * s
	content.position = Vector3(-foot_x, -foot_y, -foot_z) + model_extra_position
	return true

func _build_facing_badge() -> void:
	if _facing_badge:
		return
	_facing_badge = Label.new()
	_facing_badge.name = "FacingBadge"
	_facing_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_facing_badge.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_facing_badge.custom_minimum_size  = Vector2(52, 24)
	var head_y := -float(vp_size.y) * 0.5 + ground_offset.y - float(vp_size.y) * 0.34
	if character_mode == CharacterMode.HABBO_2D:
		head_y = ground_offset.y - HabboCharacter2D.CHAR_H + 6.0
	_facing_badge.position = Vector2(-28.0, head_y)
	_facing_badge.add_theme_font_size_override("font_size", 20)
	_facing_badge.add_theme_color_override("font_color", Color(1.0, 0.98, 0.35))
	_facing_badge.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 1.0))
	_facing_badge.add_theme_constant_override("outline_size", 12)
	_facing_badge.z_index = 50
	_facing_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_facing_badge.visible = false
	add_child(_facing_badge)

func _apply_facing_dir(dir: int) -> void:
	_current_dir = dir
	if _model_body:
		if character_mode == CharacterMode.HABBO_2D:
			var facing_2d: Dictionary = HabboIsoFacing.get_facing(dir)
			_model_body.rotation_degrees.y = facing_2d["yaw"] + model_facing_offset_deg
			_model_body.scale.x = 1.0
		else:
			var facing_3d: Dictionary = HabboIsoFacing.get_model_facing_for_grid(
				dir, model_facing_offset_deg)
			_model_body.scale = Vector3.ONE
			_model_body.rotation_degrees.y = facing_3d["yaw"]
			if facing_3d["flip"]:
				_model_body.scale.x = -1.0
	var facing_badge: Dictionary = HabboIsoFacing.get_facing(dir)
	if _sprite:
		_sprite.flip_h = facing_badge["flip"] if character_mode == CharacterMode.HABBO_2D else false
	if character_mode == CharacterMode.HABBO_2D:
		queue_redraw()
	_update_facing_badge()

func _update_facing_badge() -> void:
	if _facing_badge == null:
		return
	_facing_badge.visible = _show_facing_badge
	if _show_facing_badge:
		_facing_badge.text = HabboIsoFacing.grid_spoke_compass_short(_current_dir)

func set_facing_badge_enabled(on: bool) -> void:
	_show_facing_badge = on
	_update_facing_badge()

func is_facing_badge_enabled() -> bool:
	return _show_facing_badge

func set_moving(on: bool) -> void:
	_is_moving = on
	if not on:
		_walk_phase = 0.0
	if character_mode == CharacterMode.HABBO_2D:
		queue_redraw()

func _build_capsule_character() -> void:
	_create_character_root()
	_model_body = Node3D.new()
	_model_body.name = "ModelBody"
	_root.add_child(_model_body)
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.18
	body_mesh.height = 0.80
	var body_mi := MeshInstance3D.new()
	body_mi.mesh     = body_mesh
	body_mi.position = Vector3(0, 0.60, 0)
	body_mi.set_surface_override_material(0, _capsule_mat(body_color))
	_model_body.add_child(body_mi)
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.16
	head_mesh.height = 0.32
	var head_mi := MeshInstance3D.new()
	head_mi.mesh     = head_mesh
	head_mi.position = Vector3(0, 1.14, 0)
	head_mi.set_surface_override_material(0, _capsule_mat(head_color))
	_model_body.add_child(head_mi)

func _capsule_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness    = 0.85
	return mat

func set_facing(vel: Vector2) -> void:
	_is_moving = vel.length_squared() >= 0.5
	if not _is_moving:
		return
	_apply_facing_dir(HabboIsoFacing.snap_velocity(vel))

func get_facing_dir() -> int:
	return _current_dir

func set_facing_grid_step(step: Vector2i) -> void:
	if step == Vector2i.ZERO:
		return
	_is_moving = true
	_apply_facing_dir(HabboIsoFacing.dir_from_grid_step(step))
