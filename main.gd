
extends Node2D

@export var player_scene: PackedScene

@onready var host_button: Button = $CanvasLayer/HostButton
@onready var join_button: Button = $CanvasLayer/JoinButton
@onready var room_code_input: LineEdit = $CanvasLayer/RoomCodeInput
@onready var status_label: Label = $CanvasLayer/StatusLabel


func _ready() -> void:
	host_button.disabled = true
	join_button.disabled = true

	# UI signals
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

	# EOS signals
	EosManager.eos_ready.connect(_on_eos_ready)
	EosManager.lobby_created.connect(_on_lobby_created)
	EosManager.lobby_joined.connect(_on_lobby_joined)
	EosManager.lobby_left.connect(_on_lobby_left)
	EosManager.eos_error.connect(_on_eos_error)

	# Multiplayer signals
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)

	status_label.text = "Connecting to EOS..."
	EosManager.initialize_and_login()


func _on_eos_ready() -> void:
	status_label.text = "Ready"
	set_buttons_enabled(true)


func _on_host_pressed() -> void:
	set_buttons_enabled(false)
	status_label.text = "Creating room..."
	EosManager.host_with_code()


func _on_join_pressed() -> void:
	var code = room_code_input.text.strip_edges().to_upper()

	if code.length() != 5:
		status_label.text = "Enter a 5-character room code"
		return

	set_buttons_enabled(false)
	status_label.text = "Joining room..."
	EosManager.join_with_code(code)


func _on_lobby_created(room_code: String) -> void:
	status_label.text = "Hosting room: " + room_code
	room_code_input.text = room_code

	# Spawn the host's player
	add_player(multiplayer.get_unique_id())


func _on_lobby_joined() -> void:
	status_label.text = "Connected to host"


func _on_lobby_left() -> void:
	for child in get_children():
		if child is CharacterBody2D:
			child.queue_free()

	status_label.text = "Disconnected"
	set_buttons_enabled(EosManager.is_eos_ready)


func _on_eos_error(message: String) -> void:
	status_label.text = message
	push_error(message)

	if EosManager.current_lobby == null:
		set_buttons_enabled(EosManager.is_eos_ready)


func set_buttons_enabled(enabled: bool) -> void:
	host_button.disabled = not enabled
	join_button.disabled = not enabled


# PLAYER SPAWNING

func add_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	if has_node(str(peer_id)):
		return

	var player = player_scene.instantiate()
	player.name = str(peer_id)

	add_child(player)


func remove_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	var player = get_node_or_null(str(peer_id))

	if player:
		player.queue_free()
