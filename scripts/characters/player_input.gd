extends Node
class_name PlayerInput

## Único lugar do projeto, junto com o rig de câmera, autorizado a ler
## Input.*. Traduz teclado em intenção: um Vector2 no plano XZ do mundo,
## já composto relativo à orientação (yaw) da câmera local. O host
## recebe essa direção pronta e nunca sabe que câmera existe.

@export var move_direction: Vector2 = Vector2.ZERO
@export var is_sneaking: bool = false

@onready var camera_rig: Node3D = $"../VisualRoot/CameraRig"


func _process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return

	var input_vector := Vector2.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.y = Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")
	if input_vector.length() > 1.0:
		input_vector = input_vector.normalized()

	var cam_forward: Vector3 = camera_rig.global_transform.basis.z
	cam_forward.y = 0.0
	cam_forward = cam_forward.normalized()

	var cam_right: Vector3 = -camera_rig.global_transform.basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()

	var world_direction: Vector3 = cam_right * input_vector.x + cam_forward * -input_vector.y

	move_direction = Vector2(world_direction.x, world_direction.z)
	is_sneaking = Input.is_action_pressed("sneak")
