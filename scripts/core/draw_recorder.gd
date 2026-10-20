class_name DrawRecorder
extends RefCounted
## Stands in for the canvas (Gfx.ci) while hosting LAN co-op: forwards each draw call to the real
## canvas and records it, so Net can replay the same frame on player 2's computer.
## Only the CanvasItem draw calls the game uses are covered.

enum { RECT, POLY, POLY_COLORS, TEX, TEX_REGION, STRING, TRANSFORM }

var target: CanvasItem
## The frame so far, as a flat list: an op followed by its arguments.
var cmds: Array = []
var _ids := {} # Texture2D -> id
var _new: Array = [] # [id, Texture2D] not yet sent

func begin(canvas: CanvasItem) -> void:
	target = canvas
	cmds = []

## Forgets which textures were sent, so a newly joined player gets them all again.
func reset() -> void:
	_ids.clear()
	_new.clear()

func take_new_textures() -> Array:
	var out := _new
	_new = []
	return out

func _tex(t: Texture2D) -> int:
	if not _ids.has(t):
		_ids[t] = _ids.size()
		_new.append([_ids[t], t])
	return _ids[t]

func draw_rect(rect: Rect2, color: Color, filled := true, width := -1.0) -> void:
	target.draw_rect(rect, color, filled, width)
	cmds.append_array([RECT, rect, color])

func draw_colored_polygon(points: PackedVector2Array, color: Color, uvs := PackedVector2Array(), texture: Texture2D = null) -> void:
	target.draw_colored_polygon(points, color, uvs, texture)
	cmds.append_array([POLY, points, color])

func draw_polygon(points: PackedVector2Array, colors: PackedColorArray, uvs := PackedVector2Array(), texture: Texture2D = null) -> void:
	target.draw_polygon(points, colors, uvs, texture)
	cmds.append_array([POLY_COLORS, points, colors])

func draw_texture_rect(texture: Texture2D, rect: Rect2, tile: bool, modulate := Color.WHITE, transpose := false) -> void:
	target.draw_texture_rect(texture, rect, tile, modulate, transpose)
	cmds.append_array([TEX, _tex(texture), rect, tile, modulate])

func draw_texture_rect_region(texture: Texture2D, rect: Rect2, src_rect: Rect2, modulate := Color.WHITE, transpose := false, clip_uv := true) -> void:
	target.draw_texture_rect_region(texture, rect, src_rect, modulate, transpose, clip_uv)
	cmds.append_array([TEX_REGION, _tex(texture), rect, src_rect, modulate])

## Always drawn with the game font (Gfx.font()).
func draw_string(font: Font, pos: Vector2, text: String, alignment := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, font_size := 16, modulate := Color.WHITE) -> void:
	target.draw_string(font, pos, text, alignment, width, font_size, modulate)
	cmds.append_array([STRING, pos, text, font_size, modulate])

func draw_set_transform(pos: Vector2, rotation := 0.0, scale := Vector2.ONE) -> void:
	target.draw_set_transform(pos, rotation, scale)
	cmds.append_array([TRANSFORM, pos, rotation, scale])

## Draws a recorded frame. textures: id -> Texture2D; calls whose texture hasn't arrived are skipped.
static func replay(frame: Array, canvas: CanvasItem, textures: Dictionary) -> void:
	var font := Gfx.font()
	var i := 0
	while i < frame.size():
		match int(frame[i]):
			RECT:
				canvas.draw_rect(frame[i + 1], frame[i + 2])
				i += 3
			POLY:
				canvas.draw_colored_polygon(frame[i + 1], frame[i + 2])
				i += 3
			POLY_COLORS:
				canvas.draw_polygon(frame[i + 1], frame[i + 2])
				i += 3
			TEX:
				var t: Texture2D = textures.get(frame[i + 1])
				if t:
					canvas.draw_texture_rect(t, frame[i + 2], frame[i + 3], frame[i + 4])
				i += 5
			TEX_REGION:
				var t: Texture2D = textures.get(frame[i + 1])
				if t:
					canvas.draw_texture_rect_region(t, frame[i + 2], frame[i + 3], frame[i + 4])
				i += 5
			STRING:
				canvas.draw_string(font, frame[i + 1], frame[i + 2], HORIZONTAL_ALIGNMENT_LEFT, -1, frame[i + 3], frame[i + 4])
				i += 5
			TRANSFORM:
				canvas.draw_set_transform(frame[i + 1], frame[i + 2], frame[i + 3])
				i += 4
			_:
				break
	canvas.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
