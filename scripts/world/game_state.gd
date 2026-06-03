extends Node

# ゲーム進捗の一元管理。Main 直下のノード(Autoload は使わない方針)。
# 各システム(ride_controller / animal_manager / stars / station_manager)が
# 発見・獲得を記録し、HUD カウンターと図鑑がこれを参照する。
# セッション内のメモリ保持のみ(永続セーブは Phase 5 の SaveSystem で)。

signal changed

# 発見済みの slug(重複なし)
var boarded_trains: Array[String] = []
var befriended_animals: Array[String] = []
var visited_stations: Array[String] = []
var star_count: int = 0
var energy: int = 0  # おだんごを食べて増える「げんき」(駅のお団子で +1)
var visited_moon: bool = false  # ロケットで月へ行ったことがある(ミッション/記念用)
var visited_sky_castle: bool = false  # ひこうきで そらの おしろへ行ったことがある(ミッション用)
var visited_submarine: bool = false   # せんすいかんで うみの そこへ行ったことがある(ミッション用)
var visited_candy: bool = false       # おかしの きしゃで おかしの くにへ行ったことがある(ミッション用)
var visited_dino: bool = false        # サファリカーで きょうりゅうランドへ行ったことがある(ミッション用)
var drove_train: bool = false   # うんてんしゅモードになったことがある(ミッション用)
var play_count: int = 0         # あそんだ かいすう(起動ごとに +1。親モードで表示)


func add_boarded(slug: String) -> void:
	if slug == "" or slug in boarded_trains:
		return
	boarded_trains.append(slug)
	changed.emit()


func add_befriended(slug: String) -> void:
	if slug == "" or slug in befriended_animals:
		return
	befriended_animals.append(slug)
	changed.emit()


func add_station(slug: String) -> void:
	if slug == "" or slug in visited_stations:
		return
	visited_stations.append(slug)
	changed.emit()


func add_star() -> void:
	star_count += 1
	changed.emit()


func add_energy(amount: int = 1) -> void:
	if amount <= 0:
		return
	energy += amount
	changed.emit()


# 月へ行った/運転手になった、を一度だけ記録(ミッション「目玉ツアー」用)。
func set_moon_visited() -> void:
	if visited_moon:
		return
	visited_moon = true
	changed.emit()


func set_sky_castle_visited() -> void:
	if visited_sky_castle:
		return
	visited_sky_castle = true
	changed.emit()


func set_submarine_visited() -> void:
	if visited_submarine:
		return
	visited_submarine = true
	changed.emit()


func set_candy_visited() -> void:
	if visited_candy:
		return
	visited_candy = true
	changed.emit()


func set_dino_visited() -> void:
	if visited_dino:
		return
	visited_dino = true
	changed.emit()


func set_drove_train() -> void:
	if drove_train:
		return
	drove_train = true
	changed.emit()


# === getter(HUD / 図鑑用) ===

func has_train(slug: String) -> bool:
	return slug in boarded_trains

func has_animal(slug: String) -> bool:
	return slug in befriended_animals

func has_station(slug: String) -> bool:
	return slug in visited_stations
