extends Node

## Decide QUANDO e ONDE spawnar personagens e itens, e fixa a autoridade
## de cada parte da cena de personagem. Vive na cena de jogo, não é
## autoload. Regra de autoridade (RM-02, RM-03): CORPO sempre do host;
## só PlayerInput e CameraRig têm autoridade do peer dono.
##
## IMPORTANTE (lição da sessão 2 do M1): todo spawn inicial é adiado
## com call_deferred. O _ready() dos irmãos roda na ordem da árvore,
## então um spawner que vem DEPOIS do GameManager na árvore ainda não
## se inicializou quando o _ready() daqui roda — spawnar nesse momento
## falha ou, pior, adiciona nós que o spawner nunca rastreia (aparecem
## no host e nunca replicam). call_deferred garante que toda a cena
## terminou o _ready antes de qualquer spawn, independente da ordem
## dos nós.

const CharacterScene := preload("res://scenes/characters/character.tscn")
const ItemScene := preload("res://scenes/interactables/item.tscn")

const SPAWN_POINTS: Array[Vector3] = [
	Vector3(1.3, 1, -1),
	Vector3(2.7, 1, -1),
	Vector3(1.3, 1, -0.3),
	Vector3(2.7, 1, -0.3),
]

const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.4, 0.1),
	Color(0.1, 0.5, 0.9),
	Color(0.2, 0.8, 0.3),
	Color(0.9, 0.2, 0.6),
]

const STATS: Array[CharacterStats] = [
	preload("res://resources/characters/raccoon_stats.tres"),
	preload("res://resources/characters/bird_stats.tres"),
]

## Itens de teste: posição + classe (0=Leve, 1=Médio, 2=Pesado,
## 3=Fixo-arrastável). Ajuste as posições conforme sua cena de teste.
const TEST_ITEMS := [
	{ "pos": Vector3(2, 1, 2), "class": 0 },
	{ "pos": Vector3(3, 1, 2), "class": 1 },
	{ "pos": Vector3(4, 1, 2), "class": 2 },
	{ "pos": Vector3(5, 1, 2), "class": 3 },
]

@onready var spawner: MultiplayerSpawner = $"../MultiplayerSpawner"
@onready var players: Node3D = $"../Players"
@onready var item_spawner: MultiplayerSpawner = $"../ItemSpawner"
@onready var items: Node3D = $"../Items"


func _ready() -> void:
	spawner.spawn_function = _spawn_character
	# ItemSpawner NÃO usa spawn_function: itens entram por add_child em
	# Items e o spawner (observando Items via Spawn Path) replica sozinho.

	if not multiplayer.is_server():
		return

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

	# Adiado: roda depois que TODOS os nós da cena completaram _ready.
	_server_start.call_deferred()


func _server_start() -> void:
	_spawn_for_peer(1)  # o próprio host também tem um personagem
	_spawn_test_items()


func _on_peer_connected(peer_id: int) -> void:
	_spawn_for_peer(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var node := players.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()


func _spawn_for_peer(peer_id: int) -> void:
	spawner.spawn(peer_id)


## Chamada em TODOS os peers com o mesmo peer_id, garantindo fiação de
## autoridade idêntica dos dois lados.
func _spawn_character(peer_id: int) -> Node:
	var character := CharacterScene.instantiate()
	character.name = str(peer_id)

	var index: int = players.get_child_count()
	character.position = SPAWN_POINTS[index % SPAWN_POINTS.size()]
	character.stats = STATS[index % STATS.size()]

	character.set_multiplayer_authority(1)

	var camera_rig: Node = character.get_node("VisualRoot/CameraRig")
	camera_rig.set_multiplayer_authority(peer_id)

	var player_input: Node = character.get_node("PlayerInput")
	player_input.set_multiplayer_authority(peer_id)

	var mesh: MeshInstance3D = character.get_node("VisualRoot/MeshInstance3D")
	var material := StandardMaterial3D.new()
	material.albedo_color = PLAYER_COLORS[index % PLAYER_COLORS.size()]
	mesh.set_surface_override_material(0, material)

	return character


## Só o host cria itens. setup() define a classe ANTES do add_child,
## então ela já viaja no spawn replicado; a posição contínua fica por
## conta do ItemSync de cada item.
func _spawn_test_items() -> void:
	for i in TEST_ITEMS.size():
		var data: Dictionary = TEST_ITEMS[i]
		var item := ItemScene.instantiate()
		item.name = "item_%d" % i
		item.position = data["pos"]
		item.setup(data["class"])
		items.add_child(item)
