extends Node

## Gerencia apenas o TRANSPORTE da sessão multiplayer: cria o peer ENet
## como servidor ou cliente. Não sabe nada sobre personagens, spawn ou
## gameplay — essa separação é o que torna a troca de ENet por
## GodotSteam em M2 uma mudança só neste arquivo.

const PORT: int = 8910
const MAX_PLAYERS: int = 4

var is_server: bool = false


func _ready() -> void:
	if "--server" in OS.get_cmdline_args():
		create_server()
	else:
		create_client()


func create_server() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(PORT, MAX_PLAYERS)
	if error != OK:
		push_error("Falha ao criar servidor ENet: %s" % error)
		return
	multiplayer.multiplayer_peer = peer
	is_server = true
	print("NetworkManager: servidor criado na porta %d" % PORT)


func create_client() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_client("127.0.0.1", PORT)
	if error != OK:
		push_error("Falha ao criar cliente ENet: %s" % error)
		return
	multiplayer.multiplayer_peer = peer
	is_server = false
	print("NetworkManager: conectando como cliente em 127.0.0.1:%d" % PORT)
