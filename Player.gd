extends CharacterBody2D

# NOTE: `velocity` is built into CharacterBody2D in Godot 4 — do not declare it here.
const SPEED = 200
const JUMP_FORCE = -400
const GRAVITY = 1000
const FLOOR_NORMAL = Vector2.UP

# health
const MAX_HEALTH = 3
var health = MAX_HEALTH

# Wall climbing
const CLIMB_SPEED = -150
const WALL_CLIMB_TIME = 1.5
var is_wall_grabbing = false
var is_wall_climbing = false
var wall_climb_timer = 0.0
var was_on_wall = false
var wall_touch_buffer = 0.0
const WALL_BUFFER_TIME = 0.15

# Dash
var is_dashing = false
var dash_speed = 5000
var dash_duration = 0.3
var dash_timer = 0.0
const MAX_DASHES = 3
const DASH_COOLDOWN = 3.0
var dash_charges = MAX_DASHES
var dash_cooldowns = []

@onready var try_again_button = get_node("/root/Level/Button/TryAgainButton") 

func _physics_process(delta):
	handle_input()
	handle_dash(delta)
	handle_wall_climb_and_grab(delta)
	handle_jump()
	handle_gravity(delta)
	move_player()

	handle_dash_recharge(delta)
	update_animation()

func handle_input():
	velocity.x = 0
	if Input.is_action_pressed("ui_right"):
		velocity.x += SPEED
		$AnimatedSprite2D.flip_h = false
	elif Input.is_action_pressed("ui_left"):
		velocity.x -= SPEED
		$AnimatedSprite2D.flip_h = true

func handle_jump():
	if is_on_floor() and Input.is_action_just_pressed("Jump"):
		velocity.y = JUMP_FORCE
	elif is_on_wall() and Input.is_action_just_pressed("Jump"):
		velocity.y = JUMP_FORCE
		velocity.x = -SPEED if $AnimatedSprite2D.flip_h else SPEED
		is_wall_climbing = false
		
# NOTE: get_wall_normal() is built into CharacterBody2D in Godot 4 and cannot be
# overridden. The hand-rolled version was removed — the engine one does the same job.

func handle_gravity(delta):
	if not is_wall_climbing and not is_dashing:
		velocity.y += GRAVITY * delta

func handle_wall_climb_and_grab(delta):
	var on_floor = is_on_floor()
	var wall_normal = get_wall_normal()
	var touching_wall = abs(wall_normal.x) > 0.9

	# Buffer wall contact
	if touching_wall:
		wall_touch_buffer = WALL_BUFFER_TIME
	elif wall_touch_buffer > 0:
		wall_touch_buffer -= delta

	var wall_available = wall_touch_buffer > 0

	# Debug
	if wall_available and not was_on_wall:
		print("🧱 Started touching wall (buffered)")
	elif not wall_available and was_on_wall:
		print("🕳️ Stopped touching wall (buffered)")
	was_on_wall = wall_available

	# Start grabbing
	if wall_available and not on_floor and Input.is_action_pressed("wall_climb"):
		if not is_wall_grabbing:
			is_wall_grabbing = true
			wall_climb_timer = WALL_CLIMB_TIME
		# Slow descent while grabbing (wall cling)
		velocity.y = min(velocity.y, 50)
	else:
		is_wall_grabbing = false
		is_wall_climbing = false

	# Start climbing
	if is_wall_grabbing and Input.is_action_pressed("ui_up") and not is_wall_climbing:
		is_wall_climbing = true

	if is_wall_climbing:
		wall_climb_timer -= delta
		print("🧗 Climb Timer: %.2f" % wall_climb_timer)
		if wall_climb_timer <= 0:
			is_wall_climbing = false
		else:
			velocity.y = CLIMB_SPEED
			
func handle_dash(delta):
	if not is_dashing and dash_charges > 0 and Input.is_action_just_pressed("dash"):
		is_dashing = true
		dash_timer = dash_duration
		velocity.y = 0
		velocity.x = dash_speed if not $AnimatedSprite2D.flip_h else -dash_speed

		dash_charges -= 1
		for i in range(MAX_DASHES):
			if dash_cooldowns[i] <= 0.0:
				dash_cooldowns[i] = DASH_COOLDOWN
				break

	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0:
			is_dashing = false		

func handle_dash_recharge(delta):
	for i in range(MAX_DASHES):
		if dash_cooldowns[i] > 0.0:
			dash_cooldowns[i] -= delta
			if dash_cooldowns[i] <= 0.0:
				dash_charges += 1
				dash_charges = min(dash_charges, MAX_DASHES)

func move_player():
	up_direction = FLOOR_NORMAL
	move_and_slide()
	
func update_animation():
	if is_dashing:
		$AnimatedSprite2D.play("dash")
	elif velocity.x != 0:
		$AnimatedSprite2D.play("run")
	else:
		$AnimatedSprite2D.play("idle")
		
func take_damage(amount):
	if health <= 0:
		return
	health -= amount
	update_health_ui()
	if health <= 0:
		fail()

func update_health_ui():
	var label = $healthbar/HealthLabel
	label.text = "Health: %d/%d" % [health, MAX_HEALTH]

func fail():
	print("❌ Player failed!")
	velocity = Vector2.ZERO
	set_physics_process(false)
	
	if try_again_button: 
		try_again_button.visible = true


	
func _ready():
	update_health_ui()
	dash_cooldowns = [0.0, 0.0, 0.0]
	$AnimatedSprite2D.play("idle")


func _on_TryAgainButton_pressed():
	get_tree().reload_current_scene()
