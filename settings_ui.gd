extends CanvasLayer

var camera: Camera2D
var panel:  Panel
var button_group: ButtonGroup

var _win: Control = null

var _listening_action: String = ""
var _listening_button: Button = null

# ── Drag ──────────────────────────────────────────────────────────────────────
# gui_input mouse handle sınırının dışına çıkınca motion almayı bırakıyor.
# Çözüm: _input() her event'i alır; delta event.relative ile geliyor.
var _drag_target: Control = null

const RESOLUTIONS := [
	Vector2i(1280,  720),
	Vector2i(1366,  768),
	Vector2i(1600,  900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]
const WINDOW_MODES := ["Pencereli", "Çerçevesiz Pencere", "Tam Ekran"]

func _ready() -> void:
	camera       = get_parent().get_node("Camera2D")
	button_group = ButtonGroup.new()
	_build_ui()

# ── Input: drag + tuş yeniden atama ──────────────────────────────────────────

func _input(event: InputEvent) -> void:
	# ── 1. Drag ──────────────────────────────────────────────────────────────
	if _drag_target != null:
		if event is InputEventMouseMotion:
			var rel := (event as InputEventMouseMotion).relative
			_drag_target.offset_left   += rel.x
			_drag_target.offset_top    += rel.y
			_drag_target.offset_right  += rel.x
			_drag_target.offset_bottom += rel.y
			get_viewport().set_input_as_handled()
			return
		elif event is InputEventMouseButton \
				and not (event as InputEventMouseButton).pressed:
			_drag_target = null
			return

	# ── 2. Tuş yeniden atama ─────────────────────────────────────────────────
	if _listening_action == "" or not panel.visible: return
	if not (event is InputEventKey) or not (event as InputEventKey).pressed: return
	var keycode := (event as InputEventKey).keycode
	if keycode == KEY_ESCAPE:
		_cancel_listen()
	else:
		InputActions.set_key(_listening_action, keycode)
		_listening_button.text = _key_name(keycode)
		_listening_action = ""
		_listening_button = null
	get_viewport().set_input_as_handled()

# ── UI ────────────────────────────────────────────────────────────────────────

func _build_ui() -> void:
	_win = Control.new()
	_win.anchor_left   = 1.0
	_win.anchor_right  = 1.0
	_win.offset_left   = -260.0
	_win.offset_right  =  -10.0
	_win.offset_top    =   10.0
	_win.offset_bottom =  510.0
	_win.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_win)

	var header := HBoxContainer.new()
	header.anchor_right = 1.0
	header.offset_bottom = 36.0
	header.add_theme_constant_override("separation", 0)
	_win.add_child(header)

	header.add_child(_make_drag_handle(_win))

	var settings_btn := Button.new()
	settings_btn.text                  = "⚙  Ayarlar"
	settings_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(settings_btn)

	panel = Panel.new()
	panel.anchor_left   = 0.0
	panel.anchor_right  = 1.0
	panel.offset_top    =  46.0
	panel.offset_bottom = 500.0
	panel.visible = false
	_win.add_child(panel)

	var tab_container := TabContainer.new()
	tab_container.set_anchors_and_offsets_preset(
		Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	panel.add_child(tab_container)

	tab_container.add_child(_build_camera_tab())
	tab_container.add_child(_build_graphics_tab())
	tab_container.add_child(_build_controls_tab())
	tab_container.add_child(_build_panels_tab())

	settings_btn.pressed.connect(func(): panel.visible = not panel.visible)

# ── Drag tutacağı ─────────────────────────────────────────────────────────────

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

# ── Sekmeler ──────────────────────────────────────────────────────────────────

func _build_camera_tab() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.name = "Kamera"

	var title := Label.new()
	title.text = "Kamera Modu"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var labels := ["Takip Etmesin", "Tam Takip", "Ekran Takibi"]
	for i in labels.size():
		var btn := Button.new()
		btn.text         = labels[i]
		btn.toggle_mode  = true
		btn.button_group = button_group
		btn.pressed.connect(_on_mode_pressed.bind(i))
		vbox.add_child(btn)
		if i == 1:
			btn.button_pressed = true

	return vbox

func _build_graphics_tab() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.name = "Görüntü"

	var wm_label := Label.new()
	wm_label.text = "Pencere Modu"
	wm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(wm_label)
	vbox.add_child(HSeparator.new())

	var wm_group     := ButtonGroup.new()
	var current_mode := _get_window_mode_index()
	for i in WINDOW_MODES.size():
		var btn := Button.new()
		btn.text           = WINDOW_MODES[i]
		btn.toggle_mode    = true
		btn.button_group   = wm_group
		btn.button_pressed = (i == current_mode)
		btn.pressed.connect(_on_window_mode_pressed.bind(i))
		vbox.add_child(btn)

	vbox.add_child(_make_spacer(10))

	var res_label := Label.new()
	res_label.text = "Çözünürlük"
	res_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(res_label)
	vbox.add_child(HSeparator.new())

	var res_group   := ButtonGroup.new()
	var current_res := Vector2i(DisplayServer.window_get_size())
	for res in RESOLUTIONS:
		var btn := Button.new()
		btn.text           = "%d × %d" % [res.x, res.y]
		btn.toggle_mode    = true
		btn.button_group   = res_group
		btn.button_pressed = (res == current_res)
		btn.pressed.connect(_on_resolution_pressed.bind(res))
		vbox.add_child(btn)

	return vbox

func _build_controls_tab() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.name = "Kontroller"

	var title := Label.new()
	title.text = "Tuş Atamaları"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	for action_name in InputActions.ACTIONS:
		var info: Dictionary = InputActions.ACTIONS[action_name]

		var name_lbl := Label.new()
		name_lbl.text = info["label"]
		name_lbl.add_theme_font_size_override("font_size", 13)
		vbox.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = info["desc"]
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
		desc_lbl.add_theme_font_size_override("font_size", 11)
		vbox.add_child(desc_lbl)

		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var key_btn := Button.new()
		key_btn.custom_minimum_size   = Vector2(110, 0)
		key_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key_btn.text = _key_name(InputActions.get_key(action_name))
		key_btn.pressed.connect(_on_rebind_pressed.bind(action_name, key_btn))
		row.add_child(key_btn)

		var reset_btn := Button.new()
		reset_btn.text                = "↺"
		reset_btn.tooltip_text        = "Varsayılana sıfırla: " + _key_name(info["key"])
		reset_btn.custom_minimum_size = Vector2(32, 0)
		reset_btn.pressed.connect(_on_reset_single.bind(action_name, key_btn))
		row.add_child(reset_btn)

		vbox.add_child(row)
		vbox.add_child(HSeparator.new())

	return vbox

# ── Paneller sekmesi (Adobe stili panel görünürlük kontrolü) ──────────────────

func _build_panels_tab() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.name = "Paneller"

	var title := Label.new()
	title.text = "Panel Görünürlüğü"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "Panelleri açıp kapatın"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)
	vbox.add_child(HSeparator.new())

	vbox.add_child(_panel_toggle_row(
		"🔍  Zoom / Grid Barı",
		func() -> bool:
			var c = get_parent().get_node_or_null("Camera2D")
			return c != null and c.has_method("is_zoom_visible") and c.is_zoom_visible(),
		func(v: bool) -> void:
			var c = get_parent().get_node_or_null("Camera2D")
			if c and c.has_method("set_zoom_visible"): c.set_zoom_visible(v)
	))

	vbox.add_child(_panel_toggle_row(
		"🧱  Test Menüsü",
		func() -> bool:
			var tm = get_parent().get_node_or_null("TestMenu")
			return tm != null and tm.visible,
		func(v: bool) -> void:
			var tm = get_parent().get_node_or_null("TestMenu")
			if tm: tm.visible = v
	))

	return vbox

func _panel_toggle_row(label_text: String, getter: Callable, setter: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text                  = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	var toggle := CheckButton.new()
	toggle.button_pressed = getter.call()
	toggle.toggled.connect(setter)
	row.add_child(toggle)

	return row

# ── Yardımcılar ───────────────────────────────────────────────────────────────

func _make_spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c

func _get_window_mode_index() -> int:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN \
	or mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		return 2
	if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS):
		return 1
	return 0

func _on_mode_pressed(index: int) -> void:
	if camera: camera.set_mode(index)

func _on_rebind_pressed(action_name: String, btn: Button) -> void:
	if _listening_action != "": _cancel_listen()
	_listening_action = action_name
	_listening_button = btn
	btn.text = "Bir tuşa bas…"

func _cancel_listen() -> void:
	if _listening_button:
		_listening_button.text = _key_name(InputActions.get_key(_listening_action))
	_listening_action = ""
	_listening_button = null

func _on_reset_single(action_name: String, key_btn: Button) -> void:
	if _listening_action == action_name: _cancel_listen()
	InputActions.set_key(action_name, InputActions.ACTIONS[action_name]["key"])
	key_btn.text = _key_name(InputActions.get_key(action_name))

func _key_name(keycode: Key) -> String:
	if keycode == KEY_NONE: return "—"
	return OS.get_keycode_string(keycode)

func _on_window_mode_pressed(index: int) -> void:
	match index:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

func _on_resolution_pressed(res: Vector2i) -> void:
	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN: return
	DisplayServer.window_set_size(res)
	DisplayServer.window_set_position((DisplayServer.screen_get_size() - res) / 2)
