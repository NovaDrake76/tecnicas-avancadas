extends Node

## the hunters' coordination. it is a property of the group, not of any bird, and every hunter has
## to see the same answer, so it lives in one place. three ideas, in order of how much they matter:
##
## ATTACK TOKENS. only a token holder may open an attack; everyone else moves. that is the trick
## behind why F.E.A.R. and Halo feel intelligent: enemies take turns, so the player is never
## flattened by simultaneous fire and there is always visible movement to read.
##
## ROLES for the birds without a token: FLANK runs to cover on the player's far side, SUPPRESS puts
## a beam on the last place anyone saw you so leaving cover is punished, HOLD takes cover and waits.
## there has to be a state that means "wait" or the squad thrashes.
##
## A LEADER. the first hunter in. when it goes down every token is released and the squad is
## rattled for a moment: nobody shoots, everybody dives for cover. that gives the player a priority
## target, which is what turns a firefight into a puzzle instead of an aim test.

enum Role { HOLD, ATTACK, FLANK, SUPPRESS }

signal leader_changed(kiwi: Node3D)
signal rattled

## how often roles are reconsidered. faster and the birds dither; slower and they stand about.
const ROLE_INTERVAL := 1.5
const COVER_SEARCH := 18.0
## the tangent step a flanker takes when the level has no cover points authored.
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


func _process(delta: float) -> void:
	_sweep()
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


func reset() -> void:
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


## a hunter is in the fight. the first one in leads.
func join(kiwi: Node3D) -> void:
	if kiwi == null or kiwi in _members:
		return
	_members.append(kiwi)
	_roles[kiwi.get_instance_id()] = Role.HOLD
	if _leader == null or not is_instance_valid(_leader):
		_set_leader(kiwi)
	_role_timer = 0.0


## out of the fight, for any reason. a token held by a corpse would freeze every fight silently,
## so this is where they always come back.
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


## how many may shoot at once. one for a small group, one more for every three birds, never more
## than three however big the fight gets.
func max_firing() -> int:
	return clampi(1 + floori(_members.size() / 3.0), 1, 3)


func token_count() -> int:
	return _tokens.size()


func holds_token(kiwi: Node3D) -> bool:
	return kiwi != null and _tokens.has(kiwi.get_instance_id())


## may this bird open an attack right now. a bird that already holds a token keeps it.
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


## two token holders who can both see the player may be told to charge together. two pairs of eyes
## filling at once is an unmistakable tell, and the counter is already written: breaking the line
## during the charge fizzles it for both of them. for probes, force_sync opens the window on the
## next role tick regardless of the dice.
var force_sync := false


## a token holder about to choose its next attack asks here. false: shoot as you like. true: hold, the
## squad is lining up a sync; when the second holder arrives both are told to charge on this tick.
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


## cover for this bird against `toward`: an authored CoverPoint if the level has one that fits, else
## a spot FOUND in the geometry. for a flanker it also has to be closer to `toward` than the bird
## already is. Vector3.INF when there is none.
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


## the rings of candidate spots around a bird, and how many round each ring. 36 spots, each costing
## up to three rays, once per role tick per bird: cheap enough to never author a cover point.
const AUTO_RINGS := [3.5, 6.5, 9.5]
const AUTO_DIRS := 12
## two birds do not share a spot closer than this
const SPOT_APART := 1.8

var _spots := {}


## cover read off the level itself, no markers needed. a candidate is cover when the world blocks
## the line from the player's eyes to a bird's eye height at the spot, it has ground under it, the
## bird can run to it in a straight line (there is no navigation, so a spot behind a wall from the
## bird is no use), it is not on top of the player, and nobody else has taken it. nearer is better;
## a flanker prefers spots that also close the distance.
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


## a straight run from here to there at knee height meets nothing of the world.
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


## a point at a tangent to the line to the player, FLANK_STEP off, on the ground. not clever, but a
## squad in a level with no cover points authored still moves instead of standing in a row. the side
## alternates with the bird so two flankers do not pick the same spot.
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


## the ground under a point, or INF when there is none to stand on.
func _ground(kiwi: Node3D, at: Vector3) -> Vector3:
	var space := kiwi.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at - Vector3.UP * 6.0, 1)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	return hit["position"]


## a cover point counts as cover when the line from the player's eyes to a bird's eye height at the
## point is blocked by the world.
func _covered(point: Vector3, toward: Vector3, kiwi: Node3D) -> bool:
	var space := kiwi.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(toward + Vector3.UP * 1.2, point + Vector3.UP * 0.35, 1)
	return not space.intersect_ray(query).is_empty()


func _assign_roles() -> void:
	var idle := 0
	var seeing: Array = []
	for k in _members:
		var id: int = k.get_instance_id()
		if _tokens.has(id):
			_roles[id] = Role.ATTACK
			if k.has_method("can_see_target") and k.can_see_target():
				seeing.append(id)
			continue
		## the first bird without a turn suppresses if it can, the next flanks, the third holds, and
		## round again. a lone hunter that has lost you therefore lights up your cover rather than
		## charging in, which is the better behaviour on its own.
		var beam_ready: bool = k.has_method("beam_ready") and k.beam_ready()
		if idle % 3 == 0 and beam_ready:
			_roles[id] = Role.SUPPRESS
		elif idle % 3 == 2:
			_roles[id] = Role.HOLD
		else:
			_roles[id] = Role.FLANK
		idle += 1
	## the window opens here; the birds walk into it from _choose_attack, each holding its fire until
	## the other is ready too, so the two charges start on the same tick however their bursts were
	## staggered. a window nobody fills in SYNC_WAIT closes on its own.
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


## a freed node compares equal to null and stays in every dictionary it was ever put in. swept
## every frame, the same discipline as the ring, the reticle and the vitals bar.
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
