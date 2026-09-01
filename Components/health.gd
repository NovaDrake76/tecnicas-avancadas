class_name Health
extends Node

## generic health for any entity, attach as a child node and let something else call take_damage.

signal damaged(amount: float, current: float)
signal died
## fires on every change including heal and revive, this is the one a bar should listen to.
signal health_changed(current: float, max_health: float)

@export var max_health: float = 30.0

var current: float


func _ready() -> void:
	current = max_health


func take_damage(amount: float) -> void:
	if current <= 0.0:
		return
	current = maxf(current - amount, 0.0)
	health_changed.emit(current, max_health)
	damaged.emit(amount, current)
	if current <= 0.0:
		died.emit()


func is_alive() -> bool:
	return current > 0.0


## dead entities stay dead here, use revive for that.
func heal(amount: float) -> void:
	if current <= 0.0:
		return
	var previous := current
	current = minf(current + amount, max_health)
	if current != previous:
		health_changed.emit(current, max_health)


func revive() -> void:
	current = max_health
	health_changed.emit(current, max_health)
