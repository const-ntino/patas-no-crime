extends Area3D
class_name DeliveryZone

## Perímetro da toca (GDD 4.2). O host é a única autoridade que pode
## confirmar uma entrega: entrar na área carregando um objetivo consome o
## item e registra seu id no GameManager.

@onready var game_manager: Node = $"../GameManager"


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not multiplayer.is_server():
		return
	if not body is CharacterBody3D:
		return
	if not "held_item" in body:
		return
	var item: Item = body.held_item
	if item == null or item.objective_id.is_empty():
		return
	game_manager.deliver_objective(item, body)
