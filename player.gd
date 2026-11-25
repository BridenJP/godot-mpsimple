
extends CharacterBody2D

@export var speed: float = 300.0


func _enter_tree() -> void:
	var peer_id = int(str(name))
	set_multiplayer_authority(peer_id)

	var offset_x = 0.0 if peer_id == 1 else 100.0
	position = Vector2(400 + offset_x, 300)


func _physics_process(_delta: float) -> void:
	if not is_multiplayer_authority():
		return

	var direction = Input.get_vector(
			"ui_left",
			"ui_right",
			"ui_up",
			"ui_down"
	)

	velocity = direction * speed
	move_and_slide()
