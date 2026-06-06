extends RefCounted

# 選べる主人公の名簿(レジストリ)。
# player.gd(見た目の生成)と title.gd(選ぶ画面)が共有する。
# 新しい主人公を増やすときは character_visual.gd を継承したスクリプトを作り、
# ここに 1 行 足すだけでよい。
#
# id    : セーブに保存する識別子(英数字。氏名等の個人情報は扱わない方針に合致)
# name  : 子供に見せる名前(ひらがな・カタカナのみ)
# script: その主人公の見た目スクリプト(character_visual.gd の子孫)
# tint  : 選ぶ画面の絵カードの色(その子のイメージカラー)

const CHARACTERS: Array = [
	{
		"id": "driver",
		"name": "うんてんしさん",
		"script": "res://scripts/entities/characters/driver_character.gd",
		"tint": Color(0.16, 0.41, 0.79),
	},
	{
		"id": "fox",
		"name": "きつねさん",
		"script": "res://scripts/entities/characters/fox_character.gd",
		"tint": Color(0.953, 0.463, 0.165),
	},
]

const DEFAULT_ID: String = "driver"


# id から名簿エントリを返す(無ければ既定の主人公)。
static func get_entry(id: String) -> Dictionary:
	for c in CHARACTERS:
		if c["id"] == id:
			return c
	return get_entry(DEFAULT_ID) if id != DEFAULT_ID else CHARACTERS[0]


# id が名簿に在るか。
static func is_valid(id: String) -> bool:
	for c in CHARACTERS:
		if c["id"] == id:
			return true
	return false
