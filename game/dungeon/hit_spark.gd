class_name HitSpark
extends GPUParticles2D

# A one-shot burst of sparks for a melee hit. Builds its own material and a 2px
# dot texture in code, so there's no .tres or image to ship, and frees itself
# once the burst has played out. Drop one at a monster the moment it's struck.

@export var tint: Color = Color(1.0, 0.85, 0.4)


func _ready() -> void:
	one_shot = true
	explosiveness = 0.9
	amount = 12
	lifetime = 0.35
	local_coords = false
	z_index = 5

	var mat := ParticleProcessMaterial.new()
	mat.spread = 180.0
	mat.initial_velocity_min = 45.0
	mat.initial_velocity_max = 110.0
	mat.gravity = Vector3(0, 160, 0)
	mat.scale_min = 1.0
	mat.scale_max = 2.5
	mat.color = tint
	process_material = mat

	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	texture = ImageTexture.create_from_image(img)

	emitting = true
	get_tree().create_timer(lifetime + 0.2).timeout.connect(queue_free)
