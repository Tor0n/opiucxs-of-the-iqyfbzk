class_name Player
extends CharacterBody3D

# ==========================================
# НАСТРОЙКИ
# ==========================================
@export_group("Движение")
@export var move_speed: float = 7.0
@export var acceleration: float = 40.0
@export var friction: float = 30.0

@export_group("Рывок (Dash)")
@export var dash_speed: float = 22.0
@export var dash_duration: float = 0.25
@export var dash_cooldown: float = 1.0
@export var dash_damage: float = 35.0

@export_group("Пулемет")
@export var machinegun_fire_rate: float = 0.1
@export var machinegun_damage: float = 10.0
@export var bullet_scene: PackedScene

@export_group("Бензопила")
@export var chainsaw_damage: float = 15.0
@export var chainsaw_tick_rate: float = 0.15

@export_group("Ракетный залп")
@export var rocket_scene: PackedScene
@export var rocket_count: int = 5
@export var rocket_cooldown: float = 4.0
@export var auto_aim_radius: float = 15.0

@export_group("Механика Крови и Стойки")
@export var blood_energy: float = 0.0
@export var max_blood_energy: float = 100.0
@export var stance_duration: float = 5.0

# ==========================================
# УЗЛЫ
# ==========================================
@onready var shoot_point: Marker3D = $ShootPoint
@onready var melee_damage_area: Area3D = $MeleeDamageArea

# ==========================================
# СОСТОЯНИЯ
# ==========================================
enum Stance { NONE, DEFENSIVE, AGGRESSIVE }
var current_stance: Stance = Stance.NONE

var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cd_timer: float = 0.0

var machinegun_cd: float = 0.0
var chainsaw_cd: float = 0.0
var rocket_cd_timer: float = 0.0
var stance_timer: float = 0.0

var damage_multiplier: float = 1.0
var shield_amount: float = 0.0
var health: float = 100.0

func _ready() -> void:
	# Зона всегда включена, но урон от рывка наносится только когда is_dashing == true
	melee_damage_area.monitoring = true
	melee_damage_area.body_entered.connect(_on_melee_area_body_entered)
	melee_damage_area.area_entered.connect(_on_melee_area_area_entered)

func _physics_process(delta: float) -> void:
	handle_timers(delta)
	look_at_cursor()
	
	if is_dashing:
		process_dash(delta)
	else:
		handle_movement(delta)
		handle_inputs()

	move_and_slide()

# ==========================================
# ДВИЖЕНИЕ И ПРИЦЕЛИВАНИЕ
# ==========================================
func handle_movement(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := Vector3(input_dir.x, 0, input_dir.y).normalized()
	
	if direction != Vector3.ZERO:
		velocity.x = move_toward(velocity.x, direction.x * move_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * move_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, friction * delta)
		velocity.z = move_toward(velocity.z, 0, friction * delta)
	
	if not is_on_floor():
		velocity.y -= 9.8 * delta

func look_at_cursor() -> void:
	var camera = get_viewport().get_camera_3d()
	if not camera: return
		
	var mouse_pos = get_viewport().get_mouse_position()
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_dir = camera.project_ray_normal(mouse_pos)
	
	var plane = Plane(Vector3.UP, global_position.y)
	var intersection = plane.intersects_ray(ray_origin, ray_dir)
	
	if intersection:
		var look_target = Vector3(intersection.x, global_position.y, intersection.z)
		if global_position.distance_squared_to(look_target) > 0.1:
			look_at(look_target, Vector3.UP)

# ==========================================
# ВВОД СПОСОБНОСТЕЙ
# ==========================================
func handle_inputs() -> void:
	if Input.is_action_pressed("fire_machinegun") and machinegun_cd <= 0:
		shoot_machinegun()
	
	if Input.is_action_pressed("use_chainsaw") and chainsaw_cd <= 0:
		use_chainsaw()
		
	if Input.is_action_just_pressed("dash") and dash_cd_timer <= 0:
		start_dash()
		
	if Input.is_action_just_pressed("fire_rockets") and rocket_cd_timer <= 0:
		fire_missile_salvo()

	if Input.is_action_just_pressed("stance_defensive"):
		activate_stance(Stance.DEFENSIVE)
	elif Input.is_action_just_pressed("stance_aggressive"):
		activate_stance(Stance.AGGRESSIVE)

# ==========================================
# МЕХАНИКИ
# ==========================================

# --- РЫВОК ---
func start_dash() -> void:
	is_dashing = true
	dash_timer = dash_duration
	dash_cd_timer = dash_cooldown
	
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var dash_dir := Vector3(input_dir.x, 0, input_dir.y).normalized()
	if dash_dir == Vector3.ZERO:
		dash_dir = -transform.basis.z
		
	velocity = dash_dir * dash_speed

func process_dash(delta: float) -> void:
	dash_timer -= delta
	if dash_timer <= 0:
		is_dashing = false

# Обработка столкновений единственной зоны (работает во время рывка)
func _on_melee_area_body_entered(body: Node3D) -> void:
	if body == self: return
	if is_dashing:
		if body.has_method("take_damage"):
			body.take_damage(dash_damage * damage_multiplier)
		if body.has_method("destroy"):
			body.destroy()

func _on_melee_area_area_entered(area: Area3D) -> void:
	if area.owner == self: return
	if is_dashing:
		if area.has_method("destroy"):
			area.destroy()

# --- ПУЛЕМЕТ ---
func shoot_machinegun() -> void:
	machinegun_cd = machinegun_fire_rate
	if bullet_scene:
		var bullet = bullet_scene.instantiate()
		get_tree().root.add_child(bullet)
		bullet.global_position = shoot_point.global_position
		bullet.global_rotation = shoot_point.global_rotation
		if bullet.has_method("setup"):
			bullet.setup(machinegun_damage * damage_multiplier)

# --- БЕНЗОПИЛА ---
func use_chainsaw() -> void:
	chainsaw_cd = chainsaw_tick_rate
	# Проверяем цели, которые сейчас находятся в зоне MeleeDamageArea
	var bodies = melee_damage_area.get_overlapping_bodies()
	for body in bodies:
		if body != self and body.has_method("take_damage"):
			body.take_damage(chainsaw_damage * damage_multiplier)
			add_blood(5.0)

# --- РАКЕТНЫЙ ЗАЛП ---
func fire_missile_salvo() -> void:
	rocket_cd_timer = rocket_cooldown
	var targets = find_nearby_enemies(auto_aim_radius)
	
	for i in range(rocket_count):
		if rocket_scene:
			var rocket = rocket_scene.instantiate()
			get_tree().root.add_child(rocket)
			rocket.global_position = shoot_point.global_position
			
			var target_node: Node3D = null
			if targets.size() > 0:
				target_node = targets[i % targets.size()]
				
			if rocket.has_method("setup"):
				rocket.setup(target_node, damage_multiplier)
		
		await get_tree().create_timer(0.05).timeout

func find_nearby_enemies(radius: float) -> Array[Node3D]:
	var enemies: Array[Node3D] = []
	var all_enemies = get_tree().get_nodes_in_group("Enemies")
	for enemy in all_enemies:
		if enemy is Node3D and global_position.distance_to(enemy.global_position) <= radius:
			enemies.append(enemy)
	return enemies

# ==========================================
# СТОЙКИ И ЗДОРОВЬЕ
# ==========================================
func add_blood(amount: float) -> void:
	blood_energy = clamp(blood_energy + amount, 0, max_blood_energy)

func activate_stance(new_stance: Stance) -> void:
	if blood_energy <= 0:
		print("Недостаточно энергии крови!")
		return
		
	current_stance = new_stance
	stance_timer = stance_duration
	
	if current_stance == Stance.DEFENSIVE:
		shield_amount = blood_energy * 1.5
		damage_multiplier = 1.0
		print("Защитная стойка! Щит: ", shield_amount)
	elif current_stance == Stance.AGGRESSIVE:
		damage_multiplier = 1.0 + (blood_energy / max_blood_energy)
		shield_amount = 0
		print("Агрессивная стойка! Урон x", damage_multiplier)
		
	blood_energy = 0

func reset_stance() -> void:
	current_stance = Stance.NONE
	damage_multiplier = 1.0
	shield_amount = 0.0

func take_damage(amount: float) -> void:
	if shield_amount > 0:
		if shield_amount >= amount:
			shield_amount -= amount
			return
		else:
			amount -= shield_amount
			shield_amount = 0
			
	health -= amount
	if health <= 0:
		die()

func die() -> void:
	print("Игрок погиб!")

# ==========================================
# ТАЙМЕРЫ
# ==========================================
func handle_timers(delta: float) -> void:
	if machinegun_cd > 0: machinegun_cd -= delta
	if chainsaw_cd > 0: chainsaw_cd -= delta
	if dash_cd_timer > 0: dash_cd_timer -= delta
	if rocket_cd_timer > 0: rocket_cd_timer -= delta
	
	if current_stance != Stance.NONE:
		stance_timer -= delta
		if stance_timer <= 0:
			reset_stance()
