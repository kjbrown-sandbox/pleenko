extends Node

## Pool of AudioStreamPlayers per sound for overlapping playback.
## Bucket hits are capped at MAX_BUCKET_SOUNDS concurrent plays — extras are silently dropped.

const POOL_SIZE := 10
const MAX_BUCKET_SOUNDS := 30

var _pools: Dictionary = {}  # StringName -> Array[AudioStreamPlayer]
var _indices: Dictionary = {}  # StringName -> int (round-robin index)

var _sounds: Dictionary = {
	&"bucket_land": preload("res://assets/sounds/zapsplat_enter_bucket.mp3"),
	&"menu_item": preload("res://assets/sounds/zapsplat_menu_item.mp3"),
	&"coin": preload("res://assets/sounds/itchambroggiomusic/Coin.mp3"),
	&"old_coin": preload("res://assets/sounds/itchambroggiomusic/Old Coin.mp3"),
	&"coin_flip": preload("res://assets/sounds/itchambroggiomusic/Coin Flip.mp3"),
	&"retro_coin_1": preload("res://assets/sounds/itchambroggiomusic/Retro Coin 1.mp3"),
	&"retro_coin_2": preload("res://assets/sounds/itchambroggiomusic/Retro Coin 2.mp3"),
	&"coin_pouch_1": preload("res://assets/sounds/itchambroggiomusic/Coin Pouch 1.mp3"),
	&"coin_pouch_2": preload("res://assets/sounds/itchambroggiomusic/Coin Pouch 2.mp3"),
	&"coin_rattle": preload("res://assets/sounds/itchambroggiomusic/Coin Rattle.mp3"),
	&"prestige": preload("res://assets/sounds/lucadialessandro-prestige.wav"),
}


func _ready() -> void:
	var pool_overrides := {&"coin_flip": MAX_BUCKET_SOUNDS}
	for sound_name in _sounds:
		_pools[sound_name] = []
		_indices[sound_name] = 0
		var size: int = pool_overrides.get(sound_name, POOL_SIZE)
		for i in size:
			var player := AudioStreamPlayer.new()
			player.stream = _sounds[sound_name]
			player.bus = &"Master"
			add_child(player)
			_pools[sound_name].append(player)


func play(sound_name: StringName, pitch: float = 0.0, max_duration: float = 0.0) -> void:
	if sound_name not in _pools:
		return
	var pool: Array = _pools[sound_name]
	var idx: int = _indices[sound_name]
	var player: AudioStreamPlayer = pool[idx]
	_indices[sound_name] = (idx + 1) % pool.size()

	if pitch <= 0.0:
		pitch = randf_range(0.9, 1.1)
	player.pitch_scale = pitch
	player.play()

	if max_duration > 0.0:
		get_tree().create_timer(max_duration).timeout.connect(func():
			if player.playing:
				player.stop()
		)


## Play a coin_flip for a bucket landing, up to MAX_BUCKET_SOUNDS at once.
## Extra hits beyond the cap are silently dropped.
func play_bucket_hit() -> void:
	var pool: Array = _pools[&"coin_flip"]
	var playing_count := 0
	for player: AudioStreamPlayer in pool:
		if player.playing:
			playing_count += 1
	if playing_count >= MAX_BUCKET_SOUNDS:
		return
	# Fade volume as more coins play: full at 1, quieter as count rises
	var volume := linear_to_db(1.0 / (1.0 + playing_count * 0.05))
	var idx: int = _indices[&"coin_flip"]
	var player: AudioStreamPlayer = pool[idx]
	player.volume_db = volume
	play(&"coin_flip", 0.0, 0.27)


## Play the prestige sound and fade it out over fade_duration seconds, starting after play_duration.
func play_prestige(play_duration: float = 3.0, fade_duration: float = 2.0) -> void:
	var pool: Array = _pools[&"prestige"]
	var idx: int = _indices[&"prestige"]
	var player: AudioStreamPlayer = pool[idx]
	_indices[&"prestige"] = (idx + 1) % pool.size()
	player.volume_db = 0.0
	player.pitch_scale = 1.0
	player.play()
	# After play_duration, tween the volume down to silence then stop
	get_tree().create_timer(play_duration).timeout.connect(func():
		if player.playing:
			var tween := create_tween()
			tween.tween_property(player, "volume_db", -40.0, fade_duration)
			tween.tween_callback(player.stop)
	)
