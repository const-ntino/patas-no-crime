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
## Alcance em que uma perseguição termina acordando cachorros
## dormindo por perto (GDD 5.4/5.6, sessão 8 — antes era no-op porque
## pets não existiam ainda).
const PET_WAKE_RANGE: float = 10.0

## Raios de ruído (GDD 5.5). Passos respeita is_sneaking (furtivo =
## raio zero, GDD 5.1); item Pesado/Fixo-arrastável em movimento não
## (não dá pra carregar algo pesado na ponta dos pés). Sem raycast —
## som atravessa parede, diferente da visão (decisão #2 da sessão 6).
const NOISE_RANGE_STEPS: float = 3.0
const NOISE_RANGE_HEAVY: float = 5.0
const NOISE_MOVE_THRESHOLD: float = 0.1

## Chamar do pássaro (GDD 3.2, RF-09, sessão 7): curiosidade, não
## alerta — não usa AlertState nem mostra ?/! (diferente de
## Desconfiado). Mais curta que a investigação de Desconfiado (8s)
## porque é só curiosidade, não suspeita real.
const CURIOSITY_TIME: float = 5.0

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
## Verdadeiro enquanto acumula os 2s de visão central (GDD 5.4) — o
## humano ainda está tecnicamente Calmo nesse intervalo, mas precisa
## de um aviso visual (achado ao vivo: sem isso o jogador não tem
## nenhum sinal antes do Caos "aparecer do nada" quando visto de
## frente). HUD mostra "?" enquanto isso for true.
var is_sighting: bool = false

var _investigate_point: Vector3 = Vector3.ZERO
var _investigate_timer: float = 0.0
var _investigate_arrived: bool = false

var _chase_target: CharacterBody3D = null
var _chase_timer: float = 0.0
var _chase_los_lost_timer: float = 0.0

var _alert_move_direction: Vector3 = Vector3.ZERO
var _alert_last_next_point: Vector3 = Vector3.INF

var is_curious: bool = false
var _curiosity_point: Vector3 = Vector3.ZERO
var _curiosity_timer: float = 0.0
var _curiosity_arrived: bool = false

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var facing_sync: Node3D = $FacingSync
@onready var players: Node3D = $"../../Players"


func _ready() -> void:
	# Grupo em código, não groups=[...] no .tscn (lição k) — item.gd usa
	# isso pra achar humanos sem precisar de referência direta (sessão 6).
	add_to_group("human_npc")


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
			if is_curious:
				_process_curiosity(delta)
			else:
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
		is_sighting = false
		var noise_origin: Vector3 = _detect_noise()
		if noise_origin != Vector3.INF:
			_enter_desconfiado(noise_origin)
		return

	if sighting["carrying"]:
		is_sighting = false
		_enter_caos(sighting["player"])
		return

	if sighting["central"]:
		is_sighting = true
		_sight_timer += delta
		if _sight_timer >= CAOS_CONFIRM_TIME:
			is_sighting = false
			_enter_caos(sighting["player"])
		return

	_sight_timer = 0.0
	is_sighting = false
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
# Ruído (GDD 5.5, sessão 6)
# ---------------------------------------------------------------------------

## Passos (furtivo zera, GDD 5.1) e item Pesado/Fixo-arrastável em
## movimento (ignora furtivo). Sem raycast — som atravessa parede
## (decisão #2). Retorna a posição da fonte mais próxima ou Vector3.INF.
func _detect_noise() -> Vector3:
	var closest: Vector3 = Vector3.INF
	var closest_dist: float = INF
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

		var noise_range: float = 0.0
		if carrying_heavy and moving:
			noise_range = NOISE_RANGE_HEAVY
		elif moving and not is_sneaking:
			noise_range = NOISE_RANGE_STEPS

		if noise_range <= 0.0:
			continue

		var dist: float = global_position.distance_to(player.global_position)
		if dist <= noise_range and dist < closest_dist:
			closest_dist = dist
			closest = player.global_position

	return closest


## Chamado de fora (item.gd, no impacto) — mesma entrada que qualquer
## outro gatilho de Desconfiado, só que empurrada em vez de detectada
## no próprio scan (evento único, não condição contínua).
func notify_noise(origin: Vector3, noise_range: float) -> void:
	if alert_state == AlertState.CAOS:
		return  # já no nível máximo de alerta, ignora (GDD 5.4)
	if global_position.distance_to(origin) > noise_range:
		return
	_enter_desconfiado(origin)


# ---------------------------------------------------------------------------
# Curiosidade (GDD 3.2, RF-09, sessão 7 — Chamar do pássaro)
# ---------------------------------------------------------------------------

## Chamado de fora (character_body.gd, quando o pássaro usa Chamar).
## Só CALMO responde (GDD 3.2: "humano em Desconfiado ignora" — Caos
## também ignora aqui, já ocupado com algo mais sério).
func investigate_curiosity(point: Vector3) -> void:
	if alert_state != AlertState.CALMO:
		return
	is_curious = true
	_curiosity_point = point
	_curiosity_timer = CURIOSITY_TIME
	_curiosity_arrived = false
	_alert_last_next_point = Vector3.INF
	_alert_move_direction = Vector3.ZERO


func _process_curiosity(delta: float) -> void:
	if not _curiosity_arrived:
		var arrived: bool = _move_toward(_curiosity_point, MOVE_SPEED)
		if arrived:
			_curiosity_arrived = true
			velocity.x = 0.0
			velocity.z = 0.0
	else:
		_curiosity_timer -= delta
		if _curiosity_timer <= 0.0:
			is_curious = false
			_last_next_point = Vector3.INF
			_move_direction = Vector3.ZERO


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
	if not sighting.is_empty():
		if sighting["carrying"] or sighting["central"]:
			_enter_caos(sighting["player"])
			return
		_redirect_investigation(sighting["player"].global_position)
		return

	var noise_origin: Vector3 = _detect_noise()
	if noise_origin != Vector3.INF:
		_redirect_investigation(noise_origin)


func _redirect_investigation(new_point: Vector3) -> void:
	_investigate_point = new_point
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
		_capture(_chase_target)
		_end_chase()


## GDD 5.7 (sessão 9): solta o que o animal carregava NO PONTO DE
## CAPTURA (antes de teleportar — a ordem importa) e manda pra gaiola.
## Sem gaiola na cena (não deveria acontecer no MVP), cai de volta no
## placeholder da sessão 5 (só trava no lugar) em vez de quebrar.
func _capture(target: CharacterBody3D) -> void:
	if "held_item" in target and target.held_item:
		target.held_item._apply_release.rpc()
	if "dragging_item" in target and target.dragging_item:
		target.dragging_item._apply_release.rpc()

	var cage: Node = get_tree().get_first_node_in_group("cage")
	if cage:
		cage.capture(target)
	else:
		target.is_captured = true


func _end_chase() -> void:
	cone_multiplier *= CONE_BOOST
	_chase_target = null
	_wake_nearby_dogs()
	_exit_alert_to_routine()


func _wake_nearby_dogs() -> void:
	for dog in get_tree().get_nodes_in_group("dog_npc"):
		if global_position.distance_to(dog.global_position) <= PET_WAKE_RANGE:
			dog.wake()


func _exit_alert_to_routine() -> void:
	alert_state = AlertState.CALMO
	_sight_timer = 0.0
	is_sighting = false
	is_curious = false  # um alerta de verdade cancela curiosidade pendente
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
