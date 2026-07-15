class_name CharacterStats
extends Resource

## Dados de tuning por animal. Formato que a tabela de atributos do
## GDD (seção 3) vai preencher progressivamente a partir de M1
## (velocidade, furtividade, capacidade de carga, alcance vertical).
##
## Os valores concretos de move_speed neste M0 são placeholders
## arbitrários só pra provar que a diferenciação por Resource funciona
## — não são a escala de 1 a 5 do GDD, que é relativa pra balanceamento,
## não m/s literal. Tuning de verdade acontece quando houver mais
## mecânica pra calibrar contra (M1+).

@export var display_name: String = "Animal"
@export var move_speed: float = 5.0
@export var sneak_speed_multiplier: float = 0.5
