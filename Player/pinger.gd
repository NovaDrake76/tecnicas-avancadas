class_name Pinger
extends Node

## the callout. look at something, press the key, and it is on both operatives' screens with a word
## on it saying what it is.
##
## it is the co-op verb this game did not have. we already share MARKS, but a mark only works on a
## bird, only through the binoculars, and only after holding the middle of the lens on it -- so
## there was no way to say THIS DOOR, THAT CRATE, or GO NOW. Apex Legends' contextual ping is the
## thing the whole industry took from that generation of shooters, and Deep Rock Galactic's is
## praised for the same reason: it removes the need to say anything out loud, which is most of what
## two people playing a stealth mission actually need from each other.
##
## it costs nothing and tells the compound nothing: no bird hears it, no alarm moves, no score
## changes. the price of a ping is that both of you are looking at the same place instead of at two.
##
## THE WIRE. a ping hurts nobody and moves nobody, so it is the second thing in this game -- after
## the mark, and for exactly the same reason -- that both machines may decide and both be right:
## `net_ping` is `call_local` and broadcast rather than an ask to the host. it is stored as the
## moment it RUNS OUT rather than as a countdown, which is what makes it correct on a machine where
## this operative is a remote copy: those nodes are process-disabled, so nothing here ticks, and a
## countdown would sit frozen on a teammate's screen forever.

## how far the ray reaches. further than a kiwi can see you, because half of what gets pinged is
## something you are looking at from outside the compound.
@export var reach := 120.0
## how long one stays up. long enough to act on, short enough that a compound does not silt up
## with the last five minutes of somebody's opinions.
@export var life := 12.0
## how many one operative may have at once. the oldest goes when a fifth is placed, so the key can
## be leant on without turning the screen into a constellation.
@export var most := 4
@export var cooldown := 0.35
## how far off the aim line a bird still counts as the thing being pointed at. the binoculars' own
## number, and narrow for the same reason: what am I calling out must never be a guess.
@export var cone_deg := 2.5
## world and the layer the birds, the bodies and the interactables all sit on.
@export_flags_3d_physics var ray_mask := 9

var _pings: Array = []
var _next := 0.0


func _ready() -> void:
	add_to_group("pinger")


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ping"):
		return
	if place():
		get_viewport().set_input_as_handled()


## what the crosshair is on, named. returns whether anything was actually pinged: pinging the sky
## puts nothing up, because a marker floating in the air over the horizon is a claim about a place
## that is not there.
func place() -> bool:
	var now := _now()
	if now < _next:
		return false
	var cam := get_viewport().get_camera_3d() if get_viewport() != null else null
	if cam == null:
		return false
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * reach
	var query := PhysicsRayQueryParameters3D.create(from, to, ray_mask)
	var player := get_parent() as CollisionObject3D
	if player != null:
		query.exclude = [player.get_rid()]
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	_next = now + cooldown

	var what := hit.get("collider") as Node
	var at := hit.get("position") as Vector3
	var bird := _kiwi_of(what)
	## and a bird NEAR the line counts as the thing being pointed at. a kiwi is a small bird: at
	## thirty metres its middle is a couple of degrees wide and the crosshair held on it lands in
	## the grass a metre short, which would make "call that sentry out" a verb that only works at
	## arm's length. it is the same rule the binoculars already mark with, and the cone is just as
	## narrow -- what am I pointing at must never be a guess -- and it never reaches through a wall.
	if bird == null:
		var near := _bird_on_the_line(from, -cam.global_transform.basis.z)
		if near != null:
			bird = near
			at = near.global_position + Vector3.UP * 0.35
			what = near
	## a bird that gets pinged is also MARKED, because those are the same sentence said twice
	## otherwise: the teammate who is told there is a sniper on the tower wants the tag on it too.
	if bird != null and not bird.is_down():
		bird.net_mark.rpc(15.0)
	net_ping.rpc(at, _name_of(what, bird))
	return true


## the bird closest to the aim line inside `cone_deg`, if nothing solid is in the way of it.
##
## it deliberately does NOT care how far the ray got first. aiming at a sentry across a field puts
## the crosshair a fraction above the grass, so the ray lands in the dirt twenty metres short while
## the thing being pointed at is the bird at thirty-six -- measured, in a photograph, which is what
## this rule exists to fix. whether the bird is REACHABLE is the clear line below, and that is the
## question that actually matters: it is what stops a wall being pinged through.
func _bird_on_the_line(from: Vector3, dir: Vector3) -> Kiwi:
	var best: Kiwi = null
	var tightest := deg_to_rad(cone_deg)
	var space := get_viewport().get_world_3d().direct_space_state
	for node in get_tree().get_nodes_in_group("kiwi"):
		var bird := node as Kiwi
		if bird == null or not is_instance_valid(bird):
			continue
		var to := bird.global_position + Vector3.UP * 0.35 - from
		var away := to.length()
		if away > reach:
			continue
		var off := dir.angle_to(to)
		if off > tightest:
			continue
		## a graze at the bird's own feet is not cover. sighting across a field almost parallel to
		## the ground, the ray to a point 35 cm up a kiwi clips the grass a metre short of it, and
		## a plain "did the ray hit anything" test throws every distant bird away -- photographed,
		## twice, before it was understood. what blocks a callout is something between you and the
		## bird, not the ground the bird is standing on.
		var query := PhysicsRayQueryParameters3D.create(from, from + to, 1)
		var blocked := space.intersect_ray(query)
		if not blocked.is_empty():
			var stopped_at := blocked["position"] as Vector3
			if stopped_at.distance_to(from + to) > 1.5:
				continue
		tightest = off
		best = bird
	return best


## every ping this operative has out that has not run out yet.
func live() -> Array:
	var now := _now()
	var out: Array = []
	for row in _pings:
		if float(row["until"]) > now:
			out.append(row)
	return out


func count() -> int:
	return live().size()


## every ping on the level, from every operative, local and remote. the hud asks this rather than
## walking a group, because a remote operative's kit LEAVES its groups on purpose: a group lookup
## would only ever find this machine's own.
static func all(tree: SceneTree) -> Array:
	var out: Array = []
	for who in Player.all(tree):
		var pin := who.get_node_or_null("Pings") as Pinger
		if pin != null:
			out.append_array(pin.live())
	return out


## the shared half. both machines run it, neither asks the other's permission, and the clock is
## started where the message LANDS rather than carried in it, so two machines that disagree about
## what time it is still agree about how long a ping lasts.
@rpc("any_peer", "call_local", "reliable")
func net_ping(at: Vector3, label: String) -> void:
	_pings.append({"at": at, "label": label, "until": _now() + life})
	while _pings.size() > most:
		_pings.pop_front()
	UiSfx.play("tick")


func clear() -> void:
	_pings.clear()


## the kiwi a collider belongs to, if any: the weak point and the drag handle are children of one.
func _kiwi_of(what: Node) -> Kiwi:
	var node := what
	while node != null:
		var bird := node as Kiwi
		if bird != null:
			return bird
		node = node.get_parent()
	return null


## what the thing is called on screen. a ping that says nothing but "here" is a dot; the whole
## reason Apex's is remembered is that it names what it landed on.
func _name_of(what: Node, bird: Kiwi) -> String:
	if bird != null:
		return "BODY" if bird.is_down() else bird.kind_name()
	var node := what
	while node != null:
		if node.is_in_group("objective"):
			return "OBJECTIVE"
		if node.is_in_group("alarm_horn"):
			return "HORN"
		if node.is_in_group("interactable"):
			return "ITEM"
		node = node.get_parent()
	return "MOVE"


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0
