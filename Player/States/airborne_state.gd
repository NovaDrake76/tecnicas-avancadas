extends State


func physics_update(delta: float) -> void:
	host.solve_and_move(delta, host.wish_dir(), host.current_max_speed(), host.wants_jump())
	if host.is_on_floor():
		sm.change_to(&"Grounded")
