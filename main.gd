extends Node3D

@onready var player: CharacterBody3D = $Player


func _ready() -> void:
	move_player_to_spawn()


## the lookup lives on the player so KillPlane and this share one implementation.
func move_player_to_spawn() -> void:
	if player != null and player.has_method("respawn_from_void"):
		player.respawn_from_void()
