extends State

## airborne locomotion, the solver's air branch with strafing and no friction.
## on landing it hands back to Grounded, where a still buffered jump auto hops next tick.

func physics_update(delta: float) -> void:
	host.solve_and_move(delta, host.wish_dir(), host.current_max_speed(), host.wants_jump())
	if host.is_on_floor():
		sm.change_to(&"Grounded")
