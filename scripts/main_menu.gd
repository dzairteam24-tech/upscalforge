extends Control
## Main menu: lists every game in GAMES. Add a new entry here to add a game.

const GAMES := [
	{
		"id": "dodge",
		"title": "Dodge",
		"scene": "res://scenes/games/dodge/dodge.tscn",
	},
]

@onready var _game_list: VBoxContainer = %GameList


func _ready() -> void:
	for game in GAMES:
		var button := Button.new()
		button.text = "%s   (Best: %d)" % [game.title, SaveData.get_best_score(game.id)]
		button.custom_minimum_size = Vector2(0, 120)
		button.add_theme_font_size_override("font_size", 44)
		button.pressed.connect(_on_game_pressed.bind(game.scene))
		_game_list.add_child(button)


func _on_game_pressed(scene_path: String) -> void:
	get_tree().change_scene_to_file(scene_path)
