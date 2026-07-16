extends Node3D
class_name Door

## Porta/janela manipulável (GDD 3.1, RF-01). Estado replicado por
## evento discreto via @rpc, não por MultiplayerSynchronizer contínuo.
## Autoridade padrão do Godot (peer 1, o host); cliente pede via
## rpc_id(1,...), host valida e propaga.

const OPEN_ANGLE_DEG := 90.0
const ANIM_DURATION := 0.4

var is_open: bool = false

@onready var pivot: Node3D = $Pivot


func interact(requester: Node) -> void:
	var stats: CharacterStats = requester.stats
	if not stats or not stats.can_manipulate:
		return
	if requester.held_item and requester.held_item.item_class == Item.Class.PESADO:
		return  # GDD 4.1: item Pesado impede manipular
	_request_toggle_rpc.rpc_id(1)


@rpc("any_peer", "call_local")
func _request_toggle_rpc() -> void:
	if not multiplayer.is_server():
		return
	_apply_open.rpc(not is_open)


@rpc("call_local")
func _apply_open(value: bool) -> void:
	is_open = value
	var target_deg: float = OPEN_ANGLE_DEG if is_open else 0.0
	var tween := create_tween()
	tween.tween_property(pivot, "rotation_degrees:y", target_deg, ANIM_DURATION)
