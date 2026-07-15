extends Node3D
class_name CameraRig

## Rig de câmera em terceira pessoa. Junto com PlayerInput, é o único
## lugar do projeto autorizado a ler Input.* (CLAUDE.md). 100% local:
## nunca replicado em efeito, nunca participa da simulação — só decide
## PRA ONDE este jogador está olhando. PlayerInput usa a orientação
## deste nó (só o yaw, não o pitch) pra compor a intenção de movimento
## já em espaço de mundo antes de subir pro host.

@export var mouse_sensitivity: float = 0.005
@export var invert_y: bool = false
@export var pitch_min_deg: float = -60.0
@export var pitch_max_deg: float = 10.0

@onready var pitch_pivot: Node3D = $CameraPitch


func _ready() -> void:
	if not is_multiplayer_authority():
		set_process_unhandled_input(false)
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
