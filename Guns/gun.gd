class_name Gun
extends Node3D

signal ammo_changed(count: int, capacity: int)
signal magazine_changed(mag: Magazine)
signal fire_mode_changed(mode: FireMode)
signal hopup_changed(value: float, min_value: float, max_value: float)
signal fired(speed: float, mass_kg: float)
signal fire_failed(reason: FireBlock, message: String)

enum FireMode { SEMI, AUTO }
enum FireBlock { NONE, NO_MAGAZINE, EMPTY, COOLDOWN }

const BB_SCENE := preload("res://Guns/bb.tscn")
const DEFAULT_BB_MASS := 0.0002

const TRAIL_COLORS := [
	Color(1.0, 0.85, 0.3),
	Color(0.4, 0.9, 1.0),
	Color(1.0, 0.45, 0.65),
]

@export_group("Identity")
@export var weapon_model: String = "KE-1"
@export var accepted_mag: Ordnance.MagType = Ordnance.MagType.Rifle

@export_group("Spring")
@export_range(10.0, 2000.0, 1.0, "or_greater") var spring_constant: float = 300.0
@export_range(0.01, 0.30, 0.001, "or_greater") var spring_compression: float = 0.1

@export_group("Motor")
@export_range(100.0, 30000.0, 10.0, "or_greater") var motor_rpm: float = 8100.0
@export_range(1, 200, 1, "or_greater") var rotations_per_shot: int = 30

@export_group("Hop-up")
@export_range(0.0, 0.002, 0.00001, "or_greater") var hopup: float = 0.0002
@export_range(0.0, 0.002, 0.00001, "or_greater") var hopup_min: float = 0.0
@export_range(0.0, 0.002, 0.00001, "or_greater") var hopup_max: float = 0.0006
@export_range(0.000001, 0.0005, 0.000001, "or_greater") var hopup_step: float = 0.00003

@export_group("Loadout")
@export var magazine: Magazine
@export var fire_mode: FireMode = FireMode.SEMI

@export_group("Debug")
@export var slow_motion: float = 1.0
@export var log_shots: bool = true

@onready var muzzle: Marker3D = $Muzzle

var _shot := 0
var _clock := 0.0
var _next_shot_at := 0.0


func _ready() -> void:
	add_to_group("weapon")
	Engine.time_scale = slow_motion
	hopup = clampf(hopup, hopup_min, hopup_max)
	if magazine != null:
		magazine = magazine.duplicate()
		if not magazine.is_plausible():
			push_warning("%s: magazine mass is %.5f kg (%.1f g). This field is in KILOGRAMS - 0.20 g is 0.0002."
				% [weapon_model, magazine.bb_mass_kg, magazine.mass_grams()])
	print_config()


func muzzle_energy() -> float:
	return 0.5 * spring_constant * spring_compression * spring_compression


func shots_per_second() -> float:
	return motor_rpm / (60.0 * float(maxi(1, rotations_per_shot)))


func shot_interval() -> float:
	return 1.0 / maxf(shots_per_second(), 0.0001)


func muzzle_speed(bb_mass_kg: float) -> float:
	if bb_mass_kg <= 0.0:
		return 0.0
	return sqrt(2.0 * muzzle_energy() / bb_mass_kg)


func equipped_mass() -> float:
	return magazine.bb_mass_kg if magazine != null else DEFAULT_BB_MASS


func ammo_count() -> int:
	return magazine.count if magazine != null else 0


func ammo_capacity() -> int:
	return magazine.capacity if magazine != null else 0


func fire_mode_label() -> String:
	return "AUTO" if fire_mode == FireMode.AUTO else "SEMI"


func accepts(mag: Magazine) -> bool:
	return mag != null and mag.mag_type == accepted_mag


func block_message(reason: FireBlock) -> String:
	match reason:
		FireBlock.NO_MAGAZINE:
			return "No magazine"
		FireBlock.EMPTY:
			return "Magazine empty"
		FireBlock.COOLDOWN:
			return "Cycling"
	return ""


func emit_state() -> void:
	magazine_changed.emit(magazine)
	ammo_changed.emit(ammo_count(), ammo_capacity())
	fire_mode_changed.emit(fire_mode)
	hopup_changed.emit(hopup, hopup_min, hopup_max)


func _physics_process(delta: float) -> void:
	_clock += delta
	if fire_mode == FireMode.AUTO and is_ready() and Input.is_action_pressed("fire"):
		try_fire()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fire_mode"):
		toggle_fire_mode()
		return

	if event.is_action_pressed("fire") and fire_mode == FireMode.SEMI:
		try_fire()
		return

	if event is InputEventMouseButton and event.is_pressed():
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			adjust_hopup(1)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			adjust_hopup(-1)


func adjust_hopup(steps: int) -> void:
	var before := hopup
	hopup = clampf(hopup + float(steps) * hopup_step, hopup_min, hopup_max)
	if not is_equal_approx(hopup, before):
		hopup_changed.emit(hopup, hopup_min, hopup_max)


func hopup_percent() -> float:
	var span := hopup_max - hopup_min
	if span <= 0.0:
		return 0.0
	return (hopup - hopup_min) / span * 100.0


func is_ready() -> bool:
	return _clock >= _next_shot_at


func time_until_ready() -> float:
	return maxf(0.0, _next_shot_at - _clock)


func toggle_fire_mode() -> void:
	fire_mode = FireMode.SEMI if fire_mode == FireMode.AUTO else FireMode.AUTO
	fire_mode_changed.emit(fire_mode)
	if log_shots:
		print("Fire mode: %s | %.2f BB/s | interval %.4f s"
			% [fire_mode_label(), shots_per_second(), shot_interval()])


func try_fire() -> bool:
	if not is_ready():
		_reject(FireBlock.COOLDOWN)
		return false

	if magazine == null:
		_reject(FireBlock.NO_MAGAZINE)
		return false

	if not magazine.consume():
		_reject(FireBlock.EMPTY)
		return false

	_next_shot_at = maxf(_clock, _next_shot_at) + shot_interval()
	_spawn_bb(magazine.bb_mass_kg)
	ammo_changed.emit(magazine.count, magazine.capacity)
	return true


func _reject(reason: FireBlock) -> void:
	var message := block_message(reason)
	fire_failed.emit(reason, message)
	if log_shots and reason != FireBlock.COOLDOWN:
		print("Blocked: %s" % message)


func _spawn_bb(mass_kg: float) -> void:
	var speed := muzzle_speed(mass_kg)

	var bb: BB = BB_SCENE.instantiate()
	bb.bb_mass = mass_kg
	bb.BackspinDrag = hopup
	bb.trail_color = TRAIL_COLORS[_shot % TRAIL_COLORS.size()]
	_shot += 1

	get_tree().current_scene.add_child(bb)
	bb.global_transform = muzzle.global_transform
	bb.linear_velocity = -muzzle.global_transform.basis.z.normalized() * speed

	fired.emit(speed, mass_kg)

	if log_shots:
		print("Shot %d | %.2f m/s | %.1f fps | %.2f g | hop-up %.5f | ammo %d/%d"
			% [_shot, speed, speed * 3.28084, mass_kg * 1000.0, hopup,
			   magazine.count, magazine.capacity])


func print_config() -> void:
	var mass := equipped_mass()
	print("--- %s ---" % weapon_model)
	print("  accepts    : %s" % Ordnance.type_name(accepted_mag))
	print("  magazine   : %s" % (magazine.describe() if magazine != null else "<none>"))
	print("  spring     : k=%.1f N/m  x=%.3f m" % [spring_constant, spring_compression])
	print("  energy     : %.3f J" % muzzle_energy())
	print("  ROF        : %.2f BB/s  (%.0f RPM / %d rot per shot)  interval %.4f s"
		% [shots_per_second(), motor_rpm, rotations_per_shot, shot_interval()])
	print("  muzzle vel : %.2f m/s  (%.1f fps)  at %.2f g"
		% [muzzle_speed(mass), muzzle_speed(mass) * 3.28084, mass * 1000.0])
	print("  fire mode  : %s   hop-up %.5f  [%.5f .. %.5f]"
		% [fire_mode_label(), hopup, hopup_min, hopup_max])
