extends Node

## Varre linha de visão entre cada personagem jogador e cada alvo
## marcável (GDD 5.2). Só roda no host (RM-03: toda IA/lógica de
## detecção roda só no host). Sem cone de mira: raycast simples da
## posição do personagem até o alvo — a câmera é 100% local e nunca
## trafega pela rede (regra travada do CLAUDE.md), então "manter linha
## de visão" não pode depender de pra onde a câmera do jogador está
## virada. Custo aceito: um personagem de costas pro alvo ainda marca.

const MARK_DURATION: float = 2.0
const MAX_RANGE: float = 12.0
const EYE_HEIGHT: float = 0.6
const SCENARIO_MASK: int = 1

@onready var players: Node3D = $"../Players"

var _sight_timers: Dictionary = {}  # "<char_iid>:<target_iid>" -> segundos acumulados


func _ready() -> void:
	if not multiplayer.is_server():
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	var space_state: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	var markables: Array = get_tree().get_nodes_in_group("markable")

	for character in players.get_children():
		if not character is CharacterBody3D:
			continue
		var stats: CharacterStats = character.stats
		if not stats:
			continue

		for markable in markables:
			if markable.marked:
				continue
			if markable.requires_flying and not stats.can_fly:
				continue

			var target: Node3D = markable.get_parent()
			var key: String = "%d:%d" % [character.get_instance_id(), target.get_instance_id()]
			if _has_line_of_sight(space_state, character, target, markable.sight_offset):
				var elapsed: float = _sight_timers.get(key, 0.0) + delta
				_sight_timers[key] = elapsed
				if elapsed >= MARK_DURATION:
					markable.mark()
					_sight_timers.erase(key)
			else:
				_sight_timers.erase(key)


func _has_line_of_sight(space_state: PhysicsDirectSpaceState3D, character: Node3D, target: Node3D, sight_offset: Vector3) -> bool:
	var from: Vector3 = character.global_position + Vector3(0, EYE_HEIGHT, 0)
	var to: Vector3 = target.global_position + sight_offset
	if from.distance_to(to) > MAX_RANGE:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to, SCENARIO_MASK)
	var result: Dictionary = space_state.intersect_ray(query)
	return result.is_empty()
