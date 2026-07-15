extends Node
class_name PlayerInput

## Único lugar do projeto, junto com o rig de câmera, autorizado a ler
## Input.*. Traduz teclado em intenção: um Vector2 no plano XZ do mundo.
##
## Importante: este nó é replicado em todo peer (MultiplayerSpawner
## instancia a cena do personagem em todo mundo, pra todo mundo poder
## ver todo mundo). Sem o guard de autoridade abaixo, CADA réplica leria
## o teclado LOCAL de cada máquina, e a réplica do personagem do cliente
## rodando na tela do host leria o teclado do host — fazendo todo mundo
## se mover junto. Só a instância que pertence de fato ao peer dono
## deve gerar intenção nova; as demais só recebem o valor via
## MultiplayerSynchronizer (InputSync) e mantêm esse valor sem reescrevê-lo.

var move_direction: Vector2 = Vector2.ZERO
var is_sneaking: bool = false


func _process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return

	var input_vector := Vector2.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.y = Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")

	move_direction = input_vector.normalized() if input_vector.length() > 1.0 else input_vector
	is_sneaking = Input.is_action_pressed("sneak")
