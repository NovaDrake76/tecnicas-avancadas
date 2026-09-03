class_name Crosshair
extends Control

## four ticks and a dot, drawn rather than typed, and the ticks move.
##
## **the dot never moves and never grows, because that is where the bb goes.** this game has no
## random bullet cone for a rifle: `probe_aim` fires and asserts the bb stops within 5 cm of the
## crosshair. so the arms do not claim an accuracy penalty that does not exist -- they show how much
## your aim is being THROWN ABOUT, which is real: recoil rotates the camera, running and landing bob
## it, and every one of those moves the muzzle with it. open arms mean "you are not settled", and
## the dot underneath stays honest about where this shot lands.
##
## the one exception is a weapon that really does have a cone: the shotgun's `spread_deg` is
## projected into pixels at the current fov and added, so its wider reticle IS its pellet spread.

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
@export var bloom_per_shot := 7.0
@export var bloom_max := 26.0
## pixels per second. a burst blooms faster than this closes, which is the whole point of a burst.
@export var bloom_decay := 34.0
## how fast the arms chase the stance part. the bloom is instant on purpose.
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


## re-found whenever the reference goes bad, not once. quitting to the menu frees the player and
## spawns another, and a reticle bound to the old one would stop reacting for the rest of the
## session without ever looking broken. the vision cone re-finds its target exactly like this.
func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as CharacterBody3D


## the hud hands over whichever weapon is in hand, because only that one's cone is on screen.
func watch(gun: Gun) -> void:
	_weapon = gun


## one shot's worth of kick. the hud calls this off the weapon's own fired signal, so it cannot
## drift from the number of bbs that actually left the barrel.
func bloom() -> void:
	_bloom = minf(_bloom + bloom_per_shot, bloom_max)


## how far the arms are from the middle, in pixels. what the probe measures. the weapon's cone is
## worked out here rather than cached in _process, so the answer is right the instant the weapon
## changes instead of one frame later.
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
		if _player.is_crouching():
			want -= gap_crouch
	_stance = lerpf(_stance, want, clampf(follow * delta, 0.0, 1.0))
	_bloom = maxf(0.0, _bloom - bloom_decay * delta)
	queue_redraw()


## a cone is an angle and the screen is a projection, so this is where that angle lands in pixels.
## godot's fov is the VERTICAL one, which is why the height is the side that matters.
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
	## dark pass first, then the light one on top of it. two passes rather than an outline, because
	## a line has no outline to give it.
	for dark in [true, false]:
		var col := ink if dark else colour
		var wide := thickness + 2.0 if dark else thickness
		for arm in ARMS:
			draw_line(mid + arm * gap, mid + arm * (gap + tick), col, wide)
		draw_circle(mid, dot + (1.0 if dark else 0.0), col)
