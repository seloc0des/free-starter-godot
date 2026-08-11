extends TileMapLayer

# Paints the town square at runtime: grass with sprigs, a dirt plaza in the
# middle, and a tree line around the edge with its collision and the camera
# limits, all derived from one `town` rect. Resize it in the Inspector and
# everything follows. Fixed seed so screenshots don't shuffle.

const GRASS: int = 0
const GRASS_VARIANTS: PackedInt32Array = [1]
const TREE: int = 3
const DIRT: int = 4

const TILE: int = 16

# interior town rect, in tile coords
@export var town: Rect2i = Rect2i(16, 12, 56, 24)
# the plaza, in tile coords (sits inside the town rect)
@export var plaza: Rect2i = Rect2i(38, 19, 14, 8)
@export var variant_chance: float = 0.14
@export var camera_path: NodePath


func _ready() -> void:
	_paint()
	_build_tree_line()
	_clamp_camera()


func _paint() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x9066
	for y in range(town.position.y - 1, town.end.y + 1):
		for x in range(town.position.x - 1, town.end.x + 1):
			var src: int = GRASS
			if rng.randf() < variant_chance:
				src = GRASS_VARIANTS[rng.randi_range(0, GRASS_VARIANTS.size() - 1)]
			set_cell(Vector2i(x, y), src, Vector2i.ZERO)
	for y in range(plaza.position.y, plaza.end.y):
		for x in range(plaza.position.x, plaza.end.x):
			set_cell(Vector2i(x, y), DIRT, Vector2i.ZERO)
	for x in range(town.position.x - 1, town.end.x + 1):
		set_cell(Vector2i(x, town.position.y - 1), TREE, Vector2i.ZERO)
		set_cell(Vector2i(x, town.end.y), TREE, Vector2i.ZERO)
	for y in range(town.position.y, town.end.y):
		set_cell(Vector2i(town.position.x - 1, y), TREE, Vector2i.ZERO)
		set_cell(Vector2i(town.end.x, y), TREE, Vector2i.ZERO)


func _build_tree_line() -> void:
	var ix0: int = town.position.x * TILE
	var iy0: int = town.position.y * TILE
	var ix1: int = town.end.x * TILE
	var iy1: int = town.end.y * TILE
	var cx: float = (ix0 + ix1) * 0.5
	var cy: float = (iy0 + iy1) * 0.5

	var body := StaticBody2D.new()
	body.name = "TreeLine"
	add_child(body)
	_add_box(body, Vector2(cx, iy0 - TILE * 0.5), Vector2(ix1 - ix0 + TILE * 2, TILE))
	_add_box(body, Vector2(cx, iy1 + TILE * 0.5), Vector2(ix1 - ix0 + TILE * 2, TILE))
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
	cam.limit_left = town.position.x * TILE - TILE
	cam.limit_top = town.position.y * TILE - TILE
	cam.limit_right = town.end.x * TILE + TILE
	cam.limit_bottom = town.end.y * TILE + TILE
