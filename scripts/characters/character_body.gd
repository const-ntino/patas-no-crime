extends CharacterBody3D

@export var stats: CharacterStats

const GRAVITY: float = 9.8

@onready var player_input: PlayerInput = $PlayerInput
@onready var facing_sync: Node3D = $FacingSync
@onready var camera: Camera3D = $VisualRoot/CameraRig/CameraPitch/SpringArm3D/Camera3D


func _ready() -> void:
	var is_local_player: bool = player_input.get_multiplayer_authority() == multiplayer.get_unique_id()
	camera.current = is_local_player


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var direction := Vector3(player_input.move_direction.x, 0.0, player_input.move_direction.y)
	var speed: float = stats.move_speed
	if player_input.is_sneaking:
		speed *= stats.sneak_speed_multiplier

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	if direction.length() > 0.01:
		facing_sync.look_at(facing_sync.global_position + direction, Vector3.UP)

	move_and_slide()
