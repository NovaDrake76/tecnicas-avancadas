extends Node


enum Role { HOLD, ATTACK, FLANK, SUPPRESS, APPROACH }

signal leader_changed(kiwi: Node3D)
signal rattled

const ROLE_INTERVAL := 1.5
const COVER_SEARCH := 18.0
const FLANK_STEP := 7.0
const RATTLE_TIME := 2.5
const SYNC_CHANCE := 0.35
const SYNC_COOLDOWN := 12.0

var _members: Array = []
var _tokens := {}
var _roles := {}
var _claims := {}
var _leader: Node3D
var _rattle := 0.0
var _role_timer := 0.0
var _sync_cooldown := 0.0
var _sync_armed := false
var _sync_wait := 0.0
var _sync_waiting := {}
const SYNC_WAIT := 1.5
## an approacher walks in only while the player has been quiet this long: fire keeps them in cover.
const QUIET_TO_ADVANCE := 2.0
const APPROACHERS := 2
const FLANKERS := 2

var _player_quiet := 99.0


## physics, not process: the birds this coordinates move on the physics clock, and under load the two clocks decouple and roles rotate faster than a bird can reach its spot.
func _physics_process(delta: float) -> void:
	_sweep()
	_player_quiet += delta
	_rattle = maxf(0.0, _rattle - delta)
	_sync_cooldown = maxf(0.0, _sync_cooldown - delta)
	if _sync_armed:
		_sync_wait += delta
		if _sync_wait > SYNC_WAIT:
			_sync_armed = false
			_sync_waiting.clear()
	if _members.is_empty():
		return
	_role_timer -= delta
	if _role_timer <= 0.0:
		_role_timer = ROLE_INTERVAL
		_assign_roles()


func note_player_shot() -> void:
	_player_quiet = 0.0


func player_quiet() -> float:
	return _player_quiet


func reset() -> void:
	_player_quiet = 99.0
	_members.clear()
	_tokens.clear()
	_roles.clear()
	_claims.clear()
	_spots.clear()
	_leader = null
	_rattle = 0.0
	_sync_cooldown = 0.0
	_sync_armed = false
	_sync_waiting.clear()


func join(kiwi: Node3D) -> void:
	if kiwi == null or kiwi in _members:
		return
	_members.append(kiwi)
	_roles[kiwi.get_instance_id()] = Role.HOLD
	if _leader == null or not is_instance_valid(_leader):
		_set_leader(kiwi)
	_role_timer = 0.0


func leave(kiwi: Node3D, went_down := false) -> void:
	if kiwi == null:
		return
	var id := kiwi.get_instance_id()
	_members.erase(kiwi)
	_tokens.erase(id)
	_roles.erase(id)
	release_cover(kiwi)
	if kiwi == _leader:
		_leader = null
		if went_down and not _members.is_empty():
			_rattle_all()
		_set_leader(_pick_leader())


func members() -> Array:
	return _members.duplicate()


func hunter_count() -> int:
	return _members.size()


func max_firing() -> int:
	return clampi(1 + floori(_members.size() / 3.0), 1, 3)


func token_count() -> int:
	return _tokens.size()


func holds_token(kiwi: Node3D) -> bool:
	return kiwi != null and _tokens.has(kiwi.get_instance_id())


func request_fire(kiwi: Node3D) -> bool:
	if kiwi == null or _rattle > 0.0:
		return false
	var id := kiwi.get_instance_id()
	if _tokens.has(id):
		return true
	if not (kiwi in _members):
		join(kiwi)
	if _tokens.size() >= max_firing():
		return false
	_tokens[id] = true
	_roles[id] = Role.ATTACK
	return true


func release_fire(kiwi: Node3D) -> void:
	if kiwi == null:
		return
	var id := kiwi.get_instance_id()
	if _tokens.erase(id) and _roles.has(id):
		_roles[id] = Role.HOLD


func role_for(kiwi: Node3D) -> int:
	if kiwi == null:
		return Role.HOLD
	return int(_roles.get(kiwi.get_instance_id(), Role.HOLD))


func leader() -> Node3D:
	return _leader if _leader != null and is_instance_valid(_leader) else null


func is_leader(kiwi: Node3D) -> bool:
	return kiwi != null and kiwi == leader()


func is_rattled() -> bool:
	return _rattle > 0.0


var force_sync := false


func sync_hold(kiwi: Node3D) -> bool:
	if not _sync_armed or kiwi == null or not holds_token(kiwi):
		return false
	if not (kiwi.has_method("can_see_target") and kiwi.can_see_target()):
		return false
	_sync_waiting[kiwi.get_instance_id()] = true
	if _sync_waiting.size() < 2:
		return true
	_sync_armed = false
	force_sync = false
	_sync_cooldown = SYNC_COOLDOWN
	for id in _sync_waiting.keys():
		var k := instance_from_id(id)
		if k != null and k.has_method("sync_charge"):
			k.sync_charge()
	_sync_waiting.clear()
	return true


func is_sync_armed() -> bool:
	return _sync_armed


func claim_cover(kiwi: Node3D, toward: Vector3, flank := false) -> Vector3:
	if kiwi == null:
		return Vector3.INF
	release_cover(kiwi)
	var best: Node3D = null
	var best_d := INF
	var here := kiwi.global_position
	var my_d := here.distance_to(toward)
	for node in get_tree().get_nodes_in_group("cover_point"):
		var point := node as Node3D
		if point == null or _claims.has(point.get_instance_id()):
			continue
		var d := point.global_position.distance_to(here)
		if d > COVER_SEARCH or d < 0.5:
			continue
		if flank and point.global_position.distance_to(toward) >= my_d:
			continue
		if not _covered(point.global_position, toward, kiwi):
			continue
		if d < best_d:
			best_d = d
			best = point
	if best != null:
		_claims[best.get_instance_id()] = kiwi.get_instance_id()
		return best.global_position
	var found := find_cover(kiwi, toward, flank)
	if found != Vector3.INF:
		_spots[kiwi.get_instance_id()] = found
	return found


const AUTO_RINGS := [3.5, 6.5, 9.5]
const AUTO_DIRS := 12
const SPOT_APART := 1.8

var _spots := {}


func find_cover(kiwi: Node3D, toward: Vector3, flank := false) -> Vector3:
	var here := kiwi.global_position
	var my_d := Vector2(here.x - toward.x, here.z - toward.z).length()
	var best := Vector3.INF
	var best_score := INF
	var ring_index := 0
	for r in AUTO_RINGS:
		var offset := 0.5 if ring_index % 2 == 1 else 0.0
		ring_index += 1
		for i in AUTO_DIRS:
			var a := TAU * (float(i) + offset) / float(AUTO_DIRS)
			var cand := _ground(kiwi, here + Vector3(cos(a) * float(r), 0.0, sin(a) * float(r)))
			if cand == Vector3.INF:
				continue
			var d_player := Vector2(cand.x - toward.x, cand.z - toward.z).length()
			if d_player < 3.0:
				continue
			if flank and d_player >= my_d - 1.0:
				continue
			if _spot_taken(cand, kiwi):
				continue
			if not _covered(cand, toward, kiwi):
				continue
			if not _clear_run(kiwi, here, cand):
				continue
			var score: float = float(r) + (d_player * 0.15 if flank else 0.0)
			if score < best_score:
				best_score = score
				best = cand
	return best


func _spot_taken(at: Vector3, kiwi: Node3D) -> bool:
	var me := kiwi.get_instance_id()
	for id in _spots.keys():
		if id != me and (_spots[id] as Vector3).distance_to(at) < SPOT_APART:
			return true
	return false


func _clear_run(kiwi: Node3D, from: Vector3, to: Vector3) -> bool:
	var space := kiwi.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.3, to + Vector3.UP * 0.3, 1)
	return space.intersect_ray(query).is_empty()


func release_cover(kiwi: Node3D) -> void:
	if kiwi == null:
		return
	var id := kiwi.get_instance_id()
	_spots.erase(id)
	for key in _claims.keys():
		if _claims[key] == id:
			_claims.erase(key)


func flank_point(kiwi: Node3D, toward: Vector3) -> Vector3:
	var here := kiwi.global_position
	var to := toward - here
	to.y = 0.0
	if to.length_squared() < 0.01:
		to = Vector3.FORWARD
	var right := to.normalized().cross(Vector3.UP)
	var hand := 1.0 if (kiwi.get_instance_id() % 2) == 0 else -1.0
	var reach := clampf(to.length() * 0.8, 6.0, 14.0)
	var goal := toward + right * hand * reach + to.normalized() * 2.0
	var grounded := _ground(kiwi, goal)
	if grounded == Vector3.INF:
		return Vector3.INF
	return grounded if _clear_run(kiwi, here, grounded) else Vector3.INF


func tangent_point(kiwi: Node3D, toward: Vector3, side := 0) -> Vector3:
	var here := kiwi.global_position
	var to := toward - here
	to.y = 0.0
	if to.length_squared() < 0.01:
		to = Vector3.FORWARD
	var right := to.normalized().cross(Vector3.UP)
	var hand := float(side) if side != 0 else (1.0 if (kiwi.get_instance_id() % 2) == 0 else -1.0)
	var goal := here + right * hand * FLANK_STEP + to.normalized() * FLANK_STEP * 0.35
	var grounded := _ground(kiwi, goal)
	return goal if grounded == Vector3.INF else grounded


func _ground(kiwi: Node3D, at: Vector3) -> Vector3:
	var space := kiwi.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at - Vector3.UP * 6.0, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	return hit["position"]


func _covered(point: Vector3, toward: Vector3, kiwi: Node3D) -> bool:
	var space := kiwi.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(toward + Vector3.UP * 1.2, point + Vector3.UP * 0.35, 1)
	return not space.intersect_ray(query).is_empty()


func _assign_roles() -> void:
	var seeing: Array = []
	var free: Array = []
	for k in _members:
		var id: int = k.get_instance_id()
		if _tokens.has(id):
			_roles[id] = Role.ATTACK
			if k.has_method("can_see_target") and k.can_see_target():
				seeing.append(id)
			continue
		free.append(k)
	var focus: Vector3 = Alarm.last_known
	free.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.distance_to(focus) < b.global_position.distance_to(focus))
	var suppressors := 0 if _members.size() <= 1 else maxi(1, floori(float(free.size()) / 3.0))
	var approachers := 0
	var flankers := 0
	for i in free.size():
		var k: Node3D = free[i]
		var id: int = k.get_instance_id()
		if i < suppressors:
			_roles[id] = Role.SUPPRESS
		elif approachers < APPROACHERS:
			_roles[id] = Role.APPROACH
			approachers += 1
		elif flankers < FLANKERS:
			_roles[id] = Role.FLANK
			flankers += 1
		else:
			_roles[id] = Role.HOLD
	if seeing.size() >= 2 and not _sync_armed and (force_sync or (_sync_cooldown <= 0.0 and randf() < SYNC_CHANCE)):
		_sync_armed = true
		_sync_wait = 0.0
		_sync_waiting.clear()


func _rattle_all() -> void:
	_tokens.clear()
	_sync_armed = false
	_sync_waiting.clear()
	_rattle = RATTLE_TIME
	for k in _members:
		_roles[k.get_instance_id()] = Role.HOLD
		if k.has_method("rattle"):
			k.rattle()
	rattled.emit()


func _pick_leader() -> Node3D:
	for k in _members:
		if is_instance_valid(k):
			return k
	return null


func _set_leader(kiwi: Node3D) -> void:
	if kiwi == _leader:
		return
	_leader = kiwi
	leader_changed.emit(_leader)


func _sweep() -> void:
	var gone := false
	for i in range(_members.size() - 1, -1, -1):
		var k = _members[i]
		if k == null or not is_instance_valid(k):
			_members.remove_at(i)
			gone = true
	if gone:
		var live := {}
		for k in _members:
			live[k.get_instance_id()] = true
		for id in _tokens.keys():
			if not live.has(id):
				_tokens.erase(id)
		for id in _roles.keys():
			if not live.has(id):
				_roles.erase(id)
		for key in _claims.keys():
			if not live.has(_claims[key]):
				_claims.erase(key)
		if _leader != null and not is_instance_valid(_leader):
			_leader = null
			_set_leader(_pick_leader())
