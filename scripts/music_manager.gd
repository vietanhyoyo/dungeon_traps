extends AudioStreamPlayer

const DEFAULT_MUSIC: AudioStream = preload("res://assets/music/dungeon_theme.mp3")
const DRAMATIC_MUSIC_ATTENUATION_DB := -7.0
var _cheerful_music: AudioStreamWAV = preload("res://assets/music/cheerful_relaxing_piano_platformer_loop_3min.wav")
var _dramatic_music: AudioStreamWAV = preload("res://assets/music/dramatic_piano_platformer_loop_3min.wav")


func _ready() -> void:
	_configure_loop(_cheerful_music)
	_configure_loop(_dramatic_music)
	get_tree().scene_changed.connect(_on_scene_changed)

	if get_tree().current_scene:
		_on_scene_changed()


func _configure_loop(audio: AudioStreamWAV) -> void:
	audio.loop_begin = 0
	audio.loop_end = int(audio.get_length() * audio.mix_rate)
	audio.loop_mode = AudioStreamWAV.LOOP_FORWARD


func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	var desired_music: AudioStream = DEFAULT_MUSIC
	var desired_volume_db := 0.0
	var file_name := scene.scene_file_path.get_file()

	if file_name.begins_with("level_") and file_name.ends_with(".tscn"):
		var level_text := file_name.trim_prefix("level_").trim_suffix(".tscn")
		if level_text.is_valid_int():
			var level_number := level_text.to_int()
			if level_number >= 3 and level_number <= 6:
				desired_music = _cheerful_music
			elif level_number >= 7:
				desired_music = _dramatic_music
				desired_volume_db = DRAMATIC_MUSIC_ATTENUATION_DB

	volume_db = desired_volume_db
	if stream == desired_music and playing:
		return

	stream = desired_music
	play()
