extends Node

## the score: the ambience bed under a level, the tension stems that come in with the alarm, the
## stingers on the way up and down, and the menu theme. it reads the alarm and the run and owns no
## rule of its own. the stealth games this leans on keep music out of the sneaking, so CALM is bed
## only: a melodic entry MEANS something. the stems come in with SEARCHING and ALARM and go out
## again as the alarm decays, over seconds, so the drop itself is something the player can hear.

const STEM_UP := 2.5
const STEM_DOWN := 4.0
const BED_UP := 3.0
const BED_DOWN := 1.5
const SILENT := -80.0
const SEARCH_UNDER_ALARM := -7.0

## the beds and the stems, by name: path, bus, level. an EMPTY path is one left deliberately silent.
## Nathan cut the outdoor ambience, the birds and the safe house room tone on the first listening
## pass; the players, the fades and the level hooks all stay, so a path put back is the whole of
## turning one on again.
const BEDS := {
	"outdoors": ["", &"Ambience", -4.0],
	"wind": ["", &"Ambience", -10.0],
	"room": ["", &"Ambience", -6.0],
	"search": ["res://Sounds/music/stem_search_loop.ogg", &"Music", -6.0],
	"alarm": ["res://Sounds/music/stem_alarm_loop.ogg", &"Music", -6.0],
	"menu": ["res://Sounds/music/menu_intro.ogg", &"Music", -6.0],
}

var _outdoors: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _room: AudioStreamPlayer
var _search: AudioStreamPlayer
var _alarm: AudioStreamPlayer
var _menu: AudioStreamPlayer
var _mark: AudioStreamPlayer
var _stage: int = 0
var _tweens := {}
var _reinforce_told := false
var _stings := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_outdoors = _bed("outdoors")
	_wind = _bed("wind")
	_room = _bed("room")
	_search = _bed("search")
	_alarm = _bed("alarm")
	_menu = _bed("menu")
	_mark = Sfx.attach_2d(&"mark_tone", self)
	Alarm.stage_changed.connect(_on_stage)
	Alarm.reinforcements_changed.connect(_on_reinforcements)
	Alarm.marked_changed.connect(_on_marked)
	Run.level_started.connect(_on_level_started)
	Run.armory_entered.connect(_on_armory_entered)
	Run.level_cleared.connect(_on_level_cleared)
	Run.level_failed.connect(_on_level_failed)
	Run.run_finished.connect(_on_run_finished)
	Run.state_changed.connect(_on_run_state)


func _bed(bed: String) -> AudioStreamPlayer:
	var row: Array = BEDS[bed]
	var path := String(row[0])
	var bus: StringName = row[1]
	var db := float(row[2])
	var p := AudioStreamPlayer.new()
	if path != "" and ResourceLoader.exists(path):
		var s := load(path) as AudioStream
		if s is AudioStreamOggVorbis and path.ends_with("_loop.ogg"):
			(s as AudioStreamOggVorbis).loop = true
		p.stream = s
	p.bus = bus
	p.volume_db = SILENT
	p.set_meta(&"full_db", db)
	add_child(p)
	return p


# ---------------------------------------------------------------- the level

func _on_level_started(_index: int, _name: String) -> void:
	_stop_menu()
	_stage = Alarm.stage
	_reinforce_told = false
	_fade(_room, SILENT, BED_DOWN, true)
	_fade(_outdoors, _full(_outdoors), BED_UP)
	_fade(_wind, _full(_wind), BED_UP)
	_stems_for(Alarm.stage, 0.6)
	UiSfx.play("objective")


func _on_armory_entered(_next: int, _name: String) -> void:
	_stop_menu()
	_fade(_outdoors, SILENT, BED_DOWN, true)
	_fade(_wind, SILENT, BED_DOWN, true)
	_fade(_search, SILENT, BED_DOWN, true)
	_fade(_alarm, SILENT, BED_DOWN, true)
	_fade(_room, _full(_room), BED_UP)
	_mark.stop()


func _on_level_cleared(_index: int, _summary: Dictionary) -> void:
	_fade(_search, SILENT, 1.0, true)
	_fade(_alarm, SILENT, 1.0, true)
	_mark.stop()
	Sfx.play_2d(&"sting_mission_clear")


func _on_level_failed(_index: int, _summary: Dictionary) -> void:
	_fade(_search, SILENT, 1.0, true)
	_fade(_alarm, SILENT, 1.0, true)
	_mark.stop()
	Sfx.play_2d(&"sting_mission_fail")


func _on_run_finished(_summary: Dictionary) -> void:
	Sfx.play_2d(&"sting_mission_clear")


func _on_run_state(_state: int) -> void:
	pass


# ---------------------------------------------------------------- the alarm

## up a stage: a stinger and a stem in. down to calm: a soft resolution and the stems out, slowly.
## the stems are looping players kept alive at silence, so a stage change is only a fade.
func _on_stage(stage: int) -> void:
	if Run.state != Run.State.PLAYING:
		_stage = stage
		return
	if stage > _stage:
		Sfx.play_2d(&"sting_alarm" if stage == Alarm.Stage.ALARM else &"sting_notice")
		_count(&"sting_alarm" if stage == Alarm.Stage.ALARM else &"sting_notice")
	elif stage == Alarm.Stage.CALM and _stage != Alarm.Stage.CALM:
		Sfx.play_2d(&"sting_clear")
		_count(&"sting_clear")
	_stage = stage
	_stems_for(stage, STEM_UP if stage > 0 else STEM_DOWN)


func _stems_for(stage: int, seconds: float) -> void:
	match stage:
		Alarm.Stage.SEARCHING:
			_fade(_search, _full(_search), seconds)
			_fade(_alarm, SILENT, seconds, true)
		Alarm.Stage.ALARM:
			_fade(_search, _full(_search) + SEARCH_UNDER_ALARM, seconds)
			_fade(_alarm, _full(_alarm), seconds)
		_:
			_fade(_search, SILENT, seconds, true)
			_fade(_alarm, SILENT, seconds, true)


func _on_reinforcements(seconds_left: float) -> void:
	if seconds_left > 0.0 and not _reinforce_told:
		_reinforce_told = true
		Sfx.play_2d(&"sting_reinforce")
	elif seconds_left <= 0.0:
		_reinforce_told = false


## the gunship has you in its light: a tone in the head for as long as it does. it is the one
## non-diegetic warning in the game, because the thing warning you is 22 m over your head.
func _on_marked(marked: bool) -> void:
	if _mark.stream == null:
		return
	if marked and not _mark.playing:
		_mark.play()
	elif not marked:
		_mark.stop()


# ---------------------------------------------------------------- the menu

## the main menu's theme: an intro, then a loop.
func menu_theme() -> void:
	if _menu.stream == null or _menu.playing:
		return
	_menu.volume_db = _full(_menu)
	_menu.play()
	if not _menu.finished.is_connected(_menu_loop):
		_menu.finished.connect(_menu_loop)


func _menu_loop() -> void:
	var path := "res://Sounds/music/menu_loop.ogg"
	if not ResourceLoader.exists(path):
		return
	var s := load(path) as AudioStreamOggVorbis
	if s != null:
		s.loop = true
	_menu.stream = s
	_menu.play()


func _stop_menu() -> void:
	if _menu.playing:
		_fade(_menu, SILENT, 1.2, true)


# ---------------------------------------------------------------- probes

## a bed or stem that has been left empty on purpose. one with a path that failed to load is NOT
## silent by this answer, so a clip going missing is still a failure and a cut is not.
func is_cut(bed: String) -> bool:
	return BEDS.has(bed) and String((BEDS[bed] as Array)[0]) == ""


## the current level of a stem or bed, by name, for a probe. SILENT when off.
func level(bed: String) -> float:
	var p := _player(bed)
	return p.volume_db if p != null and p.playing else SILENT


## the clip a bed or stem would play, for a probe: null when it was cut or failed to load.
func stream_of(bed: String) -> AudioStream:
	var p := _player(bed)
	return p.stream if p != null else null


func is_on(bed: String) -> bool:
	var p := _player(bed)
	return p != null and p.playing and p.volume_db > SILENT + 1.0


func target(bed: String) -> float:
	return float(_targets.get(bed, SILENT))


func stings(sting: StringName) -> int:
	return int(_stings.get(sting, 0))


var _targets := {}


func _player(bed: String) -> AudioStreamPlayer:
	match bed:
		"outdoors": return _outdoors
		"wind": return _wind
		"room": return _room
		"search": return _search
		"alarm": return _alarm
		"menu": return _menu
		"mark": return _mark
	return null


func _name_of(p: AudioStreamPlayer) -> String:
	for n in ["outdoors", "wind", "room", "search", "alarm", "menu", "mark"]:
		if _player(n) == p:
			return n
	return ""


func _count(sting: StringName) -> void:
	_stings[sting] = stings(sting) + 1


func _full(p: AudioStreamPlayer) -> float:
	return float(p.get_meta(&"full_db", 0.0))


## a fade that starts a silent player and stops one that has reached silence, so nothing loops at
## -80 dB for a whole mission.
func _fade(p: AudioStreamPlayer, to_db: float, seconds: float, stop_after := false) -> void:
	if p == null or p.stream == null:
		return
	_targets[_name_of(p)] = to_db
	var old: Tween = _tweens.get(p)
	if old != null and old.is_valid():
		old.kill()
	if not p.playing:
		if to_db <= SILENT + 0.5:
			return
		p.volume_db = SILENT
		p.play()
	var tw := create_tween()
	tw.tween_property(p, "volume_db", to_db, maxf(seconds, 0.01))
	if stop_after:
		tw.tween_callback(func() -> void:
			if p.volume_db <= SILENT + 0.5:
				p.stop())
	_tweens[p] = tw
