extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	await get_tree().process_frame
	#gl.player.global_position = $Player_spawn.global_position


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
