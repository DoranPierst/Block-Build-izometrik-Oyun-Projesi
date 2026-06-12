extends Camera2D

enum Mode { FIXED, FULL, EDGE }

@export var follow_speed: float = 8.0
@export var edge_margin:  float = 150.0
@export var zoom_min:       float = 0.25
@export var zoom_max:       float = 10.0   # %1000
@export var fast_click_ms:  float = 0.40   # saniye eşiği

var mode: Mode = Mode.FULL
var player: Node2D
var _recentering:    bool  = false
var _zoom_label:     Label
var _last_click_time: float = -999.0
var _fast_chain:      int   = 0   # ard arda hızlı tık sayısı

# Grid görünürlük döngüsü: 0 = varsayılan | 1 = belirgin | 2 = soluk
var _grid_state:    int    = 0
var _grid_btn:      Button = null
var _iso_grid:      Node   = null
var _zoom_panel:    Control = null

# ── Drag ──────────────────────────────────────────────────────────────────────
var _drag_target: Control = null

func _input(event: InputEvent) -> void:
	if _drag_target == null: return
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

# Her durum için grid çizgi ve dolgu opaklıkları
const GRID_STATES := [
	# [floor_a, line_a, hover_line_a]
	[1.00, 0.70, 0.85],   # 0 = varsayılan
	[1.00, 1.00, 1.00],   # 1 = belirgin
	[1.00, 0.18, 0.40],   # 2 = soluk
]

func _ready() -> void:
	player      = get_parent().get_node("Player")
	_iso_grid   = get_parent().get_node_or_null("IsoGrid")
	global_position = player.global_position
	position_smoothing_enabled = false
	_build_zoom_ui()

func _build_zoom_ui() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 10
	add_child(cl)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(12, -12)
	panel.offset_bottom = 0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var ps := StyleBoxFlat.new()
	ps.bg_color        = Color(0.08, 0.08, 0.08, 0.82)
	ps.corner_radius_top_left     = 6
	ps.corner_radius_top_right    = 6
	ps.corner_radius_bottom_left  = 6
	ps.corner_radius_bottom_right = 6
	ps.content_margin_left   = 8
	ps.content_margin_right  = 8
	ps.content_margin_top    = 5
	ps.content_margin_bottom = 5
	panel.add_theme_stylebox_override("panel", ps)
	cl.add_child(panel)
	_zoom_panel = panel

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	panel.add_child(hbox)

	# ── Drag handle ───────────────────────────────────────────────────────────
	var drag_h := Panel.new()
	drag_h.custom_minimum_size        = Vector2(14, 0)
	drag_h.size_flags_vertical        = Control.SIZE_EXPAND_FILL
	drag_h.mouse_filter               = Control.MOUSE_FILTER_STOP
	drag_h.mouse_default_cursor_shape = Control.CURSOR_DRAG
	var drag_sbox := StyleBoxFlat.new()
	drag_sbox.bg_color = Color(0.25, 0.25, 0.25, 0.0)   # panelin kendi stili yeter
	drag_h.add_theme_stylebox_override("panel", drag_sbox)
	var drag_lbl := Label.new()
	drag_lbl.text = "⠿"
	drag_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drag_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drag_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	drag_lbl.add_theme_font_size_override("font_size", 11)
	drag_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	drag_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	drag_h.add_child(drag_lbl)
	hbox.add_child(drag_h)

	var drag_sep := VSeparator.new()
	drag_sep.custom_minimum_size = Vector2(1, 16)
	drag_sep.modulate = Color(1, 1, 1, 0.20)
	hbox.add_child(drag_sep)

	# Drag: _input()'a bırakıyoruz, burada sadece hedef atanıyor
	drag_h.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			_drag_target = panel if e.pressed else null
	)

	# Büyüteç ikonu
	var icon_lbl := Label.new()
	icon_lbl.text = "🔍"
	icon_lbl.add_theme_font_size_override("font_size", 14)
	hbox.add_child(icon_lbl)

	# – butonu
	var btn_minus := _make_btn("-")
	btn_minus.pressed.connect(_on_zoom_out)
	hbox.add_child(btn_minus)

	# Zoom yüzdesi
	_zoom_label = Label.new()
	_zoom_label.custom_minimum_size = Vector2(40, 0)
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_label.add_theme_font_size_override("font_size", 12)
	_zoom_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	hbox.add_child(_zoom_label)
	_update_zoom_label()

	# + butonu
	var btn_plus := _make_btn("+")
	btn_plus.pressed.connect(_on_zoom_in)
	hbox.add_child(btn_plus)

	# Ayırıcı
	var sep := VSeparator.new()
	sep.custom_minimum_size = Vector2(1, 16)
	sep.modulate = Color(1, 1, 1, 0.25)
	hbox.add_child(sep)

	# Grid toggle butonu
	_grid_btn = _make_btn("⊞")
	_grid_btn.tooltip_text = "Grid görünürlüğü"
	_grid_btn.pressed.connect(_on_grid_toggle)
	hbox.add_child(_grid_btn)
	_apply_grid_state()

func _make_btn(txt: String) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.custom_minimum_size = Vector2(24, 24)
	btn.add_theme_font_size_override("font_size", 14)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.18, 0.18, 0.18, 1.0)
	normal.corner_radius_top_left     = 4
	normal.corner_radius_top_right    = 4
	normal.corner_radius_bottom_left  = 4
	normal.corner_radius_bottom_right = 4
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.28, 0.28, 0.28, 1.0)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover",  hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	return btn

func _on_grid_toggle() -> void:
	_grid_state = (_grid_state + 1) % 3
	_apply_grid_state()

func _apply_grid_state() -> void:
	if _iso_grid == null or not _iso_grid.has_method("set"):
		return
	var s: Array = GRID_STATES[_grid_state]
	var floor_a:     float = s[0]
	var line_a:      float = s[1]
	var hover_line_a: float = s[2]

	var base_floor := Color(0.52, 0.52, 0.50)
	var base_line  := Color(0.35, 0.35, 0.33)
	var base_hover_fill  := Color(0.70, 0.70, 0.68)
	var base_hover_line  := Color(0.85, 0.85, 0.83)

	_iso_grid.set("floor_color",        Color(base_floor, floor_a))
	_iso_grid.set("grid_color",         Color(base_line,  line_a))
	_iso_grid.set("hover_fill_color",   Color(base_hover_fill, 0.20))
	_iso_grid.set("hover_border_color", Color(base_hover_line, hover_line_a))
	_iso_grid.queue_redraw()

	# Buton ikonunu duruma göre güncelle
	var icons := ["⊞", "▦", "⬚"]
	if _grid_btn:
		_grid_btn.text = icons[_grid_state]

func _on_zoom_in() -> void:
	_apply_zoom(zoom.x + _current_step())

func _on_zoom_out() -> void:
	_apply_zoom(zoom.x - _current_step())

func _current_step() -> float:
	var now := Time.get_ticks_msec() / 1000.0
	if (now - _last_click_time) < fast_click_ms:
		_fast_chain += 1
	else:
		_fast_chain = 0
	_last_click_time = now
	# 0 ardışık → %10 | 1 ardışık → %20 | 2+ ardışık → %50
	if _fast_chain == 0:
		return 0.10
	elif _fast_chain == 1:
		return 0.20
	else:
		return 0.50

func _apply_zoom(val: float) -> void:
	val = clamp(val, zoom_min, zoom_max)
	zoom = Vector2(val, val)
	_update_zoom_label()

func _update_zoom_label() -> void:
	if _zoom_label:
		_zoom_label.text = "%d%%" % roundi(zoom.x * 100)

func _process(delta: float) -> void:
	if not player:
		return
	match mode:
		Mode.FIXED:
			pass
		Mode.FULL:
			if player.velocity.length_squared() > 1.0:
				global_position = global_position.lerp(player.global_position, follow_speed * delta)
		Mode.EDGE:
			_edge_follow(delta)

func _edge_follow(delta: float) -> void:
	var vp_half := get_viewport_rect().size * 0.5
	var offset  := player.global_position - global_position
	if abs(offset.x) > vp_half.x - edge_margin or abs(offset.y) > vp_half.y - edge_margin:
		_recentering = true
	if _recentering:
		global_position = global_position.lerp(player.global_position, follow_speed * delta)
		if global_position.distance_to(player.global_position) < 2.0:
			global_position = player.global_position
			_recentering = false

func pan_by(screen_delta: Vector2) -> void:
	global_position -= screen_delta / zoom
	_recentering = false

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if not InputActions.is_pressed("camera_zoom"):
		return
	var mb := event as InputEventMouseButton
	if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_apply_zoom(zoom.x + _current_step())
		get_viewport().set_input_as_handled()
	elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_apply_zoom(zoom.x - _current_step())
		get_viewport().set_input_as_handled()

func set_mode(new_mode: int) -> void:
	mode = new_mode as Mode

func set_zoom_visible(v: bool) -> void:
	if _zoom_panel: _zoom_panel.visible = v

func is_zoom_visible() -> bool:
	return _zoom_panel != null and _zoom_panel.visible

