extends Node2D

@onready var try_again_button = get_node("Button/TryAgainButton")


func _process(delta):
	if try_again_button.visible and Input.is_action_just_pressed("try_again"):
		get_tree().reload_current_scene()
