extends Node2D

@export var grid_width: int = 41
@export var grid_height: int = 41
@export var tile_width: float = 64.0
@export var tile_height: float = 32.0

## Zemin dolgu rengi — soluk beton tonu
@export var floor_color: Color        = Color(0.52, 0.52, 0.50, 1.00)
## Hücre çizgisi rengi
@export var grid_color: Color         = Color(0.35, 0.35, 0.33, 0.70)
## Hover dolgu ve kenarlık
@export var hover_fill_color: Color   = Color(0.70, 0.70, 0.68, 0.20)
@export var hover_border_color: Color = Color(0.85, 0.85, 0.83, 0.85)
@export var hover_border_width: float = 2.0

var grid_offset: Vector2i
var hovered_cell: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
	grid_offset = Vector2i(grid_width / 2, grid_height / 2)
	z_index     = -100   # Blokların ve karakterin her zaman altında
	set_process(true)
	queue_redraw()

func _process(_delta: float) -> void:
	var mouse_world := get_global_mouse_position()
	var cell := _world_to_grid(mouse_world)
	if cell != hovered_cell:
		hovered_cell = cell
		queue_redraw()

func _draw() -> void:
	# 1. Tüm grid alanını tek dolu elmas olarak çiz (zemin)
	_draw_floor()
	# 2. Hücre çizgilerini zemin üzerine çiz
	for gx in grid_width:
		for gy in grid_height:
			_draw_iso_cell(_grid_to_world(Vector2i(gx, gy)), false)
	# 3. Hover efekti
	if hovered_cell.x >= 0 and hovered_cell.x < grid_width \
			and hovered_cell.y >= 0 and hovered_cell.y < grid_height:
		_draw_iso_cell(_grid_to_world(hovered_cell), true)

## Grid'in tüm dış sınırını oluşturan 4 köşeli elmas poligonu çizer.
## Blok Polygon2D'leri z_as_relative=false ile daha yüksek z_index'te olduğundan
## bu zemin onların altında kalır.
func _draw_floor() -> void:
	var hw := tile_width  * 0.5
	var hh := tile_height * 0.5
	var corners := PackedVector2Array([
		_grid_to_world(Vector2i(0,              0             )) + Vector2(  0, -hh),
		_grid_to_world(Vector2i(grid_width - 1, 0             )) + Vector2( hw,   0),
		_grid_to_world(Vector2i(grid_width - 1, grid_height-1 )) + Vector2(  0,  hh),
		_grid_to_world(Vector2i(0,              grid_height-1 )) + Vector2(-hw,   0),
	])
	draw_colored_polygon(corners, floor_color)

func _draw_iso_cell(center: Vector2, hovered: bool) -> void:
	var hw := tile_width * 0.5
	var hh := tile_height * 0.5
	var corners := PackedVector2Array([
		center + Vector2(0.0, -hh),
		center + Vector2(hw, 0.0),
		center + Vector2(0.0, hh),
		center + Vector2(-hw, 0.0),
	])
	if hovered:
		draw_colored_polygon(corners, hover_fill_color)
		var border := PackedVector2Array(corners)
		border.append(corners[0])
		draw_polyline(border, hover_border_color, hover_border_width)
	else:
		var border := PackedVector2Array(corners)
		border.append(corners[0])
		draw_polyline(border, grid_color)

func _world_to_grid(world_pos: Vector2) -> Vector2i:
	var half_w := tile_width * 0.5
	var half_h := tile_height * 0.5
	var gx := int(round((world_pos.x / half_w + world_pos.y / half_h) * 0.5))
	var gy := int(round((world_pos.y / half_h - world_pos.x / half_w) * 0.5))
	return Vector2i(gx, gy) + grid_offset

func _grid_to_world(cell: Vector2i) -> Vector2:
	var logical := cell - grid_offset
	var half_w := tile_width * 0.5
	var half_h := tile_height * 0.5
	return Vector2(
		(logical.x - logical.y) * half_w,
		(logical.x + logical.y) * half_h
	)
