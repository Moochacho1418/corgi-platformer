extends Area2D

func _on_hazard_body_entered(body):
	if body.has_method("take_damage"):
		body.take_damage(1, global_position)
