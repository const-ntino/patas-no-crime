extends Control

## HUD de jogo (GDD 8.1) — primeira vez no projeto. Sem timer nem
## ícones dos 3 objetivos ainda: dependem de vitória/derrota (RF-07,
## sessão 11) e dos objetivos formais (sessão 10). Aqui: contorno de
## companheiro através de parede, ícone persistente sobre alvo
## marcado, linha de rotina + relógio sobre humano marcado (GDD 5.2,
## RF-02 parte 2).
##
## Desenho em espaço de tela (Control._draw + Camera3D.unproject_position)
## em vez de geometria 3D: "através de parede" é justamente ignorar
## oclusão, o que geometria 3D real não faz de graça — e desenhar a
## linha de rotina em 2D evita duplicar em 3D algo que já dá pra ler
## direto de routine_points replicado (ver RoutineSync em human_npc.tscn).

const OUTLINE_RADIUS: float = 22.0
const MARK_ICON_RADIUS: float = 8.0
const PLAYER_OUTLINE_COLOR := Color(1, 1, 1, 0.9)
const MARK_ICON_COLOR := Color(1, 0.85, 0.2, 1)
const ROUTINE_LINE_COLOR := Color(1, 0.85, 0.2, 0.7)
const COUNTDOWN_COLOR := Color(1, 1, 1, 1)
const ALERT_ICON_COLOR := Color(1, 0.9, 0.1, 1)
const CAOS_ICON_COLOR := Color(1, 0.2, 0.2, 1)
const HUD_TEXT_COLOR := Color(1, 1, 1, 1)
const OBJECTIVE_DIM_COLOR := Color(0.4, 0.4, 0.4, 1)
const OBJECTIVES: Array[Dictionary] = [
	{ "id": &"car_key", "label": "CHAVE", "color": Color(0.95, 0.9, 0.3, 1) },
	{ "id": &"remote", "label": "CONTROLE", "color": Color(0.3, 0.75, 0.95, 1) },
	{ "id": &"food_pot", "label": "POTE", "color": Color(0.95, 0.4, 0.2, 1) },
]

enum MatchState { SETUP, ACTIVE, VICTORY, DEFEAT }

@onready var players: Node3D = $"../../Players"
@onready var humans: Node3D = $"../../Humans"
@onready var dogs: Node3D = $"../../Dogs"

var _camera: Camera3D = null
var _match_time_remaining: float = 0.0
var _match_state: MatchState = MatchState.SETUP
var _score: int = 0
var _delivered_objectives: Dictionary[StringName, bool] = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_connect_match_manager.call_deferred()


func _process(_delta: float) -> void:
	if _match_state == MatchState.ACTIVE:
		_match_time_remaining = maxf(0.0, _match_time_remaining - _delta)
	queue_redraw()


func _draw() -> void:
	_camera = get_viewport().get_camera_3d()
	if not _camera:
		return

	_draw_companion_outlines()
	_draw_marked_targets()
	_draw_human_alert_icons()
	_draw_dog_alert_icons()
	_draw_match_hud()


func _connect_match_manager() -> void:
	var manager: Node = get_tree().get_first_node_in_group("game_manager")
	if manager == null:
		return
	manager.match_state_changed.connect(_on_match_state_changed)
	_on_match_state_changed(manager.match_time_remaining, manager._objective_ids(), manager.match_state, manager.score)


func _on_match_state_changed(time_remaining: float, delivered_ids: Array[StringName], new_match_state: int, new_score: int) -> void:
	_match_time_remaining = time_remaining
	_match_state = new_match_state
	_score = new_score
	_delivered_objectives.clear()
	for objective_id in delivered_ids:
		_delivered_objectives[objective_id] = true


func _draw_match_hud() -> void:
	if _match_state == MatchState.SETUP:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var seconds: int = int(ceil(_match_time_remaining))
	var timer_text: String = "%02d:%02d" % [seconds / 60, seconds % 60]
	draw_string(ThemeDB.fallback_font, Vector2(viewport_size.x * 0.5 - 30, 34), timer_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, HUD_TEXT_COLOR)

	var start_x: float = viewport_size.x - 160.0
	for i in OBJECTIVES.size():
		var objective: Dictionary = OBJECTIVES[i]
		var objective_id: StringName = objective["id"]
		var delivered: bool = _delivered_objectives.get(objective_id, false)
		var color: Color = objective["color"] if delivered else OBJECTIVE_DIM_COLOR
		var y: float = 28.0 + i * 28.0
		draw_circle(Vector2(start_x, y - 7.0), 6.0, color)
		draw_string(ThemeDB.fallback_font, Vector2(start_x + 14.0, y), objective["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, color)

	if _match_state == MatchState.ACTIVE:
		return
	var headline: String = "VITORIA" if _match_state == MatchState.VICTORY else "TEMPO ESGOTADO"
	var color: Color = Color(0.35, 0.9, 0.45, 1) if _match_state == MatchState.VICTORY else CAOS_ICON_COLOR
	var position: Vector2 = Vector2(viewport_size.x * 0.5 - 105.0, viewport_size.y * 0.45)
	draw_string(ThemeDB.fallback_font, position, headline, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, color)
	draw_string(ThemeDB.fallback_font, position + Vector2(30.0, 30.0), "%d PTS" % _score, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, HUD_TEXT_COLOR)


func _draw_companion_outlines() -> void:
	var local_id: int = multiplayer.get_unique_id()
	for character in players.get_children():
		if character.name == str(local_id):
			continue
		var point: Vector2 = _project(character.global_position + Vector3(0, 1.0, 0))
		if point != Vector2.INF:
			draw_arc(point, OUTLINE_RADIUS, 0, TAU, 24, PLAYER_OUTLINE_COLOR, 2.0)


func _draw_marked_targets() -> void:
	for markable in get_tree().get_nodes_in_group("markable"):
		if not markable.marked:
			continue
		var target: Node3D = markable.get_parent()
		if target == null:
			continue
		var anchor: Vector3 = target.global_position + (markable.sight_offset if markable.sight_offset != Vector3.ZERO else Vector3(0, 0.6, 0))
		var point: Vector2 = _project(anchor)
		if point == Vector2.INF:
			continue
		draw_circle(point, MARK_ICON_RADIUS, MARK_ICON_COLOR)

		if target is HumanNPC:
			_draw_human_extras(target, point)


func _draw_human_extras(human: HumanNPC, head_point: Vector2) -> void:
	# Linha de rotina e relógio só fazem sentido em Calmo — Desconfiado
	# e Caos têm o próprio ícone (ver _draw_human_alert_icons), e o
	# humano nem está seguindo a rotina nesses estados.
	if human.alert_state != HumanNPC.AlertState.CALMO:
		return

	# Linha de rotina: liga os pontos em loop (sofá->cozinha->banheiro->
	# quarto->sofá). Precisa de routine_points replicado (RoutineSync).
	var points: Array[Vector3] = human.routine_points
	if points.size() >= 2:
		for i in points.size():
			var a: Vector3 = points[i]
			var b: Vector3 = points[(i + 1) % points.size()]
			var pa: Vector2 = _project(a)
			var pb: Vector2 = _project(b)
			if pa != Vector2.INF and pb != Vector2.INF:
				draw_line(pa, pb, ROUTINE_LINE_COLOR, 2.0)

	# Relógio de contagem: só faz sentido enquanto o humano está parado
	# num ponto (WAITING) — andando, não há "tempo restante" fixo.
	if human.state == HumanNPC.State.WAITING:
		var seconds_left: int = int(ceil(human.wait_timer))
		draw_string(ThemeDB.fallback_font, head_point + Vector2(-10, -20), "%ds" % seconds_left, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COUNTDOWN_COLOR)


## Ícone de estado (?, !) sobre QUALQUER humano em Desconfiado/Caos —
## GDD 8.1 não condiciona isso a estar marcado, diferente do ícone de
## marcação (que existe pra dar informação através de parede).
##
## is_sighting cobre um caso que tecnicamente ainda é Calmo: os 2s de
## visão central (GDD 5.4) antes de confirmar Caos. Sem aviso nesse
## intervalo, o "!" parecia aparecer do nada quando o humano via o
## jogador de frente — achado ao vivo, sessão 9. Mostra "?" nesse
## intervalo mesmo sem o estado interno ter mudado ainda.
func _draw_human_alert_icons() -> void:
	for human in humans.get_children():
		if human.name == "HumanSpawner" or not human is HumanNPC:
			continue
		if human.alert_state == HumanNPC.AlertState.CALMO and not human.is_sighting:
			continue
		var point: Vector2 = _project(human.global_position + Vector3(0, 1.3, 0))
		if point == Vector2.INF:
			continue
		var label: String = "!" if human.alert_state == HumanNPC.AlertState.CAOS else "?"
		var color: Color = CAOS_ICON_COLOR if human.alert_state == HumanNPC.AlertState.CAOS else ALERT_ICON_COLOR
		draw_string(ThemeDB.fallback_font, point + Vector2(-4, -24), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, color)


## O cachorro prende temporariamente o animal quando entra em PINNING
## (GDD 5.6). Como DogNPC.state já é sincronizado, o aviso chega aos
## dois peers sem incluir flags de controle no TransformSync do jogador.
func _draw_dog_alert_icons() -> void:
	for dog in dogs.get_children():
		if dog.name == "DogSpawner" or not dog is DogNPC:
			continue
		if dog.state != DogNPC.State.PINNING:
			continue
		var point: Vector2 = _project(dog.global_position + Vector3(0, 0.9, 0))
		if point == Vector2.INF:
			continue
		draw_string(ThemeDB.fallback_font, point + Vector2(-4, -24), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, CAOS_ICON_COLOR)


## Retorna Vector2.INF se o ponto está atrás da câmera (não faz sentido
## projetar — unproject_position não recorta isso sozinho).
func _project(world_pos: Vector3) -> Vector2:
	if _camera.is_position_behind(world_pos):
		return Vector2.INF
	return _camera.unproject_position(world_pos)
