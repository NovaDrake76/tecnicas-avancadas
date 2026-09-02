extends Node

## every sound the interface makes, from one place. buttons are hooked as they enter the tree, so a
## new menu gets hover and click for free; the few sounds that mean something (bought, installed,
## deploy, refused) are asked for by name by the screen that knows what happened.
## non positional on purpose: the interface is not in the world.

const BANKS := {
	"hover": ["res://Sounds/ui_hover.ogg"],
	"click": ["res://Sounds/ui_click_1.ogg", "res://Sounds/ui_click_2.ogg", "res://Sounds/ui_click_3.ogg"],
	"confirm": ["res://Sounds/ui_confirm.ogg"],
	"deploy": ["res://Sounds/ui_deploy.ogg"],
	"switch": ["res://Sounds/ui_switch.ogg"],
	"back": ["res://Sounds/ui_back.ogg"],
	"buy": ["res://Sounds/ui_buy.ogg"],
	"install": ["res://Sounds/ui_install.ogg"],
	"error": ["res://Sounds/ui_error.ogg"],
}
## the hover tick is the one sound that plays a hundred times, so it sits far under the rest.
const GAIN_DB := {"hover": -22.0, "click": -6.0, "confirm": -6.0, "deploy": -2.0, "switch": -10.0,
	"back": -8.0, "buy": -4.0, "install": -6.0, "error": -8.0}
## buttons with this meta stay silent, for the ones that play their own sound.
const QUIET := &"ui_quiet"

var _streams := {}
var _last := {}
var _players: Array[AudioStreamPlayer] = []
var _hover_at := 0.0
var _played := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for name in BANKS:
		var takes: Array[AudioStream] = []
		for path in BANKS[name]:
			if ResourceLoader.exists(path):
				takes.append(load(path))
		_streams[name] = takes
	for _i in 4:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		_players.append(p)
	get_tree().node_added.connect(_on_node_added)
	for n in _walk(get_tree().root):
		_on_node_added(n)


func has(name: String) -> bool:
	return _streams.has(name) and not (_streams[name] as Array).is_empty()


## how many times a sound has played, for the probe.
func count(name: String) -> int:
	return int(_played.get(name, 0))


func play(name: String) -> void:
	if not has(name):
		return
	var takes: Array = _streams[name]
	var pick := randi() % takes.size()
	if takes.size() > 1 and pick == int(_last.get(name, -1)):
		pick = (pick + 1) % takes.size()
	_last[name] = pick
	_played[name] = count(name) + 1
	var player := _free_player()
	player.stream = takes[pick]
	player.volume_db = float(GAIN_DB.get(name, -6.0))
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
