extends TileMapLayer

# Paints the forest clearing at runtime: grass with the odd flower patch, a
# tree line around the edge, plus the tree-line collision and camera limits,
# all derived from one `clearing` rect. Same idea as the dungeon's Ground node:
# resize the rect in the Inspector and everything follows. Fixed seed so
# screenshots don't shuffle.

const GRASS: int = 0
# sprigs only — the flowered tile reads as a pickup from a distance
const GRASS_VARIANTS: PackedInt32Array = [1]
const TREE: int = 3

const TILE: int = 16

# interior clearing rect, in tile coords
@export var clearing: Rect2i = Rect2i(16, 12, 56, 24)
@export var variant_chance: float = 0.16
# camera to clamp to the clearing; leave empty to manage limits yourself
@export var camera_path: NodePath


func _ready() -> void:
	_paint()
	_build_tree_line()
	_clamp_camera()


func _paint() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x7077
	# grass runs under the tree line too, so the border trees sit on green
	for y in range(clearing.position.y - 1, clearing.end.y + 1):
		for x in range(clearing.position.x - 1, clearing.end.x + 1):
			var src: int = GRASS
			if rng.randf() < variant_chance:
				src = GRASS_VARIANTS[rng.randi_range(0, GRASS_VARIANTS.size() - 1)]
			set_cell(Vector2i(x, y), src, Vector2i.ZERO)
	# the tree line
	for x in range(clearing.position.x - 1, clearing.end.x + 1):
		set_cell(Vector2i(x, clearing.position.y - 1), TREE, Vector2i.ZERO)
		set_cell(Vector2i(x, clearing.end.y), TREE, Vector2i.ZERO)
	for y in range(clearing.position.y, clearing.end.y):
		set_cell(Vector2i(clearing.position.x - 1, y), TREE, Vector2i.ZERO)
		set_cell(Vector2i(clearing.end.x, y), TREE, Vector2i.ZERO)


func _build_tree_line() -> void:
	var ix0: int = clearing.position.x * TILE
	var iy0: int = clearing.position.y * TILE
	var ix1: int = clearing.end.x * TILE
	var iy1: int = clearing.end.y * TILE
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
	cam.limit_left = clearing.position.x * TILE - TILE
	cam.limit_top = clearing.position.y * TILE - TILE
	cam.limit_right = clearing.end.x * TILE + TILE
	cam.limit_bottom = clearing.end.y * TILE + TILE
