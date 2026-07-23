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

@onready var players: Node3D = $"../../Players"
@onready var humans: Node3D = $"../../Humans"

var _camera: Camera3D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	_camera = get_viewport().get_camera_3d()
	if not _camera:
		return

	_draw_companion_outlines()
	_draw_marked_targets()


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


## Retorna Vector2.INF se o ponto está atrás da câmera (não faz sentido
## projetar — unproject_position não recorta isso sozinho).
func _project(world_pos: Vector3) -> Vector2:
	if _camera.is_position_behind(world_pos):
		return Vector2.INF
	return _camera.unproject_position(world_pos)
