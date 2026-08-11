extends TileMapLayer

# Paints the dungeon room at runtime: random floor variants inside, wall ring
# around the edge, plus the wall collision and camera limits derived from the
# same rect. One `room` export drives all three, so resizing the room in the
# Inspector can't desync them. Fixed seed so screenshots don't shuffle.

# tile source ids in dungeon_tiles.tres
const FLOOR_MAIN: int = 0
const FLOOR_VARIANTS: PackedInt32Array = [1, 2, 3, 4, 5, 6, 7]
const WALL_MID: int = 8
const WALL_TOP: int = 9
const EDGE_MID_LEFT: int = 10
const EDGE_MID_RIGHT: int = 11
const EDGE_TOP_LEFT: int = 12
const EDGE_TOP_RIGHT: int = 13
const EDGE_BOTTOM_LEFT: int = 14
const EDGE_BOTTOM_RIGHT: int = 15

const TILE: int = 16

# interior floor rect, in tile coords
@export var room: Rect2i = Rect2i(16, 13, 56, 23)
@export var variant_chance: float = 0.18
# camera to clamp to the room; leave empty to manage limits yourself
@export var camera_path: NodePath


func _ready() -> void:
	_paint()
	_build_walls()
	_clamp_camera()


func _paint() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x72
	var x0: int = room.position.x
	var y0: int = room.position.y
	var x1: int = room.end.x - 1
	var y1: int = room.end.y - 1

	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var src: int = FLOOR_MAIN
			if rng.randf() < variant_chance:
				src = FLOOR_VARIANTS[rng.randi_range(0, FLOOR_VARIANTS.size() - 1)]
			set_cell(Vector2i(x, y), src, Vector2i.ZERO)

	# north wall: cap row above face row
	for x in range(x0, x1 + 1):
		set_cell(Vector2i(x, y0 - 2), WALL_TOP, Vector2i.ZERO)
		set_cell(Vector2i(x, y0 - 1), WALL_MID, Vector2i.ZERO)
	# south wall: cap on the room edge, face spills below it
	for x in range(x0, x1 + 1):
		set_cell(Vector2i(x, y1 + 1), WALL_TOP, Vector2i.ZERO)
		set_cell(Vector2i(x, y1 + 2), WALL_MID, Vector2i.ZERO)
	# side columns
	for y in range(y0 - 1, y1 + 1):
		set_cell(Vector2i(x0 - 1, y), EDGE_MID_LEFT, Vector2i.ZERO)
		set_cell(Vector2i(x1 + 1, y), EDGE_MID_RIGHT, Vector2i.ZERO)
	# corners
	set_cell(Vector2i(x0 - 1, y0 - 2), EDGE_TOP_LEFT, Vector2i.ZERO)
	set_cell(Vector2i(x1 + 1, y0 - 2), EDGE_TOP_RIGHT, Vector2i.ZERO)
	set_cell(Vector2i(x0 - 1, y1 + 1), EDGE_BOTTOM_LEFT, Vector2i.ZERO)
	set_cell(Vector2i(x1 + 1, y1 + 1), EDGE_BOTTOM_RIGHT, Vector2i.ZERO)


func _build_walls() -> void:
	var ix0: int = room.position.x * TILE
	var iy0: int = room.position.y * TILE
	var ix1: int = room.end.x * TILE
	var iy1: int = room.end.y * TILE
	var cx: float = (ix0 + ix1) * 0.5
	var cy: float = (iy0 + iy1) * 0.5

	var body := StaticBody2D.new()
	body.name = "Walls"
	add_child(body)
	# top face row / bottom cap row, stretched to cover the corner tiles
	_add_box(body, Vector2(cx, iy0 - TILE * 0.5), Vector2(ix1 - ix0 + TILE * 2, TILE))
	_add_box(body, Vector2(cx, iy1 + TILE * 0.5), Vector2(ix1 - ix0 + TILE * 2, TILE))
	# side columns
	_add_box(body, Vector2(ix0 - TILE * 0.5, cy), Vector2(TILE, iy1 - iy0))
	_add_box(body, Vector2(ix1 + TILE * 0.5, cy), Vector2(TILE, iy1 - iy0))


func _add_box(body: StaticBody2D, pos: Vector2, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = pos
	body.add_child(col)


func _clamp_camera() -> void:
	if camera_path.is_empty():
		return
	var cam := get_node_or_null(camera_path) as Camera2D
	if cam == null:
		return
	cam.limit_left = room.position.x * TILE - TILE
	cam.limit_top = room.position.y * TILE - TILE * 2
	cam.limit_right = room.end.x * TILE + TILE
	cam.limit_bottom = room.end.y * TILE + TILE * 2
