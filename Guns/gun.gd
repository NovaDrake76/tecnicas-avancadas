extends Node3D

const BB_SCENE := preload("res://Guns/bb.tscn")
const MUZZLE_ENERGY := 1.49

const TRAIL_COLORS := [
	Color(1.0, 0.85, 0.3),
	Color(0.4, 0.9, 1.0),
	Color(1.0, 0.45, 0.65),
]

@export var slow_motion: float = 0.1

@onready var muzzle: Marker3D = $Muzzle

var _shot := 0


func _ready() -> void:
	Engine.time_scale = slow_motion


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fire"):
		fire()


func fire() -> void:
	var bb: BB = BB_SCENE.instantiate()

	bb.trail_color = TRAIL_COLORS[_shot % TRAIL_COLORS.size()]
	_shot += 1

	get_tree().current_scene.add_child(bb)
	bb.global_transform = muzzle.global_transform

	var speed := sqrt(2.0 * MUZZLE_ENERGY / bb.mass)
	var dir := -muzzle.global_transform.basis.z.normalized()
	bb.linear_velocity = dir * speed

	print("Shot %d | %.2f m/s | %.1f fps | mass %.5f kg | BackspinDrag %.5f"
		% [_shot, speed, speed * 3.28084, bb.mass, bb.BackspinDrag])