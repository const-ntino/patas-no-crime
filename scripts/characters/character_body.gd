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

## Acuado pelo cachorro (GDD 5.6, sessão 8) — mesmo efeito de
## movimento que is_captured, mas reversível: o cachorro solta assim
## que o animal sai do raio de detecção (`DogNPC._unpin`), diferente
## da captura (permanente até o resgate da sessão 9).
var is_pinned: bool = false

## Chamar (GDD 3.2, RF-09, sessão 7): cooldown contado só no host, que
## é sempre quem valida e processa o pedido (mesma razão de is_captured
## não precisar de RPC pra decrementar — só importa aqui).
var call_cooldown_remaining: float = 0.0

const GRAVITY: float = 9.8
const FLY_SPEED: float = 3.0
## Velocidade máxima enquanto arrasta um Fixo-arrastável (segurando Q).
## Ligeiramente ABAIXO do DRAG_SPEED do item, pra ele acompanhar.
const DRAG_MOVE_SPEED: float = 1.2
const CALL_COOLDOWN: float = 20.0
const CALL_RANGE: float = 15.0

@onready var player_input: PlayerInput = $PlayerInput
@onready var facing_sync: Node3D = $FacingSync
@onready var camera: Camera3D = $VisualRoot/CameraRig/CameraPitch/SpringArm3D/Camera3D


func _ready() -> void:
	var is_local_player: bool = player_input.get_multiplayer_authority() == multiplayer.get_unique_id()
	camera.current = is_local_player


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if call_cooldown_remaining > 0.0:
		call_cooldown_remaining -= delta

	if is_captured or is_pinned:
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


## Chamado por player_input.gd (local) quando Q é apertado por um
## personagem com can_call. Igual ao fluxo de interact() do item/porta:
## pede ao host, que valida e aplica.
func request_call() -> void:
	_request_call_rpc.rpc_id(1)


@rpc("any_peer", "call_local")
func _request_call_rpc() -> void:
	if not multiplayer.is_server():
		return
	if not stats or not stats.can_call:
		return
	if call_cooldown_remaining > 0.0:
		return
	call_cooldown_remaining = CALL_COOLDOWN
	_attract_nearest_human()


## Só o host roda isso (RM-03: toda IA só no host) — chamado depois da
## validação de cooldown acima, que só passa no host mesmo. Atrai só o
## humano CALMO mais próximo (GDD 3.2: "humano em Desconfiado ignora";
## Caos também ignora aqui, já está ocupado com algo mais sério).
func _attract_nearest_human() -> void:
	var nearest: Node = null
	var nearest_dist: float = CALL_RANGE
	for human in get_tree().get_nodes_in_group("human_npc"):
		if human.alert_state != HumanNPC.AlertState.CALMO:
			continue
		var dist: float = global_position.distance_to(human.global_position)
		if dist <= nearest_dist:
			nearest_dist = dist
			nearest = human
	if nearest:
		nearest.investigate_curiosity(global_position)
