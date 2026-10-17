extends Area2D


@export var speed = 300
@export var direction = Vector2.LEFT
@export var lifetime = 5.0

func _ready():
	# Free shots that miss, otherwise they fly forever
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _process(delta):
	position += direction * speed * delta

func _on_DirtProjectile_body_entered(body):
	if body.has_method("take_damage"):
		body.take_damage(1, global_position)
	queue_free()
