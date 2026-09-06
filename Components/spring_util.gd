class_name SpringUtil


static func apply(value: float, velocity: float, target: float, stiffness: float, damping: float, delta: float) -> Vector2:
	velocity += (target - value) * stiffness * delta
	velocity *= 1.0 - damping * delta
	value += velocity * delta
	return Vector2(value, velocity)
