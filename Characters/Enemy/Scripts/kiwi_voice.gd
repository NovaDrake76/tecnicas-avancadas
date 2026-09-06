class_name KiwiVoice
extends AudioStreamPlayer3D

## one recording, resampled: pitch_scale moves speed and pitch together, which is what turns one clip into a flock.
@export var voice: AudioStream
## found on its own once godot has imported it, so a missing file never breaks the scene.
@export var voice_path := "res://Sounds/kiwi/voice.wav"
@export var call_interval := Vector2(6.0, 17.0)
## the three bands do not overlap, so you can tell what happened without looking.
@export var idle_pitch := Vector2(0.94, 1.06)
@export var alert_pitch := Vector2(1.08, 1.16)
@export var down_pitch := Vector2(0.84, 0.92)
@export var idle_db := -14.0
@export var alert_db := -5.0
@export var down_db := -10.0
## the short rising call of a bird that has half noticed something: the calm band, cut short.
@export var query_db := -12.0
@export var query_clip := 0.42
## the settling call some birds give when the compound stands down.
@export var calm_db := -12.0
## a runner keeps calling as it goes, so the thing carrying the alarm can be followed by ear.
@export var runner_call_interval := 1.8

var _call_timer := 0.0
var _runner_call := 0.0


func _ready() -> void:
	if voice == null and ResourceLoader.exists(voice_path):
		voice = load(voice_path) as AudioStream
	stream = voice
	## staggered, or every bird on the map calls on the very same tick.
	_call_timer = randf_range(0.5, call_interval.y)


func tick(delta: float, calm: bool) -> void:
	if not calm:
		return
	## clamped, not only counted down, so shortening the interval in the inspector takes effect on the wait already running.
	_call_timer = minf(_call_timer, call_interval.y) - delta
	if _call_timer <= 0.0:
		_call_timer = randf_range(call_interval.x, call_interval.y)
		chirp()


func start_run() -> void:
	_runner_call = runner_call_interval


func run_tick(delta: float) -> void:
	_runner_call -= delta
	if _runner_call <= 0.0:
		_runner_call = runner_call_interval
		alarm()


func chirp() -> void:
	speak(idle_pitch, idle_db)


func query() -> void:
	speak(idle_pitch, query_db, query_clip)


func alarm() -> void:
	speak(alert_pitch, alert_db)


func settle() -> void:
	speak(Vector2(0.9, 0.97), calm_db)


func dying() -> void:
	speak(down_pitch, down_db)


func speak(band: Vector2, db: float, clip_after := 0.0) -> void:
	if stream == null:
		return
	pitch_scale = randf_range(band.x, band.y)
	volume_db = db
	play()
	if clip_after > 0.0:
		get_tree().create_timer(clip_after).timeout.connect(_clip.bind(get_playback_position(), clip_after))


func _clip(started: float, after: float) -> void:
	if playing and get_playback_position() >= started + after * 0.5:
		stop()
