extends CharacterBody3D

## Corpo do personagem. A simulação só roda onde houver autoridade
## multiplayer. Em sessão 1, sem peers remotos, a autoridade padrão do
## Godot já é local por definição — o guard abaixo não muda nada visível
## ainda, mas é a regra que vai importar a partir da sessão 2, quando o
## host começar a simular também os corpos dos clientes.

@export var move_speed: float = 5.0
@export var sneak_speed_multiplier: float = 0.5

const GRAVITY: float = 9.8

@onready var player_input: PlayerInput = $PlayerInput
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var camera: Camera3D = $CameraFixed


func _ready() -> void:
	# Cada instância do jogo tem uma cópia de TODOS os personagens (pra
	# poder ver os outros jogadores), mas só deve ATIVAR a câmera do
	# personagem que é seu próprio — senão a câmera ativa vira uma
	# loteria de "qual Camera3D entrou primeiro na árvore".
	var is_local_player: bool = player_input.get_multiplayer_authority() == multiplayer.get_unique_id()
	camera.current = is_local_player


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var direction := Vector3(player_input.move_direction.x, 0.0, player_input.move_direction.y)
	var speed: float = move_speed
	if player_input.is_sneaking:
		speed *= sneak_speed_multiplier

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	if direction.length() > 0.01:
		mesh_instance.look_at(mesh_instance.global_position + direction, Vector3.UP)

	move_and_slide()
