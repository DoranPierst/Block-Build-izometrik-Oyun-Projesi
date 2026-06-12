extends Control

## 8 izometrik yönün görsel önizlemesi (Kuzey, Kuzeybatı, …).
## Sahneyi F6 ile çalıştırın veya ana sahneye geçici ekleyin.

const CELL_W := 120
const CELL_H := 150
const VP_SIZE := Vector2i(72, 96)
const RENDER_SCALE := 2
const CAM_ORTHO := 1.7

## Referans diyagram düzeni (merkez = Güneybatı / kameraya dönük).
const GRID_SLOTS: Array[Dictionary] = [
	{ "dir": HabboIsoFacing.Dir.NW, "col": 0, "row": 0 },
	{ "dir": HabboIsoFacing.Dir.N,  "col": 1, "row": 0 },
	{ "dir": HabboIsoFacing.Dir.NE, "col": 2, "row": 0 },
	{ "dir": HabboIsoFacing.Dir.W,  "col": 0, "row": 1 },
	{ "dir": HabboIsoFacing.Dir.SW, "col": 1, "row": 1 },
	{ "dir": HabboIsoFacing.Dir.E,  "col": 2, "row": 1 },
	{ "dir": HabboIsoFacing.Dir.S,  "col": 1, "row": 2 },
	{ "dir": HabboIsoFacing.Dir.SE, "col": 2, "row": 2 },
]

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(40, 40)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var title := Label.new()
	title.text = "Habbo Karakter — 8 Yön Görünümü"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	margin.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	margin.add_child(grid)

	# 3×3 hücre; orta alt boş (yön yok).
	for row in 3:
		for col in 3:
			var slot: Dictionary = {}
			for s in GRID_SLOTS:
				if s["col"] == col and s["row"] == row:
					slot = s
					break
			if slot.is_empty():
				var spacer := Control.new()
				spacer.custom_minimum_size = Vector2(CELL_W, CELL_H)
				grid.add_child(spacer)
			else:
				grid.add_child(_make_direction_cell(slot["dir"] as int))

func _make_direction_cell(dir: int) -> Control:
	var cell := VBoxContainer.new()
	cell.custom_minimum_size = Vector2(CELL_W, CELL_H)
	cell.alignment = BoxContainer.ALIGNMENT_CENTER

	var label := Label.new()
	label.text = HabboIsoFacing.dir_name(dir)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cell.add_child(label)

	var scale_i := maxi(RENDER_SCALE, 1)
	var vp := SubViewport.new()
	vp.size = VP_SIZE * scale_i
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	cell.add_child(vp)

	_setup_viewport_env(vp)
	_build_habbo_in_viewport(vp, dir)

	var tex_rect := TextureRect.new()
	tex_rect.texture = vp.get_texture()
	tex_rect.custom_minimum_size = Vector2(VP_SIZE)
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cell.add_child(tex_rect)
	return cell

func _setup_viewport_env(vp: SubViewport) -> void:
	var wenv := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.14, 0.18, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.75
	wenv.environment = env
	vp.add_child(wenv)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 45, 0)
	sun.light_energy = 0.85
	vp.add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -135, 0)
	fill.light_energy = 0.40
	vp.add_child(fill)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CAM_ORTHO
	cam.rotation_degrees = Vector3(-26.565, 45.0, 0.0)
	vp.add_child(cam)
	cam.translate_object_local(Vector3(0, 0, 12))

func _build_habbo_in_viewport(vp: SubViewport, dir: int) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0.0, -(CAM_ORTHO * 0.5), 0.0)
	vp.add_child(root)

	var body := Node3D.new()
	body.name = "HabboBody"
	root.add_child(body)

	var avatar := HabboCharacterMesh.build(body, HabboCharacterMesh.Colors.new())
	var facing: Dictionary = HabboIsoFacing.get_facing(dir)
	body.rotation_degrees.y = facing["yaw"]
	HabboCharacterMesh.set_direction_view(avatar, dir)
	if facing["flip"]:
		avatar.scale.x = -1.0
	return body
