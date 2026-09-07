class_name Crosshair
extends Control


@export_group("Reticle")
@export var tick := 9.0
@export var thickness := 2.0
@export var dot := 1.6
@export var colour := Color(1.0, 1.0, 1.0, 0.9)
## drawn under the light pass and a little fatter, so the reticle reads over grass as well as sky.
@export var ink := Color(0.0, 0.0, 0.0, 0.55)

@export_group("Spread")
## the gap when you are standing still with a settled weapon.
@export var gap_rest := 6.0
## added at a full sprint, scaled by how fast you are actually going.
@export var gap_walk := 15.0
## airborne: nothing under your feet, nothing steady about your aim.
@export var gap_air := 14.0
## taken off while crouched, which is the stance the stealth rules already reward.
@export var gap_crouch := 2.5
## how far the arms open under fire, at full suppression.
@export var gap_suppressed := 14.0
@export var bloom_per_shot := 7.0
@export var bloom_max := 26.0
## pixels per second.
@export var bloom_decay := 34.0
## how fast the arms chase the stance part.
@export var follow := 12.0

const ARMS := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]

var _player: CharacterBody3D
var _weapon: Gun
var _stance := 0.0
var _bloom := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	_bind.call_deferred()


func _bind() -> void:
	_player = Player.local(get_tree())


func watch(gun: Gun) -> void:
	_weapon = gun


func bloom() -> void:
	_bloom = minf(_bloom + bloom_per_shot, bloom_max)


func spread() -> float:
	return maxf(gap_rest + _stance + _bloom + _cone_pixels(), 1.0)


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_bind()
	var want := 0.0
	if _player != null and is_instance_valid(_player):
		var speed := Vector2(_player.velocity.x, _player.velocity.z).length()
		var top: float = maxf(_player.movement.run_max_speed, 0.01)
		want += gap_walk * clampf(speed / top, 0.0, 1.0)
		if not _player.is_grounded():
			want += gap_air
		if _player.is_prone():
			want -= gap_crouch * 2.0
		elif _player.is_crouching():
			want -= gap_crouch
		if _player.has_method("suppression"):
			want += gap_suppressed * float(_player.suppression())
	_stance = lerpf(_stance, want, clampf(follow * delta, 0.0, 1.0))
	_bloom = maxf(0.0, _bloom - bloom_decay * delta)
	queue_redraw()


func _cone_pixels() -> float:
	if _weapon == null or not is_instance_valid(_weapon):
		return 0.0
	if _weapon.pellets <= 1 or _weapon.spread_deg <= 0.0:
		return 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	return (size.y * 0.5) * tan(deg_to_rad(_weapon.spread_deg)) / maxf(tan(deg_to_rad(cam.fov) * 0.5), 0.001)


func _draw() -> void:
	var mid := size * 0.5
	var gap := spread()
	for dark in [true, false]:
		var col := ink if dark else colour
		var wide := thickness + 2.0 if dark else thickness
		for arm in ARMS:
			draw_line(mid + arm * gap, mid + arm * (gap + tick), col, wide)
		draw_circle(mid, dot + (1.0 if dark else 0.0), col)
