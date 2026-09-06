class_name MovementConfig
extends Resource

## source-style movement tuning as a resource.
## swap a .tres preset to change feel without touching code.

@export var gravity := 20.32
@export var ground_max_speed := 6.35
@export var ground_accelerate := 5.5
@export var friction := 5.2
@export var stop_speed := 2.54
## high air acceleration is forgiving bhop, source uses about 12.
@export var air_accelerate := 100.0
## the 30 unit air speed cap, do not scale this with the rest.
@export var air_speed_cap := 0.762
@export var jump_impulse := 6.5
@export var run_max_speed := 9.0
@export var crouch_max_speed := 3.2
## a crawl. it is meant to cost something -- prone buys the last stretch of open ground and pays
## for it in time -- but 1.2 was a punishment rather than a price: Nathan played it and it read as
## being stuck. 2.0 is still well under a crouch's 3.2 and under a third of a walk.
@export var prone_max_speed := 2.0
## false keeps manual jump timing, true auto hops while held.
@export var auto_bhop := false
@export var jump_buffer_time := 0.1
