extends CanvasLayer

@onready var label: Label = $Label


func _process(_delta: float) -> void:
	var role: String = "HOST" if NetworkManager.is_server else "CLIENTE"
	var peer_id: int = multiplayer.get_unique_id()
	label.text = "%s — peer id: %d" % [role, peer_id]
