class_name IsoCharacter2D
extends RefCounted

## İzometrik blok karakter — 2 birim (64px), 8 yön, yüz gidiş yönüne.

const CHAR_H := 64.0

class Colors:
	var skin:  Color = Color(0.96, 0.82, 0.68)
	var skin_sh: Color = Color(0.82, 0.66, 0.52)
	var hair:  Color = Color(0.34, 0.20, 0.09)
	var shirt: Color = Color(0.16, 0.52, 0.90)
	var shirt_sh: Color = Color(0.10, 0.38, 0.72)
	var pants: Color = Color(0.18, 0.24, 0.40)
	var pants_sh: Color = Color(0.12, 0.16, 0.30)
	var shoes: Color = Color(0.10, 0.10, 0.12)
	var eye:   Color = Color(0.06, 0.06, 0.08)
	var mouth: Color = Color(0.50, 0.28, 0.26)
	var line:  Color = Color(0.08, 0.07, 0.10, 0.65)

static func draw_character(
		canvas: CanvasItem,
		dir: int,
		walk_t: float,
		colors: Colors,
		anchor: Vector2 = Vector2.ZERO) -> void:
	var v := _dir_vec(dir)
	var side := Vector2(-v.y, v.x)
	var bob := sin(walk_t) * 1.6 if walk_t != 0.0 else 0.0
	var step := sin(walk_t) * 5.0 if walk_t != 0.0 else 0.0

	var feet := anchor + Vector2(0.0, bob)
	var hip_y := feet.y - CHAR_H * 0.38
	var waist_y := feet.y - CHAR_H * 0.50
	var chest_y := feet.y - CHAR_H * 0.62
	var neck_y := feet.y - CHAR_H * 0.72
	var head_y := feet.y - CHAR_H * 0.86

	var face_on := v.dot(Vector2(0.0, 1.0)) >= -0.1
	var front := v.dot(Vector2(0.0, 1.0)) >= 0.0

	if front:
		_draw_leg(canvas, feet, hip_y, v, side, -1, step, colors)
		_draw_arm(canvas, chest_y, neck_y, v, side, -1, -step * 0.55, colors)

	_draw_body(canvas, feet, hip_y, waist_y, chest_y, neck_y, v, side, colors)
	_draw_head(canvas, Vector2(feet.x, head_y), neck_y, v, side, colors, face_on)

	if not front:
		_draw_leg(canvas, feet, hip_y, v, side, -1, step, colors)
		_draw_arm(canvas, chest_y, neck_y, v, side, -1, -step * 0.55, colors)

	_draw_leg(canvas, feet, hip_y, v, side, 1, -step, colors)
	_draw_arm(canvas, chest_y, neck_y, v, side, 1, step * 0.55, colors)

static func _dir_vec(dir: int) -> Vector2:
	var raw: Vector2 = IsoFacing.DIR_VECTORS[dir]
	if raw.length_squared() < 0.001:
		return Vector2(0.0, 1.0)
	return raw.normalized()

# ── Gövde ─────────────────────────────────────────────────────────────────────

static func _draw_body(
		canvas: CanvasItem, feet: Vector2, hip_y: float, waist_y: float,
		chest_y: float, neck_y: float, v: Vector2, side: Vector2, c: Colors) -> void:
	var cx := feet.x
	var depth := CHAR_H * 0.05

	# Pantolon — kalça bloğu
	_block(canvas,
		cx + side.x * 5.0 + v.x * depth, hip_y,
		cx - side.x * 5.0 + v.x * depth, waist_y + 2.0,
		c.pants, c.pants_sh, c.line)

	# Göğüs — gömlek
	_block(canvas,
		cx + side.x * 7.0 + v.x * depth * 1.2, waist_y,
		cx - side.x * 7.0 + v.x * depth * 1.2, chest_y,
		c.shirt, c.shirt_sh, c.line)

	# Yaka şeridi
	var collar_w := CHAR_H * 0.09
	_rect(canvas,
		Vector2(cx - collar_w, chest_y - 2.0),
		Vector2(cx + collar_w, chest_y + 3.0),
		c.shirt.lightened(0.12), c.line)

	# Boyun
	_rect(canvas,
		Vector2(cx - 3.5, chest_y),
		Vector2(cx + 3.5, neck_y),
		c.skin, c.line)

# ── Kafa ──────────────────────────────────────────────────────────────────────

static func _draw_head(
		canvas: CanvasItem, head_c: Vector2, neck_y: float,
		v: Vector2, side: Vector2, c: Colors, face_on: bool) -> void:
	var hw := CHAR_H * 0.11
	var hh := CHAR_H * 0.10
	var top := head_c.y - hh
	var bot := head_c.y + hh * 0.55

	# Saç (arka/üst blok)
	_rect(canvas,
		Vector2(head_c.x - hw - 1.0, top - 3.0),
		Vector2(head_c.x + hw + 1.0, head_c.y - hh * 0.2),
		c.hair, c.line)

	# Yüz bloğu
	_rect(canvas,
		Vector2(head_c.x - hw, top),
		Vector2(head_c.x + hw, bot),
		c.skin, c.line)

	if face_on:
		var fwd := head_c + v * (hw * 0.55)
		# Gözler — küçük dikdörtgen
		for sign: int in [-1, 1]:
			var e: Vector2 = fwd + side * (float(sign) * hw * 0.38)
			_rect(canvas, e + Vector2(-2.0, -2.0), e + Vector2(2.0, 2.0), c.eye, c.line)
			canvas.draw_rect(Rect2(e.x + 0.5, e.y - 1.5, 1.2, 1.2), Color.WHITE)
		# Burun
		var nose := fwd + v * (hw * 0.2)
		canvas.draw_rect(Rect2(nose.x - 1.0, nose.y - 1.0, 2.0, 2.0), c.skin_sh)
		# Ağız
		var mouth := fwd + v * (hw * 0.42) + Vector2(0.0, 3.0)
		canvas.draw_line(mouth - side * 3.0, mouth + side * 3.0, c.mouth, 1.6)
	else:
		# Sırt — saç tabanı
		_rect(canvas,
			Vector2(head_c.x - hw * 0.8, top + 2.0),
			Vector2(head_c.x + hw * 0.8, bot - 2.0),
			c.hair.darkened(0.08), c.line)

# ── Bacak ─────────────────────────────────────────────────────────────────────

static func _draw_leg(
		canvas: CanvasItem, feet: Vector2, hip_y: float, v: Vector2, side: Vector2,
		lr: int, step: float, c: Colors) -> void:
	var spread := lr * CHAR_H * 0.075
	var foot := Vector2(feet.x + side.x * spread + v.x * step * 0.5, feet.y)
	var knee_y := lerpf(hip_y, foot.y, 0.55) + step * 0.15
	var hip_x := feet.x + side.x * spread * 0.85

	var leg_hw := CHAR_H * 0.042
	# Üst bacak
	_block(canvas,
		hip_x + leg_hw, hip_y,
		hip_x - leg_hw, knee_y,
		c.pants, c.pants_sh, c.line)
	# Alt bacak
	_block(canvas,
		hip_x + leg_hw * 0.9, knee_y,
		hip_x - leg_hw * 0.9, foot.y - 3.0,
		c.pants.lightened(0.04), c.pants_sh, c.line)
	# Ayakkabı
	_rect(canvas,
		Vector2(foot.x - CHAR_H * 0.055, foot.y - 4.0),
		Vector2(foot.x + CHAR_H * 0.055, foot.y + 2.0),
		c.shoes, c.line)

# ── Kol ───────────────────────────────────────────────────────────────────────

static func _draw_arm(
		canvas: CanvasItem, chest_y: float, neck_y: float, v: Vector2, side: Vector2,
		lr: int, swing: float, c: Colors) -> void:
	var sh_x := lr * CHAR_H * 0.14
	var sh_y := chest_y + 2.0
	var elbow := Vector2(sh_x + v.x * swing * 0.35, sh_y + CHAR_H * 0.10 + swing * 0.12)
	var hand := Vector2(elbow.x + v.x * swing * 0.15, elbow.y + CHAR_H * 0.09)

	var aw := CHAR_H * 0.038
	_block(canvas, sh_x + aw, sh_y, sh_x - aw, elbow.y, c.shirt, c.shirt_sh, c.line)
	_block(canvas, elbow.x + aw * 0.85, elbow.y, hand.x - aw * 0.7, hand.y, c.skin, c.skin_sh, c.line)

# ── Çizim yardımcıları ────────────────────────────────────────────────────────

static func _rect(canvas: CanvasItem, tl: Vector2, br: Vector2, fill: Color, edge: Color) -> void:
	canvas.draw_rect(Rect2(tl, br - tl), fill)
	canvas.draw_rect(Rect2(tl, br - tl), edge, false, 1.0)

static func _block(
		canvas: CanvasItem,
		r_x: float, r_y: float, l_x: float, b_y: float,
		fill: Color, shade: Color, edge: Color) -> void:
	var pts := PackedVector2Array([
		Vector2(l_x, r_y),
		Vector2(r_x, r_y),
		Vector2(r_x, b_y),
		Vector2(l_x, b_y),
	])
	canvas.draw_colored_polygon(pts, fill)
	# Sağ-alt gölge şeridi
	canvas.draw_line(Vector2(r_x, r_y), Vector2(r_x, b_y), shade, 2.0)
	canvas.draw_line(Vector2(l_x, b_y), Vector2(r_x, b_y), shade, 1.5)
	canvas.draw_polyline(pts + PackedVector2Array([pts[0]]), edge, 1.0)
