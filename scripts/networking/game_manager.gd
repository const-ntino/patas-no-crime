extends Node

## Decide QUANDO e ONDE spawnar o personagem de cada peer conectado, e
## fixa a autoridade de cada parte da cena de personagem. Vive na cena
## de jogo, não é autoload — cenas diferentes (lobby, fase) podem
## spawnar de formas diferentes.
##
## Regra de autoridade (RM-02, RM-03): o CORPO (CharacterBody3D) é
## sempre autoridade do host (id 1), porque é o host quem simula todo
## mundo. Só o PlayerInput, dentro de cada personagem, tem autoridade
## do peer dono — é dali que a intenção sobe.

const CharacterScene := preload("res://scenes/characters/character.tscn")

const SPAWN_POINTS: Array[Vector3] = [
	Vector3(0, 1, 0),
	Vector3(2, 1, 0),
	Vector3(-2, 1, 0),
	Vector3(0, 1, 2),
]

const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.4, 0.1),
	Color(0.1, 0.5, 0.9),
	Color(0.2, 0.8, 0.3),
	Color(0.9, 0.2, 0.6),
]

@onready var spawner: MultiplayerSpawner = $"../MultiplayerSpawner"
@onready var players: Node3D = $"../Players"


func _ready() -> void:
	spawner.spawn_function = _spawn_character

	if not multiplayer.is_server():
		return

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_spawn_for_peer(1)  # o próprio host também tem um personagem


func _on_peer_connected(peer_id: int) -> void:
	_spawn_for_peer(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var node := players.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()


func _spawn_for_peer(peer_id: int) -> void:
	spawner.spawn(peer_id)


## Chamada em TODOS os peers (host e clientes) com o mesmo peer_id,
## garantindo que a fiação de autoridade fique idêntica dos dois lados
## — é o ponto que citei no plano como o erro clássico de sincronização
## quando os dois lados divergem.
func _spawn_character(peer_id: int) -> Node:
	var character := CharacterScene.instantiate()
	character.name = str(peer_id)

	var index: int = players.get_child_count()
	character.position = SPAWN_POINTS[index % SPAWN_POINTS.size()]

	character.set_multiplayer_authority(1)

	var player_input: Node = character.get_node("PlayerInput")
	player_input.set_multiplayer_authority(peer_id)

	var mesh: MeshInstance3D = character.get_node("MeshInstance3D")
	var material := StandardMaterial3D.new()
	material.albedo_color = PLAYER_COLORS[index % PLAYER_COLORS.size()]
	mesh.set_surface_override_material(0, material)

	return character
