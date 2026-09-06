class_name UtilityBelt
extends Node


signal changed()
signal thrown(what: Node3D)

const KINDS := [
	{"id": "mag", "title": "MAG", "max": 3, "free": true, "speed": 11.0, "lift": 2.5,
		"cooldown": 0.8, "cue": &"", "note": "A clatter. The birds walk over to look."},
	{"id": "frag", "title": "FRAG", "max": 3, "free": false, "speed": 14.0, "lift": 3.0,
		"cooldown": 1.0, "cue": &"frag_pin",
		"note": "Five metres, through armour, and the whole compound hears it."},
]

var counts := {}
var carried: Array[String] = []

var _pick := 0
var _cooldown := 0.0
var _player: CharacterBody3D
var _serial := 0
var _live := {}


func _ready() -> void:
	add_to_group("utility")
	_player = get_parent() as CharacterBody3D
	refill({})


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("throw"):
		if throw() != null:
			get_viewport().set_input_as_handled()
		return
	for i in KINDS.size():
		var action := key_for(String(KINDS[i]["id"]))
		if InputMap.has_action(action) and event.is_action_pressed(action):
			if select(String(KINDS[i]["id"])):
				get_viewport().set_input_as_handled()
			return


static func row(id: String) -> Dictionary:
	for k in KINDS:
		if k["id"] == id:
			return k
	return {}


static func title_of(id: String) -> String:
	return String(row(id).get("title", id.to_upper()))


static func note_of(id: String) -> String:
	return String(row(id).get("note", ""))


static func key_for(id: String) -> StringName:
	for i in KINDS.size():
		if KINDS[i]["id"] == id:
			return StringName("utility_%d" % (i + 1))
	return &""


func cap(id: String) -> int:
	return int(row(id).get("max", 0))


func count(id: String) -> int:
	return int(counts.get(id, 0))


func selected() -> String:
	if carried.is_empty():
		return ""
	return carried[clampi(_pick, 0, carried.size() - 1)]


func refill(supply: Dictionary) -> void:
	counts.clear()
	carried.clear()
	for k in KINDS:
		var id := String(k["id"])
		var n := int(k["max"]) if bool(k.get("free", false)) else mini(int(supply.get(id, 0)), int(k["max"]))
		if n <= 0 and not bool(k.get("free", false)):
			continue
		carried.append(id)
		counts[id] = n
	_pick = clampi(_pick, 0, maxi(carried.size() - 1, 0))
	changed.emit()


func select(id: String) -> bool:
	var where := carried.find(id)
	if where < 0 or where == _pick:
		return false
	_pick = where
	UiSfx.play("switch")
	changed.emit()
	return true


func can_throw() -> bool:
	return _player != null and _cooldown <= 0.0 and count(selected()) > 0


func throw() -> Node3D:
	if not can_throw():
		return null
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var id := selected()
	var k := row(id)
	counts[id] = count(id) - 1
	_cooldown = float(k.get("cooldown", 0.8))
	var cue := StringName(k.get("cue", &""))
	if cue != &"":
		Sfx.play_2d(cue)
	Sfx.play_2d(&"throw")
	var forward := -cam.global_transform.basis.z
	var at := cam.global_position + forward * 0.5 - cam.global_transform.basis.y * 0.15
	var push := forward * float(k["speed"]) + Vector3.UP * float(k["lift"]) + _player.velocity * 0.5
	var spin := Vector3(randf_range(-6.0, 6.0), randf_range(-3.0, 3.0), randf_range(-6.0, 6.0))
	_forget_dead()
	_serial += 1
	var thing := _lay(id, _serial, at, push, spin, true)
	if Net.is_online():
		_net_throw.rpc(id, _serial, at, push, spin)
	changed.emit()
	thrown.emit(thing)
	return thing


@rpc("any_peer", "call_remote", "reliable")
func _net_throw(id: String, serial: int, at: Vector3, push: Vector3, spin: Vector3) -> void:
	_lay(id, serial, at, push, spin, false)


func _lay(id: String, serial: int, at: Vector3, push: Vector3, spin: Vector3, mine: bool) -> Node3D:
	var world := get_tree().current_scene
	if world == null:
		return null
	var thing := _make(id)
	if thing == null:
		return null
	thing.mine = mine
	if thing is FragGrenade:
		(thing as FragGrenade).belt = self
	world.add_child(thing)
	thing.global_position = at
	thing.linear_velocity = push
	thing.angular_velocity = spin
	_live[serial] = thing
	if not mine:
		Sfx.play(&"throw", at, 0.0, 1.0, true)
	return thing


func _make(id: String) -> Throwable:
	match id:
		"mag":
			return Noisemaker.new()
		"frag":
			return FragGrenade.new()
	return null


func _forget_dead() -> void:
	for serial in _live.keys():
		if not is_instance_valid(_live[serial]):
			_live.erase(serial)


func report_burst(what: Node, at: Vector3) -> void:
	if not Net.is_online():
		return
	for serial in _live:
		if _live[serial] == what:
			_net_burst.rpc(int(serial), at)
			return


@rpc("any_peer", "call_remote", "reliable")
func _net_burst(serial: int, at: Vector3) -> void:
	var what := _live.get(serial) as FragGrenade
	if what == null or not is_instance_valid(what):
		return
	## the host is the only machine entitled to say who it hurt, wherever the thrower was sitting.
	what.burst_at(at, multiplayer.is_server())
