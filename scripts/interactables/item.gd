extends RigidBody3D
class_name Item

## Item de furto (GDD 4). RigidBody3D pra cair com física ao ser solto.
## Autoridade sempre do host. Enquanto carregado, freeze=true desliga a
## física e a posição segue o HoldPoint; ao soltar, freeze=false e cai.
## Posição e item_class replicados pelo ItemSync (ver LEIA-ME).

enum Class { LEVE, MEDIO, PESADO, FIXO_ARRASTAVEL }

@export var item_class: Class = Class.LEVE
@export var speed_multiplier: float = 1.0
## Suborno de cachorro (GDD 5.6, sessão 8): largar um item com essa
## flag perto de um cachorro acordado o ocupa por um tempo.
@export var is_food: bool = false

## Velocidade com que o item Fixo-arrastável segue o personagem. Um
## pouco ACIMA da velocidade do personagem arrastando (ver
## DRAG_MOVE_SPEED em character_body.gd) pra ele nunca ficar pra trás.
const DRAG_SPEED: float = 1.5
## Distância em que o item para de se aproximar (não entra na cápsula).
const DRAG_STOP_DISTANCE: float = 0.6

## Ruído de impacto (GDD 5.5, RF-10 recortado só pra itens — sessão 6).
## Limiar evita disparar em pousos suaves; cooldown evita rajada
## enquanto o item quica no chão.
const IMPACT_NOISE_RANGE: float = 8.0
const IMPACT_NOISE_MIN_SPEED: float = 2.0
const IMPACT_NOISE_COOLDOWN: float = 1.0

var held_by: Node = null
var _applied_class: int = -1
var _impact_noise_cooldown: float = 0.0
## linear_velocity JÁ vem zerada quando o sinal body_entered dispara (a
## física resolve a colisão antes de emitir o sinal) — guardamos a
## velocidade do início do frame anterior pra medir o impacto de
## verdade (achado via CLI headless, sessão 6).
var _last_velocity: Vector3 = Vector3.ZERO

@onready var mesh: MeshInstance3D = $Mesh

const CLASS_COLORS := {
	Class.LEVE: Color(0.9, 0.9, 0.9),
	Class.MEDIO: Color(0.9, 0.8, 0.2),
	Class.PESADO: Color(0.9, 0.2, 0.2),
	Class.FIXO_ARRASTAVEL: Color(0.9, 0.5, 0.1),
}

const CLASS_SPEED := {
	Class.LEVE: 1.0,
	Class.MEDIO: 0.8,
	Class.PESADO: 0.6,
	Class.FIXO_ARRASTAVEL: 1.0,
}


func _ready() -> void:
	_refresh_visual()
	# Cliente: item_class chega pela rede depois do _ready; quando o
	# synchronizer entregar dados, reaplica a cor se a classe mudou.
	if not is_multiplayer_authority():
		var sync := $ItemSync as MultiplayerSynchronizer
		sync.synchronized.connect(_refresh_visual)
		return

	# Ruído de impacto (GDD 5.5, sessão 6): só o host processa — cada
	# peer roda física local do RigidBody3D, mas só a simulação do host
	# é autoritativa (RM-02); processar dos dois lados duplicaria/
	# dessincronizaria o ruído.
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func _on_body_entered(_body: Node) -> void:
	if _impact_noise_cooldown > 0.0:
		return
	if _last_velocity.length() < IMPACT_NOISE_MIN_SPEED:
		return
	_impact_noise_cooldown = IMPACT_NOISE_COOLDOWN
	for human in get_tree().get_nodes_in_group("human_npc"):
		human.notify_noise(global_position, IMPACT_NOISE_RANGE)


func _refresh_visual() -> void:
	speed_multiplier = CLASS_SPEED[item_class]
	if not mesh:
		return  # setup() antes de entrar na árvore; _ready() reaplica
	if _applied_class == item_class:
		return  # cor já aplicada; evita recriar material a cada sync
	var material := StandardMaterial3D.new()
	material.albedo_color = CLASS_COLORS[item_class]
	mesh.set_surface_override_material(0, material)
	_applied_class = item_class


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if _impact_noise_cooldown > 0.0:
		_impact_noise_cooldown -= delta
	_last_velocity = linear_velocity

	if held_by == null:
		return

	if item_class == Class.FIXO_ARRASTAVEL:
		var player_input: Node = held_by.get_node("PlayerInput")
		if player_input.is_dragging:
			var target: Vector3 = held_by.global_position
			if global_position.distance_to(target) > DRAG_STOP_DISTANCE:
				global_position = global_position.move_toward(target, DRAG_SPEED * delta)
	else:
		var hold_point: Node3D = held_by.get_node("HoldPoint")
		global_position = hold_point.global_position


func interact(requester: Node) -> void:
	if held_by == requester:
		_request_release_rpc.rpc_id(1, requester.get_path())
		return
	if held_by != null:
		return

	var stats: CharacterStats = requester.stats
	if not stats:
		return

	if item_class == Class.FIXO_ARRASTAVEL:
		if not stats.can_drag:
			return
	else:
		if item_class > stats.max_carry_class:
			return
		if requester.held_item != null:
			return

	_request_attach_rpc.rpc_id(1, requester.get_path())


@rpc("any_peer", "call_local")
func _request_attach_rpc(requester_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	if held_by != null:
		return
	_apply_attach.rpc(requester_path)


@rpc("call_local")
func _apply_attach(requester_path: NodePath) -> void:
	held_by = get_node(requester_path)
	freeze = true
	if item_class == Class.FIXO_ARRASTAVEL:
		held_by.dragging_item = self
	else:
		held_by.held_item = self


@rpc("any_peer", "call_local")
func _request_release_rpc(requester_path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	if held_by == null or held_by.get_path() != requester_path:
		return
	_apply_release.rpc()


@rpc("call_local")
func _apply_release() -> void:
	if held_by:
		if item_class == Class.FIXO_ARRASTAVEL:
			held_by.dragging_item = null
		else:
			held_by.held_item = null
	held_by = null
	freeze = false


## Chamado pelo host no spawn, ANTES de add_child, pra classe já viajar
## no spawn replicado.
func setup(new_class: Class) -> void:
	item_class = new_class
	_refresh_visual()
