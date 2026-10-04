extends Node
## Stores per-game best scores in the user data folder.

const SAVE_PATH := "user://save_data.cfg"

var _config := ConfigFile.new()


func _ready() -> void:
	_config.load(SAVE_PATH)


func get_best_score(game_id: String) -> int:
	return _config.get_value("best_scores", game_id, 0)


## Saves the score if it beats the previous best. Returns true on a new record.
func submit_score(game_id: String, score: int) -> bool:
	if score <= get_best_score(game_id):
		return false
	_config.set_value("best_scores", game_id, score)
	_config.save(SAVE_PATH)
	return true
