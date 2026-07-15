extends Node3D

## Suaviza posição e rotação visuais em relação ao estado lógico do
## personagem (Character e FacingSync, ambos irmãos ou pai deste nó).
## Necessário porque os dois são sincronizados por rede a ~15 Hz
## (TransformSync) em quem não é o host — sem suavização, o personagem
## "salta" de posição e de direção a cada tick, mais perceptível quanto
## mais rápido ou mais ágil o animal.
##
## No host, os valores lógicos já atualizam a 60 Hz de física local:
## copiamos direto, sem lerp, pra não introduzir atraso onde não existe
## problema.

@export var interpolation_speed: float = 15.0

@onready var logical_body: Node3D = get_parent()
@onready var facing_sync: Node3D = logical_body.get_node("FacingSync")
@onready var mesh_instance: Node3D = $MeshInstance3D


func _process(delta: float) -> void:
	if logical_body.is_multiplayer_authority():
		global_position = logical_body.global_position
		mesh_instance.global_rotation = facing_sync.global_rotation
		return

	global_position = global_position.lerp(logical_body.global_position, interpolation_speed * delta)
	mesh_instance.rotation.y = lerp_angle(mesh_instance.rotation.y, facing_sync.rotation.y, interpolation_speed * delta)
