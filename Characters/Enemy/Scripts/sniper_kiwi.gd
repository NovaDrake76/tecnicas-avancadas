class_name SniperKiwi
extends LaserKiwi


@export var sight_line_radius := 0.008
@export var slug_speed := 95.0
@export var slug_damage := 30.0
@export var slug_thickness := 2.6
## the aim FOLLOWS you through the charge and locks this long before the shot, so the sight line on your chest says "it...
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


func _armour_kind() -> KiwiArmour.Kind:
	return KiwiArmour.Kind.SNIPER


func _physics_process(delta: float) -> void:
	super(delta)
	var lit := _state == State.ATTACK and _attack == Attack.CHARGE and not _suppressing
	if lit:
		LaserEyes.stretch(_sight, eyes.between_eyes(), _aim, sight_line_radius)
	_sight.visible = lit


func _aim_during_charge(at: Vector3) -> void:
	if _attack_timer > aim_lock_before:
		_lock_told = false
		if not _suppressing and _seen:
			_aim = at
	elif not _lock_told and not _suppressing:
		_lock_told = true
		Sfx.play(&"sniper_lock", eyes.between_eyes())


func aim_locked() -> bool:
	return _attack == Attack.CHARGE and _attack_timer <= aim_lock_before


func _fire_charged() -> void:
	_net_slug.rpc(eyes.between_eyes(), _aim)
	_attack = Attack.RECOVER
	_attack_timer = beam_recover


@rpc("authority", "call_local", "reliable")
func _net_slug(from: Vector3, at: Vector3) -> void:
	Sfx.play(&"laser_slug", from)
	eyes.set_glow(0.0)
	var bolt := LaserBolt.launch(get_parent(), from, at, slug_speed, laser_range,
		slug_damage if multiplayer.is_server() else 0.0, self, eyes)
	bolt.thickness = slug_thickness
	bolt.tail = 3.0


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


func kind_name() -> String:
	return "SNIPER"
