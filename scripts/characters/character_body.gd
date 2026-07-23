extends CharacterBody3D

## Corpo do personagem: SEMPRE autoridade do host (RM-02). held_item e
## dragging_item são setados pelos RPCs do item (rodam em todos os
## peers). Arrastar desacelera o personagem (GDD 4.1: "movimento lento
## contínuo") — o item segue um pouco mais rápido que isso, então os
## dois andam juntos.

@export var stats: CharacterStats
var held_item: Item = null
var dragging_item: Item = null

## Placeholder de captura (GDD 5.4/5.7, sessão 5): sinalizado só pelo
## host, que é sempre quem processa movimento (RM-02) — não precisa de
## RPC pra "congelar" ter efeito, a posição parada já replica sozinha
## via TransformSync. Sem gaiola/resgate ainda (sessão 9 troca isso).
var is_captured: bool = false

const GRAVITY: float = 9.8
const FLY_SPEED: float = 3.0
## Velocidade máxima enquanto arrasta um Fixo-arrastável (segurando Q).
## Ligeiramente ABAIXO do DRAG_SPEED do item, pra ele acompanhar.
const DRAG_MOVE_SPEED: float = 1.2

@onready var player_input: PlayerInput = $PlayerInput
@onready var facing_sync: Node3D = $FacingSync
@onready var camera: Camera3D = $VisualRoot/CameraRig/CameraPitch/SpringArm3D/Camera3D


func _ready() -> void:
	var is_local_player: bool = player_input.get_multiplayer_authority() == multiplayer.get_unique_id()
	camera.current = is_local_player


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if is_captured:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		move_and_slide()
		return

	var direction := Vector3(player_input.move_direction.x, 0.0, player_input.move_direction.y)
	var speed: float = stats.move_speed
	if player_input.is_sneaking:
		speed *= stats.sneak_speed_multiplier
	if held_item:
		speed *= held_item.speed_multiplier
	if dragging_item and player_input.is_dragging:
		speed = minf(speed, DRAG_MOVE_SPEED)

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	if stats.can_fly:
		velocity.y = player_input.vertical_direction * FLY_SPEED
	else:
		if not is_on_floor():
			velocity.y -= GRAVITY * delta

	var horizontal_direction := Vector3(direction.x, 0.0, direction.z)
	if horizontal_direction.length() > 0.01:
		facing_sync.look_at(facing_sync.global_position + horizontal_direction, Vector3.UP)

	move_and_slide()
