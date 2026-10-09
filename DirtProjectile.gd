extends Area2D


@export var speed = 300
@export var direction = Vector2.LEFT

func _process(delta):
	position += direction * speed * delta

func _on_DirtProjectile_body_entered(body):
	if body.has_method("take_damage"):
		body.take_damage(1)
	queue_free()
