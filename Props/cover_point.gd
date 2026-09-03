class_name CoverPoint
extends Marker3D

## a spot a hunting kiwi may run to. authored level data like Prop: place one where a crate or a
## 1.6 m barricade stands between it and the likely approach, six to ten per level is plenty. the
## squad picks the unclaimed one that is hidden from the player and, for a flanker, closer to them
## than the bird already is. there is no navigation in this project, every kiwi runs a straight
## line, so these are how the squad gets round you without a navmesh. a level with none still
## works: the squad falls back to a step to the side.


func _ready() -> void:
	add_to_group("cover_point")
