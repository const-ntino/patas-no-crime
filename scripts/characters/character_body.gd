extends CharacterBody3D

@export var move_speed: float = 5.0
@export var sneak_speed_multiplier: float = 0.5

const GRAVITY: float = 9.8

@onready var player_input: PlayerInput = $PlayerInput
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var camera: Camera3D = $CameraRig/CameraPitch/SpringArm3D/Camera3D

func _ready() -> void:
	var is_local_player: bool = player_input.get_multiplayer_authority() == multiplayer.get_unique_id()
	camera.current = is_local_player


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var direction := Vector3(player_input.move_direction.x, 0.0, player_input.move_direction.y)
	var speed: float = move_speed
	if player_input.is_sneaking:
		speed *= sneak_speed_multiplier

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	if direction.length() > 0.01:
		mesh_instance.look_at(mesh_instance.global_position + direction, Vector3.UP)

	move_and_slide()

	# DEBUG TEMPORÁRIO — remover depois de diagnosticar
	# DEBUG TEMPORÁRIO — remover depois de diagnosticar
	if camera.current:
		print("posição câmera: ", camera.global_position)
		print("posição personagem: ", global_position)
		print("direção da câmera (forward): ", -camera.global_transform.basis.z)
