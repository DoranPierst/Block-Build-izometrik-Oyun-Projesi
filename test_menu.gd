extends CanvasLayer

signal place_block_requested(
	size:      Vector2i,
	height:    int,
	multi:     bool,
	stackable: bool,
	walkable:  bool,
	wall:      bool,
)

# ── İzometrik ikon çizici ─────────────────────────────────────────────────────
class _TypeIcon extends Control:
	var is_wall := false
	var col     := Color(0.6, 0.6, 0.6)

	func _draw() -> void:
		var W := size.x
		var H := size.y
		if is_wall:
			_draw_wall(W, H)
		else:
			_draw_cube(W, H)

	func _draw_cube(W: float, H: float) -> void:
		var cx := W * 0.5;  var cy := H * 0.30
		var hw := W * 0.40; var hh := H * 0.18; var bh := H * 0.34
		var bdr := Color(0.0, 0.0, 0.0, 0.55)

		var top := PackedVector2Array([
			Vector2(cx, cy - hh), Vector2(cx + hw, cy),
			Vector2(cx, cy + hh), Vector2(cx - hw, cy)])
		draw_polygon(top, PackedColorArray([col.lightened(0.28)]))
		draw_polyline(PackedVector2Array([top[0],top[1],top[2],top[3],top[0]]), bdr, 1.0)

		var lft := PackedVector2Array([
			Vector2(cx - hw, cy),       Vector2(cx, cy + hh),
			Vector2(cx, cy + hh + bh),  Vector2(cx - hw, cy + bh)])
		draw_polygon(lft, PackedColorArray([col.darkened(0.12)]))
		draw_polyline(PackedVector2Array([lft[0],lft[1],lft[2],lft[3],lft[0]]), bdr, 1.0)

		var rgt := PackedVector2Array([
			Vector2(cx, cy + hh),       Vector2(cx + hw, cy),
			Vector2(cx + hw, cy + bh),  Vector2(cx, cy + hh + bh)])
		draw_polygon(rgt, PackedColorArray([col.darkened(0.36)]))
		draw_polyline(PackedVector2Array([rgt[0],rgt[1],rgt[2],rgt[3],rgt[0]]), bdr, 1.0)

	func _draw_wall(W: float, H: float) -> void:
		var bdr := Color(0.0, 0.0, 0.0, 0.55)
		var cx := W * 0.5; var hw := W * 0.43
		var top_y := H * 0.12; var bot_y := H * 0.72; var th := H * 0.10

		# ön yüz
		var face := PackedVector2Array([
			Vector2(cx - hw, top_y), Vector2(cx + hw, top_y),
			Vector2(cx + hw, bot_y), Vector2(cx - hw, bot_y)])
		draw_polygon(face, PackedColorArray([col]))
		draw_polyline(PackedVector2Array([face[0],face[1],face[2],face[3],face[0]]), bdr, 1.0)

		# alt kenar kalınlığı
		var bot := PackedVector2Array([
			Vector2(cx - hw, bot_y), Vector2(cx + hw, bot_y),
			Vector2(cx + hw, bot_y + th), Vector2(cx - hw, bot_y + th)])
		draw_polygon(bot, PackedColorArray([col.darkened(0.32)]))

# ─────────────────────────────────────────────────────────────────────────────

const BLOCK_SIZES := [
	Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
	Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3),
]
const WALL_SIZES := [
	Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
]
const HEIGHT_OPTS: Array[int] = [1, 2, 3, 4]

const BASE_TYPES := [
	{"name": "Blok",  "wall": false, "col": Color(0.50, 0.33, 0.10)},
	{"name": "Duvar", "wall": true,  "col": Color(0.70, 0.66, 0.58)},
]
const PROP_TYPES := [
	{"name": "Normal",         "stackable": false, "walkable": false},
	{"name": "Yığın",          "stackable": true,  "walkable": false},
	{"name": "Platform",       "stackable": false, "walkable": true},
	{"name": "Yığın+Platform", "stackable": true,  "walkable": true},
]

var _pending_size:      Vector2i
var _pending_height:    int  = 1
var _pending_stackable: bool = false
var _pending_walkable:  bool = false
var _pending_wall:      bool = false
var _active_height:     int  = 0
var _popup:             Panel
var _backdrop:          ColorRect
var _block_btns:        Array[Button] = []
var _size_grid:         GridContainer = null
var _win:               Control = null
var _panel:             Panel = null
var _drag_target:       Control = null
var _resize_target:     Control = null

const WIN_MIN_SIZE := Vector2(200.0, 400.0)
const WIN_DEFAULT_SIZE := Vector2(220.0, 548.0)
const HEADER_H := 36.0
const PANEL_GAP := 4.0

# ── Sürükleme / yeniden boyutlandırma ─────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if _resize_target:
		if event is InputEventMouseMotion:
			var rel := (event as InputEventMouseMotion).relative
			_resize_target.offset_right  += rel.x
			_resize_target.offset_bottom += rel.y
			_clamp_win_size()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton \
				and not (event as InputEventMouseButton).pressed:
			_resize_target = null
		return
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

func _clamp_win_size() -> void:
	if _win == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var w := clampf(_win.size.x, WIN_MIN_SIZE.x, vp.x - _win.position.x - 8.0)
	var h := clampf(_win.size.y, WIN_MIN_SIZE.y, vp.y - _win.position.y - 8.0)
	_win.offset_right  = _win.offset_left + w
	_win.offset_bottom = _win.offset_top + h

func _ready() -> void:
	_build_ui()

# ── UI inşası ─────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_win = Control.new()
	_win.offset_left   = 10.0
	_win.offset_top    = 10.0
	_win.offset_right  = 10.0 + WIN_DEFAULT_SIZE.x
	_win.offset_bottom = 10.0 + WIN_DEFAULT_SIZE.y
	_win.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	_win.clip_contents = true
	add_child(_win)

	# Başlık
	var header := HBoxContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = HEADER_H
	header.add_theme_constant_override("separation", 0)
	_win.add_child(header)
	header.add_child(_make_drag_handle(_win))

	var toggle := Button.new()
	toggle.text                  = "Test Menüsü"
	toggle.toggle_mode           = true
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(toggle)

	# Panel — header altında kalan alanı doldurur
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.offset_top = HEADER_H + PANEL_GAP
	_panel.offset_bottom = 0.0
	_panel.visible = false
	_win.add_child(_panel)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, 8)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	# ── Tür ikonları ──────────────────────────────────────────────────────────
	_add_section_label(vbox, "Tür")

	var type_row := HBoxContainer.new()
	type_row.alignment = BoxContainer.ALIGNMENT_CENTER
	type_row.add_theme_constant_override("separation", 10)
	vbox.add_child(type_row)

	var base_grp := ButtonGroup.new()
	for i in BASE_TYPES.size():
		var bt: Dictionary = BASE_TYPES[i]
		var btn := _make_icon_btn(bt["col"] as Color, bt["name"] as String,
								 bt["wall"] as bool, base_grp)
		btn.pressed.connect(_on_base_type.bind(i))
		if i == 0: btn.button_pressed = true
		type_row.add_child(btn)

	vbox.add_child(HSeparator.new())

	# ── Özellikler ────────────────────────────────────────────────────────────
	_add_section_label(vbox, "Özellik")

	var prop_grid := GridContainer.new()
	prop_grid.columns = 2
	prop_grid.add_theme_constant_override("h_separation", 4)
	prop_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(prop_grid)

	var prop_grp := ButtonGroup.new()
	for i in PROP_TYPES.size():
		var pt: Dictionary = PROP_TYPES[i]
		var btn := Button.new()
		btn.text                  = pt["name"] as String
		btn.toggle_mode           = true
		btn.button_group          = prop_grp
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_prop_type.bind(i))
		if i == 0: btn.button_pressed = true
		prop_grid.add_child(btn)

	vbox.add_child(HSeparator.new())

	# ── Yükseklik ─────────────────────────────────────────────────────────────
	_add_section_label(vbox, "Yükseklik")

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 2)
	vbox.add_child(hbox)

	var h_grp := ButtonGroup.new()
	for i in HEIGHT_OPTS.size():
		var h: int = HEIGHT_OPTS[i]
		var tab    := Button.new()
		tab.text                  = "%d×" % h
		tab.toggle_mode           = true
		tab.button_group          = h_grp
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_on_height_tab.bind(i))
		if i == 0: tab.button_pressed = true
		hbox.add_child(tab)

	vbox.add_child(HSeparator.new())

	# ── Boyut ─────────────────────────────────────────────────────────────────
	_add_section_label(vbox, "Boyut")

	_size_grid = GridContainer.new()
	_size_grid.columns = 2
	vbox.add_child(_size_grid)
	_refresh_size_buttons()

	vbox.add_child(HSeparator.new())
	_add_section_label(vbox, "Debug")

	var compass_row := HBoxContainer.new()
	compass_row.add_theme_constant_override("separation", 6)
	vbox.add_child(compass_row)

	var compass_cb := CheckButton.new()
	compass_cb.text = "Pusula"
	compass_cb.toggled.connect(_on_compass_toggled)
	compass_row.add_child(compass_cb)

	var facing_cb := CheckButton.new()
	facing_cb.text = "Bakış yönü"
	facing_cb.toggled.connect(_on_facing_badge_toggled)
	compass_row.add_child(facing_cb)

	toggle.toggled.connect(func(on: bool) -> void:
		_panel.visible = on
		if on:
			_clamp_win_size()
	)

	_win.add_child(_make_resize_grip(_win))

	# ── Backdrop ──────────────────────────────────────────────────────────────
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color        = Color(0, 0, 0, 0.001)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.visible      = false
	_backdrop.gui_input.connect(_on_backdrop_input)
	add_child(_backdrop)

	# ── Popup ─────────────────────────────────────────────────────────────────
	_popup      = Panel.new()
	_popup.size = Vector2(210, 115)
	_popup.visible = false
	add_child(_popup)

	var pvbox := VBoxContainer.new()
	pvbox.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	_popup.add_child(pvbox)

	var plbl := Label.new()
	plbl.text = "Yerleştirme Modu"
	plbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pvbox.add_child(plbl)
	pvbox.add_child(HSeparator.new())

	var b1 := Button.new()
	b1.text = "1 Adet Yerleştir"
	b1.pressed.connect(func() -> void: _emit(false))
	pvbox.add_child(b1)

	var b2 := Button.new()
	b2.text = "Çok Adet Yerleştir"
	b2.pressed.connect(func() -> void: _emit(true))
	pvbox.add_child(b2)

# ── Yardımcılar ───────────────────────────────────────────────────────────────

func _add_section_label(parent: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	parent.add_child(lbl)

func _make_icon_btn(col: Color, label: String, is_wall: bool,
					group: ButtonGroup) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(90, 90)
	btn.toggle_mode  = true
	btn.button_group = group

	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(7)
		match state:
			"normal":  sb.bg_color = col.darkened(0.28)
			"hover":   sb.bg_color = col
			"pressed":
				sb.bg_color = col.lightened(0.18)
				sb.border_width_left   = 2; sb.border_width_right  = 2
				sb.border_width_top    = 2; sb.border_width_bottom = 2
				sb.border_color = Color.WHITE
			"focus": sb.bg_color = col.darkened(0.28)
		btn.add_theme_stylebox_override(state, sb)

	# İkon çizici
	var icon := _TypeIcon.new()
	icon.is_wall        = is_wall
	icon.col            = col.lightened(0.12)
	icon.anchor_left    = 0.0; icon.anchor_top    = 0.0
	icon.anchor_right   = 1.0; icon.anchor_bottom = 1.0
	icon.offset_bottom  = -22
	icon.mouse_filter   = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)

	# Alt etiket
	var lbl := Label.new()
	lbl.text                     = label
	lbl.horizontal_alignment     = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment       = VERTICAL_ALIGNMENT_BOTTOM
	lbl.anchor_left   = 0.0; lbl.anchor_top    = 0.75
	lbl.anchor_right  = 1.0; lbl.anchor_bottom = 1.0
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)

	return btn

func _on_compass_toggled(on: bool) -> void:
	var comp := get_parent().get_node_or_null("CompassUI")
	if comp and comp.has_method("set_enabled"):
		comp.call("set_enabled", on)

func _on_facing_badge_toggled(on: bool) -> void:
	_set_facing_badge_recursive(get_parent(), on)
	var arrow := get_parent().get_node_or_null("FacingArrowOverlay")
	if arrow and arrow.has_method("set_enabled"):
		arrow.call("set_enabled", on)

func _set_facing_badge_recursive(node: Node, on: bool) -> void:
	if node.has_method("set_facing_badge_enabled"):
		node.call("set_facing_badge_enabled", on)
	for ch in node.get_children():
		_set_facing_badge_recursive(ch, on)

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

func _make_resize_grip(target: Control) -> Control:
	var grip := Panel.new()
	grip.name = "ResizeGrip"
	grip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grip.offset_left   = -20.0
	grip.offset_top    = -20.0
	grip.offset_right  =   0.0
	grip.offset_bottom =   0.0
	grip.custom_minimum_size = Vector2(20, 20)
	grip.mouse_filter = Control.MOUSE_FILTER_STOP
	grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	grip.z_index = 10

	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.30, 0.30, 0.30, 0.85)
	sbox.corner_radius_bottom_right = 6
	sbox.corner_radius_top_left     = 2
	grip.add_theme_stylebox_override("panel", sbox)

	var lbl := Label.new()
	lbl.text = "◢"
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grip.add_child(lbl)

	grip.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			_resize_target = target if e.pressed else null
	)
	return grip

# ── Olaylar ───────────────────────────────────────────────────────────────────

func _make_label(sz: Vector2i) -> String:
	return "%d×%d×%d" % [sz.x, sz.y, HEIGHT_OPTS[_active_height]]

func _current_sizes() -> Array:
	return WALL_SIZES if _pending_wall else BLOCK_SIZES

func _refresh_size_buttons() -> void:
	for btn in _block_btns:
		btn.queue_free()
	_block_btns.clear()
	for sz in _current_sizes():
		var btn := Button.new()
		btn.text = _make_label(sz)
		btn.pressed.connect(_on_block_btn.bind(sz))
		_size_grid.add_child(btn)
		_block_btns.append(btn)

func _on_base_type(index: int) -> void:
	_pending_wall = BASE_TYPES[index]["wall"] as bool
	_refresh_size_buttons()

func _on_prop_type(index: int) -> void:
	_pending_stackable = PROP_TYPES[index]["stackable"] as bool
	_pending_walkable  = PROP_TYPES[index]["walkable"]  as bool

func _on_height_tab(idx: int) -> void:
	_active_height  = idx
	_pending_height = HEIGHT_OPTS[idx]
	var sizes := _current_sizes()
	for i in _block_btns.size():
		_block_btns[i].text = _make_label(sizes[i])

func _on_block_btn(sz: Vector2i) -> void:
	_pending_size = sz
	var vp := get_viewport().get_visible_rect().size
	var mp := get_viewport().get_mouse_position()
	_popup.position = (mp + Vector2(10, 10)).clamp(
		Vector2.ZERO, vp - _popup.size - Vector2(4, 4))
	_popup.visible    = true
	_backdrop.visible = true

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_popup.visible    = false
		_backdrop.visible = false

func _emit(multi: bool) -> void:
	_popup.visible    = false
	_backdrop.visible = false
	place_block_requested.emit(
		_pending_size, _pending_height, multi,
		_pending_stackable, _pending_walkable, _pending_wall,
	)
