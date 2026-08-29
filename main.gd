extends Node3D

@onready var player: CharacterBody3D = $Player


func _ready() -> void:
	move_player_to_spawn()


func move_player_to_spawn() -> void:
	var spawn := get_tree().get_first_node_in_group("player_spawn") as Node3D
	if spawn == null:
		push_warning("main.gd: no node in group 'player_spawn'; falling back to the position set in main.tscn.")
		return
	player.velocity = Vector3.ZERO
	player.global_position = spawn.global_position
	player.rotation.y = spawn.global_rotation.y
