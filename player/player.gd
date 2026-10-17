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
const CLIMB_ACCEL = 900
const CLING_SLIDE_SPEED = 50
const WALL_STICK_PUSH = 20
const WALL_CLIMB_TIME = 1.5
var is_wall_grabbing = false
var is_wall_climbing = false
var wall_climb_timer = 0.0
var wall_normal_x = 0.0
var wall_touch_buffer = 0.0
const WALL_BUFFER_TIME = 0.15

# Wall jump
const WALL_JUMP_LOCK_TIME = 0.15

# Clamber (pulling up over the top of a wall)
const LEDGE_CHECK_HEIGHT = 30
const CLAMBER_UP_TIME = 0.15
const CLAMBER_OVER_TIME = 0.12
var is_clambering = false

# Sprite rotation (vertical on walls)
const ROTATE_SHARPNESS = 20.0

# Getting hit
const INVINCIBLE_TIME = 1.0
const KNOCKBACK = Vector2(220, -220)
const KNOCKBACK_LOCK_TIME = 0.2
const SHAKE_TIME = 0.2
const SHAKE_STRENGTH = 4.0
const DIRTY_TINT = Color(0.6, 0.45, 0.3)
var invincible_timer = 0.0
var shake_timer = 0.0

# Steering is ignored while this counts down (wall jump, knockback)
var control_lock_timer = 0.0

# Dash
var is_dashing = false
var dash_speed = 900
var dash_duration = 0.2
var dash_timer = 0.0
const MAX_DASHES = 3
const DASH_COOLDOWN = 3.0
var dash_charges = MAX_DASHES
var dash_cooldowns = []

# Found by group so any level can provide the button
@onready var try_again_button = get_tree().get_first_node_in_group("try_again_button")

func _physics_process(delta):
	update_feedback(delta)
	update_sprite_rotation(delta)
	# A clamber is driven by a tween, physics stays out of the way until it finishes
	if is_clambering:
		return

	if control_lock_timer > 0:
		control_lock_timer -= delta
	# Steering is skipped mid-dash, otherwise it zeroes velocity.x and kills the dash after one frame
	elif not is_dashing:
		handle_input()
	handle_dash(delta)
	handle_wall_climb_and_grab(delta)
	if is_clambering:
		return
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
	elif (is_on_wall() or is_wall_grabbing) and Input.is_action_just_pressed("Jump"):
		# Jump away from the wall, not toward the way she is facing (she faces the wall while grabbing)
		velocity.y = JUMP_FORCE
		velocity.x = wall_normal_x * SPEED
		$AnimatedSprite2D.flip_h = wall_normal_x < 0
		is_wall_grabbing = false
		is_wall_climbing = false
		wall_touch_buffer = 0.0
		# Without the lock, steering zeroes velocity.x next frame and held Space re-grabs the wall
		control_lock_timer = WALL_JUMP_LOCK_TIME

# NOTE: get_wall_normal() is built into CharacterBody2D in Godot 4 and cannot be
# overridden. The hand-rolled version was removed — the engine one does the same job.

func handle_gravity(delta):
	if not is_wall_grabbing and not is_dashing:
		velocity.y += GRAVITY * delta

func handle_wall_climb_and_grab(delta):
	var on_floor = is_on_floor()
	var wall_normal = get_wall_normal()
	# get_wall_normal() keeps its last value after leaving a wall, so it only counts while is_on_wall()
	var touching_wall = is_on_wall() and abs(wall_normal.x) > 0.9

	# Buffer wall contact
	if touching_wall:
		wall_touch_buffer = WALL_BUFFER_TIME
		wall_normal_x = sign(wall_normal.x)
	elif wall_touch_buffer > 0:
		wall_touch_buffer -= delta

	var wall_available = wall_touch_buffer > 0
	var pressing_away = (wall_normal_x > 0 and Input.is_action_pressed("ui_right")) \
		or (wall_normal_x < 0 and Input.is_action_pressed("ui_left"))

	# Start grabbing
	if wall_available and not on_floor and control_lock_timer <= 0 \
			and not pressing_away and Input.is_action_pressed("wall_climb"):
		if not is_wall_grabbing:
			is_wall_grabbing = true
			wall_climb_timer = WALL_CLIMB_TIME
		# Lean into the wall so is_on_wall() stays true without holding a direction
		velocity.x = -wall_normal_x * WALL_STICK_PUSH
		$AnimatedSprite2D.flip_h = wall_normal_x > 0
	else:
		is_wall_grabbing = false
		is_wall_climbing = false
		return

	is_wall_climbing = Input.is_action_pressed("ui_up") and wall_climb_timer > 0

	if is_wall_climbing:
		wall_climb_timer -= delta
		velocity.y = move_toward(velocity.y, CLIMB_SPEED, CLIMB_ACCEL * delta)
		if is_at_ledge():
			start_clamber()
	else:
		# Ease into the cling slide instead of snapping to it; this also bleeds off upward speed from a jump
		var slide = CLING_SLIDE_SPEED * (3 if Input.is_action_pressed("ui_down") else 1)
		velocity.y = move_toward(velocity.y, slide, GRAVITY * delta)

# True when the wall stops a little below her head, i.e. there is a top edge to pull up onto
func is_at_ledge() -> bool:
	var toward_wall = Vector2(-wall_normal_x * 4, 0)
	var head_height = global_transform.translated(Vector2(0, -LEDGE_CHECK_HEIGHT))
	return test_move(global_transform, toward_wall) and not test_move(head_height, toward_wall)

func start_clamber():
	var half = $CollisionShape2D.shape.size / 2
	var over = -wall_normal_x * (half.x + 4)
	# Find the top surface of the wall by casting down from just above and past the edge
	var from = global_position + Vector2(over, -half.y - LEDGE_CHECK_HEIGHT)
	var query = PhysicsRayQueryParameters2D.create(from, from + Vector2(0, half.y * 2 + LEDGE_CHECK_HEIGHT), collision_mask, [get_rid()])
	var hit = get_world_2d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var target = Vector2(global_position.x + over, hit.position.y - half.y - 1)
	if test_move(Transform2D(0, target), Vector2.ZERO):
		return

	is_clambering = true
	is_wall_grabbing = false
	is_wall_climbing = false
	velocity = Vector2.ZERO
	$AnimatedSprite2D.play("jump")
	var tween = create_tween()
	tween.tween_property(self, "global_position:y", target.y, CLAMBER_UP_TIME).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "global_position:x", target.x, CLAMBER_OVER_TIME).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func(): is_clambering = false)

func update_sprite_rotation(delta):
	var target = 0.0
	if is_wall_grabbing:
		# Nose up, belly to the wall. Positive rotation is clockwise in Godot.
		target = PI / 2 if wall_normal_x > 0 else -PI / 2
	var sprite = $AnimatedSprite2D
	sprite.rotation = lerp_angle(sprite.rotation, target, 1.0 - exp(-ROTATE_SHARPNESS * delta))

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
	# Placeholder until the climb art exists: legs moving while climbing, held pose while clinging
	if is_wall_climbing:
		$AnimatedSprite2D.play("run")
	elif is_wall_grabbing:
		$AnimatedSprite2D.play("idle")
	elif is_dashing:
		$AnimatedSprite2D.play("dash")
	elif velocity.x != 0:
		$AnimatedSprite2D.play("run")
	else:
		$AnimatedSprite2D.play("idle")

func update_feedback(delta):
	var sprite = $AnimatedSprite2D
	if invincible_timer > 0:
		invincible_timer -= delta
		# Blink while invincible
		sprite.self_modulate.a = 0.3 if fmod(invincible_timer, 0.12) < 0.06 else 1.0
	else:
		sprite.self_modulate.a = 1.0

	if shake_timer > 0:
		shake_timer -= delta
		$Camera2D.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * SHAKE_STRENGTH
	else:
		$Camera2D.offset = Vector2.ZERO

func take_damage(amount, from_position = null):
	if health <= 0 or invincible_timer > 0:
		return
	health -= amount
	update_health_ui()
	if health <= 0:
		fail()
		return

	invincible_timer = INVINCIBLE_TIME
	shake_timer = SHAKE_TIME

	# Red flash, then settle on a muddier tint the dirtier she gets
	var sprite = $AnimatedSprite2D
	var dirt_tint = Color.WHITE.lerp(DIRTY_TINT, float(MAX_HEALTH - health) / MAX_HEALTH)
	sprite.modulate = Color(1, 0.3, 0.3)
	create_tween().tween_property(sprite, "modulate", dirt_tint, 0.25)

	# Knock her away from whatever hit her
	if from_position != null and not is_clambering:
		var away = sign(global_position.x - from_position.x)
		if away == 0:
			away = 1 if $AnimatedSprite2D.flip_h else -1
		velocity = Vector2(KNOCKBACK.x * away, KNOCKBACK.y)
		is_wall_grabbing = false
		is_wall_climbing = false
		is_dashing = false
		control_lock_timer = KNOCKBACK_LOCK_TIME

func update_health_ui():
	var label = $healthbar/HealthLabel
	label.text = "Health: %d/%d" % [health, MAX_HEALTH]

func fail():
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
