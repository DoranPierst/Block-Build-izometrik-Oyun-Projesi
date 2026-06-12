extends Node2D

@export var tile_width:      float = 64.0
@export var tile_height:     float = 32.0
@export var grid_width:      int   = 40
@export var grid_height:     int   = 40
@export var height_per_unit: float = 32.0

const COLOR_BORDER := Color(1.00, 1.00, 1.00, 0.70)

const COLOR_PREV_TOP   := Color(0.80, 0.60, 0.20, 0.50)
const COLOR_PREV_RIGHT := Color(0.60, 0.44, 0.14, 0.50)
const COLOR_PREV_FRONT := Color(0.42, 0.28, 0.08, 0.50)
const COLOR_INVALID    := Color(0.90, 0.20, 0.20, 0.45)

# Blok tiplerine göre renkler: [top, right, front]
# Normal (not stackable, not walkable) → kahverengi
# Stackable only                       → mavi-gri
# Walkable only                        → yeşil
# Stackable + Walkable                 → teal
const BLOCK_COLORS := {
	"normal": [Color(0.50,0.33,0.10,0.92), Color(0.35,0.22,0.06,0.92), Color(0.25,0.15,0.04,0.92)],
	"stack":  [Color(0.30,0.42,0.65,0.92), Color(0.20,0.30,0.50,0.92), Color(0.14,0.20,0.38,0.92)],
	"walk":   [Color(0.22,0.55,0.22,0.92), Color(0.14,0.38,0.14,0.92), Color(0.08,0.26,0.08,0.92)],
	"both":   [Color(0.16,0.52,0.50,0.92), Color(0.10,0.36,0.34,0.92), Color(0.06,0.24,0.22,0.92)],
	"wall":   [Color(0.70,0.66,0.58,0.92), Color(0.54,0.51,0.44,0.92), Color(0.40,0.37,0.31,0.92)],
}

# ── Blok verisi ───────────────────────────────────────────────────────────────

class BlockInfo:
	var id:        int
	var cell:      Vector2i
	var size:      Vector2i
	var height:    int
	var stackable: bool = false   # üstüne başka blok konulabilir
	var walkable:  bool = false   # karakter üstünde yürüyebilir
	var wall:      bool = false   # ince duvar (sadece ön/sağ yüz çizilir)
	var wall_face: int  = 0      # 0=güney (ön yüz), 1=doğu (sağ yüz) — kare duvarlarda toggle
	var elevation: int  = 0      # yerden yükseklik (height_per_unit cinsinden)
	var nodes:     Array          # Polygon2D + Line2D

var _next_id:  int        = 0
var _blocks:   Dictionary = {}  # int → BlockInfo
var _occupied: Dictionary = {}  # Vector2i → int  (block id)
var _player:   CharacterBody2D

# ── Yerleştirme durumu ────────────────────────────────────────────────────────

var _placing:    bool     = false
var _multi:      bool     = false
var _size:       Vector2i
var _eff_size:   Vector2i
var _height:     int      = 1
var _hovered:    Vector2i = Vector2i(-1, -1)
var _stackable:  bool     = false
var _walkable:   bool     = false
var _wall:       bool     = false
var _wall_face:  int      = 0     # 0=güney, 1=doğu
var _pending_elev: int    = 0    # _can_place tarafından hesaplanan yükseklik

# ── Taşıma (move) durumu ──────────────────────────────────────────────────────

var _moving_id:     int   = -1
var _alt_drag_move: bool  = false  # Alt+sürükle ile hızlı taşıma

# ── Önizleme node'ları (z_index=4096, z_as_relative=false) ───────────────────
# _draw() yerine gerçek node kullanılır; böylece z-sırası garantilenir.
var _prev_polys: Array = []   # [Polygon2D × 3]  front, right, top
var _prev_lines: Array = []   # [Line2D   × 3]

# ── Context menu ──────────────────────────────────────────────────────────────

## Küçük izometrik blok önizleme çizen Control
class BlockPreview extends Control:
	var bsize:   Vector2i = Vector2i(1, 1)
	var bheight: int      = 1

	func _iso(gx: int, gy: int, hw: float, hh: float) -> Vector2:
		return Vector2((gx - gy) * hw, (gx + gy) * hh)

	func _get_polys(tw: float, th: float, hp: float) -> Array:
		var hw := tw / 2.0;  var hh := th / 2.0
		var sx := bsize.x;   var sy := bsize.y

		var base := PackedVector2Array()
		for i in sx: base.append(_iso(i,       0,    hw, hh) + Vector2(  0, -hh))
		for j in sy: base.append(_iso(sx-1,    j,    hw, hh) + Vector2( hw,   0))
		for i in sx: base.append(_iso(sx-1-i,  sy-1, hw, hh) + Vector2(  0,  hh))
		for j in sy: base.append(_iso(0,  sy-1-j,    hw, hh) + Vector2(-hw,   0))

		var top := PackedVector2Array()
		for p in base: top.append(p - Vector2(0, hp))

		var rg := PackedVector2Array()
		for j in sy: rg.append(_iso(sx-1, j, hw, hh)    + Vector2(hw,  0))
		rg.append(             _iso(sx-1, sy-1, hw, hh)  + Vector2( 0, hh))
		var right := PackedVector2Array()
		for p in rg:                           right.append(p - Vector2(0, hp))
		for i in range(rg.size()-1, -1, -1):   right.append(rg[i])

		var fg := PackedVector2Array()
		for i in sx: fg.append(_iso(sx-1-i, sy-1, hw, hh) + Vector2( 0, hh))
		fg.append(             _iso(0,       sy-1, hw, hh) + Vector2(-hw, 0))
		var front := PackedVector2Array()
		for p in fg:                           front.append(p - Vector2(0, hp))
		for i in range(fg.size()-1, -1, -1):   front.append(fg[i])

		return [front, right, top]

	func _draw() -> void:
		var area := get_size()
		var pad  := 5.0
		# İlk deneme ölçüsü ile bounding box hesapla
		var tw0  := 28.0; var th0 := 14.0
		var hp0  := float(bheight) * 10.0
		var polys := _get_polys(tw0, th0, hp0)
		var mn := Vector2(INF, INF);  var mx := Vector2(-INF, -INF)
		for poly in polys:
			for p: Vector2 in poly:
				mn.x = min(mn.x, p.x); mn.y = min(mn.y, p.y)
				mx.x = max(mx.x, p.x); mx.y = max(mx.y, p.y)
		var bbox := mx - mn
		# Alana sığacak şekilde ölçekle
		var avail := area - Vector2(pad * 2.0, pad * 2.0)
		var s: float = min(avail.x / max(bbox.x, 1.0), avail.y / max(bbox.y, 1.0))
		var shift: Vector2 = area / 2.0 - (mn + bbox / 2.0) * s
		# Yüzleri çiz
		var face_cols := [
			Color(0.25, 0.15, 0.04, 0.92),
			Color(0.35, 0.22, 0.06, 0.92),
			Color(0.50, 0.33, 0.10, 0.92),
		]
		for i in polys.size():
			var xp := PackedVector2Array()
			for p: Vector2 in polys[i]: xp.append(p * s + shift)
			draw_colored_polygon(xp, face_cols[i])
		# Üst yüz kenarlığı
		var tp := PackedVector2Array()
		for p: Vector2 in polys[2]: tp.append(p * s + shift)
		tp.append(tp[0])
		draw_polyline(tp, Color(1, 1, 1, 0.65), 1.0)

var _ctx_layer:    CanvasLayer
var _ctx_panel:    Panel
var _ctx_preview:  BlockPreview
var _ctx_name_lbl: Label
var _ctx_id:       int = -1

# ── Bildirim sistemi ──────────────────────────────────────────────────────────
var _notif_layer: CanvasLayer
var _notif_vbox:  VBoxContainer

enum PlaceFail { OK, BOUNDS, PLAYER, OCCUPIED, NOT_STACKABLE }
var _flash_tweens: Dictionary = {}   # block_id → Tween
var _flash_bases:  Dictionary = {}   # block_id → Array (kayıtlı orijinal renkler)

# ─────────────────────────────────────────────────────────────────────────────

func _ready() -> void:
	_player = get_parent().get_node("Player")
	_build_ctx_menu()
	_build_notif_layer()
	_setup_preview_nodes()
	set_process(false)

# ── Bildirim katmanı ──────────────────────────────────────────────────────────

func _build_notif_layer() -> void:
	_notif_layer       = CanvasLayer.new()
	_notif_layer.layer = 60
	add_child(_notif_layer)

	# Sağ kenara sabitlenmiş, aşağı büyüyen VBox
	_notif_vbox = VBoxContainer.new()
	_notif_vbox.anchor_left   = 1.0
	_notif_vbox.anchor_right  = 1.0
	_notif_vbox.anchor_top    = 0.0
	_notif_vbox.anchor_bottom = 0.0
	_notif_vbox.offset_left   = -298
	_notif_vbox.offset_right  = -10
	_notif_vbox.offset_top    = 58   # Ayarlar başlığının altında başlasın
	_notif_vbox.add_theme_constant_override("separation", 5)
	_notif_layer.add_child(_notif_vbox)

func _show_notification(text: String) -> void:
	# Panel
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(288, 0)

	var sbox := StyleBoxFlat.new()
	sbox.bg_color            = Color(0.08, 0.05, 0.02, 0.92)
	sbox.border_width_left   = 3
	sbox.border_width_top    = 1
	sbox.border_width_right  = 1
	sbox.border_width_bottom = 1
	sbox.border_color        = Color(0.85, 0.25, 0.15, 1.0)
	for c in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		sbox.set("corner_radius_" + c, 5)
	panel.add_theme_stylebox_override("panel", sbox)

	# Margin + Label
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)

	var lbl := Label.new()
	lbl.text          = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.75, 1.0))
	margin.add_child(lbl)

	# En üste ekle (en güncel üstte görünsün)
	_notif_vbox.add_child(panel)
	_notif_vbox.move_child(panel, 0)

	# 4.5s bekle → 0.5s'de silerek yok ol
	var tw := panel.create_tween()
	tw.tween_interval(4.5)
	tw.tween_property(panel, "modulate:a", 0.0, 0.5)
	tw.tween_callback(panel.queue_free)

func _collect_flash_targets(info: BlockInfo) -> Array:
	var targets: Array = []
	for n in info.nodes:
		if not is_instance_valid(n):
			continue
		if n is Polygon2D:
			var p := n as Polygon2D
			targets.append({"node": p, "kind": 0, "base": p.color})
		elif n is Line2D:
			var l := n as Line2D
			targets.append({"node": l, "kind": 1, "base": l.default_color})
	return targets

func _apply_flash_blend(targets: Array, amount: float) -> void:
	var flash_col := Color(1.0, 0.12, 0.12, 1.0)
	for item in targets:
		if not is_instance_valid(item["node"]):
			continue
		var blended: Color = (item["base"] as Color).lerp(flash_col, amount)
		if item["kind"] == 0:
			(item["node"] as Polygon2D).color = blended
		else:
			(item["node"] as Line2D).default_color = blended

func _restore_flash_targets(targets: Array) -> void:
	for item in targets:
		if not is_instance_valid(item["node"]):
			continue
		if item["kind"] == 0:
			(item["node"] as Polygon2D).color = item["base"]
		else:
			(item["node"] as Line2D).default_color = item["base"]

func _stop_block_flash(bid: int) -> void:
	if _flash_tweens.has(bid):
		var tw: Tween = _flash_tweens[bid]
		if tw and tw.is_valid():
			tw.kill()
		_flash_tweens.erase(bid)
	if _flash_bases.has(bid):
		_restore_flash_targets(_flash_bases[bid])
		_flash_bases.erase(bid)

func _flash_blocks_red(block_ids: Array) -> void:
	const FADE_TIME := 0.55
	for bid in block_ids:
		var info: BlockInfo = _blocks.get(bid)
		if info == null:
			continue
		_stop_block_flash(bid)
		var targets := _collect_flash_targets(info)
		if targets.is_empty():
			continue
		_flash_bases[bid] = targets

		var tw := get_tree().create_tween()
		tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tw.set_trans(Tween.TRANS_SINE)
		tw.set_ease(Tween.EASE_IN_OUT)
		_flash_tweens[bid] = tw
		tw.tween_method(func(amount: float) -> void:
			_apply_flash_blend(targets, amount)
		, 0.0, 1.0, FADE_TIME)
		tw.tween_method(func(amount: float) -> void:
			_apply_flash_blend(targets, amount)
		, 1.0, 0.0, FADE_TIME)
		tw.finished.connect(func() -> void:
			if _flash_tweens.get(bid) == tw:
				_stop_block_flash(bid)
		)

# ── Önizleme node kurulumu ────────────────────────────────────────────────────

func _setup_preview_nodes() -> void:
	for i in 3:
		var p := Polygon2D.new()
		p.z_index       = 4096
		p.z_as_relative = false
		p.visible       = false
		add_child(p)
		_prev_polys.append(p)

		var l := Line2D.new()
		l.z_index       = 4096
		l.z_as_relative = false
		l.closed        = true
		l.width         = 1.5
		l.default_color = COLOR_BORDER
		l.visible       = false
		add_child(l)
		_prev_lines.append(l)

func _hide_preview() -> void:
	for n in _prev_polys:
		var p: Polygon2D = n
		p.visible = false
	for n in _prev_lines:
		var l: Line2D = n
		l.visible = false

func _update_preview() -> void:
	if not _placing or not _in_bounds(_hovered, _eff_size):
		_hide_preview()
		return
	var h_px    := _height * height_per_unit
	var valid   := _can_place(_hovered, _eff_size)
	var elev_px := _pending_elev * height_per_unit

	if _wall:
		# Duvar önizlemesi: sadece ilgili tek yüzü göster
		var ep := elev_px if valid else 0.0
		var face_pts: PackedVector2Array
		match _wall_face:
			0: face_pts = _build_front_face(_hovered, _eff_size, h_px, ep)
			1: face_pts = _build_right_face(_hovered, _eff_size, h_px, ep)
			2: face_pts = _build_north_face(_hovered, _eff_size, h_px, ep)
			3: face_pts = _build_west_face (_hovered, _eff_size, h_px, ep)
		var pc2 := _preview_cols()
		# [cols_idx: 0=kuzey/batı, 1=doğu, 2=güney] sırası BLOCK_COLORS["wall"] ile uyumlu
		var col_idx: Array[int] = [2, 1, 0, 0]
		var face_col: Color = (pc2[col_idx[_wall_face]] if valid else COLOR_INVALID)
		var p0: Polygon2D = _prev_polys[0]; var l0: Line2D = _prev_lines[0]
		p0.polygon = face_pts; p0.color = face_col; p0.visible = true
		l0.points  = face_pts; l0.visible = true
		for i in range(1, 3):
			(_prev_polys[i] as Polygon2D).visible = false
			(_prev_lines[i] as Line2D).visible    = false
		return

	if valid:
		var pc := _preview_cols()
		var pts := [
			_build_front_face(_hovered, _eff_size, h_px, elev_px),
			_build_right_face(_hovered, _eff_size, h_px, elev_px),
			_build_top_face  (_hovered, _eff_size, h_px, elev_px),
		]
		var face_cols: Array = [pc[2], pc[1], pc[0]]   # front, right, top
		for i in 3:
			var p: Polygon2D = _prev_polys[i]
			var lc: Line2D   = _prev_lines[i]
			p.polygon = pts[i]
			p.color   = face_cols[i]
			p.visible = true
			lc.points  = pts[i]
			lc.visible = true
	else:
		var inv_pts := [
			_build_front_face(_hovered, _eff_size, h_px, 0.0),
			_build_right_face(_hovered, _eff_size, h_px, 0.0),
			_build_top_face  (_hovered, _eff_size, h_px, 0.0),
		]
		for i in 3:
			var p: Polygon2D = _prev_polys[i]
			var lc: Line2D   = _prev_lines[i]
			p.polygon = inv_pts[i]
			p.color   = COLOR_INVALID
			p.visible = true
			lc.points  = inv_pts[i]
			lc.visible = true

# ── Context menu inşası ───────────────────────────────────────────────────────

func _build_ctx_menu() -> void:
	_ctx_layer       = CanvasLayer.new()
	_ctx_layer.layer = 50
	add_child(_ctx_layer)

	_ctx_panel         = Panel.new()
	_ctx_panel.visible = false

	# Ekranın sağ-alt köşesine sabitle
	_ctx_panel.anchor_left   = 1.0
	_ctx_panel.anchor_top    = 1.0
	_ctx_panel.anchor_right  = 1.0
	_ctx_panel.anchor_bottom = 1.0
	_ctx_panel.offset_left   = -200
	_ctx_panel.offset_top    = -295
	_ctx_panel.offset_right  = -10
	_ctx_panel.offset_bottom = -10

	var sbox := StyleBoxFlat.new()
	sbox.bg_color            = Color(0.10, 0.06, 0.01, 0.93)
	sbox.border_width_left   = 2
	sbox.border_width_top    = 2
	sbox.border_width_right  = 2
	sbox.border_width_bottom = 2
	sbox.border_color        = Color(0.78, 0.56, 0.14, 1.0)
	for corner in ["top_left","top_right","bottom_left","bottom_right"]:
		sbox.set("corner_radius_" + corner, 7)
	_ctx_panel.add_theme_stylebox_override("panel", sbox)
	_ctx_layer.add_child(_ctx_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	_ctx_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	# ── Üst alan: önizleme + isim ────────────────────────────────────────────
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	vbox.add_child(top_row)

	# Küçük izometrik önizleme kutusu
	var preview_wrap := Panel.new()
	preview_wrap.custom_minimum_size = Vector2(72, 58)
	var pw_sbox := StyleBoxFlat.new()
	pw_sbox.bg_color      = Color(0.06, 0.04, 0.01, 0.85)
	pw_sbox.border_color  = Color(0.60, 0.44, 0.12, 0.70)
	pw_sbox.border_width_left   = 1
	pw_sbox.border_width_top    = 1
	pw_sbox.border_width_right  = 1
	pw_sbox.border_width_bottom = 1
	for c in ["top_left","top_right","bottom_left","bottom_right"]:
		pw_sbox.set("corner_radius_" + c, 4)
	preview_wrap.add_theme_stylebox_override("panel", pw_sbox)
	top_row.add_child(preview_wrap)

	_ctx_preview = BlockPreview.new()
	_ctx_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ctx_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_wrap.add_child(_ctx_preview)

	# İsim + boş alan
	var name_col := VBoxContainer.new()
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_child(name_col)

	_ctx_name_lbl = Label.new()
	_ctx_name_lbl.text               = "Blok"
	_ctx_name_lbl.autowrap_mode      = TextServer.AUTOWRAP_WORD_SMART
	_ctx_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_ctx_name_lbl.add_theme_color_override("font_color", Color(0.95, 0.80, 0.30))
	_ctx_name_lbl.add_theme_font_size_override("font_size", 13)
	name_col.add_child(_ctx_name_lbl)

	vbox.add_child(HSeparator.new())

	var actions := [
		["🔨  Kaldır",  Callable(self, "_ctx_remove")],
		["🔄  Döndür",  Callable(self, "_ctx_rotate")],
		["✋  Taşı",    Callable(self, "_ctx_move")],
		["⚡  Kullan",  Callable(self, "_ctx_use")],
	]
	for a in actions:
		var btn := Button.new()
		btn.text      = a[0]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_color_override("font_color",       Color(0.90, 0.85, 0.75))
		btn.add_theme_color_override("font_hover_color", Color(1.00, 0.95, 0.50))
		var n_sbox := StyleBoxFlat.new()
		n_sbox.bg_color = Color.TRANSPARENT
		for s in ["normal","focus","pressed"]:
			btn.add_theme_stylebox_override(s, n_sbox)
		var h_sbox := StyleBoxFlat.new()
		h_sbox.bg_color = Color(0.80, 0.60, 0.10, 0.25)
		for corner in ["top_left","top_right","bottom_left","bottom_right"]:
			h_sbox.set("corner_radius_" + corner, 4)
		btn.add_theme_stylebox_override("hover", h_sbox)
		btn.pressed.connect(a[1])
		vbox.add_child(btn)

func _show_ctx(id: int) -> void:
	_ctx_id = id
	var info: BlockInfo = _blocks.get(id)
	if info == null: return
	# Önizlemeyi güncelle
	_ctx_preview.bsize   = info.size
	_ctx_preview.bheight = info.height
	_ctx_preview.queue_redraw()
	var type_name: String
	if info.wall:
		if   info.stackable and info.walkable: type_name = "İnce Duvar (Yığın+Platform)"
		elif info.stackable:                   type_name = "İnce Duvar (Yığın)"
		elif info.walkable:                    type_name = "İnce Duvar (Platform)"
		else:                                  type_name = "İnce Duvar"
	elif info.stackable and info.walkable:     type_name = "Yığın Platformu"
	elif info.stackable:                       type_name = "Yığın Bloğu"
	elif info.walkable:                        type_name = "Platform"
	else:                                      type_name = "Blok"
	_ctx_name_lbl.text = "%d×%d×%d\n%s" % [info.size.x, info.size.y, info.height, type_name]
	_ctx_panel.visible = true

func _hide_ctx() -> void:
	_ctx_panel.visible = false
	_ctx_id            = -1

# ── Context menu eylemleri ────────────────────────────────────────────────────

func _ctx_remove() -> void:
	if _ctx_id < 0: return
	_remove_block(_ctx_id)

func _stack_surface_elev(info: BlockInfo) -> int:
	# Aynı hücre + boyuttaki en üst yüzey; döndürülen blok oraya terfi edebilir.
	var best_top := -1
	for bid in _blocks:
		if bid == info.id:
			continue
		var bi: BlockInfo = _blocks[bid]
		if bi.cell == info.cell and bi.size == info.size:
			var t := bi.elevation + bi.height
			if t > best_top:
				best_top = t
	if best_top > info.elevation + info.height - 1:
		return best_top
	return -1

func _resolve_rotate_elevation(stack_elev: int, place_elev: int) -> int:
	if stack_elev >= 0:
		return maxi(place_elev, stack_elev)
	return place_elev

func _rebuild_rotated_block(info: BlockInfo) -> void:
	for n in info.nodes:
		if is_instance_valid(n):
			n.queue_free()
	info.nodes.clear()
	_occupy_block_cells(info)
	_build_block_visuals(info)

func _ctx_rotate() -> void:
	if _ctx_id < 0:
		return
	var info: BlockInfo = _blocks.get(_ctx_id)
	if info == null:
		return

	# Yığın terfisi döndürmeden ÖNCE hesaplanır; erken çıkış yok — ikisi birlikte uygulanır.
	var stack_elev := _stack_surface_elev(info)

	# ── Duvar döndürme ────────────────────────────────────────────────────────
	if info.wall:
		var new_face := (info.wall_face + 3) % 4
		var new_size := Vector2i(info.size.y, info.size.x)
		_free_block_cells(info)
		if _can_rotate_place(info, info.cell, new_size, true):
			info.wall_face  = new_face
			info.size       = new_size
			info.elevation  = _resolve_rotate_elevation(stack_elev, _pending_elev)
			_rebuild_rotated_block(info)
		else:
			_occupy_block_cells(info)
			_fail_rotate_action(info, info.cell, new_size, "Döndürme")
		_hide_ctx()
		return

	# ── Küp döndürme ──────────────────────────────────────────────────────────
	var rot := Vector2i(info.size.y, info.size.x)
	if rot == info.size:
		# Boyut değişmez (1×1, 2×2 …) ama yığın terfisi uygulanabilir.
		if stack_elev >= 0:
			info.elevation = stack_elev
			_rebuild_rotated_block(info)
		_hide_ctx()
		return

	_free_block_cells(info)
	if _can_rotate_place(info, info.cell, rot, true):
		info.size      = rot
		info.elevation = _resolve_rotate_elevation(stack_elev, _pending_elev)
		_rebuild_rotated_block(info)
	else:
		_occupy_block_cells(info)
		_fail_rotate_action(info, info.cell, rot, "Döndürme")
	_hide_ctx()

func _ctx_move() -> void:
	if _ctx_id < 0: return
	var info: BlockInfo = _blocks.get(_ctx_id)
	if info == null: return
	_moving_id = _ctx_id
	# _occupied ve astar'a dokunma: blok yerleştirilene kadar eski konumunda
	# varmış gibi davranır. Karakter üstündeyse düşmez; içinden geçilemez.
	# _can_place() içinde taşınan bloğun hücreleri "serbest" sayılır.
	for n in info.nodes:
		if is_instance_valid(n): n.modulate = Color(1.0, 1.0, 1.0, 0.35)
	_hide_ctx()
	_wall_face = info.wall_face   # Taşırken oryantasyonu koru
	start_placement(info.size, info.height, false,
		info.stackable, info.walkable, info.wall, true)

func _ctx_use() -> void:
	# Gelecekte uygulanabilir
	_hide_ctx()

# ── Blok hücre yardımcıları ───────────────────────────────────────────────────

## Belirtilen hücrede, exclude_id dışında en üstteki bloğun id'sini döndürür.
## Yığınlı bloklar aynı hücreyi paylaşır; _occupied her zaman en üsttekini tutar.
## Bir blok taşınırken/silinirken altındaki bloğun kaydını geri yüklemek için kullanılır.
func _find_top_block_at_cell(cell: Vector2i, exclude_id: int) -> int:
	var best_id  := -1
	var best_top := -1
	for id: int in _blocks:
		if id == exclude_id: continue
		var b: BlockInfo = _blocks[id]
		var local := cell - b.cell
		if local.x < 0 or local.x >= b.size.x: continue
		if local.y < 0 or local.y >= b.size.y: continue
		var top := b.elevation + b.height
		if top > best_top:
			best_top = top
			best_id  = id
	return best_id

func _occupy_block_cells(info: BlockInfo) -> void:
	for dx in info.size.x:
		for dy in info.size.y:
			var c := info.cell + Vector2i(dx, dy)
			_occupied[c] = info.id
			# En üstteki bloğun walkable durumu astar'ı belirler.
			_player.astar.set_point_solid(c, not info.walkable)

func _free_block_cells(info: BlockInfo) -> void:
	for dx in info.size.x:
		for dy in info.size.y:
			var c := info.cell + Vector2i(dx, dy)
			# Altında başka blok varsa _occupied'ı ona devret, yoksa sil.
			var below_id := _find_top_block_at_cell(c, info.id)
			if below_id >= 0:
				_occupied[c] = below_id
				var below_info: BlockInfo = _blocks.get(below_id)
				# Altındaki bloğun walkable durumu astar'ı belirler.
				_player.astar.set_point_solid(c, below_info == null or not below_info.walkable)
			else:
				_occupied.erase(c)
				_player.astar.set_point_solid(c, false)

# ── Blok kaldır ───────────────────────────────────────────────────────────────

func _remove_block(id: int) -> void:
	if not _blocks.has(id): return
	_stop_block_flash(id)
	var info: BlockInfo = _blocks[id]
	for n in info.nodes:
		if is_instance_valid(n): n.queue_free()
	_free_block_cells(info)
	_blocks.erase(id)
	if _ctx_id    == id: _hide_ctx()
	if _moving_id == id: _moving_id = -1

# ── Blok görseli inşa et ──────────────────────────────────────────────────────

func _block_colors(info: BlockInfo) -> Array:
	if info.wall:                        return BLOCK_COLORS["wall"]
	if info.stackable and info.walkable: return BLOCK_COLORS["both"]
	if info.stackable:                   return BLOCK_COLORS["stack"]
	if info.walkable:                    return BLOCK_COLORS["walk"]
	return BLOCK_COLORS["normal"]

func _build_block_visuals(info: BlockInfo) -> void:
	if info.wall:
		_build_wall_visuals(info)
		return

	var h_px    := info.height    * height_per_unit
	var elev_px := info.elevation * height_per_unit
	var cx      := info.cell.x
	var cy      := info.cell.y
	var sx      := info.size.x
	var sy      := info.size.y
	var cols    := _block_colors(info)
	var eb      := info.elevation * IsoDepth.STRIDE

	# ── ÜST YÜZ: hücre başına 1×1 elmas polygon ──────────────────────────────
	# d * STRIDE − 1: güneydeki hücreler daha yüksek z → önde görünür.
	for dx in sx:
		for dy in sy:
			var d := (cx + dx) + (cy + dy)
			info.nodes.append(_make_poly(
				_build_top_face(Vector2i(cx + dx, cy + dy), Vector2i(1, 1), h_px, elev_px),
				cols[0],
				d * IsoDepth.STRIDE - 1 + eb
			))

	# ── ÖN YÜZ: güney kenar — kolon başına ayrı polygon ─────────────────────
	# Derinlik cy+sy-2 (orijinal formül): bloğun güney kenarındaki karakter önde kalır.
	for dx in sx:
		var d := (cx + dx) + (cy + sy - 2)
		info.nodes.append(_make_poly(
			_build_front_face(Vector2i(cx + dx, cy + sy - 1), Vector2i(1, 1), h_px, elev_px),
			cols[2],
			d * IsoDepth.STRIDE + 2 + eb
		))

	# ── SAĞ YÜZ: doğu kenar — satır başına ayrı polygon ─────────────────────
	# Kuzey satırlar küçük z (arkada), güney satırlar büyük z (önde).
	for dy in sy:
		var d := (cx + sx - 1) + (cy + dy)
		info.nodes.append(_make_poly(
			_build_right_face(Vector2i(cx + sx - 1, cy + dy), Vector2i(1, 1), h_px, elev_px),
			cols[1],
			d * IsoDepth.STRIDE + 0 + eb
		))

	# ── KENARLIKLAR — eski (min-depth) formülleri: karakterin başının önüne çıkmaz ──
	# Ön kenarlık: batı kolonun derinliği (en düşük z)
	# Sağ kenarlık: kuzey satırın derinliği (en düşük z)
	# Üst kenarlık: KK köşe derinliği (en düşük z)
	var z_front_border := (cx + cy + sy - 2) * IsoDepth.STRIDE + 2 + eb
	var z_right_border := (cx + sx - 1 + cy) * IsoDepth.STRIDE + 0 + eb
	var z_top_border   := (cx + cy)          * IsoDepth.STRIDE - 1 + eb
	for pts_z: Array in [
		[_build_front_face(info.cell, info.size, h_px, elev_px), z_front_border],
		[_build_right_face(info.cell, info.size, h_px, elev_px), z_right_border],
		[_build_top_face  (info.cell, info.size, h_px, elev_px), z_top_border  ],
	]:
		var l := Line2D.new()
		l.points        = pts_z[0] as PackedVector2Array
		l.closed        = true
		l.width         = 1.5
		l.default_color = COLOR_BORDER
		l.z_index       = pts_z[1] as int
		l.z_as_relative = false
		add_child(l)
		info.nodes.append(l)

func _add_wall_border(pts: PackedVector2Array, z: int, info: BlockInfo, width: float = 1.5) -> void:
	var l := Line2D.new()
	l.points = pts; l.closed = true; l.width = width
	l.default_color = COLOR_BORDER; l.z_index = z; l.z_as_relative = false
	add_child(l); info.nodes.append(l)

func _build_wall_visuals(info: BlockInfo) -> void:
	var h_px    := info.height    * height_per_unit
	var elev_px := info.elevation * height_per_unit
	var cx      := info.cell.x
	var cy      := info.cell.y
	var sx      := info.size.x
	var sy      := info.size.y
	var eb      := info.elevation * IsoDepth.STRIDE
	var cols    := BLOCK_COLORS["wall"]   # [top, right, front]

	var wall_col: Color = cols[2]   # tüm yüzlerde aynı renk

	match info.wall_face:
		0:  # ── Güney (SW) ── slot +2, d = güney kenar (cy+sy-1)
			for dx in sx:
				var d := (cx + dx) + (cy + sy - 1)
				info.nodes.append(_make_poly(
					_build_front_face(Vector2i(cx + dx, cy + sy - 1), Vector2i(1, 1), h_px, elev_px),
					wall_col, d * IsoDepth.STRIDE + 2 + eb))
			_add_wall_border(_build_front_face(info.cell, info.size, h_px, elev_px),
				(cx + cy + sy - 1) * IsoDepth.STRIDE + 2 + eb, info, 2.0)

		1:  # ── Doğu (SE) ── slot +2
			for dy in sy:
				var d := (cx + sx - 1) + (cy + dy)
				info.nodes.append(_make_poly(
					_build_right_face(Vector2i(cx + sx - 1, cy + dy), Vector2i(1, 1), h_px, elev_px),
					wall_col, d * IsoDepth.STRIDE + 2 + eb))
			_add_wall_border(_build_right_face(info.cell, info.size, h_px, elev_px),
				(cx + sx - 1 + cy) * IsoDepth.STRIDE + 2 + eb, info, 2.0)

		2:  # ── Kuzey (NE) ── slot -1
			for dx in sx:
				var d := (cx + dx) + cy
				info.nodes.append(_make_poly(
					_build_north_face(Vector2i(cx + dx, cy), Vector2i(1, 1), h_px, elev_px),
					wall_col, d * IsoDepth.STRIDE - 1 + eb))
			_add_wall_border(_build_north_face(info.cell, info.size, h_px, elev_px),
				(cx + cy) * IsoDepth.STRIDE - 1 + eb, info, 2.0)

		3:  # ── Batı (NW) ── slot -1
			for dy in sy:
				var d := cx + (cy + dy)
				info.nodes.append(_make_poly(
					_build_west_face(Vector2i(cx, cy + dy), Vector2i(1, 1), h_px, elev_px),
					wall_col, d * IsoDepth.STRIDE - 1 + eb))
			_add_wall_border(_build_west_face(info.cell, info.size, h_px, elev_px),
				(cx + cy) * IsoDepth.STRIDE - 1 + eb, info, 2.0)

## Belirtilen hücrede yürünebilir blok varsa yüzeyinin piksel yüksekliğini döndürür.
func get_walkable_surface_px(cell: Vector2i) -> float:
	if not _occupied.has(cell): return 0.0
	var info: BlockInfo = _blocks.get(_occupied[cell])
	if info == null or not info.walkable: return 0.0
	# Duvarlar yükseklik katmaz: karakter duvarın taban seviyesinde durur.
	var effective_h := info.elevation if info.wall else info.elevation + info.height
	return effective_h * height_per_unit

## Yürünebilir blok yüzeyinin tam sayı yüksekliğini döndürür (z_index bonusu için).
func get_walkable_surface_h(cell: Vector2i) -> int:
	if not _occupied.has(cell): return 0
	var info: BlockInfo = _blocks.get(_occupied[cell])
	if info == null or not info.walkable: return 0
	return info.elevation if info.wall else info.elevation + info.height

func _make_poly(pts: PackedVector2Array, col: Color, z: int) -> Polygon2D:
	var p := Polygon2D.new()
	p.color          = col
	p.polygon        = pts
	p.z_index        = z
	p.z_as_relative  = false   # ebeveyn z_index'inden bağımsız mutlak z
	add_child(p)
	return p

# ── Yerleştirme ───────────────────────────────────────────────────────────────

func start_placement(size: Vector2i, height: int, multi: bool,
		stackable: bool = false, walkable: bool = false, wall: bool = false,
		keep_orient: bool = false) -> void:
	# Yerleştirmede büyük boyutu Y'ye koy (NW varsayılan yön size.y'yi kullanır).
	if not keep_orient and size.x > size.y:
		size = Vector2i(size.y, size.x)
	_size      = size
	_height    = height
	_multi     = multi
	_stackable = stackable
	_walkable  = walkable
	_wall      = wall
	if not keep_orient:
		_wall_face = 3   # Yeni yerleştirme: kuzey batı yönü varsayılan
	_placing   = true
	_hovered   = _w2g(get_global_mouse_position())
	_resolve_size()
	set_process(true)

func _stop() -> void:
	if _moving_id >= 0 and _blocks.has(_moving_id):
		var info: BlockInfo = _blocks[_moving_id]
		# _occupy_block_cells ÇAĞIRMA: _ctx_move() hücreleri hiç boşaltmadı,
		# yani _occupied zaten doğru durumda (üstteki blok kaydı bozulmaz).
		# Çağırırsak alt bloğun ID'si üstteki bloğun ID'sini ezer → karakter düşer.
		for n in info.nodes:
			if is_instance_valid(n): n.modulate = Color.WHITE
		_moving_id = -1
	_alt_drag_move = false
	_placing       = false
	_pending_elev  = 0
	z_index        = 0
	_hide_ctx()
	_hide_preview()
	set_process(false)

func _process(_delta: float) -> void:
	if _placing:
		var c := _w2g(get_global_mouse_position())
		if c != _hovered:
			_hovered = c
			_resolve_size()
		_update_preview()


func _resolve_size() -> void:
	if _can_place(_hovered, _size):
		_eff_size = _size
		return
	# Duvarlar için otomatik döndürme yok: yön wall_face ile belirlenir.
	if not _wall:
		var rotated := Vector2i(_size.y, _size.x)
		if rotated != _size and _can_place(_hovered, rotated):
			_eff_size = rotated
			return
	_eff_size = _size

func _input(event: InputEvent) -> void:
	# ── Alt+sürükle aktifken mouse hareketi kamera kaydırmayı engeller ────────
	if _alt_drag_move and event is InputEventMouseMotion:
		get_viewport().set_input_as_handled()
		return

	# ── ESC ───────────────────────────────────────────────────────────────────
	if event is InputEventKey and event.is_action_pressed("block_cancel"):
		if _placing:
			_stop()
			get_viewport().set_input_as_handled()
			return
		if _ctx_id >= 0:
			_hide_ctx()
			get_viewport().set_input_as_handled()
			return

	# ── Sol tuş BASMA: sadece Alt+sürükle başlatır ────────────────────────────
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if InputActions.is_pressed("block_move") and not _placing \
				and get_viewport().gui_get_hovered_control() == null:
			var hit: int = _find_block_at_mouse()
			if hit >= 0:
				_alt_drag_move = true
				_ctx_id        = hit
				_ctx_move()
				get_viewport().set_input_as_handled()
		return   # Press olayları başka bir şey yapmaz

	# ── Buradan sonrası yalnızca sol tuş BIRAKMA ──────────────────────────────
	if not (event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and not event.pressed):
		return
	if _player._is_dragging:
		return
	if get_viewport().gui_get_hovered_control() != null:
		return

	# Yerleştirme modundayken bırakma (normal + Alt+sürükle)
	if _placing:
		get_viewport().set_input_as_handled()
		if _fail_action(_hovered, _eff_size, false, "Yerleştirme",
				_moving_id if _moving_id >= 0 else -1):
			_place(_hovered, _eff_size)
			if not _multi:
				_stop()
		else:
			_stop()
		return

	# Yerleştirme modunda değilken: kısayol tuşlarına bak
	var hit_id: int = _find_block_at_mouse()
	if InputActions.is_pressed("block_remove") and hit_id >= 0:
		_remove_block(hit_id)
		get_viewport().set_input_as_handled()
	elif InputActions.is_pressed("block_rotate") and hit_id >= 0:
		# döndür
		_ctx_id = hit_id
		_ctx_rotate()
		get_viewport().set_input_as_handled()
	elif hit_id >= 0:
		# Normal tıklama → bağlam menüsü AÇ + event'i tüketme:
		# player da aynı tıklamayı alır ve eşyanın yanına yürür.
		_show_ctx(hit_id)
	else:
		_hide_ctx()

## Fare altındaki bloğun id'sini döndürür, yoksa -1.
## Öncelik sırası:
##   1. Farenin zemin yansıması işgal altındaysa → kesin blok tıklaması.
## Fare altındaki bloğun id'sini döndürür, yoksa -1.
## Sıralama: derinlik (cx+cy) büyükten küçüğe, eşit derinlikte yükseklik büyükten küçüğe.
## Bu sayede yığınlı blokların üstteki yüzleri önce kontrol edilir; ön yüze
## tıklandığında ise sadece o bloğun polygon'u fare noktasını içerdiğinden
## doğru blok seçilir.
## Duvar tıklaması: yalnızca ince yüzey segmentleri test edilir.
## Küp hitbox'ları (top/front/right) kullanılmaz → alttaki karoya tıklanınca menü açılmaz.
func _wall_hit_at_mouse(info: BlockInfo, mp: Vector2) -> bool:
	var h_px    := info.height    * height_per_unit
	var elev_px := info.elevation * height_per_unit
	var cx := info.cell.x
	var cy := info.cell.y
	var sx := info.size.x
	var sy := info.size.y
	match info.wall_face:
		0:  # Güney (SW)
			for dx in sx:
				if Geometry2D.is_point_in_polygon(mp,
						_build_front_face(Vector2i(cx + dx, cy + sy - 1), Vector2i(1, 1), h_px, elev_px)):
					return true
		1:  # Doğu (SE)
			for dy in sy:
				if Geometry2D.is_point_in_polygon(mp,
						_build_right_face(Vector2i(cx + sx - 1, cy + dy), Vector2i(1, 1), h_px, elev_px)):
					return true
		2:  # Kuzey (NE)
			for dx in sx:
				if Geometry2D.is_point_in_polygon(mp,
						_build_north_face(Vector2i(cx + dx, cy), Vector2i(1, 1), h_px, elev_px)):
					return true
		3:  # Batı (NW)
			for dy in sy:
				if Geometry2D.is_point_in_polygon(mp,
						_build_west_face(Vector2i(cx, cy + dy), Vector2i(1, 1), h_px, elev_px)):
					return true
	return false

func _find_block_at_mouse() -> int:
	var mp          := get_global_mouse_position()
	var ground_cell := _w2g(mp)

	var ids: Array = _blocks.keys()
	ids.sort_custom(func(a, b) -> bool:
		var ia: BlockInfo = _blocks[a]
		var ib: BlockInfo = _blocks[b]
		var da := ia.cell.x + ia.cell.y
		var db := ib.cell.x + ib.cell.y
		if da != db: return da > db
		return (ia.elevation + ia.height) > (ib.elevation + ib.height)
	)
	for id in ids:
		var info: BlockInfo = _blocks[id]
		var hit := false
		if info.wall:
			hit = _wall_hit_at_mouse(info, mp)
		else:
			var h_px: float    = info.height    * height_per_unit
			var elev_px: float = info.elevation * height_per_unit
			var top   := _build_top_face  (info.cell, info.size, h_px, elev_px)
			var front := _build_front_face(info.cell, info.size, h_px, elev_px)
			var right := _build_right_face(info.cell, info.size, h_px, elev_px)
			hit = Geometry2D.is_point_in_polygon(mp, top)   or \
				  Geometry2D.is_point_in_polygon(mp, front) or \
				  Geometry2D.is_point_in_polygon(mp, right)
		if not hit:
			continue

		var front_depth := (info.cell.x + info.size.x - 1) \
						 + (info.cell.y + info.size.y - 1)
		var click_depth := ground_cell.x + ground_cell.y
		if click_depth <= front_depth:
			return id

	return -1

func _in_bounds(cell: Vector2i, size: Vector2i) -> bool:
	for dx in size.x:
		for dy in size.y:
			if not _player.astar.is_in_boundsv(cell + Vector2i(dx, dy)):
				return false
	return true

## Tüm hücreler aynı yükseklikte stacklenebilir blok içeriyorsa o yüksekliği,
## aksi hâlde -1 döndürür.
## Tüm hücreler aynı yükseklikte stacklenebilir blok içeriyorsa o yüksekliği,
## aksi hâlde -1 döndürür.
## Taşıma modunda taşınan bloğun hücresinde altındaki gerçek blok kullanılır.
func _find_stack_elevation(cell: Vector2i, size: Vector2i) -> int:
	var common_top: int = -1
	for dx in size.x:
		for dy in size.y:
			var c := cell + Vector2i(dx, dy)
			if not _occupied.has(c):
				return -1
			var occ_id: int = _occupied[c]
			# Taşınan bloğun kendi hücresi → altındaki gerçek bloğa geç
			if _moving_id >= 0 and occ_id == _moving_id:
				occ_id = _find_top_block_at_cell(c, _moving_id)
				if occ_id < 0:
					return -1   # Gerçekten boş → yığınamaz
			var existing: BlockInfo = _blocks.get(occ_id)
			if existing == null or not existing.stackable:
				return -1
			# Duvar yükseklik katmaz: üstüne yerleştirilen blok taban seviyesine gider.
			var top := existing.elevation if existing.wall else existing.elevation + existing.height
			if common_top == -1:
				common_top = top
			elif common_top != top:
				return -1
	return max(common_top, 0)

## Döndürme sonrası yükseklik: boş hücre=0, stacklenebilir blok=üst yüzey.
## Farklı yükseklikteki stacklenebilir bloklar altında → -1.
func _find_rotate_elevation(cell: Vector2i, size: Vector2i, exclude_id: int) -> int:
	var max_elev := 0
	var occ_tops: Array[int] = []
	for dx in size.x:
		for dy in size.y:
			var c := cell + Vector2i(dx, dy)
			if not _occupied.has(c):
				continue
			var occ_id: int = _occupied[c]
			if occ_id == exclude_id:
				continue
			var existing: BlockInfo = _blocks.get(occ_id)
			if existing == null or not existing.stackable:
				return -1
			var top := existing.elevation if existing.wall else existing.elevation + existing.height
			occ_tops.append(top)
			max_elev = maxi(max_elev, top)
	if occ_tops.size() > 1:
		for t in occ_tops:
			if t != occ_tops[0]:
				return -1
	return max_elev

func _rotate_fail_check(info: BlockInfo, cell: Vector2i, size: Vector2i,
		ignore_player: bool = false) -> PlaceFail:
	if not _in_bounds(cell, size):
		return PlaceFail.BOUNDS
	var player_cell := _w2g(_player.global_position)
	var player_blocked   := false
	var foreign_occupied := false
	for dx in size.x:
		for dy in size.y:
			var c := cell + Vector2i(dx, dy)
			if not ignore_player and c == player_cell:
				player_blocked = true
			if _occupied.has(c):
				var occ_id: int = _occupied[c]
				if occ_id != info.id:
					foreign_occupied = true
	if player_blocked:
		return PlaceFail.PLAYER
	if foreign_occupied:
		if not info.stackable:
			return PlaceFail.OCCUPIED
		var elev := _find_rotate_elevation(cell, size, info.id)
		if elev < 0:
			return PlaceFail.NOT_STACKABLE
		_pending_elev = elev
	else:
		_pending_elev = info.elevation
	return PlaceFail.OK

func _can_rotate_place(info: BlockInfo, cell: Vector2i, size: Vector2i,
		ignore_player: bool = false) -> bool:
	return _rotate_fail_check(info, cell, size, ignore_player) == PlaceFail.OK

func _fail_rotate_action(info: BlockInfo, cell: Vector2i, size: Vector2i,
		action: String, ignore_player: bool = true) -> bool:
	var fail := _rotate_fail_check(info, cell, size, ignore_player)
	if fail == PlaceFail.OK:
		return true
	_show_notification(_place_fail_message(action, fail))
	if fail == PlaceFail.OCCUPIED or fail == PlaceFail.NOT_STACKABLE:
		_flash_blocks_red(_find_blocking_block_ids(cell, size, info.id))
	return false

func _find_blocking_block_ids(cell: Vector2i, size: Vector2i, exclude_id: int = -1) -> Array:
	var ids: Array = []
	var seen: Dictionary = {}
	for dx in size.x:
		for dy in size.y:
			var c := cell + Vector2i(dx, dy)
			if not _occupied.has(c):
				continue
			var occ_id: int = _occupied[c]
			if occ_id == exclude_id:
				continue
			if _moving_id >= 0 and occ_id == _moving_id:
				occ_id = _find_top_block_at_cell(c, _moving_id)
				if occ_id < 0 or occ_id == exclude_id:
					continue
			if seen.has(occ_id):
				continue
			seen[occ_id] = true
			ids.append(occ_id)
	return ids

func _place_fail_check(cell: Vector2i, size: Vector2i, ignore_player: bool = false) -> PlaceFail:
	if not _in_bounds(cell, size):
		return PlaceFail.BOUNDS
	var player_cell := _w2g(_player.global_position)
	var player_blocked := false
	var any_occupied   := false
	for dx in size.x:
		for dy in size.y:
			var c := cell + Vector2i(dx, dy)
			if not ignore_player and c == player_cell:
				player_blocked = true
			if _occupied.has(c):
				var occ_id: int = _occupied[c]
				if _moving_id >= 0 and occ_id == _moving_id:
					if _find_top_block_at_cell(c, _moving_id) >= 0:
						any_occupied = true
					continue
				any_occupied = true
	if player_blocked:
		return PlaceFail.PLAYER
	if any_occupied:
		if not _stackable:
			return PlaceFail.OCCUPIED
		var elev := _find_stack_elevation(cell, size)
		if elev < 0:
			return PlaceFail.NOT_STACKABLE
		_pending_elev = elev
	else:
		_pending_elev = 0
	return PlaceFail.OK

func _place_fail_message(action: String, fail: PlaceFail) -> String:
	match fail:
		PlaceFail.BOUNDS:
			return "%s işlemi tamamlanamadı.\nSeçili alan oyun sınırlarının dışında." % action
		PlaceFail.PLAYER:
			return "%s işlemi tamamlanamadı.\nSeçili alanda karakter bulunuyor." % action
		PlaceFail.OCCUPIED:
			return "%s işlemi tamamlanamadı.\nSeçili alan başka bir nesne tarafından işgal edilmiş." % action
		PlaceFail.NOT_STACKABLE:
			return "%s işlemi tamamlanamadı.\nBu konuma yığınlanamaz." % action
	return ""

## Başarılıysa true; aksi hâlde bildirim gösterir, nesne engeliyse kırmızı yanıp söndürür.
func _fail_action(cell: Vector2i, size: Vector2i, ignore_player: bool,
		action: String, exclude_id: int = -1) -> bool:
	var fail := _place_fail_check(cell, size, ignore_player)
	if fail == PlaceFail.OK:
		return true
	_show_notification(_place_fail_message(action, fail))
	if fail == PlaceFail.OCCUPIED or fail == PlaceFail.NOT_STACKABLE:
		_flash_blocks_red(_find_blocking_block_ids(cell, size, exclude_id))
	return false

func _can_place(cell: Vector2i, size: Vector2i, ignore_player: bool = false) -> bool:
	return _place_fail_check(cell, size, ignore_player) == PlaceFail.OK

func _place(cell: Vector2i, size: Vector2i) -> void:
	# Taşıma modundaysa eski bloğu ÖNCE sil.
	# Eski ve yeni konum aynı olsa bile önce sil → astar walkable olur,
	# ardından yeni blok solid yapar. Ters sırada: yeni blok solid yaptıktan
	# sonra _free_block_cells aynı hücreleri tekrar walkable yapıyor (bug).
	if _moving_id >= 0:
		_remove_block(_moving_id)
		_moving_id = -1

	var info       := BlockInfo.new()
	info.id        = _next_id
	info.cell      = cell
	info.size      = size
	info.height    = _height
	info.stackable = _stackable
	info.walkable  = _walkable
	info.wall      = _wall
	info.wall_face = _wall_face
	info.elevation = _pending_elev
	_next_id      += 1

	_occupy_block_cells(info)
	_build_block_visuals(info)
	_blocks[info.id] = info

	# Yeni solid hücreler mevcut rotayı engelliyor olabilir → geçersizse iptal et
	_player.invalidate_path_if_blocked()

# ── Önizleme ─────────────────────────────────────────────────────────────────

func _preview_cols() -> Array:
	var key: String
	if _wall:                        key = "wall"
	elif _stackable and _walkable:   key = "both"
	elif _stackable:                 key = "stack"
	elif _walkable:                  key = "walk"
	else:                            key = "normal"
	var c: Array = BLOCK_COLORS[key]
	return [Color(c[0], 0.5), Color(c[1], 0.5), Color(c[2], 0.5)]


# ── Yüz oluşturucular ─────────────────────────────────────────────────────────

func _build_poly(cell: Vector2i, size: Vector2i) -> PackedVector2Array:
	var hw  := tile_width  * 0.5
	var hh  := tile_height * 0.5
	var pts := PackedVector2Array()
	for i in size.x:
		pts.append(_g2w(cell + Vector2i(i, 0))                 + Vector2(0.0, -hh))
	for j in size.y:
		pts.append(_g2w(cell + Vector2i(size.x - 1, j))        + Vector2(hw,  0.0))
	for i in size.x:
		pts.append(_g2w(cell + Vector2i(size.x-1-i, size.y-1)) + Vector2(0.0,  hh))
	for j in size.y:
		pts.append(_g2w(cell + Vector2i(0, size.y-1-j))        + Vector2(-hw, 0.0))
	return pts

func _build_top_face(cell: Vector2i, size: Vector2i, h_px: float, elev_px: float = 0.0) -> PackedVector2Array:
	var base := _build_poly(cell, size)
	var pts  := PackedVector2Array()
	for p in base:
		pts.append(p + Vector2(0.0, -(h_px + elev_px)))
	return pts

func _build_right_face(cell: Vector2i, size: Vector2i, h_px: float, elev_px: float = 0.0) -> PackedVector2Array:
	var hw     := tile_width  * 0.5
	var hh     := tile_height * 0.5
	var ground := PackedVector2Array()
	for j in size.y:
		ground.append(_g2w(cell + Vector2i(size.x - 1, j))        + Vector2(hw,  0.0))
	ground.append(  _g2w(cell + Vector2i(size.x - 1, size.y - 1)) + Vector2(0.0,  hh))
	var poly := PackedVector2Array()
	for p in ground:                           poly.append(p + Vector2(0.0, -(h_px + elev_px)))
	for i in range(ground.size() - 1, -1, -1): poly.append(ground[i] + Vector2(0.0, -elev_px))
	return poly

func _build_front_face(cell: Vector2i, size: Vector2i, h_px: float, elev_px: float = 0.0) -> PackedVector2Array:
	var hw     := tile_width  * 0.5
	var hh     := tile_height * 0.5
	var ground := PackedVector2Array()
	for i in size.x:
		ground.append(_g2w(cell + Vector2i(size.x - 1 - i, size.y - 1)) + Vector2(0.0, hh))
	ground.append(_g2w(cell + Vector2i(0, size.y - 1)) + Vector2(-hw, 0.0))
	var poly := PackedVector2Array()
	for p in ground:                           poly.append(p + Vector2(0.0, -(h_px + elev_px)))
	for i in range(ground.size() - 1, -1, -1): poly.append(ground[i] + Vector2(0.0, -elev_px))
	return poly

## Kuzey (NE) yüzü: hücrenin kuzey‑doğu kenarı boyunca dikey duvar.
## size.x kadar hücre genişliğinde, size.y kullanılmaz (her zaman kuzey kenar).
func _build_north_face(cell: Vector2i, size: Vector2i, h_px: float, elev_px: float = 0.0) -> PackedVector2Array:
	var hw     := tile_width  * 0.5
	var hh     := tile_height * 0.5
	var ground := PackedVector2Array()
	for i in size.x:
		ground.append(_g2w(cell + Vector2i(i, 0)) + Vector2(0.0, -hh))
	ground.append(_g2w(cell + Vector2i(size.x - 1, 0)) + Vector2(hw, 0.0))
	var poly := PackedVector2Array()
	for p in ground:                           poly.append(p + Vector2(0.0, -(h_px + elev_px)))
	for i in range(ground.size() - 1, -1, -1): poly.append(ground[i] + Vector2(0.0, -elev_px))
	return poly

## Batı (NW) yüzü: hücrenin kuzey‑batı kenarı boyunca dikey duvar.
## size.y kadar hücre derinliğinde, size.x kullanılmaz (her zaman batı kenar).
func _build_west_face(cell: Vector2i, size: Vector2i, h_px: float, elev_px: float = 0.0) -> PackedVector2Array:
	var hw     := tile_width  * 0.5
	var hh     := tile_height * 0.5
	var ground := PackedVector2Array()
	ground.append(_g2w(cell) + Vector2(0.0, -hh))   # Kuzey köşe (başlangıç)
	for j in size.y:
		ground.append(_g2w(cell + Vector2i(0, j)) + Vector2(-hw, 0.0))
	var poly := PackedVector2Array()
	for p in ground:                           poly.append(p + Vector2(0.0, -(h_px + elev_px)))
	for i in range(ground.size() - 1, -1, -1): poly.append(ground[i] + Vector2(0.0, -elev_px))
	return poly

# ── Koordinat dönüştürücüler ──────────────────────────────────────────────────

func _w2g(wp: Vector2) -> Vector2i:
	var hw := tile_width  * 0.5
	var hh := tile_height * 0.5
	var gx := int(round((wp.x / hw + wp.y / hh) * 0.5))
	var gy := int(round((wp.y / hh - wp.x / hw) * 0.5))
	return Vector2i(gx, gy) + Vector2i(grid_width / 2, grid_height / 2)

func _g2w(cell: Vector2i) -> Vector2:
	var logical := cell - Vector2i(grid_width / 2, grid_height / 2)
	var hw := tile_width  * 0.5
	var hh := tile_height * 0.5
	return Vector2((logical.x - logical.y) * hw, (logical.x + logical.y) * hh)
