extends CharacterBody3D
class_name HumanNPC

## Humano NPC com rotina de pontos fixos (GDD 5.3, RF-02 parte 1).
## SEMPRE autoridade do host (RM-03: toda IA roda só no host).
## Caminha entre routine_points via NavigationAgent3D (malha assada
## pelo GameManager a partir da colisão da casa) em vez de waypoints
## manuais — evita adivinhar coordenadas sobre a escada sem poder
## testar ao vivo (lição f do estado-do-projeto-m1.md).

enum State { WAITING, WALKING }

const GRAVITY: float = 9.8
const MOVE_SPEED: float = 1.6
const WAIT_MIN: float = 20.0
const WAIT_MAX: float = 60.0

var routine_points: Array[Vector3] = []
var current_target_index: int = 0
var state: State = State.WAITING
var wait_timer: float = 0.0
var rng: RandomNumberGenerator
var _move_direction: Vector3 = Vector3.ZERO
var _last_next_point: Vector3 = Vector3.INF

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var facing_sync: Node3D = $FacingSync


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

	match state:
		State.WAITING:
			_process_waiting(delta)
		State.WALKING:
			_process_walking()

	# Gravidade sempre ativa (parado ou andando): é ela + move_and_slide
	# que faz o corpo seguir o contorno da rampa da escada ao encostar
	# nela andando na horizontal, igual ao personagem jogável.
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
## oscilava de sinal (ziguezague): o alvo de altura (rampa) nunca é
## alcançado só andando na horizontal, então "quase lá" em XZ virava
## "passei, volto" no frame seguinte, preso num vaivém sem nunca
## empurrar o corpo pra dentro da rampa por tempo suficiente pra subir.
## Travar a direção por corner imita um jogador que segura a tecla até
## atravessar, em vez de soltar assim que "chega" no X/Z (achado via
## CLI headless, sessão 3).
func _process_walking() -> void:
	if nav_agent.is_navigation_finished():
		_enter_waiting()
		velocity.x = 0.0
		velocity.z = 0.0
		_move_direction = Vector3.ZERO
		_last_next_point = Vector3.INF
		return

	var next_point: Vector3 = nav_agent.get_next_path_position()
	# Recalcula quando o corner muda OU quando a direção travada ainda
	# está zerada (salvaguarda: se o primeiro cálculo de um corner novo
	# coincidiu com distância ~0 por acaso, sem isso ficaria sem rumo
	# pra sempre, mesmo com a navegação não concluída).
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
