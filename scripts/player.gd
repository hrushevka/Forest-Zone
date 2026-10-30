extends CharacterBody3D


@export var SPEED = 5.0
@export var JUMP_VELOCITY = 4.5
@export var mouse_sensitivity = 0.005

@onready var camera = $Camera3D
#@onready var anim = $AnimationPlayer

func _ready() -> void:
	gl.player = self
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, -PI/3, PI/3)
	
#func _process(delta: float) -> void:
	#var light := $Camera3D/SpotLight3D
	#light.global_position = camera.global_position
	#
	## Интерполируем каждую ось отдельно через lerp_angle
	#light.global_rotation = Vector3(
		#lerp_angle(light.global_rotation.x, camera.global_rotation.x, 10.0 * delta),
		#lerp_angle(light.global_rotation.y, camera.global_rotation.y, 10.0 * delta),
		#lerp_angle(light.global_rotation.z, camera.global_rotation.z, 10.0 * delta)
	#)
	
func _physics_process(delta: float) -> void:
	y_pos_update(delta)
	handle_move(delta)

	move_and_slide()

func y_pos_update(delta):
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

func handle_move(delta):
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity.x = direction.x * SPEED * delta
		velocity.z = direction.z * SPEED * delta
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)
