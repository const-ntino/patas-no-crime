extends Node
class_name Markable

## Componente reutilizável: marca um alvo (humano, item, esconderijo,
## rota) como visto pela equipe (GDD 5.2). "marked" é permanente, nunca
## desmarca — replicado por evento discreto (@rpc call_local), mesmo
## padrão de Door.is_open (door.gd), não por MultiplayerSynchronizer
## contínuo.
##
## requires_flying = true restringe quem PODE marcar este alvo a
## personagens com stats.can_fly (GDD 5.2: "rota marcada, só pelo
## pássaro").

@export var requires_flying: bool = false
## Ponto de mira relativo à origem do alvo, pra raycast e ícone de HUD.
## Necessário pra Door: a própria folha (colisão camada 1, igual ao
## cenário) bloqueia a linha de visão até a origem do nó — mirar acima
## dela, no vão da porta/janela, evita o alvo se auto-obstruir.
@export var sight_offset: Vector3 = Vector3.ZERO

var marked: bool = false

signal became_marked


func _ready() -> void:
	add_to_group("markable")


## Chamado só pelo host (ScoutingManager). Idempotente.
func mark() -> void:
	if marked:
		return
	_apply_marked.rpc()


@rpc("call_local")
func _apply_marked() -> void:
	if marked:
		return
	marked = true
	became_marked.emit()
