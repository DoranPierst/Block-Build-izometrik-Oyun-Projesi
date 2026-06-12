class_name HabboIsoFacing
extends RefCounted

## 8 izometrik yön — grid adımı = ekran gidiş yönü (2:1, 64×32).

enum Dir { N, NE, E, SE, S, SW, W, NW }

const DIR_NAMES: PackedStringArray = [
	"Kuzey", "Kuzeydoğu", "Doğu", "Güneydoğu",
	"Güney", "Güneybatı", "Batı", "Kuzeybatı",
]

const GRID_STEPS: Array[Vector2i] = [
	Vector2i(-1,  0),  # N  sol-üst
	Vector2i(-1, -1),  # NE yukarı
	Vector2i( 0, -1),  # E  sağ-üst
	Vector2i( 1, -1),  # SE sağ
	Vector2i( 1,  0),  # S  sağ-alt
	Vector2i( 1,  1),  # SW aşağı
	Vector2i( 0,  1),  # W  sol-alt
	Vector2i(-1,  1),  # NW sol
]

const DIR_VECTORS: Array[Vector2] = [
	Vector2(-0.8944271909999159, -0.447213595499958),  # N
	Vector2( 0.0,               -1.0),                 # NE
	Vector2( 0.8944271909999159, -0.447213595499958),  # E
	Vector2( 1.0,                0.0),                 # SE
	Vector2( 0.8944271909999159,  0.447213595499958),  # S
	Vector2( 0.0,                1.0),                 # SW
	Vector2(-0.8944271909999159,  0.447213595499958),  # W
	Vector2(-1.0,                0.0),                 # NW
]

const DEFAULT_DIR := Dir.SE

static func dir_from_grid_step(step: Vector2i) -> int:
	var sx := clampi(step.x, -1, 1)
	var sy := clampi(step.y, -1, 1)
	var s := Vector2i(sx, sy)
	if s == Vector2i.ZERO:
		return DEFAULT_DIR
	for i in range(GRID_STEPS.size()):
		if GRID_STEPS[i] == s:
			return i
	return DEFAULT_DIR

static func snap_velocity(vel: Vector2) -> int:
	if vel.length_squared() < 0.25:
		return DEFAULT_DIR
	var v := vel.normalized()
	var best_i := DEFAULT_DIR
	var best_dot := -INF
	for i in range(DIR_VECTORS.size()):
		var d: float = v.dot(DIR_VECTORS[i])
		if d > best_dot:
			best_dot = d
			best_i = i
	return best_i

static func get_facing(dir: int) -> Dictionary:
	# 2D Habbo sprite — 4 açı + yatay ayna.
	const YAWS: Array[float] = [90.0, 90.0, 180.0, 180.0, 0.0, 0.0, 270.0, 270.0]
	const FLIP: Array[bool] = [false, true, false, true, false, true, false, true]
	return {"yaw": YAWS[dir], "flip": FLIP[dir]}

## ═══════════════════════════════════════════════════════════════════
## KİLİTLİ — Kullanıcı onaylı 3D model + pusula bakış açıları (2026-06-07)
## Bu tablo, grid→etiket eşlemesi ve flip değerleri ONAY OLMADAN değiştirilmez.
## ═══════════════════════════════════════════════════════════════════
const MODEL_FACING_LOCKED := true
## Dir: N(K), NE(KD), E(D), SE(GD), S(G), SW(GB), W(B), NW(KB)
const MODEL_YAW_LOCKED: Array[float] = [225.0, 180.0, 135.0, 90.0, 45.0, 0.0, 315.0, 270.0]
const MODEL_FLIP_LOCKED: Array[bool] = [false, false, true, false, false, false, false, false]

## Pusula etiketi (0=K,3=GD,4=G…) → ham model açısı.
static func get_model_facing(dir: int, offset_deg: float = 90.0) -> Dictionary:
	return _raw_model_facing(dir, offset_deg)

## Grid yürüyüş/bakış yönü → pusula etiketine hizalı model açısı.
static func get_model_facing_for_grid(grid_dir: int, offset_deg: float = 90.0) -> Dictionary:
	return _raw_model_facing(_model_lookup_for_grid(grid_dir), offset_deg)

static func _model_lookup_for_grid(grid_dir: int) -> int:
	# Grid kolu → pusula etiket harfi (D, GD, G, GB…); açı o harfe göre.
	return compass_label_dir_for_grid_spoke(grid_dir)

static func _raw_model_facing(dir: int, _offset_deg: float) -> Dictionary:
	if dir < 0 or dir >= MODEL_YAW_LOCKED.size():
		return {"yaw": 0.0, "flip": false}
	return {"yaw": MODEL_YAW_LOCKED[dir], "flip": MODEL_FLIP_LOCKED[dir]}

static func dir_to_yaw(dir: int) -> float:
	return get_facing(dir)["yaw"]

static func toward_camera_amount(dir: int) -> float:
	return DIR_VECTORS[dir].dot(Vector2(0.0, 1.0))

static func dir_name(dir: int) -> String:
	return DIR_NAMES[dir]

const COMPASS_SHORT: PackedStringArray = [
	"K", "KD", "D", "GD", "G", "GB", "B", "KB",
]
const COMPASS_NAMES: PackedStringArray = [
	"Kuzey", "Kuzeydoğu", "Doğu", "Güneydoğu",
	"Güney", "Güneybatı", "Batı", "Kuzeybatı",
]
## Pusula gülünde grid kolu i → etiket harfi (45° kaydırma).
static func compass_label_dir_for_grid_spoke(grid_i: int) -> int:
	return (grid_i + 7) % 8

static func dir_to_compass_short(dir: int) -> String:
	if dir < 0 or dir >= COMPASS_SHORT.size():
		return "?"
	return COMPASS_SHORT[dir]

static func dir_to_compass_name(dir: int) -> String:
	if dir < 0 or dir >= COMPASS_NAMES.size():
		return "—"
	return COMPASS_NAMES[dir]

static func grid_spoke_compass_short(grid_dir: int) -> String:
	return dir_to_compass_short(compass_label_dir_for_grid_spoke(grid_dir))

static func grid_spoke_compass_name(grid_dir: int) -> String:
	return dir_to_compass_name(compass_label_dir_for_grid_spoke(grid_dir))

static func grid_step(dir: int) -> Vector2i:
	return GRID_STEPS[dir]
