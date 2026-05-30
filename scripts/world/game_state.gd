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


# === getter(HUD / 図鑑用) ===

func has_train(slug: String) -> bool:
	return slug in boarded_trains

func has_animal(slug: String) -> bool:
	return slug in befriended_animals

func has_station(slug: String) -> bool:
	return slug in visited_stations
