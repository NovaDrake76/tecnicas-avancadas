extends Node


const POOL_3D := 32
const POOL_2D := 12
const DUCKED: Array[StringName] = [&"World", &"Kiwis", &"Ambience", &"Music", &"Player"]
const OPEN_CUTOFF := 5000.0
const OCCLUDED_CUTOFF := 700.0
const OCCLUDED_DB := -7.0
const OCCLUDE_EVERY := 0.15

const EVENTS := {
	&"kestrel_fire": {"2d": true, "bus": &"Weapons", "db": -4.0, "voices": 6, "layers": [
		{"clips": "weapons/kestrel_mech", "n": 3, "db": 0.0, "pitch": [0.95, 1.05]},
		{"clips": "weapons/kestrel_pop", "n": 4, "db": -1.0, "pitch": [0.96, 1.04], "delay": 0.008}]},
	&"kestrel_dry": {"2d": true, "bus": &"Weapons", "db": -8.0, "clips": "weapons/kestrel_dry", "n": 2},
	&"kestrel_mag_out": {"2d": true, "bus": &"Weapons", "db": -8.0, "clips": "weapons/rifle_mag_out", "n": 3},
	&"kestrel_mag_in": {"2d": true, "bus": &"Weapons", "db": -6.0, "clips": "weapons/rifle_mag_in", "n": 4},
	&"shrike_fire": {"2d": true, "bus": &"Weapons", "db": -3.0, "voices": 3, "clips": "weapons/shrike_thwack", "n": 3, "pitch": [0.97, 1.03]},
	&"shrike_cycle": {"2d": true, "bus": &"Weapons", "db": -7.0, "clips": "weapons/shrike_pump", "n": 4, "pitch": [0.96, 1.04]},
	&"shrike_dry": {"2d": true, "bus": &"Weapons", "db": -8.0, "clips": "weapons/shrike_dry", "n": 1},
	&"shrike_mag_out": {"2d": true, "bus": &"Weapons", "db": -12.0, "clips": "weapons/shrike_pump", "n": 4, "pitch": [0.84, 0.9]},
	&"shrike_mag_in": {"2d": true, "bus": &"Weapons", "db": -6.0, "clips": "weapons/shell_in", "n": 3},
	&"harrier_fire": {"2d": true, "bus": &"Weapons", "db": -5.0, "voices": 4, "layers": [
		{"clips": "weapons/pistol_pop", "n": 4, "db": 0.0, "pitch": [0.96, 1.03]},
		{"clips": "weapons/pistol_slide", "n": 2, "db": -9.0, "delay": 0.05}]},
	&"harrier_dry": {"2d": true, "bus": &"Weapons", "db": -8.0, "clips": "weapons/pistol_dry", "n": 1},
	&"harrier_mag_out": {"2d": true, "bus": &"Weapons", "db": -8.0, "clips": "weapons/pistol_mag_out", "n": 2},
	&"harrier_mag_in": {"2d": true, "bus": &"Weapons", "db": -6.0, "clips": "weapons/pistol_mag_in", "n": 2},
	&"merlin_fire": {"2d": true, "bus": &"Weapons", "db": -6.0, "voices": 8, "layers": [
		{"clips": "weapons/pistol_pop", "n": 4, "db": 0.0, "pitch": [1.05, 1.12]},
		{"clips": "weapons/merlin_slide", "n": 2, "db": -10.0, "pitch": [1.0, 1.08], "delay": 0.035}]},
	&"merlin_dry": {"2d": true, "bus": &"Weapons", "db": -8.0, "clips": "weapons/pistol_dry", "n": 1, "pitch": [1.05, 1.1]},
	&"merlin_mag_out": {"2d": true, "bus": &"Weapons", "db": -8.0, "clips": "weapons/pistol_mag_out", "n": 2},
	&"merlin_mag_in": {"2d": true, "bus": &"Weapons", "db": -6.0, "clips": "weapons/pistol_mag_in", "n": 2},
	&"osprey_fire": {"2d": true, "bus": &"Weapons", "db": -2.0, "voices": 2, "clips": "weapons/osprey_fire", "n": 3, "pitch": [0.98, 1.02]},
	&"osprey_cycle": {"2d": true, "bus": &"Weapons", "db": -8.0, "clips": "weapons/osprey_bolt", "n": 2, "pitch": [0.97, 1.03]},
	&"osprey_dry": {"2d": true, "bus": &"Weapons", "db": -8.0, "clips": "weapons/osprey_dry", "n": 1},
	&"osprey_mag_out": {"2d": true, "bus": &"Weapons", "db": -9.0, "clips": "weapons/rifle_mag_out", "n": 3, "pitch": [0.88, 0.94]},
	&"osprey_mag_in": {"2d": true, "bus": &"Weapons", "db": -6.0, "clips": "weapons/osprey_round_in", "n": 2},
	&"weapon_draw": {"2d": true, "bus": &"Weapons", "db": -10.0, "clips": "weapons/draw", "n": 2},
	&"fire_select": {"2d": true, "bus": &"Weapons", "db": -8.0, "clips": "weapons/select", "n": 2},
	&"fire_refused": {"2d": true, "bus": &"Weapons", "db": -10.0, "clips": "weapons/refused", "n": 1},
	&"ads": {"2d": true, "bus": &"Weapons", "silent": true},

	&"player_hurt": {"2d": true, "bus": &"Player", "db": -6.0, "voices": 2, "cooldown": 0.12, "clips": "player/hurt", "n": 4, "pitch": [0.94, 1.06]},
	&"player_down": {"2d": true, "bus": &"Player", "db": -2.0, "clips": "player/down", "n": 1},
	&"jump": {"2d": true, "bus": &"Player", "db": -14.0, "clips": "player/jump", "n": 2},
	&"crouch": {"2d": true, "bus": &"Player", "silent": true},
	&"land_hard": {"2d": true, "bus": &"Player", "db": -6.0, "clips": "player/land_hard", "n": 1},
	&"throw": {"2d": true, "bus": &"Player", "db": -10.0, "clips": "player/throw", "n": 1},
	&"takedown_swing": {"2d": true, "bus": &"Player", "db": -14.0, "clips": "player/takedown_swing", "n": 1},
	&"takedown": {"bus": &"Player", "db": -9.0, "unit": 3.0, "max": 24.0, "clips": "player/takedown", "n": 3, "pitch": [0.96, 1.04]},
	&"binocs_up": {"2d": true, "bus": &"Player", "db": -15.0, "clips": "player/binocs_up", "n": 1, "pitch": [0.98, 1.02]},
	&"binocs_down": {"2d": true, "bus": &"Player", "db": -16.0, "clips": "player/binocs_down", "n": 1, "pitch": [0.98, 1.02]},
	&"body_grab": {"2d": true, "bus": &"Player", "db": -16.0, "clips": "player/crouch", "n": 3, "pitch": [0.82, 0.9]},
	&"body_drop": {"bus": &"World", "db": -10.0, "unit": 6.0, "max": 40.0, "voices": 2, "clips": "impacts/bb_body", "n": 3, "pitch": [0.62, 0.7]},
	&"step_grass": {"2d": true, "bus": &"Player", "db": -25.0, "voices": 2, "clips": "player/step_grass", "n": 5, "pitch": [0.92, 1.1]},
	&"step_dirt": {"2d": true, "bus": &"Player", "db": -25.0, "voices": 2, "clips": "player/step_dirt", "n": 8, "pitch": [0.92, 1.1]},
	&"step_concrete": {"2d": true, "bus": &"Player", "db": -25.0, "voices": 2, "clips": "player/step_concrete", "n": 6, "pitch": [0.94, 1.08]},
	&"step_metal": {"2d": true, "bus": &"Player", "db": -23.0, "voices": 2, "clips": "player/step_metal", "n": 7, "pitch": [0.94, 1.08]},
	&"step_wood": {"2d": true, "bus": &"Player", "db": -24.0, "voices": 2, "clips": "player/step_wood", "n": 8, "pitch": [0.94, 1.08]},
	&"step_gravel": {"2d": true, "bus": &"Player", "db": -25.0, "voices": 2, "clips": "player/step_gravel", "n": 5, "pitch": [0.92, 1.1]},

	&"bb_metal": {"bus": &"World", "db": -12.0, "unit": 4.0, "max": 30.0, "voices": 3, "cooldown": 0.02, "clips": "impacts/bb_metal", "n": 4, "pitch": [0.95, 1.08]},
	&"bb_wood": {"bus": &"World", "db": -12.0, "unit": 4.0, "max": 30.0, "voices": 3, "cooldown": 0.02, "clips": "impacts/bb_wood", "n": 4, "pitch": [0.95, 1.08]},
	&"bb_concrete": {"bus": &"World", "db": -13.0, "unit": 4.0, "max": 30.0, "voices": 3, "cooldown": 0.02, "clips": "impacts/bb_concrete", "n": 3, "pitch": [0.95, 1.08]},
	&"bb_dirt": {"bus": &"World", "db": -16.0, "unit": 4.0, "max": 24.0, "voices": 3, "cooldown": 0.02, "clips": "impacts/bb_dirt", "n": 4, "pitch": [0.92, 1.06]},
	&"bb_body": {"bus": &"World", "db": -10.0, "unit": 5.0, "max": 36.0, "voices": 3, "cooldown": 0.02, "clips": "impacts/bb_body", "n": 3, "pitch": [0.95, 1.08]},
	&"bb_glass": {"bus": &"World", "db": -4.0, "unit": 8.0, "max": 60.0, "voices": 2, "clips": "impacts/bb_glass", "n": 5, "pitch": [0.97, 1.05]},
	&"bb_plate": {"bus": &"World", "db": -8.0, "unit": 8.0, "max": 60.0, "voices": 3, "cooldown": 0.03, "clips": "impacts/bb_plate", "n": 4, "pitch": [0.96, 1.1]},
	&"bb_dent": {"bus": &"World", "db": -6.0, "unit": 8.0, "max": 60.0, "voices": 3, "cooldown": 0.03, "clips": "impacts/bb_dent", "n": 3, "pitch": [0.96, 1.06]},
	&"plates_shed": {"bus": &"World", "db": -4.0, "unit": 8.0, "max": 60.0, "voices": 2, "clips": "impacts/plates_shed", "n": 2},
	&"target_hit": {"bus": &"World", "db": -6.0, "unit": 8.0, "max": 90.0, "voices": 3, "cooldown": 0.03, "clips": "impacts/target_hit", "n": 4, "pitch": [0.96, 1.06]},
	&"target_fall": {"bus": &"World", "db": -6.0, "unit": 8.0, "max": 90.0, "voices": 2, "clips": "impacts/target_fall", "n": 1},
	&"target_rise": {"bus": &"World", "db": -10.0, "unit": 8.0, "max": 90.0, "voices": 2, "clips": "impacts/target_rise", "n": 1},
	&"clank": {"bus": &"World", "db": -4.0, "unit": 10.0, "max": 60.0, "voices": 2, "clips": "impacts/clank", "n": 3, "pitch": [0.94, 1.08]},
	&"pickup": {"bus": &"World", "db": -8.0, "unit": 3.0, "max": 20.0, "clips": "ui/pickup", "n": 1},
	&"objective_start": {"2d": true, "bus": &"Player", "db": -14.0, "clips": "ui/tick", "n": 1},
	&"objective_done": {"2d": true, "bus": &"UI", "db": -8.0, "clips": "ui/objective", "n": 1},
	&"charge_set": {"bus": &"World", "db": -8.0, "unit": 6.0, "max": 40.0, "clips": "ui/install", "n": 1},

	&"kiwi_step": {"bus": &"Kiwis", "db": -18.0, "unit": 3.0, "max": 24.0, "voices": 6, "cooldown": 0.03, "clips": "kiwi/step", "n": 8, "pitch": [0.95, 1.1]},
	&"kiwi_poof": {"bus": &"Kiwis", "db": -6.0, "unit": 8.0, "max": 50.0, "voices": 3, "clips": "kiwi/poof", "n": 3, "pitch": [0.95, 1.08]},
	&"kiwi_blaster": {"bus": &"Kiwis", "db": -7.0, "unit": 6.0, "max": 70.0, "voices": 6, "cooldown": 0.03, "clips": "weapons/pistol_pop", "n": 4, "pitch": [1.18, 1.3]},
	&"kiwi_radio": {"bus": &"Kiwis", "db": -4.0, "unit": 10.0, "max": 60.0, "voices": 2, "clips": "kiwi/radio", "n": 2},

	&"laser_bolt": {"bus": &"Threat", "db": -2.0, "unit": 10.0, "max": 80.0, "voices": 6, "clips": "laser/bolt", "n": 4, "pitch": [0.94, 1.06]},
	&"laser_fizzle": {"bus": &"Threat", "db": -4.0, "unit": 10.0, "max": 70.0, "voices": 3, "clips": "laser/fizzle", "n": 1, "pitch": [0.95, 1.05]},
	&"laser_charge_110": {"bus": &"Threat", "db": -3.0, "unit": 12.0, "max": 80.0, "clips": "laser/charge_110", "n": 0},
	&"laser_charge_200": {"bus": &"Threat", "db": -3.0, "unit": 12.0, "max": 80.0, "clips": "laser/charge_200", "n": 0},
	&"laser_beam": {"bus": &"Threat", "db": -3.0, "unit": 12.0, "max": 80.0, "clips": "laser/beam_loop", "n": 0},
	&"laser_hit": {"bus": &"Threat", "db": -8.0, "unit": 6.0, "max": 40.0, "voices": 4, "cooldown": 0.03, "clips": "laser/hit", "n": 3, "pitch": [0.95, 1.08]},
	&"laser_slug": {"bus": &"Threat", "db": 0.0, "unit": 20.0, "max": 160.0, "voices": 2, "clips": "laser/slug", "n": 1, "pitch": [0.97, 1.03]},
	&"sniper_lock": {"bus": &"Threat", "db": -6.0, "unit": 30.0, "max": 120.0, "voices": 2, "clips": "laser/sniper_lock", "n": 1},
	&"mortar_fire": {"bus": &"Threat", "db": -2.0, "unit": 18.0, "max": 200.0, "voices": 3, "clips": "mortar/fire", "n": 4, "pitch": [0.95, 1.05]},
	&"mortar_blast": {"bus": &"Threat", "db": 2.0, "unit": 26.0, "max": 240.0, "voices": 3, "clips": "mortar/blast", "n": 5, "pitch": [0.95, 1.05],
		"far": {"from": 45.0, "layers": [{"clips": "mortar/blast_far", "n": 4, "db": -2.0, "pitch": [0.95, 1.05]}]}},
	&"frag_pin": {"2d": true, "bus": &"Player", "db": -10.0, "clips": "grenade/pin", "n": 2, "pitch": [0.97, 1.05]},
	&"frag_bounce": {"bus": &"World", "db": -10.0, "unit": 8.0, "max": 45.0, "voices": 3, "cooldown": 0.05, "clips": "grenade/bounce", "n": 3, "pitch": [0.9, 1.1]},
	&"frag_blast": {"bus": &"Threat", "db": 0.0, "unit": 20.0, "max": 200.0, "voices": 3, "clips": "grenade/blast", "n": 4, "pitch": [0.96, 1.05],
		"far": {"from": 40.0, "layers": [{"clips": "grenade/blast_far", "n": 2, "db": -2.0, "pitch": [0.95, 1.05]}]}},
	&"heli_rotor_near": {"bus": &"Threat", "db": 0.0, "unit": 40.0, "max": 160.0, "clips": "gunship/rotor_near_loop", "n": 0},
	&"heli_rotor_far": {"bus": &"Threat", "db": -2.0, "unit": 60.0, "max": 450.0, "clips": "gunship/rotor_far_loop", "n": 0},
	&"heli_gun": {"bus": &"Threat", "db": 0.0, "unit": 30.0, "max": 260.0, "clips": "gunship/gun_burst", "n": 1},
	&"heli_ping": {"bus": &"Threat", "db": -4.0, "unit": 14.0, "max": 120.0, "voices": 3, "clips": "gunship/ping", "n": 2, "pitch": [0.94, 1.06]},
	&"mark_tone": {"2d": true, "bus": &"UI", "db": -16.0, "clips": "gunship/mark_tone_loop", "n": 0},

	&"siren": {"bus": &"World", "db": -3.0, "unit": 14.0, "max": 140.0, "clips": "alarm/siren_loop", "n": 0},
	&"horn_lever": {"bus": &"World", "db": -6.0, "unit": 8.0, "max": 40.0, "clips": "alarm/horn_lever", "n": 1},
	&"horn_cut": {"bus": &"World", "db": -6.0, "unit": 8.0, "max": 40.0, "clips": "alarm/horn_cut", "n": 1},

	&"sting_notice": {"2d": true, "bus": &"Music", "db": 0.0, "voices": 1, "clips": "music/sting_notice", "n": 1},
	&"sting_alarm": {"2d": true, "bus": &"Music", "db": 0.0, "voices": 1, "clips": "music/sting_alarm", "n": 1},
	&"sting_clear": {"2d": true, "bus": &"Music", "db": 0.0, "voices": 1, "clips": "music/sting_clear", "n": 1},
	&"sting_mission_clear": {"2d": true, "bus": &"Music", "db": 4.0, "voices": 1, "clips": "music/sting_mission_clear", "n": 1},
	&"sting_mission_fail": {"2d": true, "bus": &"Music", "db": 0.0, "voices": 1, "clips": "music/sting_mission_fail", "n": 1},
	&"sting_reinforce": {"2d": true, "bus": &"Music", "db": 0.0, "voices": 1, "clips": "music/sting_reinforce", "n": 1},
}

var _clips := {}
var _last := {}
var _played := {}
var _cooldown := {}
var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _tag := {}
var _tracked: Array = []
var _rest := {}
var _gains := {}
var _duck := 0.0
var _duck_tween: Tween
var _occlude_timer := 0.0
var _last_pitch := 1.0
var _missing: Array[String] = []
var _last_started := PackedStringArray()


func _ready() -> void:
	for i in AudioServer.bus_count:
		_rest[AudioServer.get_bus_name(i)] = AudioServer.get_bus_volume_db(i)
	for event in EVENTS:
		for layer in layers_of(event):
			for path in clip_paths(layer):
				_load(path)
	for _i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.max_polyphony = 1
		p.finished.connect(_on_finished.bind(p))
		add_child(p)
		_pool3d.append(p)
	for _i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.max_polyphony = 1
		p.finished.connect(_on_finished.bind(p))
		add_child(p)
		_pool2d.append(p)


func _process(delta: float) -> void:
	for key in _cooldown.keys():
		_cooldown[key] = float(_cooldown[key]) - delta
		if float(_cooldown[key]) <= 0.0:
			_cooldown.erase(key)
	_occlude_timer -= delta
	if _occlude_timer <= 0.0:
		_occlude_timer = OCCLUDE_EVERY
		_update_tracked()


func has(event: StringName) -> bool:
	return EVENTS.has(event)


func is_silent(event: StringName) -> bool:
	return bool((EVENTS.get(event, {}) as Dictionary).get("silent", false))


func count(event: StringName) -> int:
	return int(_played.get(event, 0))


func last_pitch() -> float:
	return _last_pitch


func last_started() -> PackedStringArray:
	return _last_started


func active(event: StringName) -> int:
	var n := 0
	for p in _pool3d:
		if p.playing and _tag.get(p.get_instance_id(), {}).get("event", &"") == event:
			n += 1
	for p in _pool2d:
		if p.playing and _tag.get(p.get_instance_id(), {}).get("event", &"") == event:
			n += 1
	return n


func missing() -> Array[String]:
	return _missing.duplicate()


func layers_of(event: StringName) -> Array:
	var evt: Dictionary = EVENTS.get(event, {})
	var out := []
	if evt.has("layers"):
		out.append_array(evt["layers"])
	elif evt.has("clips"):
		out.append({"clips": evt["clips"], "n": evt.get("n", 1)})
	if evt.has("far"):
		out.append_array((evt["far"] as Dictionary).get("layers", []))
	return out


func clip_paths(layer: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var n := int(layer.get("n", 1))
	if n <= 0:
		out.append("res://Sounds/%s.ogg" % layer["clips"])
	for i in n:
		out.append("res://Sounds/%s_%d.ogg" % [layer["clips"], i + 1])
	return out


func play(event: StringName, at: Vector3, extra_db := 0.0, pitch_mul := 1.0, in_world := false) -> bool:
	var evt: Dictionary = EVENTS.get(event, {})
	if evt.is_empty() or evt.get("silent", false):
		return false
	if bool(evt.get("2d", false)) and not in_world:
		return play_2d(event, extra_db, pitch_mul)
	if _cooling(event, evt):
		return false
	var layers: Array = evt.get("layers", [{"clips": evt.get("clips", ""), "n": evt.get("n", 1)}])
	var far: Dictionary = evt.get("far", {})
	if not far.is_empty() and at.distance_to(listener()) > float(far.get("from", INF)):
		layers = far.get("layers", layers)
	var occluded := occluded_from(at)
	var started := false
	_last_started = PackedStringArray()
	for layer in layers:
		var take := _pick(layer)
		if take == null:
			continue
		_last_started.append(take.resource_path)
		var p := _voice_3d(event, evt)
		p.stream = take
		p.bus = evt.get("bus", &"World")
		p.unit_size = float(evt.get("unit", 10.0))
		p.max_distance = float(evt.get("max", 60.0))
		p.attenuation_filter_cutoff_hz = OCCLUDED_CUTOFF if occluded else OPEN_CUTOFF
		p.volume_db = float(evt.get("db", 0.0)) + float(layer.get("db", 0.0)) + extra_db + (OCCLUDED_DB if occluded else 0.0)
		p.pitch_scale = _pitch_for(evt, layer) * pitch_mul
		p.global_position = at
		_start(p, event, float(layer.get("delay", 0.0)))
		started = true
	if started:
		_played[event] = count(event) + 1
	return started


func play_2d(event: StringName, extra_db := 0.0, pitch_mul := 1.0) -> bool:
	var evt: Dictionary = EVENTS.get(event, {})
	if evt.is_empty() or evt.get("silent", false) or _cooling(event, evt):
		return false
	var layers: Array = evt.get("layers", [{"clips": evt.get("clips", ""), "n": evt.get("n", 1)}])
	var started := false
	_last_started = PackedStringArray()
	for layer in layers:
		var take := _pick(layer)
		if take == null:
			continue
		_last_started.append(take.resource_path)
		var p := _voice_2d(event, evt)
		p.stream = take
		p.bus = evt.get("bus", &"SFX")
		p.volume_db = float(evt.get("db", 0.0)) + float(layer.get("db", 0.0)) + extra_db
		p.pitch_scale = _pitch_for(evt, layer) * pitch_mul
		_start(p, event, float(layer.get("delay", 0.0)))
		started = true
	if started:
		_played[event] = count(event) + 1
	return started


func stream(event: StringName) -> AudioStream:
	var layers := layers_of(event)
	if layers.is_empty():
		return null
	return _pick(layers[0])


func attach(event: StringName, parent: Node3D, offset := Vector3.ZERO) -> AudioStreamPlayer3D:
	var evt: Dictionary = EVENTS.get(event, {})
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(event)
	p.bus = evt.get("bus", &"World")
	p.unit_size = float(evt.get("unit", 10.0))
	p.max_distance = float(evt.get("max", 60.0))
	p.volume_db = float(evt.get("db", 0.0))
	p.position = offset
	p.set_meta(&"sfx_event", event)
	parent.add_child(p)
	return p


func attach_2d(event: StringName, parent: Node) -> AudioStreamPlayer:
	var evt: Dictionary = EVENTS.get(event, {})
	var p := AudioStreamPlayer.new()
	p.stream = stream(event)
	p.bus = evt.get("bus", &"SFX")
	p.volume_db = float(evt.get("db", 0.0))
	p.set_meta(&"sfx_event", event)
	parent.add_child(p)
	return p


func level_of(event: StringName) -> float:
	return float((EVENTS.get(event, {}) as Dictionary).get("db", 0.0))


func occluded_from(at: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null or cam.get_world_3d() == null:
		return false
	var from := cam.global_position
	if from.distance_squared_to(at) < 1.0:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, at, 1)
	query.hit_from_inside = false
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit["position"].distance_to(at) > 0.6


func track(p: AudioStreamPlayer3D) -> void:
	if not _tracked.has(p):
		_tracked.append(p)
		p.set_meta(&"sfx_base_db", p.volume_db)


func untrack(p: AudioStreamPlayer3D) -> void:
	_tracked.erase(p)


func _update_tracked() -> void:
	for i in range(_tracked.size() - 1, -1, -1):
		var entry = _tracked[i]
		if entry == null or not is_instance_valid(entry) or not (entry as Node).is_inside_tree():
			_tracked.remove_at(i)
			continue
		var p := entry as AudioStreamPlayer3D
		if not p.playing:
			continue
		var occluded := occluded_from(p.global_position)
		var base := float(p.get_meta(&"sfx_base_db", p.volume_db))
		var want_cut := OCCLUDED_CUTOFF if occluded else OPEN_CUTOFF
		var want_db := base + (OCCLUDED_DB if occluded else 0.0)
		p.attenuation_filter_cutoff_hz = lerpf(p.attenuation_filter_cutoff_hz, want_cut, 0.5)
		p.volume_db = lerpf(p.volume_db, want_db, 0.5)


func listener() -> Vector3:
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	return cam.global_position if cam != null else Vector3.ZERO


func hdr(at: Vector3, depth_db := 10.0, radius := 30.0, hold := 0.3, release := 1.2) -> void:
	var d := at.distance_to(listener())
	var depth := depth_db * clampf(1.0 - d / maxf(radius, 0.01), 0.0, 1.0)
	if depth <= 0.5 or depth <= _duck:
		return
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_set_duck(depth)
	_duck_tween = create_tween()
	_duck_tween.tween_interval(hold)
	_duck_tween.tween_method(_set_duck, depth, 0.0, release)


func duck_db() -> float:
	return _duck


func _set_duck(value: float) -> void:
	_duck = value
	for bus in DUCKED:
		_apply(bus)


func set_gain(bus: StringName, source: StringName, gain_db: float) -> void:
	if not _gains.has(bus):
		_gains[bus] = {}
	_gains[bus][source] = gain_db
	_apply(bus)


func bus_db(bus: StringName) -> float:
	var idx := AudioServer.get_bus_index(bus)
	return AudioServer.get_bus_volume_db(idx) if idx >= 0 else 0.0


func _apply(bus: StringName) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var total := float(_rest.get(bus, 0.0))
	for source in (_gains.get(bus, {}) as Dictionary).values():
		total += float(source)
	if DUCKED.has(bus):
		total -= _duck
	AudioServer.set_bus_volume_db(idx, total)


func surface_of(body: Object) -> StringName:
	if body == null or not is_instance_valid(body):
		return &"dirt"
	if body.has_method("surface"):
		return body.surface()
	var node := body as Node
	var hint := node.name.to_lower() if node != null else ""
	return surface_from_name(hint)


func surface_from_name(hint: String) -> StringName:
	for word in ["container", "barrel", "metal", "tower", "horn", "toolbox", "tube", "steel", "fence", "target"]:
		if word in hint:
			return &"metal" if not "wood" in hint else &"wood"
	for word in ["crate", "pallet", "wood", "gate", "barricade", "plank", "box", "deck", "bench", "board"]:
		if word in hint:
			return &"wood"
	for word in ["wall", "concrete", "road", "block", "floor", "step", "tarmac", "asphalt", "bunker"]:
		if word in hint:
			return &"concrete"
	for word in ["gravel", "stone", "rock"]:
		if word in hint:
			return &"gravel"
	if "dirt" in hint or "sand" in hint:
		return &"dirt"
	return &"grass"


func _load(path: String) -> AudioStream:
	if _clips.has(path):
		return _clips[path]
	if not ResourceLoader.exists(path):
		_missing.append(path)
		return null
	var s := load(path) as AudioStream
	if s != null and path.ends_with("_loop.ogg"):
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		elif s is AudioStreamWAV:
			(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_clips[path] = s
	return s


func _pick(layer: Dictionary) -> AudioStream:
	var paths := clip_paths(layer)
	var takes: Array[AudioStream] = []
	for path in paths:
		var s: AudioStream = _clips.get(path)
		if s != null:
			takes.append(s)
	if takes.is_empty():
		return null
	var key := String(layer["clips"])
	var index := randi() % takes.size()
	if takes.size() > 1 and index == int(_last.get(key, -1)):
		index = (index + 1 + randi() % (takes.size() - 1)) % takes.size()
	_last[key] = index
	return takes[index]


func _pitch_for(evt: Dictionary, layer: Dictionary) -> float:
	var band: Array = layer.get("pitch", evt.get("pitch", [1.0, 1.0]))
	_last_pitch = randf_range(float(band[0]), float(band[1]))
	return _last_pitch


func _cooling(event: StringName, evt: Dictionary) -> bool:
	var cd := float(evt.get("cooldown", 0.0))
	if cd <= 0.0:
		return false
	if _cooldown.has(event):
		return true
	_cooldown[event] = cd
	return false


func _start(p: Node, event: StringName, delay: float) -> void:
	_tag[p.get_instance_id()] = {"event": event, "t": Time.get_ticks_msec()}
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if is_instance_valid(p) and _tag.has(p.get_instance_id()) and _tag[p.get_instance_id()]["event"] == event:
				p.play())
	else:
		p.play()


func _on_finished(p: Node) -> void:
	_tag.erase(p.get_instance_id())


func _voice_3d(event: StringName, evt: Dictionary) -> AudioStreamPlayer3D:
	return _voice(_pool3d, event, evt) as AudioStreamPlayer3D


func _voice_2d(event: StringName, evt: Dictionary) -> AudioStreamPlayer:
	return _voice(_pool2d, event, evt) as AudioStreamPlayer


func _voice(pool: Array, event: StringName, evt: Dictionary) -> Node:
	var cap := int(evt.get("voices", 4))
	var same := []
	var oldest: Node = null
	var oldest_t := INF
	for p in pool:
		var tag: Dictionary = _tag.get(p.get_instance_id(), {})
		if tag.is_empty() and not p.playing:
			if same.size() < cap:
				return p
		if tag.get("event", &"") == event:
			same.append(p)
		if not tag.is_empty() and float(tag["t"]) < oldest_t:
			oldest_t = float(tag["t"])
			oldest = p
	if same.size() >= cap:
		var victim: Node = same[0]
		for p in same:
			if float(_tag[p.get_instance_id()]["t"]) < float(_tag[victim.get_instance_id()]["t"]):
				victim = p
		victim.stop()
		return victim
	for p in pool:
		if _tag.get(p.get_instance_id(), {}).is_empty() and not p.playing:
			return p
	if oldest != null:
		oldest.stop()
		return oldest
	return pool[0]
