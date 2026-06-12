extends Node2D

## Karakterin baktığı grid hücresinde ok — pusuladan bağımsız (gerçek facing).

var _player: CharacterBody2D
var _enabled: bool = false

func _ready() -> void:
	_player = get_parent().get_node_or_null("Player") as CharacterBody2D

func set_enabled(on: bool) -> void:
	_enabled = on
	visible = on
	queue_redraw()

func is_enabled() -> bool:
	return _enabled

func _process(_delta: float) -> void:
	if _enabled:
		queue_redraw()

func _draw() -> void:
	if not _enabled or _player == null:
		return
	if not _player.has_method("get_grid_cell"):
		return

	var cv := _find_character_view(_player)
	if cv == null or not cv.has_method("get_facing_dir"):
		return

	var dir: int = cv.call("get_facing_dir")
	var step: Vector2i = IsoFacing.grid_step(dir)
	var target: Vector2i = _player.call("get_grid_cell") + step

	var center: Vector2 = _player.grid_to_world(target)
	var elev: float = 0.0
	if _player.has_method("get_surface_px"):
		elev = _player.call("get_surface_px", target)
	center.y -= elev

	var tw: float = _player.tile_width if "tile_width" in _player else 64.0
	var th: float = _player.tile_height if "tile_height" in _player else 32.0
	var hw := tw * 0.5
	var hh := th * 0.5

	z_index = IsoDepth.single(target.x, target.y) + 2
	z_as_relative = false

	_draw_tile_mark(center, hw, hh)
	_draw_facing_arrow(center, IsoFacing.DIR_VECTORS[dir], hw * 0.55)

func _draw_tile_mark(center: Vector2, hw: float, hh: float) -> void:
	var tile := PackedVector2Array([
		center + Vector2(0.0, -hh),
		center + Vector2(hw, 0.0),
		center + Vector2(0.0, hh),
		center + Vector2(-hw, 0.0),
	])
	draw_colored_polygon(tile, Color(1.0, 0.88, 0.12, 0.28))
	draw_polyline(tile + PackedVector2Array([tile[0]]), Color(1.0, 0.92, 0.2, 0.95), 2.5)

func _draw_facing_arrow(center: Vector2, dir: Vector2, length: float) -> void:
	if dir.length_squared() < 0.001:
		return
	var d := dir.normalized()
	var tip := center + d * length
	var wing := Vector2(-d.y, d.x) * length * 0.42
	var base := center + d * (length * 0.22)
	var fill := Color(1.0, 0.35, 0.12, 0.95)
	var outline := Color(0.05, 0.05, 0.08, 1.0)
	var head := PackedVector2Array([tip, base + wing, base - wing])
	draw_colored_polygon(head, fill)
	draw_polyline(head + PackedVector2Array([head[0]]), outline, 2.0)
	draw_line(base, tip, outline, 2.5)

func _find_character_view(root: Node) -> Node:
	if root.has_method("get_facing_dir"):
		return root
	for ch in root.get_children():
		var f := _find_character_view(ch)
		if f:
			return f
	return null
