extends CharacterBody2D

@export var speed: float = 300.0


func _enter_tree() -> void:
	# Give control of this player to the correct peer.
	var peer_id = int(str(name))

	# Authority means which peer is responsible for updating this node.
	# This also sets authority on its children, including the synchronizer.
	# Do this on every machine, before the node is fully ready.
	set_multiplayer_authority(peer_id)


func _physics_process(_delta: float) -> void:
	# Every computer has a copy of each player, but only the owner reads
	# input and moves this particular player. The other copies receive
	# position updates through MultiplayerSynchronizer.
	if not is_multiplayer_authority():
		return

	# Normal Godot movement code: it does not need to know anything about EOS.
	var direction = Input.get_vector(
		"ui_left", "ui_right", "ui_up", "ui_down"
	)
	velocity = direction * speed
	move_and_slide()
