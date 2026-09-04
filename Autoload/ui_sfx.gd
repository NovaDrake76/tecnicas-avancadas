extends Node

## every sound the interface makes, from one place. buttons are hooked as they enter the tree, so a
## new menu gets hover and click for free; the few sounds that mean something (bought, installed,
## deploy, refused) are asked for by name by the screen that knows what happened.
## non positional on purpose: the interface is not in the world.

const BANKS := {
	"hover": ["res://Sounds/ui/hover_1.ogg"],
	"click": ["res://Sounds/ui/click_1.ogg", "res://Sounds/ui/click_2.ogg", "res://Sounds/ui/click_3.ogg"],
	"confirm": ["res://Sounds/ui/confirm_1.ogg"],
	"deploy": ["res://Sounds/ui/deploy_1.ogg"],
	"switch": ["res://Sounds/ui/switch_1.ogg"],
	"back": ["res://Sounds/ui/back_1.ogg"],
	"buy": ["res://Sounds/ui/buy_1.ogg"],
	"install": ["res://Sounds/ui/install_1.ogg"],
	"error": ["res://Sounds/ui/error_1.ogg"],
	"tick": ["res://Sounds/ui/tick_1.ogg", "res://Sounds/ui/tick_2.ogg", "res://Sounds/ui/tick_3.ogg"],
	"stamp": ["res://Sounds/ui/stamp_1.ogg"],
	"objective": ["res://Sounds/ui/objective_1.ogg"],
	"bench_open": ["res://Sounds/ui/bench_open_1.ogg"],
	"bench_close": ["res://Sounds/ui/bench_close_1.ogg"],
	"page": ["res://Sounds/ui/page_1.ogg"],
	## deliberately EMPTY, after Nathan listened: leaving the pause menu says nothing, the game coming
	## back is what says it. its own name rather than "back", so the bench and the board keep theirs.
	"pause_close": [],
}
## the clips are normalised to a quiet body level already (the build script does that), so these are
## small offsets between them. the hover tick is the one sound that plays a hundred times, so it
## sits far under the rest.
const GAIN_DB := {"hover": -12.0, "click": -4.0, "confirm": -4.0, "deploy": 0.0, "switch": -6.0,
	"back": -4.0, "buy": -2.0, "install": -4.0, "error": -4.0, "tick": -6.0, "stamp": -4.0, "objective": -6.0,
	"bench_open": -6.0, "bench_close": -6.0, "page": -6.0}
## buttons with this meta stay silent, for the ones that play their own sound.
const QUIET := &"ui_quiet"
## banks that are empty ON PURPOSE. the name stays so the call site stays and a clip can go back in;
## the smoke probe asserts these are empty and every other bank is not, so a missing file is still
## a failure and a cut is not.
const SILENT := ["pause_close"]

var _streams := {}
var _last := {}
var _players: Array[AudioStreamPlayer] = []
var _hover_at := 0.0
var _played := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for sound in BANKS:
		var takes: Array[AudioStream] = []
		for path in BANKS[sound]:
			if ResourceLoader.exists(path):
				takes.append(load(path))
		_streams[sound] = takes
	for _i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = &"UI"
		add_child(p)
		_players.append(p)
	get_tree().node_added.connect(_on_node_added)
	for n in _walk(get_tree().root):
		_on_node_added(n)


func has(sound: String) -> bool:
	return _streams.has(sound) and not (_streams[sound] as Array).is_empty()


## how many times a sound has played, for the probe.
func count(sound: String) -> int:
	return int(_played.get(sound, 0))


func play(sound: String) -> void:
	if not has(sound):
		return
	var takes: Array = _streams[sound]
	var pick := randi() % takes.size()
	if takes.size() > 1 and pick == int(_last.get(sound, -1)):
		pick = (pick + 1) % takes.size()
	_last[sound] = pick
	_played[sound] = count(sound) + 1
	var player := _free_player()
	player.stream = takes[pick]
	player.volume_db = float(GAIN_DB.get(sound, -6.0))
	player.pitch_scale = randf_range(0.97, 1.03)
	player.play()


func _free_player() -> AudioStreamPlayer:
	for p in _players:
		if not p.playing:
			return p
	return _players[0]


func _on_node_added(node: Node) -> void:
	if node is BaseButton and not node.has_meta(QUIET):
		var b := node as BaseButton
		if not b.mouse_entered.is_connected(_on_hover):
			b.mouse_entered.connect(_on_hover)
			b.pressed.connect(func() -> void: play("click"))


## a row of buttons swept by the mouse fires one tick, not a burst.
func _on_hover() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _hover_at < 0.05:
		return
	_hover_at = now
	play("hover")


func _walk(node: Node) -> Array:
	var out := [node]
	for c in node.get_children():
		out.append_array(_walk(c))
	return out
