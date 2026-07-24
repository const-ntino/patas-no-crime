extends Node

## Decide QUANDO e ONDE spawnar personagens e itens, e fixa a autoridade
## de cada parte da cena de personagem. Vive na cena de jogo, não é
## autoload. Regra de autoridade (RM-02, RM-03): CORPO sempre do host;
## só PlayerInput e CameraRig têm autoridade do peer dono.
##
## IMPORTANTE (lição da sessão 2 do M1): todo spawn inicial é adiado
## com call_deferred. O _ready() dos irmãos roda na ordem da árvore,
## então um spawner que vem DEPOIS do GameManager na árvore ainda não
## se inicializou quando o _ready() daqui roda — spawnar nesse momento
## falha ou, pior, adiciona nós que o spawner nunca rastreia (aparecem
## no host e nunca replicam). call_deferred garante que toda a cena
## terminou o _ready antes de qualquer spawn, independente da ordem
## dos nós.

const CharacterScene := preload("res://scenes/characters/character.tscn")
const ItemScene := preload("res://scenes/interactables/item.tscn")
const HumanScene := preload("res://scenes/characters/human_npc.tscn")
const DogScene := preload("res://scenes/characters/dog_npc.tscn")

signal match_state_changed(time_remaining: float, delivered_ids: Array[StringName], match_state: int, score: int)

enum MatchState { SETUP, ACTIVE, VICTORY, DEFEAT }

const MATCH_DURATION: float = 12.0 * 60.0

## Casa redimensionada 2x na sessão 10 do M1 (a estrutura do greybox
## ganhou scale = Vector3(2,2,2) nos 4 contêineres Node3D). Todos os
## pontos deste arquivo têm coordenadas em metros do mundo, que foram
## afinadas pra casa 1x — então cada Vector3 aqui foi multiplicado por 2
## pra continuar caindo no mesmo cômodo da casa 2x. Personagens, cápsulas
## e a malha de navegação (agent_radius etc.) NÃO escalaram: descrevem o
## corpo/os sentidos do animal, não o tamanho da casa.
const SPAWN_POINTS: Array[Vector3] = [
	Vector3(2.6, 2, -2),
	Vector3(5.4, 2, -2),
	Vector3(2.6, 2, -0.6),
	Vector3(5.4, 2, -0.6),
]

const PLAYER_COLORS: Array[Color] = [
	Color(0.9, 0.4, 0.1),
	Color(0.1, 0.5, 0.9),
	Color(0.2, 0.8, 0.3),
	Color(0.9, 0.2, 0.6),
]

const STATS: Array[CharacterStats] = [
	preload("res://resources/characters/raccoon_stats.tres"),
	preload("res://resources/characters/bird_stats.tres"),
]

## Os 3 objetivos da fase MVP (GDD 6.3), cada um ensinando uma mecânica.
## class: 0=Leve, 1=Médio, 2=Pesado, 3=Fixo-arrastável (Item.Class).
## Posições em coordenadas da casa 2x (ver nota em SPAWN_POINTS), estimadas
## a partir da geometria das paredes dobradas — mesmo espírito de estimativa
## da HUMAN_ROUTE: o cômodo está certo, o ponto exato pode precisar de
## ajuste visual depois de testar ao vivo.
##
## 1) Chave (Leve) ALTA no hall: ensina verticalidade (só o pássaro voando
##    alcança nesta roster do MVP). item.gd a mantém congelada no gancho até
##    a primeira coleta; depois ela volta a obedecer física normal.
## 2) Controle remoto (Médio) na sala, junto do sofá / ponto de rotina
##    principal: ensina rotina, janela de tempo e esconderijo.
## 3) Pote de comida (Pesado) na cozinha, sobre a rota de patrulha do
##    cachorro (DOG_PATROL_POINTS): objetivo clímax, aula de coordenação
##    total (GDD 6.3, princípio 4 de 6.1: Pesado no ponto de máxima
##    exposição).
const OBJECTIVES := [
	{ "id": &"car_key", "pos": Vector3(3.0, 4.0, 3.0), "class": Item.Class.LEVE },
	{ "id": &"remote", "pos": Vector3(10.5, 1.0, 13.0), "class": Item.Class.MEDIO },
	{ "id": &"food_pot", "pos": Vector3(22.0, 1.0, 6.0), "class": Item.Class.PESADO },
]

## Rotina do humano da Casa da Rua 7 (GDD 6.2): sofá, cozinha, banheiro,
## quarto, nessa ordem, em loop. Coordenadas são minha mel+hor estimativa
## a partir da geometria das paredes (sessão 3, M1) — o caminho ENTRE os
## pontos é resolvido pela malha de navegação (NavigationAgent3D), só a
## posição de cada ponto pode precisar de ajuste visual depois de testar.
const HUMAN_ROUTE: Array[Vector3] = [
	Vector3(9.0, 2.0, 13.0),   # sofá (sala, térreo)
	Vector3(25.0, 2.0, 13.0),  # cozinha (balcão, térreo)
	Vector3(3.0, 7.6, 13.0),   # banheiro (andar superior)
	Vector3(23.0, 7.6, 9.0),   # quarto (andar superior)
]

## Cachorro (GDD 5.6, sessão 8): dorme na sala (GDD 6.2), patrulha 2
## pontos no térreo — mesmo espírito de estimativa da HUMAN_ROUTE,
## deliberadamente longe do vão da escada (x 6.2-10.6, z<1.6).
const DOG_SLEEP_POINT: Vector3 = Vector3(8.0, 1.0, 6.5)
const DOG_PATROL_POINTS: Array[Vector3] = [
	Vector3(6.0, 1.0, 3.0),
	Vector3(10.0, 1.0, 3.0),
]

## Item de comida de teste (GDD 5.6: suborno de cachorro) — perto do
## ponto de sono do cachorro, pra dar pra testar sem precisar carregar
## de longe.
const FOOD_ITEM_POS: Vector3 = Vector3(7.0, 1.0, 5.5)

@onready var spawner: MultiplayerSpawner = $"../MultiplayerSpawner"
@onready var players: Node3D = $"../Players"
@onready var item_spawner: MultiplayerSpawner = $"../Items/ItemSpawner"
@onready var items: Node3D = $"../Items"
@onready var humans: Node3D = $"../Humans"
@onready var dogs: Node3D = $"../Dogs"
@onready var nav_region: NavigationRegion3D = $"../NavigationRegion3D"

var match_seed: int = 0
var delivered_objectives: Dictionary[StringName, bool] = {}
var match_state: MatchState = MatchState.SETUP
var match_time_remaining: float = MATCH_DURATION
var score: int = 0
var capture_count: int = 0
var _last_broadcast_second: int = -1


func _ready() -> void:
	add_to_group("game_manager")
	spawner.spawn_function = _spawn_character
	# ItemSpawner NÃO usa spawn_function: itens entram por add_child em
	# Items e o spawner (observando Items via Spawn Path) replica sozinho.

	if multiplayer.is_server():
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		# Adiado: roda depois que TODOS os nós da cena completaram _ready.
		_server_start.call_deferred()
	else:
		multiplayer.connected_to_server.connect(_request_match_state)


func _server_start() -> void:
	match_seed = randi()
	print("Seed da partida: %d" % match_seed)

	# A NavigationRegion3D precisa de vários frames de física depois de
	# entrar na árvore pra terminar de se registrar no NavigationServer
	# (achado empírico via CLI headless, sessão 3 do M1: assar cedo
	# demais produz uma malha com vértices "corretos" na aparência, mas
	# que falha silenciosamente em toda consulta de caminho). 1 frame
	# (o que call_deferred já dá de graça) não é suficiente.
	for i in 10:
		await get_tree().physics_frame
	nav_region.bake_navigation_mesh(false)  # síncrono: precisa terminar antes do humano andar

	_spawn_for_peer(1)  # o próprio host também tem um personagem
	_spawn_objectives()
	_spawn_food_item()
	_spawn_human()
	_spawn_dog()
	var cage: Cage = get_tree().get_first_node_in_group("cage") as Cage
	if cage:
		cage.animal_captured.connect(_on_animal_captured)
	_start_match()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or match_state != MatchState.ACTIVE:
		return
	match_time_remaining = maxf(0.0, match_time_remaining - delta)
	var whole_seconds: int = int(ceil(match_time_remaining))
	if whole_seconds != _last_broadcast_second:
		_last_broadcast_second = whole_seconds
		_broadcast_match_state()
	if match_time_remaining <= 0.0:
		_finish_match(MatchState.DEFEAT)


func _on_peer_connected(peer_id: int) -> void:
	_spawn_for_peer(peer_id)
	_send_match_state_to_peer.call_deferred(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	var node := players.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()


func _spawn_for_peer(peer_id: int) -> void:
	spawner.spawn(peer_id)


## Chamada em TODOS os peers com o mesmo peer_id, garantindo fiação de
## autoridade idêntica dos dois lados.
func _spawn_character(peer_id: int) -> Node:
	var character := CharacterScene.instantiate()
	character.name = str(peer_id)

	var index: int = players.get_child_count()
	character.position = SPAWN_POINTS[index % SPAWN_POINTS.size()]
	character.stats = STATS[index % STATS.size()]

	character.set_multiplayer_authority(1)

	var camera_rig: Node = character.get_node("VisualRoot/CameraRig")
	camera_rig.set_multiplayer_authority(peer_id)

	var player_input: Node = character.get_node("PlayerInput")
	player_input.set_multiplayer_authority(peer_id)

	var mesh: MeshInstance3D = character.get_node("VisualRoot/MeshInstance3D")
	var material := StandardMaterial3D.new()
	material.albedo_color = PLAYER_COLORS[index % PLAYER_COLORS.size()]
	mesh.set_surface_override_material(0, material)

	return character


## Só o host cria objetivos. setup() define sua classe e identidade ANTES
## de add_child; ItemSpawner replica a criação e a remoção para clientes.
func _spawn_objectives() -> void:
	for data: Dictionary in OBJECTIVES:
		var item := ItemScene.instantiate()
		item.name = "objective_%s" % String(data["id"])
		item.position = data["pos"]
		item.setup(data["class"], data["id"])
		items.add_child(item)


## Chamado pela DeliveryZone somente no host. A remoção do nó é o estado
## replicado para os peers nesta sessão; a tabela local prepara a Sessão 11
## para consultar progresso/vitória sem inferir pela física do item.
func deliver_objective(item: Item, _carrier: CharacterBody3D) -> void:
	if not multiplayer.is_server() or match_state != MatchState.ACTIVE or item.objective_id.is_empty():
		return
	if delivered_objectives.get(item.objective_id, false):
		return
	delivered_objectives[item.objective_id] = true
	item._apply_delivered.rpc()
	item.queue_free()
	print("Objetivo entregue: %s" % item.objective_id)
	if delivered_objectives.size() == OBJECTIVES.size():
		_finish_match(MatchState.VICTORY)
	else:
		_broadcast_match_state()


func _start_match() -> void:
	match_state = MatchState.ACTIVE
	match_time_remaining = MATCH_DURATION
	_last_broadcast_second = int(MATCH_DURATION)
	_broadcast_match_state()


func _finish_match(outcome: MatchState) -> void:
	if match_state != MatchState.ACTIVE:
		return
	match_state = outcome
	score = delivered_objectives.size() * 1000
	if outcome == MatchState.VICTORY:
		var elapsed: float = MATCH_DURATION - match_time_remaining
		if elapsed < 8.0 * 60.0:
			score += 1000  # Relâmpago (GDD 7.1)
		if capture_count == 0:
			score += 500  # Sem capturas (GDD 7.1)
	for player in players.get_children():
		if player is CharacterBody3D:
			player.is_match_finished = true
	_broadcast_match_state()


func _on_animal_captured(_animal: CharacterBody3D) -> void:
	if match_state == MatchState.ACTIVE:
		capture_count += 1


func _objective_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for objective_id in delivered_objectives:
		ids.append(objective_id)
	return ids


func _broadcast_match_state() -> void:
	_apply_match_state.rpc(match_time_remaining, _objective_ids(), match_state, score)


func _send_match_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_apply_match_state.rpc_id(peer_id, match_time_remaining, _objective_ids(), match_state, score)


func _request_match_state() -> void:
	_request_match_state_rpc.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_match_state_rpc() -> void:
	if not multiplayer.is_server():
		return
	_send_match_state_to_peer(multiplayer.get_remote_sender_id())


@rpc("authority", "call_local", "reliable")
func _apply_match_state(time_remaining: float, delivered_ids: Array[StringName], new_match_state: int, new_score: int) -> void:
	match_time_remaining = time_remaining
	match_state = new_match_state
	score = new_score
	match_state_changed.emit(match_time_remaining, delivered_ids, match_state, score)


## Só o host cria o humano. Autoridade sempre do host (RM-03: toda IA
## roda só no host) — não precisa set_multiplayer_authority explícito
## porque 1 já é a autoridade padrão de qualquer nó, mas fica explícito
## aqui pra seguir o mesmo padrão de fiação de autoridade do resto do
## arquivo.
func _spawn_human() -> void:
	var human := HumanScene.instantiate()
	human.name = "human_0"
	human.set_multiplayer_authority(1)
	human.setup(HUMAN_ROUTE, match_seed)  # ANTES do add_child (mesmo padrão de item.gd)
	humans.add_child(human)


## Item de comida de teste (suborno de cachorro, GDD 5.6). Mesmo
## padrão de _spawn_test_items(): setup() antes do add_child.
func _spawn_food_item() -> void:
	var item := ItemScene.instantiate()
	item.name = "food_0"
	item.position = FOOD_ITEM_POS
	item.setup(Item.Class.LEVE)
	item.is_food = true
	items.add_child(item)


## Só o host cria o cachorro. Autoridade sempre do host (RM-03), mesmo
## padrão de _spawn_human().
func _spawn_dog() -> void:
	var dog := DogScene.instantiate()
	dog.name = "dog_0"
	dog.set_multiplayer_authority(1)
	dog.setup(DOG_PATROL_POINTS, DOG_SLEEP_POINT)  # ANTES do add_child
	dogs.add_child(dog)
