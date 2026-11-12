class_name HealthLite
extends Node

# Health component. Drop it on any body; other nodes call take_damage / heal.
# Pure logic + signals — no physics, no dependencies.

signal damaged(amount: float, source: Node)
signal healed(amount: float)
signal died

@export var max_health: float = 100.0
## Removes the character (the node this Health sits on) from the game when it dies.
@export var remove_on_death: bool = false
## Flashes the character (the node this Health sits on) when a hit hurts it but doesn't
## kill it, so you can see hits land before anything else is set up. Works on 2D and 3D characters.
## Untick it if yours already has a hit effect of its own.
@export var flash_on_hit: bool = true
## The colour of that flash, multiplied over the character for a moment before it fades.
## Above 1 brightens: the default flashes any sprite white. A tint like red only shows on
## sprites that have that colour in them (a green one just goes dark). On a 3D character the
## colour is laid over every mesh and fades out, so the default flashes white and red flashes red.
## Sprite3D and Label3D children are tinted instead, like a 2D sprite, and particles are left alone.
## Meshes with cut-out edges (hair cards, leaves) flash as solid shapes.
@export var flash_color: Color = Color(2.5, 2.5, 2.5)

var current: float = -1.0   # lazily initialised to max_health on first use
var _flash_tween: Tween
var _rest_modulate := Color.WHITE
var _flash_overlay: StandardMaterial3D
var _flash_rests: Dictionary = {}   # GeometryInstance3D -> the overlay it had before
var _flash_3d_running := false
var _flash_sprites: Dictionary = {}   # Sprite3D / Label3D -> the modulate it had before


func _ready() -> void:
	_ensure_init()


func _ensure_init() -> void:
	if current < 0.0:
		current = max_health


func take_damage(amount: float, source: Node = null) -> void:
	_ensure_init()
	if amount <= 0.0 or not is_alive():
		return
	current = max(0.0, current - amount)
	damaged.emit(amount, source)
	if current <= 0.0:
		died.emit()
		# after the emit, so everything listening for the death heard it first
		if remove_on_death:
			_remove_body()
	elif flash_on_hit:
		# not on the killing hit: a death fade or removal owns the character by then
		_flash()


func heal(amount: float) -> void:
	_ensure_init()
	if amount <= 0.0 or not is_alive():
		return
	current = min(max_health, current + amount)
	healed.emit(amount)


func revive(to: float = -1.0) -> void:
	current = max_health if to < 0.0 else min(max_health, to)


func is_alive() -> bool:
	_ensure_init()
	return current > 0.0


func fraction() -> float:
	_ensure_init()
	return current / max_health if max_health > 0.0 else 0.0


# Deferred, so the hit that killed it gets to finish (the hit bus) and deferred
# listeners still find it. Never the root window itself.
func _remove_body() -> void:
	var body: Node = get_parent()
	if body == null or body is Viewport:
		body = self
	body.call_deferred("queue_free")


# Tints the whole character and eases back. It remembers the colour from before the
# first flash, so a second hit landing mid-flash doesn't leave the character stuck lit up.
func _flash() -> void:
	if get_parent() is Node3D:
		_flash_3d(get_parent() as Node3D)
		return
	var body := get_parent() as CanvasItem
	if body == null or not is_inside_tree():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	else:
		_rest_modulate = body.modulate
	body.modulate = _rest_modulate * flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(body, "modulate", _rest_modulate, 0.25)


# The 3D version of that: a see-through unshaded layer over every mesh under the body
# that fades out, then each mesh gets back whatever overlay it had. Overlays are used
# instead of changing the materials, so the character's own look is never touched.
func _flash_3d(body: Node3D) -> void:
	if not is_inside_tree():
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	else:
		_flash_rests.clear()
		_flash_sprites.clear()
		_flash_overlay = StandardMaterial3D.new()
		_flash_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		for g in body.find_children("*", "GeometryInstance3D", true, false):
			if g is GPUParticles3D or g is CPUParticles3D:
				continue    # particles draw their own quads, an overlay would turn them into white boxes
			if g is SpriteBase3D or g is Label3D:
				# a flat quad: an overlay would paint a plain box over it, so tint it like a 2D sprite
				_flash_sprites[g] = g.modulate
				continue
			var gi := g as GeometryInstance3D
			_flash_rests[gi] = gi.material_overlay
			gi.material_overlay = _flash_overlay
	_flash_3d_running = true
	_flash_step_3d(0.0)
	_flash_tween = create_tween()
	_flash_tween.tween_method(_flash_step_3d, 0.0, 1.0, 0.25)
	_flash_tween.tween_callback(_end_flash_3d)


# 0 = the full flash, 1 = back to normal.
func _flash_step_3d(t: float) -> void:
	_flash_overlay.albedo_color = Color(flash_color.r, flash_color.g, flash_color.b, 0.75 * (1.0 - t))
	for s in _flash_sprites:
		if is_instance_valid(s):
			var rest: Color = _flash_sprites[s]
			s.modulate = (rest * flash_color).lerp(rest, t)


func _end_flash_3d() -> void:
	for gi in _flash_rests:
		if is_instance_valid(gi):
			(gi as GeometryInstance3D).material_overlay = _flash_rests[gi]
	for s in _flash_sprites:
		if is_instance_valid(s):
			s.modulate = _flash_sprites[s]
	_flash_rests.clear()
	_flash_sprites.clear()
	_flash_3d_running = false


# A Health taken out of the tree mid-flash would leave the overlay on the meshes. Only the
# 3D flash is ended here: the 2D tween is bound to this node and carries on when it is back.
func _exit_tree() -> void:
	if _flash_3d_running and _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
		_end_flash_3d()
