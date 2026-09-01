class_name KillPlane
extends Area3D

## void safety net placed far below the world.
## the player is respawned, anything else that falls out is freed so it stops eating physics.

func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		if body.has_method("respawn_from_void"):
			body.respawn_from_void()
	elif body is RigidBody3D:
		body.queue_free()
