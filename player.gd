extends CharacterBody2D

@export var seconds_per_cell: float = 0.5
@export var arrival_distance: float = 4.0
@export var grid_width: int = 41
@export var grid_height: int = 41
@export var tile_width: float = 64.0
@export var tile_height: float = 32.0
## Karakterin tek seferde çıkabileceği / inebileceği maks yükseklik (px).
## 1 birim = tile_width = 64 px.
@export var max_step_px: float = 64.0

var astar: AStarGrid2D
var grid_offset: Vector2i
var path: Array[Vector2] = []
var path_index: int = 0

var _step_start:    Vector2 = Vector2.ZERO
var _last_step_idx: int     = -1

const DRAG_THRESHOLD := 6.0
var _camera:        Camera2D
var _char_view:     Node2D = null
var _press_pos:     Vector2
var _is_dragging:   bool    = false

var _vis_root:      Node2D  = null   # Görsel çocukların kapsayıcısı
var _elev_px:       float   = 0.0   # Geçerli görsel yükseklik (px)
var _block_manager: Node    = null   # Yürünebilir yüzey sorgusu için
var _move_step:     Vector2i = Vector2i.ZERO
var _origin_cell:   Vector2i = Vector2i.ZERO
var _origin_z:      int     = 0

func _ready() -> void:
	grid_offset = Vector2i(grid_width / 2, grid_height / 2)
	_setup_astar()
	global_position = _grid_to_world(_world_to_grid(global_position))
	_camera        = get_parent().get_node("Camera2D")
	_block_manager = get_parent().get_node_or_null("BlockManager")
	_origin_cell   = _world_to_grid(global_position)
	_origin_z      = _surface_h_at(_origin_cell)

	# Görsel kök: tüm görsel çocuklar buraya taşınır.
	# CharacterBody2D hareketsiz kalır, sadece _vis_root kayar.
	_vis_root = Node2D.new()
	add_child(_vis_root)
	# Eski yer tutucu elmas (Shape) — 3D karakter varken gizle.
	var shape := get_node_or_null("Shape") as Polygon2D
	if shape == null:
		shape = get_node_or_null("Polygon2D") as Polygon2D
	if shape:
		shape.visible = false
		shape.reparent(_vis_root)

	_add_character_view()

func _add_character_view() -> void:
	# Habbo karakter (varsayılan). Idle FBX yedeği:
	# load("res://character_view.idle_backup.gd")
	var script = load("res://character_view.gd")
	if script == null:
		return
	_char_view = script.new()
	# vis_root yoksa doğrudan self'e ekle
	if _vis_root:
		_vis_root.add_child(_char_view)
	else:
		add_child(_char_view)

func _setup_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, grid_width, grid_height)
	astar.cell_size = Vector2(tile_width, tile_height)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_pos = event.position
			_is_dragging = false
		else:
			if not _is_dragging:
				_request_path(get_global_mouse_position())
			_is_dragging = false
	elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if not _is_dragging and event.position.distance_to(_press_pos) > DRAG_THRESHOLD:
			_is_dragging = true
		if _is_dragging and _camera:
			_camera.pan_by(event.relative)

## Belirtilen hücrenin yürünebilir yüzey yüksekliğini (px) döndürür.
func _surface_px(cell: Vector2i) -> float:
	if _block_manager and _block_manager.has_method("get_walkable_surface_px"):
		return _block_manager.call("get_walkable_surface_px", cell)
	return 0.0

func _request_path(world_target: Vector2) -> void:
	var start_cell := _world_to_grid(global_position)
	var end_cell   := _world_to_grid(world_target)
	if not astar.is_in_boundsv(start_cell) or not astar.is_in_boundsv(end_cell):
		return
	# Hedef hücre yürünemez (solid) ise hareket başlatma.
	if astar.is_point_solid(end_cell):
		return
	var grid_path := _height_path(start_cell, end_cell)
	if grid_path.is_empty():
		return
	path.clear()
	for cell in grid_path:
		path.append(_grid_to_world(cell))
	path_index     = 0
	_last_step_idx = -1
	while path_index < path.size() - 1 \
			and _world_to_grid(global_position) == _world_to_grid(path[path_index]):
		path_index += 1

## Ağırlıklı A* yol bulma (kardinal=10, çapraz=14).
## - Düz gidişte kardinal her zaman daha ucuz → zigzag olmaz.
## - L-yolda oktil sezgiseli A*'ı çapraz adımları öne alacak şekilde yönlendirir.
## - Hedef erişilemez ise en yakın erişilebilir hücreye kadar yol verir.
const _CARD_COST := 10
const _DIAG_COST := 14

func _height_path(start: Vector2i, end: Vector2i) -> Array[Vector2i]:
	if start == end:
		return [start]
	var sentinel := Vector2i(-1, -1)
	var g_cost: Dictionary = {start: 0}
	var prev:   Dictionary = {start: sentinel}
	# open list: [f, g, cell]  —  f küçükten büyüğe sıralı
	# Sıralama: [f, h, g, cell] — eşit f'de küçük h (hedefe yakın) önce gelir.
	# Bu sayede A* çapraz adımları önce atar (çapraz h'yi daha hızlı düşürür).
	var sh0 := _path_h(start, end)
	var open: Array = [[sh0, sh0, 0, start]]
	var found := false
	while open.size() > 0:
		open.sort()
		var entry: Array    = open.pop_front()
		var g:     int      = entry[2]
		var cur:   Vector2i = entry[3]
		if cur == end:
			found = true
			break
		if g > g_cost.get(cur, 999999):
			continue   # eski açık liste girdisi, atla
		for nb_data: Array in _height_neighbors(cur):
			var nb:   Vector2i = nb_data[0]
			var cost: int      = nb_data[1]
			var ng:   int      = g + cost
			if ng < g_cost.get(nb, 999999):
				g_cost[nb] = ng
				prev[nb]   = cur
				var h := _path_h(nb, end)
				open.append([ng + h, h, ng, nb])
	# Hedef erişilemezse (yükseklik / engel) yürüme — dibine kadar gitme.
	if not found:
		return []
	var target := end
	# Yolu geri oku
	var result: Array[Vector2i] = []
	var cur := target
	while cur != sentinel:
		result.push_front(cur)
		cur = prev.get(cur, sentinel)
	return result

## Oktil mesafe sezgiseli (admissible, optimal yolu garanti eder).
func _path_h(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return _CARD_COST * (dx + dy) + (_DIAG_COST - 2 * _CARD_COST) * mini(dx, dy)

## A* komşuları: çaprazlar ÖNCE (sezgisel A*'ı çapraz adımları öne almaya iter),
## kardinallar SONRA. Düz yolda kardinal zaten daha ucuz olduğu için zigzag olmaz.
func _height_neighbors(cell: Vector2i) -> Array:
	var result: Array = []
	var sh := _surface_px(cell)
	# Çaprazlar önce → L-yolda A* önce çapraz adımı seçer
	var dirs: Array[Vector2i] = [
		Vector2i( 1,  1), Vector2i( 1, -1),
		Vector2i(-1,  1), Vector2i(-1, -1),
		Vector2i( 1,  0), Vector2i(-1,  0),
		Vector2i( 0,  1), Vector2i( 0, -1),
	]
	for dir: Vector2i in dirs:
		var nb: Vector2i = cell + dir
		if not astar.is_in_boundsv(nb): continue
		if astar.is_point_solid(nb):    continue
		var diag := dir.x != 0 and dir.y != 0
		if diag:
			# Her iki kardinal komşu da solid ise çapraz engellenir
			if astar.is_point_solid(cell + Vector2i(dir.x, 0)) and \
			   astar.is_point_solid(cell + Vector2i(0, dir.y)):
				continue
		if _surface_px(nb) - sh > max_step_px: continue
		result.append([nb, _DIAG_COST if diag else _CARD_COST])
	return result

func _physics_process(_delta: float) -> void:
	if path_index >= path.size():
		velocity = Vector2.ZERO
		_move_step = Vector2i.ZERO
		if _char_view and _char_view.has_method("set_moving"):
			_char_view.set_moving(false)
		move_and_slide()
		_update_depth()
		return

	var target    := path[path_index]
	var to_target := target - global_position
	var distance  := to_target.length()

	# Yeni adım — hemen o yöne dön
	if path_index != _last_step_idx:
		_step_start    = global_position
		_last_step_idx = path_index
		var new_step := _world_to_grid(target) - _world_to_grid(_step_start)
		if new_step != Vector2i.ZERO:
			_move_step = new_step
			if _char_view and _char_view.has_method("set_facing_grid_step"):
				_char_view.set_facing_grid_step(new_step)

	var step_dist:  float = max(_step_start.distance_to(target), 1.0)
	var step_speed: float = step_dist / seconds_per_cell

	if distance <= arrival_distance:
		global_position = target
		path_index     += 1
		_last_step_idx  = -1
		velocity        = Vector2.ZERO
		if path_index >= path.size() and _char_view and _char_view.has_method("set_moving"):
			_char_view.set_moving(false)
		move_and_slide()
		_update_depth()
		return

	velocity = to_target.normalized() * step_speed
	move_and_slide()
	if _char_view:
		var step_cell := _world_to_grid(target) - _world_to_grid(_step_start)
		_move_step = step_cell
		if _char_view.has_method("set_facing_grid_step"):
			_char_view.set_facing_grid_step(step_cell)
		elif _char_view.has_method("set_facing"):
			_char_view.set_facing(velocity)
	_update_depth()

func _update_depth() -> void:
	var cell := _world_to_grid(global_position)
	# Yürünebilir blok yüksekliği → z_index bonusu (alttakinden yüksekse önde çizilir)
	var surface_h: int = 0
	if _block_manager and _block_manager.has_method("get_walkable_surface_h"):
		surface_h = _block_manager.call("get_walkable_surface_h", cell)
	z_index = IsoDepth.single(cell.x, cell.y) + surface_h * IsoDepth.STRIDE
	# Görsel yükselme (px cinsinden)
	var target_px: float = 0.0
	if _block_manager and _block_manager.has_method("get_walkable_surface_px"):
		target_px = _block_manager.call("get_walkable_surface_px", cell)
	_elev_px = lerpf(_elev_px, target_px, 0.25)
	if _vis_root:
		_vis_root.position.y = -_elev_px

## Hareketi tamamen durdurur (Taşı modu başlarken çağrılır).
func stop_movement() -> void:
	path.clear()
	path_index     = 0
	_last_step_idx = -1
	velocity       = Vector2.ZERO
	_move_step     = Vector2i.ZERO
	if _char_view and _char_view.has_method("set_moving"):
		_char_view.set_moving(false)

## Yeni blok konulduğunda çağrılır.
## 1) Aynı hedefe çevre yoldan rota varsa yeniden hesapla.
## 2) Yoksa engele kadar gidebildiği kadarını yap, sonra dur.
func invalidate_path_if_blocked() -> void:
	if path.is_empty() or path_index >= path.size():
		return

	# Önce mevcut rota hâlâ temiz mi kontrol et
	var blocked := false
	for i in range(path_index, path.size()):
		if astar.is_point_solid(_world_to_grid(path[i])):
			blocked = true
			break
	if not blocked:
		return

	# Yeniden rota dene (aynı hedef) — yükseklik kısıtlarına duyarlı BFS
	var dest:   Vector2   = path.back()
	var s_cell: Vector2i  = _world_to_grid(global_position)
	var e_cell: Vector2i  = _world_to_grid(dest)
	# Hedef artık solid ise yolu iptal et, yeniden deneme.
	if astar.is_point_solid(e_cell):
		path.clear()
		return
	if astar.is_in_boundsv(s_cell) and astar.is_in_boundsv(e_cell):
		var new_grid := _height_path(s_cell, e_cell)
		if not new_grid.is_empty():
			path.clear()
			for cell in new_grid:
				path.append(_grid_to_world(cell))
			path_index = 0
			while path_index < path.size() - 1 \
					and _world_to_grid(global_position) == _world_to_grid(path[path_index]):
				path_index += 1
			return

	# Rota bulunamadı: engel öncesine kadar git, sonra dur
	var safe := path.size()
	for i in range(path_index, path.size()):
		if astar.is_point_solid(_world_to_grid(path[i])):
			safe = i
			break
	if safe <= path_index:
		path.clear()
		path_index = 0
		velocity   = Vector2.ZERO
	else:
		path.resize(safe)   # engelden önceki son güvenli adıma kadar yürü

func get_move_step() -> Vector2i:
	return _move_step

func get_grid_cell() -> Vector2i:
	return _world_to_grid(global_position)

func grid_to_world(cell: Vector2i) -> Vector2:
	return _grid_to_world(cell)

func get_surface_px(cell: Vector2i) -> float:
	return _surface_px(cell)

## Spawn noktasına göre konum — başlangıç (0, 0, 0).
func get_relative_position() -> Vector3:
	var cell := _world_to_grid(global_position)
	var z := _surface_h_at(cell)
	return Vector3(
		float(cell.x - _origin_cell.x),
		float(cell.y - _origin_cell.y),
		float(z - _origin_z),
	)

func _surface_h_at(cell: Vector2i) -> int:
	if _block_manager and _block_manager.has_method("get_walkable_surface_h"):
		return _block_manager.call("get_walkable_surface_h", cell) as int
	return 0

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
