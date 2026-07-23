extends Area3D
class_name HidingSpot

## Esconderijo (GDD 5.2, 6.2: "sofá = esconderijo + ponto de rotina").
## Marcável como qualquer outro alvo (via Markable filho). O EFEITO de
## anular detecção visual (GDD 5.2: "espaços que anulam detecção
## visual enquanto o animal estiver neles") ainda não tem detecção
## nenhuma pra anular — estados de alerta são a sessão 5. is_character_inside()
## já fica pronto pra ela consumir; ninguém chama isso ainda.

var _occupants: Array[Node3D] = []


func _ready() -> void:
	add_to_group("hiding_spot")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body not in _occupants:
		_occupants.append(body)


func _on_body_exited(body: Node3D) -> void:
	_occupants.erase(body)


func is_character_inside(character: Node3D) -> bool:
	return character in _occupants
