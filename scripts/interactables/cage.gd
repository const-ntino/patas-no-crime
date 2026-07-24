extends Area3D
class_name Cage

signal animal_captured(animal: CharacterBody3D)

## Gaiola de captura (GDD 5.7, RF-04, sessão 9) — substitui o
## placeholder "congela no lugar" da sessão 5 (is_captured continua
## existindo, mas agora tem efeito real: teleporta pra cá em vez de só
## travar no ponto de captura). Resgate: outro animal fica na área da
## gaiola por RESCUE_TIME_NORMAL (3s) — guaxinim, RESCUE_TIME_MANIPULATOR
## (1s, "abre o trinco", GDD 5.7) — soltando TODOS os animais presos de
## uma vez (trinco único; MVP não tem cadeia de resgate parcial).
##
## Simplificação deliberada: GDD diz "executa interação de 3s", que eu
## li como "fica perto por 3s" em vez de "segura E por 3s" — mesmo
## custo de tempo/risco pro jogador, sem precisar de infraestrutura
## nova de input contínuo só pra isso.

const RESCUE_TIME_NORMAL: float = 3.0
const RESCUE_TIME_MANIPULATOR: float = 1.0

var captured_animals: Array[CharacterBody3D] = []
var _rescuer: CharacterBody3D = null
var _rescue_progress: float = 0.0


func _ready() -> void:
	add_to_group("cage")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if captured_animals.is_empty() or _rescuer == null or not is_instance_valid(_rescuer):
		_rescue_progress = 0.0
		return

	var duration: float = RESCUE_TIME_NORMAL
	if "stats" in _rescuer and _rescuer.stats and _rescuer.stats.can_manipulate:
		duration = RESCUE_TIME_MANIPULATOR

	_rescue_progress += delta
	if _rescue_progress >= duration:
		_release_all()


func _on_body_entered(body: Node3D) -> void:
	if not body is CharacterBody3D:
		return
	if body in captured_animals:
		return
	if "is_captured" in body and body.is_captured:
		return
	if _rescuer == null:
		_rescuer = body


func _on_body_exited(body: Node3D) -> void:
	if body == _rescuer:
		_rescuer = null
		_rescue_progress = 0.0


## Chamado pelo HumanNPC (host) ao alcançar um animal em Caos. O item
## carregado já deve ter sido solto ANTES desta chamada, no ponto de
## captura (GDD 5.7: "dropa o que carregava no ponto de captura") —
## esta função só cuida do "ir pra gaiola".
func capture(animal: CharacterBody3D) -> void:
	if animal in captured_animals:
		return
	captured_animals.append(animal)
	animal.is_captured = true
	var offset: Vector3 = Vector3(captured_animals.size() * 0.4, 0, 0)
	animal.global_position = global_position + offset
	animal_captured.emit(animal)


func _release_all() -> void:
	for animal in captured_animals:
		if is_instance_valid(animal):
			animal.is_captured = false
	captured_animals.clear()
	_rescuer = null
	_rescue_progress = 0.0
