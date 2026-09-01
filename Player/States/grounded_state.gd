extends State

## grounded locomotion, runs the shared solver with friction unless jumping.
## leaves for Airborne the moment we are off the floor, including the jump we just made.

func physics_update(delta: float) -> void:
	host.solve_and_move(delta, host.wish_dir(), host.current_max_speed(), host.wants_jump())
	if not host.is_on_floor():
		sm.change_to(&"Airborne")
