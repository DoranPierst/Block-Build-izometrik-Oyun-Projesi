extends CanvasLayer

## İzometrik grid pusulası — etiketler 45° kaydırılmış (eski düzen).
## Açı = harfin gerçek yönü (G→Güney, GD→Güneydoğu). Sağ alt, sürüklenebilir.

const GRID_AXIS_IDX := [0, 2, 4, 6]   # N, E, S, W — yeşil grid ekseni
const GRID_DIAG_IDX := [1, 3, 5, 7]   # NE, SE, SW, NW — kırmızı çapraz

var _win:         Control
var _panel:       Panel
var _compass:     Control
var _info:        Label
var _player:      CharacterBody2D
var _facing_dir:  int = -1
var _move_step:   Vector2i = Vector2i.ZERO
var _walk_dir:    int = -1
var _drag_target: Control = null

func _ready() -> void:
	layer = 20
	add_to_group("compass_ui")
	_player = get_parent().get_node_or_null("Player") as CharacterBody2D
	_build_ui()
	set_enabled(false)

func _input(event: InputEvent) -> void:
	if _drag_target == null:
		return
	if event is InputEventMouseMotion:
		var rel := (event as InputEventMouseMotion).relative
		_drag_target.offset_left   += rel.x
		_drag_target.offset_top    += rel.y
		_drag_target.offset_right  += rel.x
		_drag_target.offset_bottom += rel.y
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton \
			and not (event as InputEventMouseButton).pressed:
		_drag_target = null

func _process(_delta: float) -> void:
	if not _win.visible:
		return
	_update_state()
	if _compass:
		_compass.queue_redraw()

func set_enabled(on: bool) -> void:
	if _win:
		_win.visible = on

func is_enabled() -> bool:
	return _win != null and _win.visible

func _update_state() -> void:
	if _player == null:
		return
	var cv := _find_character_view(_player)
	if cv and cv.has_method("get_facing_dir"):
		_facing_dir = cv.call("get_facing_dir")
	if _player.has_method("get_move_step"):
		_move_step = _player.call("get_move_step")
	_walk_dir = IsoFacing.dir_from_grid_step(_move_step) \
		if _move_step != Vector2i.ZERO else -1
	_update_info_label()

func _find_character_view(root: Node) -> Node:
	return _search_character_view(root)

func _search_character_view(node: Node) -> Node:
	if node.has_method("get_facing_dir"):
		return node
	for ch in node.get_children():
		var f := _search_character_view(ch)
		if f:
			return f
	return null

func _update_info_label() -> void:
	if _info == null:
		return
	var warn := ""
	if _walk_dir >= 0 and _facing_dir >= 0 and _walk_dir != _facing_dir:
		warn = "\n⚠ Bakış ≠ yürüyüş"

	var pos_line := "konum —"
	if _player and _player.has_method("get_relative_position"):
		var p: Vector3 = _player.call("get_relative_position")
		pos_line = "konum x:%.0f y:%.0f z:%.0f" % [p.x, p.y, p.z]

	if _move_step != Vector2i.ZERO:
		_info.text = "%s\nYürüyüş: %s  %s%s" % [
			pos_line,
			_compass_name(_walk_dir),
			_fmt_facing(_walk_dir),
			warn,
		]
	else:
		var face := _compass_name(_facing_dir) if _facing_dir >= 0 else "—"
		var extra := _fmt_facing(_facing_dir) if _facing_dir >= 0 else ""
		_info.text = "%s\nDuruyor — %s  %s%s" % [pos_line, face, extra, warn]

func _compass_name(grid_dir: int) -> String:
	return IsoFacing.grid_spoke_compass_name(grid_dir)

func _fmt_facing(dir: int) -> String:
	var facing: Dictionary = IsoFacing.get_model_facing_for_grid(dir)
	var flip_txt := " flip" if facing["flip"] else ""
	var yaw := fmod((facing["yaw"] as float) + 360.0, 360.0)
	return "yaw %s°%s" % [str(snapped(yaw, 0.1)), flip_txt]

func _build_ui() -> void:
	_win = Control.new()
	_win.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_win.offset_left   = -268.0
	_win.offset_right  =  -12.0
	_win.offset_top    = -332.0
	_win.offset_bottom =  -12.0
	_win.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_win)

	var header := HBoxContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = 30.0
	header.add_theme_constant_override("separation", 0)
	_win.add_child(header)
	header.add_child(_make_drag_handle(_win))

	var toggle := Button.new()
	toggle.text                  = "Pusula"
	toggle.toggle_mode           = true
	toggle.button_pressed        = true
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(toggle)

	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_top = 34.0
	_win.add_child(_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_compass = _CompassRose.new()
	_compass.custom_minimum_size = Vector2(220, 220)
	_compass.clip_contents = false
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_compass)

	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 11)
	_info.add_theme_color_override("font_color", Color(0.88, 0.90, 0.95))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_info)

	toggle.toggled.connect(func(on: bool) -> void: _panel.visible = on)

func _make_drag_handle(target: Control) -> Control:
	var h := Panel.new()
	h.custom_minimum_size        = Vector2(18, 0)
	h.size_flags_vertical        = Control.SIZE_EXPAND_FILL
	h.mouse_filter               = Control.MOUSE_FILTER_STOP
	h.mouse_default_cursor_shape = Control.CURSOR_DRAG

	var sbox := StyleBoxFlat.new()
	sbox.bg_color                  = Color(0.25, 0.25, 0.25, 0.92)
	sbox.corner_radius_top_left    = 4
	sbox.corner_radius_bottom_left = 4
	h.add_theme_stylebox_override("panel", sbox)

	var lbl := Label.new()
	lbl.text = "⠿"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(lbl)

	h.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			_drag_target = target if e.pressed else null
	)
	return h

func _get_highlight_dir() -> int:
	return _walk_dir if _walk_dir >= 0 else _facing_dir

class _CompassRose extends Control:
	const AXIS_SPOKE_R  := 0.50
	const DIAG_SPOKE_R  := 0.42
	const AXIS_LABEL_R  := 0.88
	const DIAG_LABEL_R  := 0.84
	const LABEL_Y_SHIFT := 6.0
	const LABEL_NUDGE: Array[Vector2] = [
		Vector2(-1, 0),   # grid N  → KB
		Vector2( 0, 0),   # grid NE → K
		Vector2( 1, 0),   # grid E  → KD
		Vector2( 2, 1),   # grid SE → D
		Vector2( 1, 2),   # grid S  → GD
		Vector2( 0, 3),   # grid SW → G
		Vector2(-1, 2),   # grid W  → GB
		Vector2(-2, 1),   # grid NW → B
	]

	func _draw() -> void:
		var layer := get_tree().get_first_node_in_group("compass_ui")
		var hi := -1
		if layer and layer.has_method("_get_highlight_dir"):
			hi = layer._get_highlight_dir()

		var cx := size.x * 0.5
		var cy := size.y * 0.5
		var R  := minf(size.x, size.y) * 0.43
		var center := Vector2(cx, cy)

		draw_circle(center, R, Color(0.07, 0.09, 0.13, 0.94))
		draw_arc(center, R, 0.0, TAU, 72, Color(0.38, 0.44, 0.52), 1.8)
		draw_arc(center, R * 0.50, 0.0, TAU, 48, Color(0.22, 0.26, 0.32, 0.55), 1.0)

		_draw_center_tile(center, R)

		for i in GRID_DIAG_IDX:
			_draw_spoke(i, center, R, hi, false)
		for i in GRID_AXIS_IDX:
			_draw_spoke(i, center, R, hi, true)

		for i in 8:
			var letter_i := _label_index(i)
			var is_axis := i in GRID_AXIS_IDX
			var pos := _label_pos(i, center, R, is_axis)
			var col := Color(0.50, 0.96, 0.55) if is_axis else Color(0.96, 0.52, 0.44)
			if i == hi:
				col = Color(1.0, 0.92, 0.22)
			# Etiket eski konumda; açı harfin yönüne göre (G≠grid kolu).
			var facing := IsoFacing.get_model_facing(letter_i)
			_draw_label(
				IsoFacing.COMPASS_SHORT[letter_i],
				pos, col, is_axis,
				facing["yaw"] as float,
				facing["flip"] as bool
			)

	func _label_index(grid_i: int) -> int:
		return (grid_i + 7) % 8

	func _label_pos(grid_i: int, center: Vector2, R: float, axis: bool) -> Vector2:
		var v: Vector2 = IsoFacing.DIR_VECTORS[grid_i]
		var ring := AXIS_LABEL_R if axis else DIAG_LABEL_R
		return center + v * (R * ring) + LABEL_NUDGE[grid_i] + Vector2(0.0, LABEL_Y_SHIFT)

	func _draw_spoke(grid_i: int, center: Vector2, R: float, hi: int, axis: bool) -> void:
		var v: Vector2 = IsoFacing.DIR_VECTORS[grid_i]
		var len := R * (AXIS_SPOKE_R if axis else DIAG_SPOKE_R)
		var col := Color(0.32, 0.90, 0.44, 0.95) if axis else Color(0.92, 0.38, 0.34, 0.82)
		if grid_i == hi:
			col = Color(1.0, 0.90, 0.20, 1.0)
		draw_line(center, center + v * len, col, 2.2 if axis else 1.5)

	func _draw_center_tile(center: Vector2, R: float) -> void:
		var hw := R * 0.19
		var hh := R * 0.095
		var tile := PackedVector2Array([
			center + Vector2(0.0, -hh),
			center + Vector2(hw, 0.0),
			center + Vector2(0.0, hh),
			center + Vector2(-hw, 0.0),
		])
		draw_colored_polygon(tile, Color(0.14, 0.17, 0.21, 0.95))
		draw_polyline(tile + PackedVector2Array([tile[0]]),
			Color(0.48, 0.54, 0.62), 1.3)

	func _draw_label(
			text: String, at: Vector2, col: Color, axis: bool,
			yaw_deg: float = -999.0, flip: bool = false) -> void:
		var font := ThemeDB.fallback_font
		var fs := 13 if axis else 11
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		var pos := at - Vector2(ts.x * 0.5, ts.y * 0.9)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		if yaw_deg > -900.0:
			var norm_yaw := fmod(yaw_deg + 360.0, 360.0)
			var angle_txt := "%.0f°" % snappedf(norm_yaw, 0.1)
			if flip:
				angle_txt += " f"
			var afs := 9
			var acol := Color(col.r, col.g, col.b, 0.85)
			var ats := font.get_string_size(angle_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, afs)
			var apos := at + Vector2(-ats.x * 0.5, ts.y * 0.42)
			draw_string(font, apos, angle_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, afs, acol)
