extends Node

const CharacterScene := preload("res://scenes/characters/character.tscn")

const SPAWN_POINTS: Array[Vector3] = [
	Vector3(8, 1, 8),
	Vector3(10, 1, 8),
	Vector3(-2, 1, 0),
	Vector3(0, 1, 2),
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

@onready var spawner: MultiplayerSpawner = $"../MultiplayerSpawner"
@onready var players: Node3D = $"../Players"


func _ready() -> void:
	spawner.spawn_function = _spawn_character

	if not multiplayer.is_server():
		return

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_spawn_for_peer(1)


func _on_peer_connected(peer_id: int) -> void:
	_spawn_for_peer(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var node := players.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()


func _spawn_for_peer(peer_id: int) -> void:
	spawner.spawn(peer_id)


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
