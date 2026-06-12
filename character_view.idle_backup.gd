extends Node2D

## YEDEK — Idle karakter (Mixamo). Geri dönmek için player.gd içinde:
##   load("res://character_view.idle_backup.gd")

@export var cam_ortho_size: float    = 1.7
@export var vp_size:        Vector2i = Vector2i(72, 96)
@export_range(1, 4, 1) var render_scale: int = 2
@export var ground_offset:  Vector2  = Vector2(0.0, 6.0)

@export var use_fbx_model:  bool    = true
@export_file("*.fbx", "*.glb", "*.gltf", "*.scn", "*.tscn") var model_path: String = "res://assets/characters/Idle.fbx"
@export var model_correction_rotation: Vector3 = Vector3.ZERO
@export var model_facing_offset_deg: float = 90.0
@export var model_extra_scale:    float   = 1.0
@export var model_extra_position: Vector3 = Vector3.ZERO

@export var body_color: Color = Color(0.25, 0.45, 0.80)
@export var head_color: Color = Color(0.88, 0.72, 0.58)

const TARGET_HEIGHT := 1.1
const MODEL_FALLBACKS: Array[String] = [
	"res://assets/characters/Idle.fbx",
	"res://.godot/imported/Idle.fbx-8a6b99c3f39a286d07c69099650ee048.scn",
	"res://assets/characters/Breathing Idle.fbx",
]

var _vp:     SubViewport
var _sprite: Sprite2D
var _root:   Node3D

func _ready() -> void:
	_build_viewport()
	if use_fbx_model and _try_load_fbx_model():
		return
	_build_capsule_character()

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
	env.ambient_light_energy = 0.6
	wenv.environment = env
	_vp.add_child(wenv)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 45, 0)
	sun.light_energy     = 1.0
	_vp.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -135, 0)
	fill.light_energy     = 0.45
	_vp.add_child(fill)

	var cam := Camera3D.new()
	cam.projection       = Camera3D.PROJECTION_ORTHOGONAL
	cam.size             = cam_ortho_size
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

func _create_character_root() -> void:
	_root = Node3D.new()
	_root.position = Vector3(0.0, -(cam_ortho_size * 0.5), 0.0)
	_vp.add_child(_root)

func _try_load_fbx_model() -> bool:
	var paths: Array[String] = []
	if not model_path.is_empty():
		paths.append(model_path)
	for fb in MODEL_FALLBACKS:
		if fb not in paths:
			paths.append(fb)

	for path in paths:
		if _load_single_model(path):
			print("CharacterView: model yüklendi → ", path)
			return true

	push_warning("CharacterView: hiçbir FBX yüklenemedi → kapsül kullanılacak.")
	return false

func _cleanup_failed_model_load() -> void:
	if _root and is_instance_valid(_root):
		_root.queue_free()
	_root = null

func _load_single_model(path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return false

	_create_character_root()

	var pivot := Node3D.new()
	pivot.name = "ModelPivot"
	_root.add_child(pivot)

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

	pivot.rotation_degrees = model_correction_rotation
	_auto_upright(pivot)
	pivot.rotate_object_local(Vector3.UP, deg_to_rad(model_facing_offset_deg))
	_fit_model(pivot)
	_play_idle_animation(content)
	return true

func _auto_upright(pivot: Node3D) -> void:
	var aabb := _combined_aabb(pivot)
	if aabb.size.length() < 0.001:
		return
	var s := aabb.size
	if s.y >= s.x * 0.85 and s.y >= s.z * 0.85:
		return
	if s.x >= s.z:
		pivot.rotate_object_local(Vector3.FORWARD, deg_to_rad(90.0))
	else:
		pivot.rotate_object_local(Vector3.RIGHT, deg_to_rad(-90.0))

func _combined_aabb(root: Node3D) -> AABB:
	var mins := Vector3(INF, INF, INF)
	var maxs := Vector3(-INF, -INF, -INF)
	var found := false
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := mi as MeshInstance3D
		var ab        := mesh_inst.get_aabb()
		var rel       := root.global_transform.affine_inverse() * mesh_inst.global_transform
		for i in 8:
			var pt := rel * ab.get_endpoint(i)
			mins  = mins.min(pt)
			maxs  = maxs.max(pt)
			found = true
	if not found:
		return AABB()
	return AABB(mins, maxs - mins)

func _fit_model(model: Node3D) -> void:
	var aabb := _combined_aabb(model)
	if aabb.size.y < 0.001:
		push_warning("CharacterView: model AABB boş — varsayılan ölçek uygulanıyor.")
		model.scale    = Vector3.ONE * 0.01 * model_extra_scale
		model.position = model_extra_position
		return

	var s := (TARGET_HEIGHT / aabb.size.y) * model_extra_scale
	model.scale    = Vector3.ONE * s
	var foot_y     := aabb.position.y * s
	var center_xz  := aabb.get_center() * s
	model.position = Vector3(-center_xz.x, -foot_y, -center_xz.z) + model_extra_position

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_anim_player(child)
		if found:
			return found
	return null

func _play_idle_animation(model: Node) -> void:
	var ap := _find_anim_player(model)
	if ap == null:
		return
	for anim_name: String in ap.get_animation_list():
		if "idle" in anim_name.to_lower():
			ap.play(anim_name)
			var anim: Animation = ap.get_animation(anim_name)
			if anim:
				anim.loop_mode = Animation.LOOP_LINEAR
			ap.advance(0.0)
			return
	var list := ap.get_animation_list()
	if list.size() > 0:
		ap.play(list[0])
		ap.advance(0.0)

func _build_capsule_character() -> void:
	_create_character_root()

	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.18
	body_mesh.height = 0.80
	var body_mi := MeshInstance3D.new()
	body_mi.mesh     = body_mesh
	body_mi.position = Vector3(0, 0.60, 0)
	body_mi.set_surface_override_material(0, _mat(body_color))
	_root.add_child(body_mi)

	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.16
	head_mesh.height = 0.32
	var head_mi := MeshInstance3D.new()
	head_mi.mesh     = head_mesh
	head_mi.position = Vector3(0, 1.14, 0)
	head_mi.set_surface_override_material(0, _mat(head_color))
	_root.add_child(head_mi)

	_add_leg(Vector3(-0.09, 0.0, 0.0))
	_add_leg(Vector3( 0.09, 0.0, 0.0))
	_add_arm(Vector3(-0.28, 0.72, 0.0))
	_add_arm(Vector3( 0.28, 0.72, 0.0))

func _add_leg(offset: Vector3) -> void:
	var m := CapsuleMesh.new()
	m.radius = 0.07
	m.height = 0.38
	var mi := MeshInstance3D.new()
	mi.mesh     = m
	mi.position = offset + Vector3(0, 0.19, 0)
	mi.set_surface_override_material(0, _mat(Color(0.20, 0.20, 0.35)))
	_root.add_child(mi)

func _add_arm(offset: Vector3) -> void:
	var m := CapsuleMesh.new()
	m.radius = 0.065
	m.height = 0.36
	var mi := MeshInstance3D.new()
	mi.mesh     = m
	mi.position = offset
	mi.rotation_degrees = Vector3(0, 0, 20 if offset.x < 0 else -20)
	mi.set_surface_override_material(0, _mat(body_color))
	_root.add_child(mi)

func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness    = 0.85
	return mat

func set_facing(vel: Vector2) -> void:
	if vel.length_squared() < 0.5 or _root == null:
		return
	var dir := Vector3(vel.x - vel.y, 0.0, vel.x + vel.y).normalized()
	_root.rotation_degrees.y = rad_to_deg(atan2(dir.x, dir.z))
