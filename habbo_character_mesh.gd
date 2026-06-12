class_name HabboCharacterMesh
extends RefCounted

## Habbo Hotel tarzı bloklu karakter — tamamen kod ile, harici asset yok.

class Colors:
	var skin:  Color = Color(0.96, 0.82, 0.68)
	var hair:  Color = Color(0.36, 0.22, 0.10)
	var shirt: Color = Color(0.18, 0.55, 0.92)
	var pants: Color = Color(0.20, 0.26, 0.42)
	var shoes: Color = Color(0.12, 0.12, 0.14)
	var eyes:  Color = Color(0.08, 0.08, 0.10)
	var mouth: Color = Color(0.55, 0.30, 0.28)
	var belt:  Color = Color(0.10, 0.10, 0.12)

static func build(parent: Node3D, colors: Colors = null) -> Node3D:
	var c := colors if colors else Colors.new()
	var root := Node3D.new()
	root.name = "HabboAvatar"
	parent.add_child(root)

	var face := Node3D.new()
	face.name = "Face"
	root.add_child(face)

	# ── Ayaklar ──────────────────────────────────────────────────────────────
	_box(root, "ShoeL", Vector3(-0.09, 0.045, 0.02), Vector3(0.12, 0.07, 0.20), c.shoes)
	_box(root, "ShoeR", Vector3( 0.09, 0.045, 0.02), Vector3(0.12, 0.07, 0.20), c.shoes)

	# ── Bacaklar ─────────────────────────────────────────────────────────────
	_box(root, "LegL_Lower", Vector3(-0.09, 0.21, 0.01), Vector3(0.11, 0.26, 0.12), c.pants)
	_box(root, "LegR_Lower", Vector3( 0.09, 0.21, 0.01), Vector3(0.11, 0.26, 0.12), c.pants)
	_box(root, "LegL_Upper", Vector3(-0.09, 0.40, 0.01), Vector3(0.10, 0.18, 0.11), c.pants)
	_box(root, "LegR_Upper", Vector3( 0.09, 0.40, 0.01), Vector3(0.10, 0.18, 0.11), c.pants)

	# ── Gövde ─────────────────────────────────────────────────────────────────
	_box(root, "Torso", Vector3(0.0, 0.58, 0.0), Vector3(0.34, 0.30, 0.20), c.shirt)
	_box(root, "Collar", Vector3(0.0, 0.70, 0.06), Vector3(0.18, 0.06, 0.06), c.shirt.lightened(0.12))
	_box(root, "Belt", Vector3(0.0, 0.46, 0.02), Vector3(0.32, 0.05, 0.14), c.belt)

	# ── Kollar ───────────────────────────────────────────────────────────────
	_box(root, "ArmL_Upper", Vector3(-0.24, 0.58, 0.0), Vector3(0.10, 0.22, 0.11), c.shirt)
	_box(root, "ArmR_Upper", Vector3( 0.24, 0.58, 0.0), Vector3(0.10, 0.22, 0.11), c.shirt)
	_box(root, "ArmL_Lower", Vector3(-0.24, 0.40, 0.0), Vector3(0.09, 0.20, 0.10), c.skin)
	_box(root, "ArmR_Lower", Vector3( 0.24, 0.40, 0.0), Vector3(0.09, 0.20, 0.10), c.skin)
	_box(root, "HandL", Vector3(-0.24, 0.28, 0.02), Vector3(0.08, 0.08, 0.08), c.skin)
	_box(root, "HandR", Vector3( 0.24, 0.28, 0.02), Vector3(0.08, 0.08, 0.08), c.skin)

	# ── Boyun + kafa ─────────────────────────────────────────────────────────
	_box(root, "Neck", Vector3(0.0, 0.76, 0.02), Vector3(0.10, 0.06, 0.09), c.skin)
	_sphere(root, "Head", Vector3(0.0, 0.96, 0.0), 0.19, Vector3(1.0, 0.94, 0.96), c.skin)

	# ── Saç (ön + arka) ──────────────────────────────────────────────────────
	var hair_front := Node3D.new()
	hair_front.name = "HairFront"
	root.add_child(hair_front)
	_box(hair_front, "HairTop", Vector3(0.0, 1.12, -0.01), Vector3(0.30, 0.10, 0.28), c.hair)
	_box(hair_front, "HairBangs", Vector3(0.0, 1.06, -0.10), Vector3(0.32, 0.14, 0.10), c.hair)
	_box(hair_front, "HairSideL", Vector3(-0.14, 0.98, 0.04), Vector3(0.08, 0.18, 0.12), c.hair)
	_box(hair_front, "HairSideR", Vector3( 0.14, 0.98, 0.04), Vector3(0.08, 0.18, 0.12), c.hair)

	var hair_back := Node3D.new()
	hair_back.name = "HairBack"
	root.add_child(hair_back)
	_box(hair_back, "HairBackTop", Vector3(0.0, 1.10, -0.14), Vector3(0.28, 0.12, 0.10), c.hair.darkened(0.08))
	_box(hair_back, "HairBackBase", Vector3(0.0, 0.96, -0.18), Vector3(0.26, 0.20, 0.08), c.hair.darkened(0.12))

	# ── Yüz (ön) ─────────────────────────────────────────────────────────────
	_box(face, "EyeL", Vector3(-0.07, 0.97, 0.16), Vector3(0.05, 0.05, 0.02), c.eyes)
	_box(face, "EyeR", Vector3( 0.07, 0.97, 0.16), Vector3(0.05, 0.05, 0.02), c.eyes)
	_box(face, "EyeGlowL", Vector3(-0.06, 0.98, 0.175), Vector3(0.018, 0.018, 0.01), Color.WHITE)
	_box(face, "EyeGlowR", Vector3( 0.08, 0.98, 0.175), Vector3(0.018, 0.018, 0.01), Color.WHITE)
	_box(face, "Mouth", Vector3(0.0, 0.90, 0.165), Vector3(0.06, 0.025, 0.02), c.mouth)

	return root

static func set_direction_view(avatar: Node3D, dir: int) -> void:
	if avatar == null:
		return
	var face := avatar.get_node_or_null("Face") as Node3D
	var hair_f := avatar.get_node_or_null("HairFront") as Node3D
	var hair_b := avatar.get_node_or_null("HairBack") as Node3D
	# Yüz her zaman açık — 3D rotasyonla gittiği yöne bakar.
	var toward_cam: float = HabboIsoFacing.toward_camera_amount(dir)
	var front_hair: bool = toward_cam > -0.25
	if face:
		face.visible = true
	if hair_f:
		hair_f.visible = front_hair
	if hair_b:
		hair_b.visible = not front_hair

static func _box(parent: Node3D, node_name: String, pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = pos
	mi.set_surface_override_material(0, _mat(color))
	parent.add_child(mi)

static func _sphere(parent: Node3D, node_name: String, pos: Vector3, radius: float, scale: Vector3, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.position = pos
	mi.scale = scale
	mi.set_surface_override_material(0, _mat(color))
	parent.add_child(mi)

static func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
