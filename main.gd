extends Node2D

# Assign player.tscn to this property in the Main node's Inspector.
@export var player_scene: PackedScene

# These paths must match the node names in main.tscn.
@onready var host_button: Button = $CanvasLayer/HostButton
@onready var join_button: Button = $CanvasLayer/JoinButton
@onready var room_code_input: LineEdit = $CanvasLayer/RoomCodeInput
@onready var status_label: Label = $CanvasLayer/StatusLabel

# Players spawn about the centre and arranged in two rings (if needed)
const SPAWN_CENTRE = Vector2(576, 324)
const INNER_RADIUS = 100.0
const OUTER_RADIUS = 200.0

# Maps each player's peer ID to their spawn index.
var player_slots: Dictionary = {}

@onready var spawner = $MultiplayerSpawner

func _ready() -> void:
	# Do not let the user host or join until EOS is ready.
	host_button.disabled = true
	join_button.disabled = true

	# Connect button signals in code rather than in the editor.
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)

	# Listen to our Autoload. These signals report the outcome of EOS requests.
	EOSManager.eos_ready.connect(_on_eos_ready)
	EOSManager.lobby_created.connect(_on_lobby_created)
	EOSManager.lobby_joined.connect(_on_lobby_joined)
	EOSManager.lobby_left.connect(_on_lobby_left)
	EOSManager.eos_error.connect(_on_eos_error)

	# Godot tells us when another peer connects or disconnects.
	# Only the server will act on these signals (see add_player/remove_player).
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)

	# Tell the spawner how to spawn
	spawner.spawn_function = spawn_player

	# Connect all signals BEFORE requesting login, so we never miss a response.
	status_label.text = "Connecting to EOS..."
	EOSManager.initialize_and_login()


func _on_eos_ready() -> void:
	status_label.text = "Ready"
	set_buttons_enabled(true)


func _on_host_pressed() -> void:
	# Prevent another button press while the request is in progress.
	set_buttons_enabled(false)
	status_label.text = "Creating room..."
	# The manager generates a code when no code is supplied.
	EOSManager.host_with_code()


func _on_join_pressed() -> void:
	var code = room_code_input.text.strip_edges().to_upper()
	if code.length() != 5:
		status_label.text = "Enter a 5-character room code"
		return
	set_buttons_enabled(false)
	status_label.text = "Joining room..."
	EOSManager.join_with_code(code)


func _on_lobby_created(room_code: String) -> void:
	# Share this code with the other players.
	status_label.text = "Hosting room: " + room_code
	room_code_input.text = room_code

	# The host does not get a peer_connected signal for itself.
	# Spawn its player explicitly. Godot's server peer ID is 1.
	add_player(multiplayer.get_unique_id())


func _on_lobby_joined() -> void:
	# The client does NOT spawn its own player. The host does that for us.
	status_label.text = "Connected to host"


func _on_lobby_left() -> void:
	# Clear any remaining player nodes when returning to the lobby UI.
	for child in get_children():
		if child is CharacterBody2D:
			child.queue_free()
	player_slots.clear()

	status_label.text = "Disconnected"
	
	set_buttons_enabled(EOSManager.is_eos_ready)


func _on_eos_error(message: String) -> void:
	# Show errors both in the game window and the Godot output/debugger.
	status_label.text = message
	push_error(message)
	if EOSManager.current_lobby == null:
		set_buttons_enabled(EOSManager.is_eos_ready)


func set_buttons_enabled(enabled: bool) -> void:
	host_button.disabled = not enabled
	join_button.disabled = not enabled



func add_player(peer_id: int) -> void:
	# Only the host decides when and where players spawn.
	if not multiplayer.is_server():
		return

	if player_slots.has(peer_id):
		return

	# Find the first available spawn index.
	# This also allows us to reuse slots when players leave.
	for i in range(20):
		if not player_slots.values().has(i):
			player_slots[peer_id] = i

			# Send the peer ID and spawn position to all peers.
			spawner.spawn({
				"peer_id": peer_id,
				"position": get_spawn_position(i)
			})
			return


func get_spawn_position(index: int) -> Vector2:
	var radius: float
	var angle: float

	if index < 8:
		# Inner ring: 8 equally spaced positions.
		radius = INNER_RADIUS
		angle = TAU * index / 8.0
	else:
		# Outer ring: 12 equally spaced positions.
		radius = OUTER_RADIUS
		angle = TAU * (index - 8) / 12.0

	# Rotate by 90 degrees so each ring starts at the top.
	angle -= PI / 2.0

	# Convert polar coordinates to Cartesian coordinates.
	var offset = Vector2(cos(angle), sin(angle)) * radius

	return SPAWN_CENTRE + offset


func spawn_player(data: Dictionary) -> Node:
	# This function runs on every peer, ensuring that
	# each computer creates the same player.
	var player = player_scene.instantiate()

	player.name = str(data["peer_id"])
	player.position = data["position"]

	# MultiplayerSpawner adds the node to the scene tree.
	return player


func remove_player(peer_id: int) -> void:
	if not multiplayer.is_server():
		return

	# Make this spawn slot available for another player.
	player_slots.erase(peer_id)

	var player = get_node_or_null(str(peer_id))

	if player:
		player.queue_free()
