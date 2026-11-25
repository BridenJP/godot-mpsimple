
extends Node

signal eos_ready
signal lobby_created(room_code: String)
signal lobby_joined
signal eos_error(message: String)
signal lobby_left

# Epic Developer Portal credentials
const PRODUCT_ID: String = "78078644fee046bca2822227ecec3141"
const SANDBOX_ID: String = "28e27dd8e7704093be5bf9dfe2e8d2b5"
const DEPLOYMENT_ID: String = "f94b93d171d04d38bd26390401f75c73"
const CLIENT_ID: String = "xyza78912zofMEOJt4Kdk0exG58346w2"
const CLIENT_SECRET: String = "5Y06jCUboKH1EoC6FVZaF8H2GS9aTNasCGEPOuvXuZY"

const SOCKET_NAME = "MySocket"
const ROOM_ATTRIBUTE = "ROOM_CODE"
const MAX_PLAYERS = 4

var current_lobby: HLobby
var peer: EOSGMultiplayerPeer
var is_eos_ready: bool = false
var current_room_code: String = ""


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# INITIALISATION AND LOGIN

func initialize_and_login() -> void:
	if is_eos_ready:
		eos_ready.emit()
		return

	var credentials = HCredentials.new()
	credentials.product_name = "MyMultiplayerGame"
	credentials.product_version = "1.0"
	credentials.product_id = PRODUCT_ID
	credentials.sandbox_id = SANDBOX_ID
	credentials.deployment_id = DEPLOYMENT_ID
	credentials.client_id = CLIENT_ID
	credentials.client_secret = CLIENT_SECRET

	var success = await HPlatform.setup_eos_async(credentials)

	if not success:
		eos_error.emit("EOS initialisation failed")
		return

	HLobbies.presence_enabled = false

	success = await HAuth.login_anonymous_async("Player")

	if not success:
		eos_error.emit("EOS anonymous login failed")
		return

	is_eos_ready = true
	print("EOS ready")
	eos_ready.emit()


# ROOM CODE GENERATION

func generate_room_code() -> String:
	const CHARACTERS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

	var code = ""

	for i in range(5):
		code += CHARACTERS[randi_range(0, CHARACTERS.length() - 1)]

	return code


# HOST GAME

func host_with_code(room_code: String = "") -> void:
	if not is_eos_ready:
		eos_error.emit("EOS is not ready")
		return

	if current_lobby != null:
		eos_error.emit("Already in a lobby")
		return

	if room_code.is_empty():
		room_code = generate_room_code()

	room_code = room_code.strip_edges().to_upper()

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

	# Start P2P server
	peer = EOSGMultiplayerPeer.new()

	var result = peer.create_server(SOCKET_NAME)

	if result != OK:
		await leave_lobby()
		eos_error.emit("Failed to create server: " + str(result))
		return

	multiplayer.multiplayer_peer = peer

	# Publish the room code
	current_lobby.add_attribute(ROOM_ATTRIBUTE, room_code)

	var success = await current_lobby.update_async()

	if not success:
		await leave_lobby()
		eos_error.emit("Failed to publish room code")
		return

	current_room_code = room_code

	print("Hosting room: ", room_code)
	lobby_created.emit(room_code)


# JOIN GAME

func join_with_code(room_code: String) -> void:
	if not is_eos_ready:
		eos_error.emit("EOS is not ready")
		return

	if current_lobby != null:
		eos_error.emit("Already in a lobby")
		return

	room_code = room_code.strip_edges().to_upper()

	if room_code.length() != 5:
		eos_error.emit("Invalid room code")
		return

	# Find matching lobby
	var lobbies = await HLobbies.search_by_attribute_async({
		"key": ROOM_ATTRIBUTE,
		"value": room_code
	})

	if lobbies == null or lobbies.is_empty():
		eos_error.emit("Room not found: " + room_code)
		return

	if lobbies.size() > 1:
		eos_error.emit("Multiple rooms found with this code")
		return

	current_lobby = await HLobbies.join_async(lobbies[0])

	if current_lobby == null:
		eos_error.emit("Failed to join lobby")
		return

	current_room_code = room_code

	# Connect to the lobby owner
	peer = EOSGMultiplayerPeer.new()

	var result = peer.create_client(
			SOCKET_NAME,
			current_lobby.owner_product_user_id
	)

	if result != OK:
		await leave_lobby()
		eos_error.emit("Failed to create client: " + str(result))
		return

	multiplayer.multiplayer_peer = peer

	print("Connecting to room: ", room_code)


# LEAVE GAME

func leave_lobby() -> void:
	if peer != null:
		peer.close()
		multiplayer.multiplayer_peer = null
		peer = null

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

	current_room_code = ""
	lobby_left.emit()


# CONNECTION CALLBACKS

func _on_connected() -> void:
	print("Connected to host")
	lobby_joined.emit()


func _on_connection_failed() -> void:
	await leave_lobby()
	eos_error.emit("Connection to host failed")


func _on_server_disconnected() -> void:
	await leave_lobby()
	eos_error.emit("Host disconnected")
