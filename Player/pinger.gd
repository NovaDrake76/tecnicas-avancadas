class_name Pinger
extends Node


## how far the ray reaches.
@export var reach := 120.0
## how long one stays up.
@export var life := 12.0
## how many one operative may have at once.
@export var most := 4
@export var cooldown := 0.35
## how far off the aim line a bird still counts as the thing being pointed at.
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
	if bird == null:
		var near := _bird_on_the_line(from, -cam.global_transform.basis.z)
		if near != null:
			bird = near
			at = near.global_position + Vector3.UP * 0.35
			what = near
	if bird != null and not bird.is_down():
		bird.net_mark.rpc(15.0)
	net_ping.rpc(at, _name_of(what, bird))
	return true


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
		var query := PhysicsRayQueryParameters3D.create(from, from + to, 1)
		var blocked := space.intersect_ray(query)
		if not blocked.is_empty():
			var stopped_at := blocked["position"] as Vector3
			if stopped_at.distance_to(from + to) > 1.5:
				continue
		tightest = off
		best = bird
	return best


func live() -> Array:
	var now := _now()
	var out: Array = []
	for row in _pings:
		if float(row["until"]) > now:
			out.append(row)
	return out


func count() -> int:
	return live().size()


static func all(tree: SceneTree) -> Array:
	var out: Array = []
	for who in Player.all(tree):
		var pin := who.get_node_or_null("Pings") as Pinger
		if pin != null:
			out.append_array(pin.live())
	return out


@rpc("any_peer", "call_local", "reliable")
func net_ping(at: Vector3, label: String) -> void:
	_pings.append({"at": at, "label": label, "until": _now() + life})
	while _pings.size() > most:
		_pings.pop_front()
	UiSfx.play("tick")


func clear() -> void:
	_pings.clear()


func _kiwi_of(what: Node) -> Kiwi:
	var node := what
	while node != null:
		var bird := node as Kiwi
		if bird != null:
			return bird
		node = node.get_parent()
	return null


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
