extends Node
class_name PlayerInput

## Único lugar do projeto, junto com o rig de câmera, autorizado a ler
## Input.*. Traduz teclado em intenção: um Vector2 no plano XZ do mundo.
##
## Sessão 1: câmera fixa atrás, então o eixo do mundo já coincide com o
## eixo da câmera. A partir da sessão 3 (câmera de verdade), este script
## vai compor a direção relativa à orientação da câmera antes de expor
## move_direction — o corpo (character_body.gd) não muda nada quando
## isso acontecer, porque ele só consome o vetor já pronto.

var move_direction: Vector2 = Vector2.ZERO
var is_sneaking: bool = false


func _process(_delta: float) -> void:
	var input_vector := Vector2.ZERO
	input_vector.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vector.y = Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")

	move_direction = input_vector.normalized() if input_vector.length() > 1.0 else input_vector
	is_sneaking = Input.is_action_pressed("sneak")
