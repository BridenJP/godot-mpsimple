extends Node

# This Autoload is the bridge between our game and Epic Online Services.
# Other scripts use EOSManager instead of dealing directly with EOS.

# Signals tell main.gd when an asynchronous operation has finished.
signal eos_ready
signal lobby_created(room_code: String)
signal lobby_joined
signal eos_error(message: String)
signal lobby_left

# Your teacher supplies these five values for your group's game.
# All copies of the same game must use the same product/deployment.
# Never use trusted-server credentials in a game client.
const PRODUCT_ID: String = "78078644fee046bca2822227ecec3141"
const SANDBOX_ID: String = "28e27dd8e7704093be5bf9dfe2e8d2b5"
const DEPLOYMENT_ID: String = "f94b93d171d04d38bd26390401f75c73"
const CLIENT_ID: String = "xyza78912zofMEOJt4Kdk0exG58346w2"
const CLIENT_SECRET: String = "5Y06jCUboKH1EoC6FVZaF8H2GS9aTNasCGEPOuvXuZY"

# Both ends of the connection must use the same socket name.
const SOCKET_NAME = "MySocket"

# This is the name of the searchable lobby property, not the code itself.
const ROOM_ATTRIBUTE = "ROOM_CODE"

# Control the maximum number of players
const MAX_PLAYERS = 20 # Includes the host.

# Keep references so we can disconnect and leave the lobby later.
var current_lobby: HLobby
var peer: EOSGMultiplayerPeer
var is_eos_ready: bool = false
var current_room_code: String = ""


func _ready() -> void:
	# Godot emits these signals as the network connection changes.
	# Joining an EOS lobby is not the same as connecting to a game host.
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func initialize_and_login() -> void:
	# Avoid setting up EOS twice if it is already ready.
	if is_eos_ready:
		eos_ready.emit()
		return

	# Tell the EOSG plugin which Epic product our game belongs to.
	var credentials = HCredentials.new()
	credentials.product_name = "MyMultiplayerGame"
	credentials.product_version = "1.0"
	credentials.product_id = PRODUCT_ID
	credentials.sandbox_id = SANDBOX_ID
	credentials.deployment_id = DEPLOYMENT_ID
	credentials.client_id = CLIENT_ID
	credentials.client_secret = CLIENT_SECRET

	# await suspends this function until EOS finishes; the game can keep running.
	var success = await HPlatform.setup_eos_async(credentials)
	if not success:
		eos_error.emit("EOS initialisation failed")
		return

	# We do not use Epic account presence for this anonymous login example.
	HLobbies.presence_enabled = false

	# Device ID login gives EOS a player identity without an account popup.
	# Two game instances on one computer may share the same EOS identity.
	success = await HAuth.login_anonymous_async("Player")
	if not success:
		eos_error.emit("EOS anonymous login failed")
		return

	# Only now should the UI allow hosting or joining.
	is_eos_ready = true
	print("EOS ready")
	eos_ready.emit()


func generate_room_code() -> String:
	# Avoid easily confused characters such as O & 0.
	# Random codes are convenient, but not guaranteed unique or private.
	# Note that codes use lower case. Later when checking, user entered code is converted to lower case.
	const CHARACTERS = "abcdefghijkmnopqrstuvwxyz023456789"
	var code = ""
	for i in range(5):
		code += CHARACTERS[randi_range(0, CHARACTERS.length() - 1)]
	return code


func host_with_code(room_code: String = "") -> void:
	# We must be logged in and not already in a lobby.
	if not is_eos_ready:
		eos_error.emit("EOS is not ready")
		return
	if current_lobby != null:
		eos_error.emit("Already in a lobby")
		return

	# Generate a code if the caller did not supply one.
	if room_code.is_empty():
		room_code = generate_room_code()
	room_code = room_code.strip_edges().to_lower()

	# A lobby is a record held by EOS so other players can find us.
	# It is not the game world and does not synchronise player movement.
	var opts = EOS.Lobby.CreateLobbyOptions.new()
	opts.bucket_id = "DefaultBucket"
	opts.max_lobby_members = MAX_PLAYERS
	opts.presence_enabled = false
	opts.permission_level = EOS.Lobby.LobbyPermissionLevel.PublicAdvertised
	opts.disable_host_migration = true

	current_lobby = await HLobbies.create_lobby_async(opts)
	if current_lobby == null:
		eos_error.emit("Failed to create lobby")
		return

	# Create the host's actual game networking connection.
	# EOSGMultiplayerPeer plugs EOS P2P into Godot's multiplayer API.
	peer = EOSGMultiplayerPeer.new()
	var result = peer.create_server(SOCKET_NAME)
	if result != OK:
		await leave_lobby()
		eos_error.emit("Failed to create server: " + str(result))
		return

	# From now on Godot can send multiplayer messages using EOS.
	multiplayer.multiplayer_peer = peer

	# Publish the room code after the server is ready to accept connections.
	# add_attribute prepares the change; update_async sends it to EOS.
	current_lobby.add_attribute(ROOM_ATTRIBUTE, room_code)
	var success = await current_lobby.update_async()
	if not success:
		await leave_lobby()
		eos_error.emit("Failed to publish room code")
		return

	# Notify main.gd so it can display the code and spawn the host player.
	current_room_code = room_code
	print("Hosting room: ", room_code)
	lobby_created.emit(room_code)


func join_with_code(room_code: String) -> void:
	if not is_eos_ready:
		eos_error.emit("EOS is not ready")
		return
	if current_lobby != null:
		eos_error.emit("Already in a lobby")
		return

	# Normalise the input so upper-case codes work too.
	room_code = room_code.strip_edges().to_lower()
	if room_code.length() != 5:
		eos_error.emit("Invalid room code")
		return

	# Ask EOS for lobbies with a matching ROOM_CODE attribute.
	var lobbies = await HLobbies.search_by_attribute_async({
		"key": ROOM_ATTRIBUTE,
		"value": room_code
	})
	if lobbies == null or lobbies.is_empty():
		eos_error.emit("Room not found: " + room_code)
		return
	# Do not accidentally join the wrong lobby if codes collide.
	if lobbies.size() > 1:
		eos_error.emit("Multiple rooms found with this code")
		return

	# Join the EOS lobby before opening the game connection.
	current_lobby = await HLobbies.join_async(lobbies[0])
	if current_lobby == null:
		eos_error.emit("Failed to join lobby")
		return

	current_room_code = room_code

	# EOS uses the host's Product User ID instead of an IP address.
	# The socket name identifies the P2P connection within our game.
	peer = EOSGMultiplayerPeer.new()
	var result = peer.create_client(
		SOCKET_NAME,
		current_lobby.owner_product_user_id
	)

	if result != OK:
		await leave_lobby()
		eos_error.emit("Failed to create client: " + str(result))
		return

	# Godot now manages the connection. OK above does not mean connected yet.
	multiplayer.multiplayer_peer = peer
	print("Connecting to room: ", room_code)


func leave_lobby() -> void:
	# Shut down the game connection first.
	if peer != null:
		peer.close()
		multiplayer.multiplayer_peer = null
		peer = null

	# The owner destroys the lobby; other players only leave it.
	if current_lobby != null:
		var success: bool
		if current_lobby.is_owner():
			success = await current_lobby.destroy_async()
		else:
			success = await current_lobby.leave_async()
		if not success:
			eos_error.emit("Failed to leave EOS lobby")
			return
		current_lobby = null

	# Clear our local state and tell the UI to reset.
	current_room_code = ""
	lobby_left.emit()


func _on_connected() -> void:
	# The client's game connection has actually completed.
	print("Connected to host")
	lobby_joined.emit()


func _on_connection_failed() -> void:
	await leave_lobby()
	eos_error.emit("Connection to host failed")


func _on_server_disconnected() -> void:
	# No host migration: the game ends for this client if the host leaves.
	await leave_lobby()
	eos_error.emit("Host disconnected")
