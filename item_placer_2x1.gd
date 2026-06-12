extends Node2D

## 2×1 izometrik eşya yerleştirici.
## Görsel atamak için preview_changed sinyalini dinle;
## yerleştirme mantığını block_manager._occupied ile bağlamak için
## start(occupied_ref) çağrısında sözlük referansını geç.

# ── Sinyaller ────────────────────────────────────────────────────────────────
## valid=true  → preview göster (cell_a ve cell_b dünya pozisyonları verilir)
## valid=false → preview gizle
signal preview_changed(world_a: Vector2, world_b: Vector2, valid: bool, dir: int)

## İki hücre başarıyla yerleştirildi.
signal item_placed(cell_a: Vector2i, cell_b: Vector2i)

## Geçersiz konumda tıklandı → moddan çıkıldı, işlem iptal.
signal placement_cancelled()

# ── Sabitler ─────────────────────────────────────────────────────────────────
## İzometrik perspektife göre yalnızca iki geçerli yön:
##   0 = RIGHT_DOWN : B → A + (1, 0)  (ekranda sağ-alt)
##   1 = LEFT_DOWN  : B → A + (0, 1)  (ekranda sol-alt)
enum Dir { RIGHT_DOWN = 0, LEFT_DOWN = 1 }

const DIR_OFFSET: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]

# ── Export parametreleri (BlockManager ile aynı tutulmalı) ───────────────────
@export var tile_width:  float = 64.0
@export var tile_height: float = 32.0
@export var grid_width:  int   = 40
@export var grid_height: int   = 40

# ── Durum değişkenleri ───────────────────────────────────────────────────────
var active:    bool        = false
var valid:     bool        = false
var cell_a:    Vector2i            ## Pivot — fare her zaman buranın üzerinde
var cell_b:    Vector2i            ## B bloğu — yöne göre hesaplanır
var direction: Dir         = Dir.LEFT_DOWN

var _occupied: Dictionary          ## Dışarıdan geçirilen doluluk referansı
var _characters: Array[Node2D] = [] ## Hücreleri engel sayılacak oyuncu/NPC'ler


# ── Genel API ────────────────────────────────────────────────────────────────

## Yerleştirme modunu başlat.
## occupied_ref: block_manager._occupied sözlüğünü direkt referans geçin
## (değer kopyası değil, aynı nesne → otomatik senkronize kalır).
## characters: oyuncu/NPC node listesi — bulundukları hücreye eşya koyulamaz.
func start(occupied_ref: Dictionary, characters: Array[Node2D] = []) -> void:
	_occupied   = occupied_ref
	_characters = characters
	active     = true
	direction  = Dir.LEFT_DOWN
	set_process(true)
	set_process_input(true)
	_evaluate(_w2g(get_global_mouse_position()))


## Yerleştirme modunu durdur (dışarıdan da çağrılabilir).
func stop() -> void:
	active = false
	valid  = false
	set_process(false)
	set_process_input(false)
	queue_redraw()
	preview_changed.emit(Vector2.ZERO, Vector2.ZERO, false, int(direction))


# ── Godot Döngüsü ────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	var new_a := _w2g(get_global_mouse_position())
	if new_a != cell_a:
		_evaluate(new_a)


func _input(event: InputEvent) -> void:
	if not active:
		return
	if not (event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed):
		return
	if get_viewport().is_input_handled():
		return

	get_viewport().set_input_as_handled()

	if not valid:
		# Kural 6: Geçersiz konumda tıklandı → iptal
		stop()
		placement_cancelled.emit()
		return

	# Yerleştir
	_occupied[cell_a] = true
	_occupied[cell_b] = true
	item_placed.emit(cell_a, cell_b)
	stop()


# ── Temel Mantık ─────────────────────────────────────────────────────────────

func _evaluate(new_a: Vector2i) -> void:
	cell_a = new_a

	# Kural 4: Önce mevcut yönü dene, sonra diğerini
	var try_order: Array[Dir]
	if direction == Dir.RIGHT_DOWN:
		try_order = [Dir.RIGHT_DOWN, Dir.LEFT_DOWN]
	else:
		try_order = [Dir.LEFT_DOWN, Dir.RIGHT_DOWN]

	for d in try_order:
		var b := cell_a + DIR_OFFSET[d]
		if _placeable(cell_a) and _placeable(b):
			# Kural 1, 2: A pivot, B hesaplanan yönde
			direction = d
			cell_b    = b
			valid     = true
			queue_redraw()
			preview_changed.emit(_g2w(cell_a), _g2w(cell_b), true, int(d))
			return

	# Kural 5: Her iki yön de engelli → gizle
	valid = false
	queue_redraw()
	preview_changed.emit(_g2w(cell_a), _g2w(cell_a), false, int(direction))


func _placeable(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= grid_width:
		return false
	if cell.y < 0 or cell.y >= grid_height:
		return false
	if _occupied.has(cell):
		return false
	for ch in _characters:
		if _w2g(ch.global_position) == cell:
			return false
	return true


# ── Dahili Önizleme Çizimi (opsiyonel — sinyal ile kendi görselinizi kullanın) ─

func _draw() -> void:
	if not active or not valid:
		return  # Kural 5: Geçersizse tamamen gizle

	var hw  := tile_width  * 0.5
	var hh  := tile_height * 0.5
	var col := Color(0.85, 0.65, 0.15, 0.50)
	var bdr := Color(1.00, 1.00, 1.00, 0.80)

	for cell in [cell_a, cell_b]:
		var center := _g2w(cell)
		var diamond := PackedVector2Array([
			center + Vector2( 0.0, -hh),
			center + Vector2( hw,  0.0),
			center + Vector2( 0.0,  hh),
			center + Vector2(-hw,  0.0),
		])
		draw_colored_polygon(diamond, col)
		var closed := PackedVector2Array(diamond)
		closed.append(diamond[0])
		draw_polyline(closed, bdr, 1.5)

	# A bloğunu öne çıkar
	var ac := _g2w(cell_a)
	draw_circle(ac, 3.0, Color(1, 1, 0, 0.9))


# ── Koordinat Dönüştürücüler ─────────────────────────────────────────────────

func _w2g(wp: Vector2) -> Vector2i:
	var hw := tile_width  * 0.5
	var hh := tile_height * 0.5
	var gx := int(round((wp.x / hw + wp.y / hh) * 0.5))
	var gy := int(round((wp.y / hh - wp.x / hw) * 0.5))
	return Vector2i(gx, gy) + Vector2i(grid_width / 2, grid_height / 2)


func _g2w(cell: Vector2i) -> Vector2:
	var off := Vector2i(grid_width / 2, grid_height / 2)
	var log := cell - off
	var hw  := tile_width  * 0.5
	var hh  := tile_height * 0.5
	return Vector2((log.x - log.y) * hw, (log.x + log.y) * hh)
