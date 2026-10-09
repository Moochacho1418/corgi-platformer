extends Node2D


@export var fire_interval = 1.0
@export var bullet_speed = 300
@export var direction = Vector2.LEFT
@export var projectile_scene: PackedScene

func _ready():
	$Timer.wait_time = fire_interval
	$Timer.start()

func _on_Timer_timeout():
	if projectile_scene:
		var bullet = projectile_scene.instantiate()
		bullet.position = global_position
		bullet.speed = bullet_speed
		bullet.direction = direction
		get_parent().add_child(bullet)
