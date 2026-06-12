extends Node2D

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	$TestMenu.place_block_requested.connect($BlockManager.start_placement)
