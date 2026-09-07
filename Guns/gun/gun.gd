class_name Gun
extends Node3D

signal ammo_changed(count: int, capacity: int)
signal magazine_changed(mag: Magazine)
signal fire_mode_changed(mode: FireMode)
signal hopup_changed(value: float, min_value: float, max_value: float)
signal fired(speed: float, mass_kg: float)
signal fire_failed(reason: FireBlock, message: String)
signal magazine_rejected(offered: Magazine, message: String)
signal mode_refused(message: String)
signal reload_started(duration: float)
signal reload_finished(mag: Magazine)
signal reload_cancelled
signal reload_failed(message: String)

enum FireMode { SEMI, AUTO }
enum FireBlock { NONE, NO_MAGAZINE, EMPTY, COOLDOWN, RELOADING }
enum Action { AEG, GAS_BLOWBACK, PUMP, BOLT }

const BB_SCENE := preload("res://Guns/bb/bb.tscn")
const DEFAULT_BB_MASS := 0.0002
const AIM_MASK := 0b1001

const TRAIL_COLORS := [
	Color(1.0, 0.85, 0.3),
	Color(0.4, 0.9, 1.0),
	Color(1.0, 0.45, 0.65),
]

@export_group("Identity")
@export var weapon_model: String = "KESTREL"
@export var accepted_mag: Ordnance.MagType = Ordnance.MagType.Rifle
@export var action: Action = Action.AEG

@export_group("Spring")
@export_range(10.0, 2000.0, 1.0, "or_greater") var spring_constant: float = 300.0
@export_range(0.01, 0.30, 0.001, "or_greater") var spring_compression: float = 0.1

@export_group("Motor")
@export_range(100.0, 30000.0, 10.0, "or_greater") var motor_rpm: float = 8100.0
@export_range(1, 200, 1, "or_greater") var rotations_per_shot: int = 30

@export_group("Shot")
## bbs released per unit of ammunition.
@export_range(1, 12) var pellets: int = 1
## half angle of the cone the pellets leave in.
@export_range(0.0, 15.0, 0.1) var spread_deg: float = 0.0
## a pump or a gas slide cannot hold the trigger down for continuous fire.
@export var allow_auto := true

@export_group("Hop-up")
@export_range(0.0, 0.002, 0.00001, "or_greater") var hopup: float = 0.0002
@export_range(0.0, 0.002, 0.00001, "or_greater") var hopup_min: float = 0.0
@export_range(0.0, 0.002, 0.00001, "or_greater") var hopup_max: float = 0.0006
@export_range(0.000001, 0.0005, 0.000001, "or_greater") var hopup_step: float = 0.00003

@export_group("Loadout")
@export var magazine: Magazine
@export var fire_mode: FireMode = FireMode.SEMI

@export_group("Aim")
## the fov the camera narrows to for THIS weapon while aiming, or 0 to use the scope's own.
@export_range(0.0, 90.0, 0.5) var aim_fov := 0.0
## off for a weapon that is only ever aimed through its scope: no crosshair at the hip.
@export var hip_reticle := true
## the muzzle sits right of and below the eye, so firing straight down the barrel never crosses the crosshair.
@export var converge_on_crosshair := true
@export var max_aim_distance := 300.0
@export var min_aim_distance := 2.0

@export_group("Muzzle")
## off by default, an aeg vents its air down the barrel and shows nothing.
@export var muzzle_fx := false
@export var muzzle_fx_scale := 1.0
@export var muzzle_fx_intensity := 0.4
## how far the REPORT carries.
@export var muzzle_hearing := 6.0

@export_group("Reload")
## the weapon is out of frame for this long, then the fullest spare of its type goes in and the old magazine is gone, ro...
@export var reload_time := 2.2

@export_group("Sound")
## the pump rack or the slide coming back, a moment after the shot.
@export var cycle_delay := 0.25

@export_group("Debug")
@export var slow_motion: float = 1.0
@export var log_shots: bool = true

@onready var muzzle: Marker3D = $Muzzle
## the weapon's sounds are events in the Sfx table, named by this prefix: <prefix>_fire, _dry, _cycle, _mag_out, _mag_in.
@export var sfx_prefix := &"kestrel"
var _dry_at := 0.0

var _shot := 0
var _clock := 0.0
var _next_shot_at := 0.0
var _reload_until := -1.0
var _reload_began := 0.0


func owning_player() -> Player:
	var node := get_parent()
	while node != null:
		var who := node as Player
		if who != null:
			return who
		node = node.get_parent()
	return null


func _ready() -> void:
	## the rack decides which weapon is in the group; a weapon on its own joins by itself.
	if not (get_parent() is WeaponRack):
		add_to_group("weapon")
	Engine.time_scale = slow_motion
	hopup = clampf(hopup, hopup_min, hopup_max)
	if not allow_auto:
		fire_mode = FireMode.SEMI
	if magazine != null:
		magazine = magazine.duplicate()
		if not magazine.is_plausible():
			push_warning("%s: magazine mass is %.5f kg (%.1f g). This field is in KILOGRAMS - 0.20 g is 0.0002."
				% [weapon_model, magazine.bb_mass_kg, magazine.mass_grams()])
	print_config()


func muzzle_energy() -> float:
	return 0.5 * spring_constant * spring_compression * spring_compression


func pellet_energy() -> float:
	return muzzle_energy() / float(maxi(1, pellets))


func shots_per_second() -> float:
	return motor_rpm / (60.0 * float(maxi(1, rotations_per_shot)))


func shot_interval() -> float:
	return 1.0 / maxf(shots_per_second(), 0.0001)


func muzzle_speed(bb_mass_kg: float) -> float:
	if bb_mass_kg <= 0.0:
		return 0.0
	return sqrt(2.0 * pellet_energy() / bb_mass_kg)


func equipped_mass() -> float:
	return magazine.bb_mass_kg if magazine != null else DEFAULT_BB_MASS


func ammo_count() -> int:
	return magazine.count if magazine != null else 0


func ammo_capacity() -> int:
	return magazine.capacity if magazine != null else 0


func fire_mode_label() -> String:
	return "AUTO" if fire_mode == FireMode.AUTO else "SEMI"


func action_label() -> String:
	match action:
		Action.GAS_BLOWBACK:
			return "gas blowback"
		Action.PUMP:
			return "pump action"
		Action.BOLT:
			return "bolt action"
	return "aeg"


func accepts(mag: Magazine) -> bool:
	return mag != null and mag.mag_type == accepted_mag


func equip_magazine(mag: Magazine) -> bool:
	if mag == null:
		return false

	if not accepts(mag):
		var message := "%s magazine required - this one is %s" % [
			Ordnance.type_name(accepted_mag), Ordnance.type_name(mag.mag_type)]
		var rack := get_parent() as WeaponRack
		if rack != null:
			var taker := rack.weapon_for(mag.mag_type)
			if taker != null:
				message += ". Switch to the %s" % taker.weapon_model
		magazine_rejected.emit(mag, message)
		if log_shots:
			print("Rejected: %s" % message)
		return false

	magazine = mag.duplicate()
	Sfx.play_2d(sfx_prefix + "_mag_in")
	magazine_changed.emit(magazine)
	ammo_changed.emit(magazine.count, magazine.capacity)
	if log_shots:
		print("Equipped: %s" % magazine.describe())
	return true


func block_message(reason: FireBlock) -> String:
	match reason:
		FireBlock.NO_MAGAZINE:
			return "No magazine"
		FireBlock.EMPTY:
			return "Magazine empty"
		FireBlock.COOLDOWN:
			return "Cycling"
		FireBlock.RELOADING:
			return "Reloading"
	return ""


func emit_state() -> void:
	magazine_changed.emit(magazine)
	ammo_changed.emit(ammo_count(), ammo_capacity())
	fire_mode_changed.emit(fire_mode)
	hopup_changed.emit(hopup, hopup_min, hopup_max)


func _physics_process(delta: float) -> void:
	_clock += delta
	if is_reloading() and _clock >= _reload_until:
		_finish_reload()
	if fire_mode == FireMode.AUTO and is_ready() and not is_reloading() and Input.is_action_pressed("fire"):
		try_fire()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reload"):
		start_reload()
		return

	if event.is_action_pressed("toggle_fire_mode"):
		toggle_fire_mode()
		return

	if event.is_action_pressed("fire") and fire_mode == FireMode.SEMI:
		try_fire()
		return

	if event is InputEventMouseButton and event.is_pressed():
		var optic := get_tree().get_first_node_in_group("aim_scope") as AimScope
		if optic != null and optic.has_optic():
			return
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
	if not allow_auto:
		var message := "%s is %s: semi only" % [weapon_model, action_label()]
		mode_refused.emit(message)
		Sfx.play_2d(&"fire_refused")
		if log_shots:
			print("Refused: %s" % message)
		return
	fire_mode = FireMode.SEMI if fire_mode == FireMode.AUTO else FireMode.AUTO
	fire_mode_changed.emit(fire_mode)
	Sfx.play_2d(&"fire_select")
	if log_shots:
		print("Fire mode: %s | %.2f BB/s | interval %.4f s"
			% [fire_mode_label(), shots_per_second(), shot_interval()])


func try_fire() -> bool:
	if is_reloading():
		_reject(FireBlock.RELOADING)
		return false

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
	_spawn_shot(magazine.bb_mass_kg)
	Sfx.play_2d(sfx_prefix + "_fire")
	if Sfx.has(sfx_prefix + "_cycle"):
		get_tree().create_timer(cycle_delay).timeout.connect(func() -> void: Sfx.play_2d(sfx_prefix + "_cycle"))
	ammo_changed.emit(magazine.count, magazine.capacity)
	return true


func is_reloading() -> bool:
	return _reload_until >= 0.0


func reload_fraction() -> float:
	if not is_reloading():
		return 0.0
	var span := maxf(_reload_until - _reload_began, 0.001)
	return clampf((_clock - _reload_began) / span, 0.0, 1.0)


func _pouch() -> MagazinePouch:
	return get_tree().get_first_node_in_group("pouch") as MagazinePouch


func start_reload() -> bool:
	if is_reloading():
		return false
	var pouch := _pouch()
	if pouch == null or pouch.count(accepted_mag) == 0:
		var message := "No spare %s magazines" % Ordnance.type_name(accepted_mag)
		reload_failed.emit(message)
		if log_shots:
			print("Reload refused: %s" % message)
		return false
	_reload_began = _clock
	_reload_until = _clock + reload_time
	reload_started.emit(reload_time)
	Sfx.play_2d(sfx_prefix + "_mag_out")
	if log_shots:
		print("Reloading %s, %.1f s" % [weapon_model, reload_time])
	return true


func cancel_reload() -> void:
	if not is_reloading():
		return
	_reload_until = -1.0
	reload_cancelled.emit()


func _finish_reload() -> void:
	_reload_until = -1.0
	var pouch := _pouch()
	var fresh: Magazine = pouch.take(accepted_mag) if pouch != null else null
	if fresh == null:
		reload_cancelled.emit()
		return
	if log_shots and magazine != null and magazine.count > 0:
		print("Discarded %s with %d left" % [magazine.type_label(), magazine.count])
	magazine = fresh
	Sfx.play_2d(sfx_prefix + "_mag_in")
	reload_finished.emit(magazine)
	magazine_changed.emit(magazine)
	ammo_changed.emit(magazine.count, magazine.capacity)
	if log_shots:
		print("Loaded: %s" % magazine.describe())


func reset_cadence() -> void:
	_next_shot_at = _clock


func _reject(reason: FireBlock) -> void:
	var message := block_message(reason)
	fire_failed.emit(reason, message)
	if (reason == FireBlock.EMPTY or reason == FireBlock.NO_MAGAZINE) and _clock >= _dry_at:
		_dry_at = _clock + 0.25
		Sfx.play_2d(sfx_prefix + "_dry")
	if log_shots and reason != FireBlock.COOLDOWN:
		print("Blocked: %s" % message)


func _spawn_shot(mass_kg: float) -> void:
	var speed := muzzle_speed(mass_kg)
	var dir := aim_direction()
	_shot += 1

	var shots := PackedVector3Array()
	for i in maxi(1, pellets):
		shots.append(_scatter(dir) * speed)
	_lay_shot(muzzle.global_transform, shots, mass_kg, hopup, true)
	if Net.is_online():
		_net_shot.rpc(muzzle.global_transform, shots, mass_kg, hopup)
	_report_heard(muzzle.global_position)

	fired.emit(speed, mass_kg)

	if log_shots:
		print("Shot %d | %d x %.2f m/s | %.1f fps | %.2f g | hop-up %.5f | ammo %d/%d"
			% [_shot, pellets, speed, speed * 3.28084, mass_kg * 1000.0, hopup,
			   magazine.count, magazine.capacity])


func _report_heard(at: Vector3) -> void:
	if muzzle_hearing <= 0.0:
		return
	if multiplayer.is_server():
		_heard_shot(at, muzzle_hearing)
	else:
		_heard_shot.rpc_id(1, at, muzzle_hearing)


@rpc("any_peer", "call_remote", "reliable")
func _heard_shot(at: Vector3, radius: float) -> void:
	if not multiplayer.is_server():
		return
	for node in get_tree().get_nodes_in_group("kiwi"):
		var listener := node as Kiwi
		if listener != null:
			listener.hear(at, radius)


@rpc("any_peer", "call_remote", "unreliable")
func _net_shot(from: Transform3D, shots: PackedVector3Array, mass_kg: float, spin: float) -> void:
	_lay_shot(from, shots, mass_kg, spin, false)


func _lay_shot(from: Transform3D, shots: PackedVector3Array, mass_kg: float, spin: float,
		mine: bool) -> void:
	var world := get_tree().current_scene
	if world == null:
		return
	for i in shots.size():
		var bb: BB = BB_SCENE.instantiate()
		bb.bb_mass = mass_kg
		bb.BackspinDrag = spin
		bb.mine = mine
		bb.trail_color = TRAIL_COLORS[(_shot + i) % TRAIL_COLORS.size()]
		world.add_child(bb)
		bb.global_transform = from
		bb.linear_velocity = shots[i]
	if muzzle_fx:
		MuzzleFlashFx.spawn(world, from.origin, -from.basis.z,
			MuzzleFlashFx.GAS_COLOR, muzzle_fx_scale, muzzle_fx_intensity)
	if not mine:
		Sfx.play(sfx_prefix + "_fire", from.origin, 0.0, 1.0, true)


func _scatter(dir: Vector3) -> Vector3:
	if spread_deg <= 0.0 or pellets <= 1:
		return dir
	var cone := deg_to_rad(spread_deg)
	var theta := acos(lerpf(1.0, cos(cone), randf()))
	var phi := randf() * TAU
	var side := dir.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = dir.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(dir).normalized()
	return (dir * cos(theta) + (side * cos(phi) + up * sin(phi)) * sin(theta)).normalized()


func aim_direction() -> Vector3:
	var barrel := -muzzle.global_transform.basis.z.normalized()
	if not converge_on_crosshair:
		return barrel

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return barrel

	var from := cam.global_position
	var forward := -cam.global_transform.basis.z.normalized()
	var to := from + forward * max_aim_distance

	var query := PhysicsRayQueryParameters3D.create(from, to, AIM_MASK)
	query.collide_with_areas = false
	var body := owning_player()
	if body != null:
		query.exclude = [body.get_rid()]

	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var point: Vector3 = hit.position if not hit.is_empty() else to

	## anything nearer than the eye-to-muzzle offset would aim the barrel back at ourselves.
	if from.distance_to(point) < min_aim_distance:
		point = from + forward * min_aim_distance

	return (point - muzzle.global_position).normalized()


func print_config() -> void:
	var mass := equipped_mass()
	print("--- %s (%s) ---" % [weapon_model, action_label()])
	print("  accepts    : %s" % Ordnance.type_name(accepted_mag))
	print("  magazine   : %s" % (magazine.describe() if magazine != null else "<none>"))
	print("  spring     : k=%.1f N/m  x=%.3f m" % [spring_constant, spring_compression])
	if pellets > 1:
		print("  energy     : %.3f J per shell, %d pellets, %.3f J each" % [muzzle_energy(), pellets, pellet_energy()])
	else:
		print("  energy     : %.3f J" % muzzle_energy())
	print("  ROF        : %.2f BB/s  (%.0f RPM / %d rot per shot)  interval %.4f s"
		% [shots_per_second(), motor_rpm, rotations_per_shot, shot_interval()])
	print("  muzzle vel : %.2f m/s  (%.1f fps)  at %.2f g"
		% [muzzle_speed(mass), muzzle_speed(mass) * 3.28084, mass * 1000.0])
	print("  fire mode  : %s%s   hop-up %.5f  [%.5f .. %.5f]"
		% [fire_mode_label(), "" if allow_auto else " (semi only)", hopup, hopup_min, hopup_max])
