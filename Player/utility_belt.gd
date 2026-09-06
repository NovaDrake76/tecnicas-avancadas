class_name UtilityBelt
extends Node

## what the player throws. G throws the thing in hand, and a NUMBER picks which thing that is -- one
## key per row of the table, the way the weapon rack gives one key per weapon on it. The belt owns
## nothing else: how far it flies is a number in the table, what it does when it lands is the
## throwable's own business.
##
## a number per utility rather than a cycle key, Nathan's call and Ghost Recon Wildlands' layout.
## cycling is a key whose meaning depends on what was pressed before it, so the player has to look at
## the screen to find out what they are about to throw; a number always means the same thing, and
## reaching for the grenade is one press whatever is in hand. it is also why the key is the row's
## place in the TABLE and not its place in what is carried: the grenade is 7 whether or not one was
## bought, exactly as a weapon keeps its slot key whether or not it is in the loadout.
##
## it started as the thrown magazine alone, and the magazine is still the first row of the table.
## generalising it was the point of the frag grenade rather than a tidy-up afterwards: a second
## throwable bolted on beside the first would have needed a second key, a second cooldown, a second
## count in the hud and a second entry in the armoury, and the third one would have needed a third.
## adding a utility now is a row here, a script under Props/, and a row in Armory.CATALOG.
##
## the counts are per level, filled by the armoury and by nothing else, so they cannot be farmed
## halfway through a mission -- the same rule the spare magazines follow, for the same reason.

## the count of one kind changed, or a different one came to hand. the hud draws the belt off this
## and never asks the scene for it.
signal changed()
signal thrown(what: Node3D)

## every utility in the game. `free` is a thing the player always has and never buys, which is what
## the magazine is: it costs nothing because its whole job is to be spent freely, and a distraction
## the player rations is a distraction they never use.
const KINDS := [
	{"id": "mag", "title": "MAG", "max": 3, "free": true, "speed": 11.0, "lift": 2.5,
		"cooldown": 0.8, "cue": &"", "note": "A clatter. The birds walk over to look."},
	{"id": "frag", "title": "FRAG", "max": 3, "free": false, "speed": 14.0, "lift": 3.0,
		"cooldown": 1.0, "cue": &"frag_pin",
		"note": "Five metres, through armour, and the whole compound hears it."},
]

## id -> how many are in the belt now
var counts := {}
## the kinds this operative actually walked out with, in table order. a kind stays listed at zero
## for the rest of the mission: the hud row going to x0 is how the player learns they are out, and
## a row that vanished would read as the verb having been taken away.
var carried: Array[String] = []

var _pick := 0
var _cooldown := 0.0
var _player: CharacterBody3D
var _serial := 0
## serial -> the copy of it on this machine, so a message about one grenade finds that grenade
## without either machine having to agree on a node name.
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


## ---------------------------------------------------------------- the table

static func row(id: String) -> Dictionary:
	for k in KINDS:
		if k["id"] == id:
			return k
	return {}


static func title_of(id: String) -> String:
	return String(row(id).get("title", id.to_upper()))


## what it does, in the player's words, for the bench card. it lives in the table with everything
## else about a utility, so the sentence and the numbers it describes cannot drift apart.
static func note_of(id: String) -> String:
	return String(row(id).get("note", ""))


## the action that puts this kind in hand. the hud draws the key off this rather than off a letter
## anybody typed, the same rule every other prompt in the game follows.
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


## ---------------------------------------------------------------- filling it

## the armoury dresses the operative: the free kinds come back full, the bought ones come back with
## however many were paid for. called on entering the safe house, on every change at the bench and
## on deploy, and never from inside a mission.
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


## ---------------------------------------------------------------- using it

## put one kind in hand. a kind the operative did not walk out with is not on the belt at all, so
## its key does nothing -- the same as a weapon slot that is not in the loadout. a kind that is
## carried but SPENT still comes to hand and reads x0, because being out of grenades is a thing the
## player has to be able to see rather than a key that has gone quiet.
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


## from the camera, a little up and forward, so it arcs over low cover the way a throw does and does
## not start inside the player's own capsule. the player's own speed is added at half weight: a
## grenade thrown while running goes further, which is real and is also the only way to throw one
## while retreating.
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
	## the same thing, thrown the same way, on every machine: the arc is the tell. a teammate who
	## could not see a magazine fly would not know where the birds are about to be looking, and one
	## who could not see a grenade fly would be standing where it lands.
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
	## a throw is in the player's own hands and stays in their head; a teammate's throw happens over
	## there, and the flag is overridden at the call site because that is where the difference is.
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


## ---------------------------------------------------------------- the wire

## the table of live throwables is only there so a message can find one again, so anything that has
## already gone off or timed out is swept before the next throw rather than kept for the level.
func _forget_dead() -> void:
	for serial in _live.keys():
		if not is_instance_valid(_live[serial]):
			_live.erase(serial)


## the thrower's grenade went off. every other machine is told where, and bursts its own copy there
## rather than on a clock of its own: a bouncing body does not come to rest in the same place twice,
## so the one thing that may not be worked out again on the other side is WHERE.
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
