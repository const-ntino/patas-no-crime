extends Node
class_name PlayerInput

## Único lugar do projeto, junto com o rig de câmera, autorizado a ler
## Input.*. Traduz teclado em intenção: direção no plano XZ do mundo
## (já composta relativa à câmera), eixo vertical de voo, furtivo, drag,
## e dispara interação (E). Todas as variáveis @export que o host
## precisa enxergar TÊM que estar na lista de replicação do InputSync.

@export var move_direction: Vector2 = Vector2.ZERO
@export var is_sneaking: bool = false
@export var vertical_direction: float = 0.0
@export var is_dragging: bool = false

@onready var camera_rig: Node3D = $"../VisualRoot/CameraRig"
@onready var interaction_area: Area3D = $"../InteractionArea"
@onready var character: Node3D = $".."


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
	vertical_direction = Input.get_action_strength("fly_up") - Input.get_action_strength("fly_down")
	is_dragging = Input.is_action_pressed("verb")

	if Input.is_action_just_pressed("interact"):
		_try_interact()


func _try_interact() -> void:
	var areas := interaction_area.get_overlapping_areas()
	var closest: Node = null
	var closest_dist: float = INF
	for area in areas:
		var parent := area.get_parent()
		if not parent.is_in_group("interactable"):
			continue
		var dist: float = area.global_position.distance_to(character.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest = parent

	if closest and closest.has_method("interact"):
		closest.interact(character)
