## Единая таблица объектов и структур.
## Поле kind: "object" — ставится по сэмплам, "structure" — по ang/dist.
##
## Общие поля:
##   id, kind, scene, count, scale_min, scale_max, y_offset, random_yaw,
##   rule ("anywhere" | "clearing"), min_slope, max_slope, occupancy_radius
##
## Для kind="object":
##   density — вероятность на сэмпл, используется только при count == 0
##   count == 0 — плотностный режим
##   count > 0  — от 1 до count на чанк
##
## Для kind="structure":
##   ang   — угол в градусах от центра карты (0..360). Опционально.
##   dist  — расстояние в долях от радиуса BLOB (0..0.95). Опционально.
##   count — сколько штук.
##     Если ang+dist указаны — ВСЕГДА 1 структура в этой точке (count игнорируется)
##     Если ang+dist не указаны:
##       count == 1 — одна случайная точка на весь мир
##       count > 1  — случайная точка на каждом чанке, count штук в ней
##
## Поле scene: строка (сцена / папка), массив строк, или пусто (заглушка).
class_name ForestObjects
extends RefCounted

static func get_table() -> Array[Dictionary]:
	return [
		# ---------- ОБЪЕКТЫ ----------
		{
			"id": "tree_pine",
			"kind": "object",
			"scene": "res://map_objects/wood.tscn",
			"density": 0.25,
			"count": 0,
			"scale_min": 0.75, "scale_max": 1.35,
			"y_offset": 0.0,
			"random_yaw": true,
			"rule": "anywhere",
			"min_slope": 0.0, "max_slope": 1.5,
			"occupancy_radius": 1.5,
		},

		# ---------- СТРУКТУРЫ ----------
		{
			"id": "starter_house",
			"kind": "structure",
			"scene": "res://map_objects/starter_house.tscn",
			"count": 1,
			"scale_min": 1.0, "scale_max": 1.0,
			"y_offset": 0.0,
			"random_yaw": true,
			"rule": "anywhere",
			"min_slope": 0.0, "max_slope": 1.5,
			"occupancy_radius": 5.0,
			"clear_radius": 15.0,
		},
	]
