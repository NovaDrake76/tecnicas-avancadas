class_name SniperKiwi
extends LaserKiwi

## the long-range answer. the airsoft gun makes range perfectly safe: a bb is silent and a plain kiwi
## twenty metres off cannot see you. this is what argues back, with a rule the player can see and
## beat. it is a laser kiwi configured for one job: it holds its post, it only ever takes the aimed
## shot, the charge is long and the beam is a snapshot that does not follow you. THE TELL is a thin
## sight line from its eyes to where the shot will land, for the whole charge, visible from anywhere
## in the level. THE COUNTER is already written: step out of the line, or break it, and the shot
## never comes. standing still in a sniper's line for two seconds is the one thing that gets you hit.
##
## the shot is ONE PROJECTILE, not a beam: a heavy slug that leaves when the charge completes, aimed
## at the locked point, fast enough that at 40 m you have under half a second after it leaves. the
## charge and the sight line are the window; the flight is a small second one.
##
## the laser numbers that make it a sniper live in sniper_kiwi.tscn, not here: attack_range 60,
## hunt_sight 70, charge_time 2.0, beam_track 0, hunt_speed 0, beam_chance 1. an inherited scene that
## swaps the script keeps the parent instance's property values over anything _init sets, so values
## written in code here were silently overwritten by the laser kiwi's, and the scene is where they
## are tuned. it is still a kiwi: the same plate, the same eyes to aim for.

@export var sight_line_radius := 0.008
@export var slug_speed := 95.0
@export var slug_damage := 30.0
@export var slug_thickness := 2.6
## the aim FOLLOWS you through the charge and locks this long before the shot, so the sight line on
## your chest says "it is on me" and the last moment is the one that decides it. locking at the START
## of the charge instead made the whole two seconds free, which is a warning you can ignore.
@export var aim_lock_before := 0.3
var _lock_told := false

var _sight: MeshInstance3D


func _ready() -> void:
	super()
	var parts := LaserEyes.dart_parts()
	_sight = parts[1]
	_sight.top_level = true
	_sight.visible = false
	add_child(_sight)
	add_to_group("sniper")


func _physics_process(delta: float) -> void:
	super(delta)
	## the sight line lives exactly as long as the charge, on the locked aim, so what it shows is
	## where the shot will actually land and not where the bird is looking.
	var lit := _state == State.ATTACK and _attack == Attack.CHARGE and not _suppressing
	if lit:
		LaserEyes.stretch(_sight, eyes.between_eyes(), _aim, sight_line_radius)
	_sight.visible = lit


## tracking until the lock: while it can see you, the aim is where you are. a suppressing charge is
## aimed at a spot and never tracks.
func _aim_during_charge(at: Vector3) -> void:
	if _attack_timer > aim_lock_before:
		_lock_told = false
		if not _suppressing and _seen:
			_aim = at
	elif not _lock_told and not _suppressing:
		## the lock is audible: from here the shot is coming to THIS spot, and the sound is the cue to leave it
		_lock_told = true
		Sfx.play(&"sniper_lock", eyes.between_eyes())


func aim_locked() -> bool:
	return _attack == Attack.CHARGE and _attack_timer <= aim_lock_before


## the charge is done: one slug at the locked aim, then the recovery. a suppressing charge fires the
## same slug at the spot it was lighting up.
func _fire_charged() -> void:
	Sfx.play(&"laser_slug", eyes.between_eyes())
	eyes.set_glow(0.0)
	var bolt := LaserBolt.launch(get_parent(), eyes.between_eyes(), _aim, slug_speed, laser_range,
		slug_damage, self, eyes)
	bolt.thickness = slug_thickness
	bolt.tail = 3.0
	_attack = Attack.RECOVER
	_attack_timer = beam_recover


## the aimed shot or nothing. a sniper waiting on its beam waits; it does not fall back to a burst.
func _choose_attack() -> void:
	if _beam_ready <= 0.0:
		_start_charge()
	else:
		_attack = Attack.NONE
		_attack_timer = 0.3


func sight_line_visible() -> bool:
	return _sight != null and _sight.visible


func _go_down() -> void:
	if _sight != null:
		_sight.visible = false
	super()
