class_name CharacterStats
extends Resource

## Dados de tuning por animal. Formato que a tabela de atributos do
## GDD (seção 3) vai preencher progressivamente.

@export var display_name: String = "Animal"
@export var move_speed: float = 5.0
@export var sneak_speed_multiplier: float = 0.5

## Capacidades exclusivas (GDD 3.x). Centralizadas aqui em vez de
## checagem por nome espalhada pelos scripts de gameplay.
@export var can_manipulate: bool = false  # guaxinim: abrir porta/janela/gaveta
@export var can_fly: bool = false          # pássaro: mobilidade vertical livre
