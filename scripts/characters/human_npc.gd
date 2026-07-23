extends CharacterBody3D
class_name HumanNPC

## Humano NPC: rotina de pontos fixos (GDD 5.3, RF-02 parte 1) +
## estados de alerta (GDD 5.4, RF-03, sessão 5). SEMPRE autoridade do
## host (RM-03: toda IA roda só no host). Caminha via NavigationAgent3D
## (malha assada pelo GameManager) em vez de waypoints manuais — evita
## adivinhar coordenadas sobre a escada sem poder testar ao vivo
## (lição f do estado-do-projeto-m1.md).
##
## alert_state tem prioridade sobre a rotina: fora de Calmo, a máquina
## WAITING/WALKING da rotina é ignorada inteira e um bloco de
## movimento próprio (investigar/perseguir) assume nav_agent e
## velocity. Ao voltar pra Calmo, a rotina resume do
## current_target_index que já estava — não "lembra" o ponto exato
## onde parou de andar, só o próximo destino (simplificação aceita).

enum State { WAITING, WALKING }
enum AlertState { CALMO, DESCONFIADO, CAOS }

const GRAVITY: float = 9.8
const MOVE_SPEED: float = 1.6
const CHASE_SPEED: float = 3.0
const WAIT_MIN: float = 20.0
const WAIT_MAX: float = 60.0

## Cones de detecção (GDD 5.4). Ângulo é a abertura TOTAL do cone;
## metade de cada lado da direção de frente. "Central" é o sub-cone
## mais estreito que conta como "viu claramente" (gatilho de Caos por
## sustentação de 2s); fora dele mas dentro do cone principal conta só
## como "viu na borda" (gatilho instantâneo de Desconfiado).
const RANGE_CALMO: float = 4.0
const ANGLE_CALMO: float = 60.0
const RANGE_DESCONFIADO: float = 6.0
const ANGLE_DESCONFIADO: float = 90.0
const ANGLE_CENTRAL: float = 30.0
const EYE_HEIGHT: float = 1.4
const SCENARIO_MASK: int = 1

const CAOS_CONFIRM_TIME: float = 2.0
const INVESTIGATE_TIME: float = 8.0
const CHASE_TIME: float = 20.0
const CHASE_LOS_GRACE: float = 3.0
const CHASE_RANGE: float = 14.0
const CATCH_DISTANCE: float = 1.0
const CONE_BOOST: float = 1.25
const HUMAN_PROXIMITY_ALERT: float = 2.0

var routine_points: Array[Vector3] = []
var current_target_index: int = 0
var state: State = State.WAITING
var alert_state: AlertState = AlertState.CALMO
var wait_timer: float = 0.0
var rng: RandomNumberGenerator
var cone_multiplier: float = 1.0

var _move_direction: Vector3 = Vector3.ZERO
var _last_next_point: Vector3 = Vector3.INF

var _sight_timer: float = 0.0

var _investigate_point: Vector3 = Vector3.ZERO
var _investigate_timer: float = 0.0
var _investigate_arrived: bool = false

var _chase_target: CharacterBody3D = null
var _chase_timer: float = 0.0
var _chase_los_lost_timer: float = 0.0

var _alert_move_direction: Vector3 = Vector3.ZERO
var _alert_last_next_point: Vector3 = Vector3.INF

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var facing_sync: Node3D = $FacingSync
@onready var players: Node3D = $"../../Players"


## Chamado pelo GameManager (host) ANTES do add_child — mesma ordem já
## usada em item.gd, pra que a posição inicial já viaje no snapshot de
## spawn replicado, sem esperar o próximo tick do TransformSync.
## seed_value torna a duração de espera em cada ponto reproduzível
## (GDD 5.3: "determinística por seed da partida").
func setup(points: Array[Vector3], seed_value: int) -> void:
	routine_points = points
	rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	current_target_index = 0
	position = routine_points[0]
	_enter_waiting()


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	match alert_state:
		AlertState.CALMO:
			match state:
				State.WAITING:
					_process_waiting(delta)
				State.WALKING:
					_process_walking()
			_scan_and_react(delta)
		AlertState.DESCONFIADO:
			_process_desconfiado(delta)
		AlertState.CAOS:
			_process_caos(delta)

	# Gravidade sempre ativa: é ela + move_and_slide que faz o corpo
	# seguir o contorno da rampa da escada ao encostar nela andando na
	# horizontal, igual ao personagem jogável.
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	move_and_slide()


func _process_waiting(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	wait_timer -= delta
	if wait_timer <= 0.0:
		_enter_walking()


## A direção só é recalculada quando o PRÓXIMO PONTO do caminho muda de
## verdade (novo corner do NavigationAgent3D), nunca com base na
## distância atual até ele. Recalcular a cada frame perto do alvo
## oscilava de sinal (ziguezague) porque o alvo de altura (rampa) nunca
## é alcançado só andando na horizontal — travar a direção por corner
## imita um jogador que segura a tecla até atravessar (achado via CLI
## headless, sessão 3).
func _process_walking() -> void:
	if nav_agent.is_navigation_finished():
		_enter_waiting()
		velocity.x = 0.0
		velocity.z = 0.0
		_move_direction = Vector3.ZERO
		_last_next_point = Vector3.INF
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


func _enter_waiting() -> void:
	state = State.WAITING
	wait_timer = rng.randf_range(WAIT_MIN, WAIT_MAX)


func _enter_walking() -> void:
	current_target_index = (current_target_index + 1) % routine_points.size()
	nav_agent.target_position = routine_points[current_target_index]
	state = State.WALKING


# ---------------------------------------------------------------------------
# Detecção (GDD 5.4)
# ---------------------------------------------------------------------------

## Varre jogadores dentro do cone/alcance atual e reage: carregando
## item ou visto no cone central por CAOS_CONFIRM_TIME -> Caos; visto
## só na borda -> Desconfiado instantâneo.
func _scan_and_react(delta: float) -> void:
	var sighting: Dictionary = _detect_best_sighting(RANGE_CALMO, ANGLE_CALMO)
	if sighting.is_empty():
		_sight_timer = 0.0
		return

	if sighting["carrying"]:
		_enter_caos(sighting["player"])
		return

	if sighting["central"]:
		_sight_timer += delta
		if _sight_timer >= CAOS_CONFIRM_TIME:
			_enter_caos(sighting["player"])
		return

	_sight_timer = 0.0
	_enter_desconfiado(sighting["player"].global_position)


## Retorna {} se ninguém visto, senão {"player", "carrying", "central"}
## do avistamento mais relevante (prioriza carregando item > central).
func _detect_best_sighting(vision_range: float, angle: float) -> Dictionary:
	var effective_range: float = vision_range * cone_multiplier
	var half_angle: float = angle * 0.5
	var half_central: float = ANGLE_CENTRAL * 0.5
	var space_state: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var forward: Vector3 = -facing_sync.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()

	var best: Dictionary = {}
	for player in players.get_children():
		if not player is CharacterBody3D:
			continue
		if "is_captured" in player and player.is_captured:
			continue
		if _is_hidden(player):
			continue

		var to_player: Vector3 = player.global_position - global_position
		to_player.y = 0.0
		var dist: float = to_player.length()
		if dist > effective_range or dist < 0.01:
			continue

		var angle_to: float = rad_to_deg(forward.angle_to(to_player.normalized()))
		if angle_to > half_angle:
			continue
		if not _has_line_of_sight(space_state, player.global_position + Vector3(0, 0.9, 0)):
			continue

		var carrying: bool = "held_item" in player and player.held_item != null
		var central: bool = angle_to <= half_central
		best = {"player": player, "carrying": carrying, "central": central}
		if carrying:
			break

	return best


func _is_hidden(player: Node3D) -> bool:
	for spot in get_tree().get_nodes_in_group("hiding_spot"):
		if spot.is_character_inside(player):
			return true
	return false


func _has_line_of_sight(space_state: PhysicsDirectSpaceState3D, target_pos: Vector3) -> bool:
	var from: Vector3 = global_position + Vector3(0, EYE_HEIGHT, 0)
	var query := PhysicsRayQueryParameters3D.create(from, target_pos, SCENARIO_MASK)
	var result: Dictionary = space_state.intersect_ray(query)
	return result.is_empty()


# ---------------------------------------------------------------------------
# Desconfiado (GDD 5.4)
# ---------------------------------------------------------------------------

func _enter_desconfiado(stimulus_point: Vector3) -> void:
	alert_state = AlertState.DESCONFIADO
	_investigate_point = stimulus_point
	_investigate_timer = INVESTIGATE_TIME
	_investigate_arrived = false
	_alert_last_next_point = Vector3.INF
	nav_agent.target_position = _investigate_point


func _process_desconfiado(delta: float) -> void:
	if not _investigate_arrived:
		var arrived: bool = _move_toward(_investigate_point, MOVE_SPEED)
		if arrived:
			_investigate_arrived = true
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		_investigate_timer -= delta
		if _investigate_timer <= 0.0:
			_exit_alert_to_routine()
			return

	# Novo estímulo durante a investigação redireciona (GDD 5.3: "novo
	# estímulo durante investigação redireciona").
	var sighting: Dictionary = _detect_best_sighting(RANGE_DESCONFIADO, ANGLE_DESCONFIADO)
	if sighting.is_empty():
		return
	if sighting["carrying"] or sighting["central"]:
		_enter_caos(sighting["player"])
		return
	_investigate_point = sighting["player"].global_position
	_investigate_timer = INVESTIGATE_TIME
	_investigate_arrived = false
	_alert_last_next_point = Vector3.INF
	nav_agent.target_position = _investigate_point


# ---------------------------------------------------------------------------
# Caos (GDD 5.4)
# ---------------------------------------------------------------------------

func _enter_caos(target: CharacterBody3D) -> void:
	alert_state = AlertState.CAOS
	_chase_target = target
	_chase_timer = CHASE_TIME
	_chase_los_lost_timer = 0.0
	_alert_last_next_point = Vector3.INF
	_alert_move_direction = Vector3.ZERO

	# Humano em Caos perto de outro humano o coloca em Desconfiado
	# (GDD 5.4). Só testável com mais de 1 humano na fase — código
	# genérico, pronto pra quando houver.
	var parent_node: Node = get_parent()
	if parent_node:
		for sibling in parent_node.get_children():
			if sibling == self or not sibling is HumanNPC:
				continue
			if sibling.alert_state == AlertState.CALMO and global_position.distance_to(sibling.global_position) <= HUMAN_PROXIMITY_ALERT:
				sibling._enter_desconfiado(global_position)


func _process_caos(delta: float) -> void:
	if _chase_target == null or not is_instance_valid(_chase_target):
		_end_chase()
		return

	var space_state: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var in_sight: bool = global_position.distance_to(_chase_target.global_position) <= CHASE_RANGE \
		and _has_line_of_sight(space_state, _chase_target.global_position + Vector3(0, 0.9, 0))
	if in_sight:
		_chase_los_lost_timer = 0.0
	else:
		_chase_los_lost_timer += delta
		if _chase_los_lost_timer >= CHASE_LOS_GRACE:
			_end_chase()
			return

	_chase_timer -= delta
	if _chase_timer <= 0.0:
		_end_chase()
		return

	nav_agent.target_position = _chase_target.global_position
	_move_toward(_chase_target.global_position, CHASE_SPEED)

	if global_position.distance_to(_chase_target.global_position) <= CATCH_DISTANCE:
		if "is_captured" in _chase_target:
			_chase_target.is_captured = true
		_end_chase()


func _end_chase() -> void:
	cone_multiplier *= CONE_BOOST
	_chase_target = null
	_exit_alert_to_routine()


func _exit_alert_to_routine() -> void:
	alert_state = AlertState.CALMO
	_sight_timer = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	# Retoma a rotina em direção ao ponto que já era o destino atual —
	# não recalcula desvio, só reafirma o alvo pro nav_agent.
	nav_agent.target_position = routine_points[current_target_index]
	state = State.WALKING
	_last_next_point = Vector3.INF
	_move_direction = Vector3.ZERO


## Move em direção a target_pos usando o mesmo padrão de "trava direção
## por corner" da rotina (ver _process_walking), mas com variáveis
## PRÓPRIAS (prefixo _alert_) pra não conflitar com o estado da rotina
## — investigar/perseguir e andar a rotina nunca rodam ao mesmo tempo,
## mas usam o nav_agent em instantes diferentes, então cada um precisa
## da própria memória de "pra onde eu já tava indo". Retorna true
## quando chega perto o bastante de target_pos.
func _move_toward(target_pos: Vector3, speed: float) -> bool:
	nav_agent.target_position = target_pos
	if nav_agent.is_navigation_finished():
		return true

	var next_point: Vector3 = nav_agent.get_next_path_position()
	if next_point != _alert_last_next_point or _alert_move_direction.length() <= 0.01:
		_alert_last_next_point = next_point
		var to_next := Vector3(next_point.x - global_position.x, 0.0, next_point.z - global_position.z)
		if to_next.length() > 0.01:
			_alert_move_direction = to_next.normalized()

	if _alert_move_direction.length() > 0.01:
		velocity.x = _alert_move_direction.x * speed
		velocity.z = _alert_move_direction.z * speed
		facing_sync.look_at(facing_sync.global_position + _alert_move_direction, Vector3.UP)

	return global_position.distance_to(target_pos) <= CATCH_DISTANCE
