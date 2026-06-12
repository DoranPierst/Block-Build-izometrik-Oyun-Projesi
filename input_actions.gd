## input_actions.gd  (Autoload: "InputActions")
## Yeniden atanabilir tuş bağlamalarını yönetir.
## Tüm scriptler Input.is_key_pressed(KEY_*) yerine bu autoload'u kullanır.
extends Node

## action_name → { label, desc, key }
const ACTIONS: Dictionary = {
	"block_move": {
		"label": "Blok Taşı",
		"desc":  "Tuşu basılı tut, bloğa sol tıkla ve sürükle — bırakınca yerleşir.",
		"key":   KEY_ALT,
	},
	"block_remove": {
		"label": "Blok Kaldır",
		"desc":  "Tuşu basılı tutarken bloğa sol tıkla — blok silinir.",
		"key":   KEY_CTRL,
	},
	"block_rotate": {
		"label": "Blok Döndür",
		"desc":  "Tuşu basılı tutarken bloğa sol tıkla — blok 90° döner.",
		"key":   KEY_SHIFT,
	},
	"block_cancel": {
		"label": "İptal / Kapat",
		"desc":  "Yerleştirme veya taşıma modundan çık, açık menüyü kapat.",
		"key":   KEY_ESCAPE,
	},
	"camera_zoom": {
		"label": "Kamera Zoom",
		"desc":  "Tuşu basılı tutarken fare tekerleğini çevir — yakınlaş / uzaklaş.",
		"key":   KEY_CTRL,
	},
}

func _ready() -> void:
	for action_name in ACTIONS:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		else:
			InputMap.action_erase_events(action_name)
		var ev := InputEventKey.new()
		ev.keycode = ACTIONS[action_name]["key"]
		InputMap.action_add_event(action_name, ev)

## Bir eyleme atanmış ilk tuşun keycode'unu döndürür.
func get_key(action_name: String) -> Key:
	for ev in InputMap.action_get_events(action_name):
		if ev is InputEventKey:
			return ev.keycode as Key
	return KEY_NONE

## Bir eylemi yeni tuşa atar.
func set_key(action_name: String, keycode: Key) -> void:
	InputMap.action_erase_events(action_name)
	var ev := InputEventKey.new()
	ev.keycode = keycode
	InputMap.action_add_event(action_name, ev)

## Modifier tuşu şu an basılı mı? (ALT/CTRL/SHIFT gibi physical key için)
func is_pressed(action_name: String) -> bool:
	return Input.is_action_pressed(action_name)
