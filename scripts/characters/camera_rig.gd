extends Node3D
class_name CameraRig

## Rig de câmera em terceira pessoa, DESACOPLADO da hierarquia visual.
##
## top_level = true faz este nó ignorar o transform dos pais: ele não
## herda mais o chase-lerp do VisualRoot (que se move em pulsos ao
## perseguir a posição de rede em degraus de ~66 ms). Em vez disso, o
## rig segue o corpo lógico por conta própria, com amortecimento
## exponencial contínuo — a câmera se move suave mesmo que o alvo se
## mova em degraus. Resultado: o mundo para de pulsar na tela; sobra
## só o micro-passo da cápsula, muito menos perceptível (a eliminação
## total disso é predição/buffer, escopo de M2 — ver docs/backlog.md).
##
## Junto com PlayerInput, é o único lugar do projeto autorizado a ler
## Input.*. 100% local: nunca replicado em efeito, nunca participa da
## simulação. Os sinais de rotação do mouse foram calibrados
## empiricamente na sessão 3 do M0 — não alterar sem retestar os dois
## eixos e o WASD relativo à câmera.

@export var mouse_sensitivity: float = 0.005
@export var invert_y: bool = false
@export var pitch_min_deg: float = -60.0
@export var pitch_max_deg: float = 10.0

## Altura do pivô da câmera acima da origem do personagem (substitui a
## antiga posição local Y do rig, que top_level torna irrelevante).
@export var follow_height: float = 0.6

## Rigidez do seguimento. Maior = mais colada (menos lag, esconde menos
## o degrau da rede); menor = mais suave (mais lag). A constante de
## tempo é ~1/valor: 12 => ~83 ms de suavidade, na escala certa pra
## diluir o tick de rede de ~66 ms. Faixa útil pra testar: 8 a 18.
@export var follow_smoothing: float = 12.0

@onready var pitch_pivot: Node3D = $CameraPitch
@onready var character: Node3D = owner


func _ready() -> void:
	top_level = true
	global_position = character.global_position + Vector3(0, follow_height, 0)

	if not is_multiplayer_authority():
		set_process(false)
		set_process_unhandled_input(false)
		return

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var target: Vector3 = character.global_position + Vector3(0, follow_height, 0)
	# Suavização exponencial independente de framerate: mesmo resultado
	# a 60 ou 120 fps (lerp com peso fixo*delta NÃO tem essa garantia).
	var weight: float = 1.0 - exp(-follow_smoothing * delta)
	global_position = global_position.lerp(target, weight)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)
		return

	if event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var y_sign: float = -1.0 if invert_y else 1.0

		rotate_y(-event.relative.x * mouse_sensitivity)

		var pitch: float = pitch_pivot.rotation.x + (event.relative.y * mouse_sensitivity * y_sign)
		pitch = clamp(pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
		pitch_pivot.rotation.x = pitch
