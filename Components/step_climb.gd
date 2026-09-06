class_name StepClimb


const MAX_HEIGHT := 0.4
const LOOK_AHEAD := 0.35


static func try_step(body: CharacterBody3D, wish: Vector3, samples := 8) -> bool:
	if not body.is_on_floor():
		return false
	if body.velocity.y > 0.1:
		return false

	var flat := Vector3(wish.x, 0.0, wish.z)
	if flat.length_squared() < 0.01:
		return false

	var dir := flat.normalized()
	var here := body.global_transform
	var ahead := KinematicCollision3D.new()
	if not body.test_move(here, dir * LOOK_AHEAD, ahead):
		return false

	if ahead.get_normal().angle_to(Vector3.UP) <= body.floor_max_angle:
		return false

	for i in samples:
		var lift: float = MAX_HEIGHT * float(i + 1) / float(samples)
		if body.test_move(here, Vector3.UP * lift):
			return false
		var raised := here.translated(Vector3.UP * lift)
		if body.test_move(raised, dir * LOOK_AHEAD):
			continue

		var dest := raised.translated(dir * LOOK_AHEAD)
		var hit := KinematicCollision3D.new()
		if not body.test_move(dest, Vector3.DOWN * (lift + 0.1), hit):
			continue
		if hit.get_normal().angle_to(Vector3.UP) > body.floor_max_angle:
			continue

		## the 2 cm keeps the capsule off the boundary it just cleared; velocity is untouched so the caller's move_and_slide carries full speed.
		body.global_position += Vector3.UP * (lift + 0.02)
		body.apply_floor_snap()
		return true

	return false
