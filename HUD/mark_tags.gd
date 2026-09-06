class_name MarkTags
extends Control

## the tags the binoculars leave behind: one diamond per marked bird, with what it is and how far
## away, drawn wherever that bird is now and through whatever is in front of it.
##
## drawing them THROUGH cover is the whole value and it is deliberate. a mark you can only see when
## you can already see the bird tells you nothing you did not have; the reason to spend twenty
## seconds glassing a compound from a hill is to still know where the mortar crew is once you are
## down among the crates and cannot see anything at all. that is what every game this one reads from
## does with a tag, and it is what makes recon a plan rather than a look.
##
## it is the same screen-space job the extraction marker does, and it inherits that node's two hard
## lessons: `unproject_position` MIRRORS a point that is behind the camera through the centre, so the
## sign of z in the camera's own space is what says in front or behind; and a tag is simply not drawn
## when it is off the frame rather than clamped to the edge, because a mark's whole claim is "the
## thing is HERE", and an icon pinned to the side of the screen saying that is a lie about a position.

const INK := Color(0.98, 0.86, 0.35)
const DIM := Color(0.98, 0.86, 0.35, 0.55)
## the diamond's half height in pixels at the near end, shrinking with distance so a compound full
## of tags does not become a wall of icons.
const NEAR := 11.0
const FAR := 6.0

var _rows: Array = []
var _optic: BinocularView


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	## worked out here and not in _draw, the same rule the extraction marker follows: a headless
	## probe can read a position and cannot read a drawing.
	var was := _rows.size()
	_rows.clear()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		queue_redraw()
		return
	var eye := Player.local(get_tree())
	## while the binoculars are up the world is only visible through the lens, so a tag is only
	## honest inside it. photographed: one sat out in the black surround and read as a bug.
	if _optic == null or not is_instance_valid(_optic):
		_optic = get_parent().find_child("BinocularView", true, false) as BinocularView
	var field := _optic.field_rect() if _optic != null else Rect2(Vector2.ZERO, size)
	for node in get_tree().get_nodes_in_group("kiwi"):
		var bird := node as Kiwi
		if bird == null or not is_instance_valid(bird) or not bird.is_marked():
			continue
		## clear of the bird rather than on it: at seven metres a kiwi fills enough of the frame that
		## a diamond at its shoulder is a diamond nobody can read.
		var at := bird.global_position + Vector3.UP * 0.95
		## the camera's own space, because a point behind the eye unprojects to the wrong side of the
		## screen and a tag that led the player the wrong way would be worse than no tag.
		var local := cam.to_local(at)
		if local.z >= -0.2:
			continue
		var where := cam.unproject_position(at)
		if not field.has_point(where):
			continue
		var away := at.distance_to(eye.global_position) if eye != null else -local.z
		_rows.append({"at": where, "name": bird.kind_name(), "away": away,
			"fade": clampf(bird.mark_left() / 3.0, 0.25, 1.0)})
	if was != _rows.size() or not _rows.is_empty():
		queue_redraw()


## for the probe: how many tags are on screen right now.
func shown() -> int:
	return _rows.size()


## for the probe: where a named kind is drawn, or a huge vector when it is not on screen.
func spot_of(kind: String) -> Vector2:
	for row in _rows:
		if String(row["name"]) == kind:
			return row["at"] as Vector2
	return Vector2.ONE * 99999.0


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for row in _rows:
		var at: Vector2 = row["at"]
		var away: float = row["away"]
		## a tag fades out over its last three seconds rather than blinking off, so a player watching
		## one go is told the clock is running rather than that the bird moved.
		var alpha: float = row["fade"]
		var r: float = lerpf(NEAR, FAR, clampf(away / 90.0, 0.0, 1.0))
		var ink := Color(INK, alpha)
		draw_polyline(PackedVector2Array([
			at + Vector2(0.0, -r), at + Vector2(r * 0.72, 0.0),
			at + Vector2(0.0, r), at + Vector2(-r * 0.72, 0.0),
			at + Vector2(0.0, -r)]), ink, 2.0)
		if font == null:
			continue
		var label := "%s  %d m" % [String(row["name"]), int(round(away))]
		var wide := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15).x
		## above the diamond, so the words are never printed across the thing they are naming.
		font.draw_string(get_canvas_item(), at + Vector2(-wide * 0.5, -r - 7.0), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(DIM, alpha))
