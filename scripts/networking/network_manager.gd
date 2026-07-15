extends Node

## Gerencia a sessão multiplayer: cria o servidor ENet. Único lugar do
## projeto que sabe qual transporte está em uso (ENet agora, GodotSteam
## a partir de M2). Nada de gameplay deve depender de ENet diretamente.
##
## Sessão 1: só cria servidor, mesmo rodando sozinho ("servidor de 1").
## A lógica de conectar como cliente entra na sessão 2, junto com o
## MultiplayerSpawner.

const PORT: int = 8910
const MAX_PLAYERS: int = 4

var is_server: bool = false


func _ready() -> void:
	create_server()


func create_server() -> void:
	var peer := ENetMultiplayerPeer.new()
	var error: Error = peer.create_server(PORT, MAX_PLAYERS)
	if error != OK:
		push_error("Falha ao criar servidor ENet: %s" % error)
		return
	multiplayer.multiplayer_peer = peer
	is_server = true
	print("NetworkManager: servidor criado na porta %d" % PORT)
