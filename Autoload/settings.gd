extends Node

## the settings, loaded at boot, pushed into the real engine systems, saved on every change.
## the options panel is only a view onto this. nothing else needs to know a config file exists.

signal changed

enum WindowMode { WINDOWED, FULLSCREEN, BORDERLESS }

const VSYNC_MODES := [DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED, DisplayServer.VSYNC_ADAPTIVE]
const FPS_CAPS := [0, 60, 120, 144, 240]

## a var rather than a const, so a probe can point it at a throwaway file and never touch yours.
var path := "user://settings.cfg"

var window_mode := WindowMode.WINDOWED
var vsync := 1
var max_fps := 0
var master_volume := 0.8
var music_volume := 0.8
var sfx_volume := 1.0
## a multiplier over the player's tuned base, never the raw number. storing the raw value would mean
## a player who nudged it once could never get the default back, and it would compound per spawn.
var look_scale := 1.0
var invert_look := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_from_disk()
	apply_all()


func apply_all() -> void:
	_apply_video()
	_apply_audio()
	changed.emit()


func commit() -> void:
	apply_all()
	save()


## headless has no window, and every window call there is an error rather than a no op.
func _apply_video() -> void:
	Engine.max_fps = max_fps
	if DisplayServer.get_name() == "headless":
		return
	## a game launched minimized stays minimized. forcing the saved fullscreen on it would drag a
	## window nobody asked to see over whatever is on the screen.
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		DisplayServer.window_set_vsync_mode(VSYNC_MODES[clampi(vsync, 0, 2)])
		return
	match window_mode:
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		WindowMode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(VSYNC_MODES[clampi(vsync, 0, 2)])


func _apply_audio() -> void:
	var master := AudioServer.get_bus_index(&"Master")
	if master >= 0:
		AudioServer.set_bus_volume_db(master, linear_to_db(clampf(master_volume, 0.0001, 1.0)))
	## the music and effects sliders are one voice each in the mix, on top of the layout's own levels,
	## so they never compound and never fight the ducking
	Sfx.set_gain(&"Music", &"settings", linear_to_db(clampf(music_volume, 0.0001, 1.0)))
	Sfx.set_gain(&"SFX", &"settings", linear_to_db(clampf(sfx_volume, 0.0001, 1.0)))


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "window_mode", window_mode)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "max_fps", max_fps)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("controls", "look_scale", look_scale)
	cfg.set_value("controls", "invert_look", invert_look)
	cfg.save(path)


func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	window_mode = clampi(int(cfg.get_value("video", "window_mode", window_mode)), 0, 2) as WindowMode
	vsync = clampi(int(cfg.get_value("video", "vsync", vsync)), 0, 2)
	max_fps = int(cfg.get_value("video", "max_fps", max_fps))
	master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cfg.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	look_scale = clampf(float(cfg.get_value("controls", "look_scale", look_scale)), 0.25, 3.0)
	invert_look = bool(cfg.get_value("controls", "invert_look", invert_look))
