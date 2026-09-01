class_name SfxBank
extends AudioStreamPlayer3D

## several takes of the same sound, played at random and at a slightly different pitch each time.
## one clip on repeat is what makes footsteps sound like a machine rather than a person.

@export var clips: Array[AudioStream] = []
## filled from these once godot has imported them, so a missing file leaves it silent, not broken.
@export var clip_paths: PackedStringArray = []
@export var pitch_range := Vector2(0.94, 1.07)
@export var base_db := 0.0

var _last := -1


func _ready() -> void:
	if clips.is_empty():
		for path in clip_paths:
			if ResourceLoader.exists(path):
				clips.append(load(path) as AudioStream)


## never the same take twice running, which is the difference between variety and a stutter.
func play_one(extra_db := 0.0) -> void:
	if clips.is_empty():
		return
	var index := randi() % clips.size()
	if clips.size() > 1 and index == _last:
		index = (index + 1 + randi() % (clips.size() - 1)) % clips.size()
	_last = index
	stream = clips[index]
	pitch_scale = randf_range(pitch_range.x, pitch_range.y)
	volume_db = base_db + extra_db
	play()
