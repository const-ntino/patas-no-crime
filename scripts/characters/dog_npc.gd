extends CharacterBody3D
class_name DogNPC

## Cachorro (GDD 5.6, sessão 8) — zona de risco viva. Dorme num ponto
## fixo até: (a) ruído no raio de WAKE_NOISE_RANGE, ou (b) um humano
## terminando uma perseguição por perto (HumanNPC._end_chase, sessão
## 5-6, "acorda o pet" — deixado como no-op até esta sessão existir).
## Acordado, patrulha 2 pontos farejando: detecção por PROXIMIDADE (não
## cone como o humano) que ignora esconderijo visual (é faro, não
## visão) mas ainda é bloqueada por parede/porta fechada (raycast na
## mesma camada de cenário). Detectar não captura: prende o animal no
## lugar (`is_pinned`, igual `is_captured` no efeito, mas reversível
## assim que sai do raio) e chama o humano mais próximo pra lá — quem
## chega e VÊ o animal preso escala pra Caos pela visão normal dele,
## sem precisar de lógica nova.
##
## SEMPRE autoridade do host (RM-03). Mesmo padrão de movimento
## "trava direção por corner" do humano (sessão 3/5) — ver
## scripts/characters/human_npc.gd pra explicação completa do porquê.

enum State { SLEEPING, PATROLLING, PINNING, BRIBED }

const GRAVITY: float = 9.8
const MOVE_SPEED: float = 2.0
const PATROL_TIME: float = 60.0
const WAKE_NOISE_RANGE: float = 5.0
const DETECTION_RANGE: float = 3.0
const BRIBE_RANGE: float = 2.0
const BRIBE_DURATION: float = 20.0
const NOISE_MOVE_THRESHOLD: float = 0.1
const SCENARIO_MASK: int = 1
const EYE_HEIGHT: float = 0.4

var patrol_points: Array[Vector3] = []
var current_patrol_index: int = 0
var state: State = State.SLEEPING
var patrol_timer: float = 0.0
var bribe_timer: float = 0.0

var _pinned_target: CharacterBody3D = null
var _move_direction: Vector3 = Vector3.ZERO
var _last_next_point: Vector3 = Vector3.INF

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var facing_sync: Node3D = $FacingSync
@onready var players: Node3D = $"../../Players"
@onready var items: Node3D = $"../../Items"


func _ready() -> void:
	add_to_group("dog_npc")


## Chamado pelo GameManager (host) ANTES do add_child — mesmo padrão
## de human_npc.gd.setup().
func setup(points: Array[Vector3], sleep_point: Vector3) -> void:
	patrol_points = points
	position = sleep_point
	state = State.SLEEPING


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	match state:
		State.SLEEPING:
			_process_sleeping()
		State.PATROLLING:
			_process_patrolling(delta)
		State.PINNING:
			_process_pinning()
		State.BRIBED:
			_process_bribed(delta)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	move_and_slide()


## Público — chamado por qualquer coisa que deveria acordar o cachorro
## (ruído próprio, ou HumanNPC pós-perseguição).
func wake() -> void:
	if state != State.SLEEPING:
		return
	state = State.PATROLLING
	current_patrol_index = 0
	if patrol_points.size() > 0:
		nav_agent.target_position = patrol_points[0]


func _process_sleeping() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _is_noise_nearby(WAKE_NOISE_RANGE):
		wake()


func _process_patrolling(delta: float) -> void:
	patrol_timer -= delta
	if patrol_timer <= 0.0 and patrol_points.size() > 0:
		current_patrol_index = (current_patrol_index + 1) % patrol_points.size()
		nav_agent.target_position = patrol_points[current_patrol_index]
		patrol_timer = PATROL_TIME
	_move_toward(nav_agent.target_position)

	var target: CharacterBody3D = _detect_nearby_animal()
	if target:
		_pin(target)
		return

	var bribe: Item = _find_nearby_bribe()
	if bribe:
		state = State.BRIBED
		bribe_timer = BRIBE_DURATION
		velocity.x = 0.0
		velocity.z = 0.0


func _process_pinning() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if _pinned_target == null or not is_instance_valid(_pinned_target):
		_unpin()
		return
	if global_position.distance_to(_pinned_target.global_position) > DETECTION_RANGE:
		_unpin()
		return
	_pull_nearest_human()


func _process_bribed(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	bribe_timer -= delta
	if bribe_timer <= 0.0:
		state = State.PATROLLING
		patrol_timer = PATROL_TIME


func _pin(target: CharacterBody3D) -> void:
	state = State.PINNING
	_pinned_target = target
	if "is_pinned" in target:
		target.is_pinned = true
	velocity.x = 0.0
	velocity.z = 0.0


func _unpin() -> void:
	if _pinned_target and "is_pinned" in _pinned_target:
		_pinned_target.is_pinned = false
	_pinned_target = null
	state = State.PATROLLING
	patrol_timer = PATROL_TIME


## Detecção por proximidade (não cone): raio + raycast (bloqueado por
## parede/porta fechada, camada 1), sem checar esconderijo — GDD 5.6:
## "ignora esconderijos visuais".
func _detect_nearby_animal() -> CharacterBody3D:
	var space_state: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	for player in players.get_children():
		if not player is CharacterBody3D:
			continue
		if "is_captured" in player and player.is_captured:
			continue
		if "is_pinned" in player and player.is_pinned:
			continue
		var dist: float = global_position.distance_to(player.global_position)
		if dist > DETECTION_RANGE:
			continue
		var from: Vector3 = global_position + Vector3(0, EYE_HEIGHT, 0)
		var to: Vector3 = player.global_position + Vector3(0, 0.5, 0)
		var query := PhysicsRayQueryParameters3D.create(from, to, SCENARIO_MASK)
		var result: Dictionary = space_state.intersect_ray(query)
		if result.is_empty():
			return player
	return null


func _find_nearby_bribe() -> Item:
	for item in items.get_children():
		if not item is Item:
			continue
		if not item.is_food:
			continue
		if item.held_by != null:
			continue
		if global_position.distance_to(item.global_position) <= BRIBE_RANGE:
			return item
	return null


## Ruído pra acordar (GDD 5.6). Mesmo espírito de
## HumanNPC._detect_noise (sessão 6): furtivo zera passos, item
## pesado/arrastado não. Duplicado em vez de compartilhado — os dois
## NPCs têm raios/condições ligeiramente diferentes e são pequenos o
## bastante pra não valer a pena uma abstração ainda.
func _is_noise_nearby(range_check: float) -> bool:
	for player in players.get_children():
		if not player is CharacterBody3D:
			continue
		if "is_captured" in player and player.is_captured:
			continue

		var carrying_heavy: bool = false
		if "held_item" in player and player.held_item and player.held_item.item_class == Item.Class.PESADO:
			carrying_heavy = true
		if "dragging_item" in player and player.dragging_item != null:
			carrying_heavy = true

		var moving: bool = Vector2(player.velocity.x, player.velocity.z).length() > NOISE_MOVE_THRESHOLD
		var is_sneaking: bool = "player_input" in player and player.player_input and player.player_input.is_sneaking

		if not ((carrying_heavy and moving) or (moving and not is_sneaking)):
			continue
		if global_position.distance_to(player.global_position) <= range_check:
			return true
	return false


func _pull_nearest_human() -> void:
	var nearest: Node = null
	var nearest_dist: float = INF
	for human in get_tree().get_nodes_in_group("human_npc"):
		if human.alert_state == HumanNPC.AlertState.CAOS:
			continue
		var dist: float = global_position.distance_to(human.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = human
	if nearest:
		nearest._enter_desconfiado(global_position)


## Mesmo padrão de "trava direção por corner" do humano (sessão 3) —
## evita ziguezague perto do alvo.
func _move_toward(target_pos: Vector3) -> void:
	nav_agent.target_position = target_pos
	if nav_agent.is_navigation_finished():
		velocity.x = 0.0
		velocity.z = 0.0
		return

	var next_point: Vector3 = nav_agent.get_next_path_position()
	if next_point != _last_next_point or _move_direction.length() <= 0.01:
		_last_next_point = next_point
		var to_next := Vector3(next_point.x - global_position.x, 0.0, next_point.z - global_position.z)
		if to_next.length() > 0.01:
			_move_direction = to_next.normalized()

	if _move_direction.length() > 0.01:
		velocity.x = _move_direction.x * MOVE_SPEED
		velocity.z = _move_direction.z * MOVE_SPEED
		facing_sync.look_at(facing_sync.global_position + _move_direction, Vector3.UP)
