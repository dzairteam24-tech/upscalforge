extends Node2D
## Dodge: drag your finger to move the block and avoid the falling squares.

const GAME_ID := "dodge"
const MENU_SCENE := "res://scenes/main_menu.tscn"

const PLAYER_SIZE := Vector2(110, 60)
const PLAYER_BOTTOM_MARGIN := 140.0
const PLAYER_FOLLOW_SPEED := 18.0
const OBSTACLE_MIN_SIZE := 50.0
const OBSTACLE_MAX_SIZE := 110.0
const OBSTACLE_COLOR := Color(1.0, 0.44, 0.26)
const START_FALL_SPEED := 450.0
const FALL_SPEED_GAIN := 18.0  # Added to the fall speed every second.
const START_SPAWN_INTERVAL := 0.8
const MIN_SPAWN_INTERVAL := 0.25

var _obstacles: Array[ColorRect] = []
var _target_x := 0.0
var _elapsed := 0.0
var _spawn_timer := 0.0
var _playing := false

@onready var _player: ColorRect = %Player
@onready var _obstacle_layer: Node2D = %Obstacles
@onready var _score_label: Label = %ScoreLabel
@onready var _game_over_panel: Control = %GameOverPanel
@onready var _result_label: Label = %ResultLabel


func _ready() -> void:
	%RestartButton.pressed.connect(_start)
	%MenuButton.pressed.connect(_go_to_menu)
	_player.size = PLAYER_SIZE
	_start()


func _start() -> void:
	for obstacle in _obstacles:
		obstacle.queue_free()
	_obstacles.clear()
	var screen := get_viewport_rect().size
	_target_x = (screen.x - PLAYER_SIZE.x) / 2.0
	_player.position = Vector2(_target_x, screen.y - PLAYER_BOTTOM_MARGIN - PLAYER_SIZE.y)
	_elapsed = 0.0
	_spawn_timer = 0.0
	_game_over_panel.hide()
	_update_score_label()
	_playing = true


func _unhandled_input(event: InputEvent) -> void:
	if not _playing:
		return
	if event is InputEventScreenTouch and event.pressed:
		_set_target(event.position.x)
	elif event is InputEventScreenDrag:
		_set_target(event.position.x)


func _set_target(finger_x: float) -> void:
	var max_x := get_viewport_rect().size.x - PLAYER_SIZE.x
	_target_x = clampf(finger_x - PLAYER_SIZE.x / 2.0, 0.0, max_x)


func _process(delta: float) -> void:
	if not _playing:
		return
	_elapsed += delta
	_update_score_label()

	_player.position.x = lerpf(_player.position.x, _target_x, minf(1.0, PLAYER_FOLLOW_SPEED * delta))

	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_obstacle()
		_spawn_timer = maxf(MIN_SPAWN_INTERVAL, START_SPAWN_INTERVAL - _elapsed * 0.01)

	var fall_speed := START_FALL_SPEED + FALL_SPEED_GAIN * _elapsed
	var screen_height := get_viewport_rect().size.y
	var player_rect := _player.get_rect().grow(-6.0)  # Slightly forgiving hitbox.
	for obstacle in _obstacles.duplicate():
		obstacle.position.y += fall_speed * delta
		if obstacle.get_rect().intersects(player_rect):
			_game_over()
			return
		if obstacle.position.y > screen_height:
			_obstacles.erase(obstacle)
			obstacle.queue_free()


func _spawn_obstacle() -> void:
	var obstacle := ColorRect.new()
	var side := randf_range(OBSTACLE_MIN_SIZE, OBSTACLE_MAX_SIZE)
	obstacle.size = Vector2(side, side)
	obstacle.color = OBSTACLE_COLOR
	obstacle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	obstacle.position = Vector2(randf_range(0.0, get_viewport_rect().size.x - side), -side)
	_obstacle_layer.add_child(obstacle)
	_obstacles.append(obstacle)


func _score() -> int:
	return int(_elapsed * 10.0)


func _update_score_label() -> void:
	_score_label.text = str(_score())


func _game_over() -> void:
	_playing = false
	var score := _score()
	var is_record := SaveData.submit_score(GAME_ID, score)
	_result_label.text = "Score: %d\n%s" % [
		score,
		"New record!" if is_record else "Best: %d" % SaveData.get_best_score(GAME_ID),
	]
	_game_over_panel.show()


func _go_to_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)
