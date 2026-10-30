## Генератор леса: один террейн на всю карту, одна коллизия, BLOB, забор, объекты.
## @tool — видно в редакторе. Кнопка Regenerate пересобирает мир.
@tool
extends Node3D

@export_group("World")
@export var world_seed: int = 42
@export var world_size: float = 256.0
@export var world_resolution: int = 129
@export var height_scale: float = 16.0
@export var blob_radius: float = 120.0
@export_range(0.0, 1.0) var blob_amplitude: float = 0.35
@export var blob_frequency: float = 2.0

@export_group("Noise")
@export var elevation_frequency: float = 0.006
@export var density_frequency: float = 0.012
@export var color_frequency: float = 0.05

@export_group("Fence")
@export var fence_material: Material
@export var fence_height: float = 2.0

@export_group("Terrain Visual")
@export var terrain_material: Material

@export_group("Actions")
@export_tool_button("Regenerate", "Reload") var regenerate_action = _regenerate

var _elevation_noise: FastNoiseLite
var _density_noise: FastNoiseLite
var _color_noise: FastNoiseLite
var _blob_noise: FastNoiseLite
var _scene_cache: Dictionary = {}
var _terrain_root: Node3D
var _heights: PackedFloat32Array
var _res: int
var _step: float

func _ready() -> void:
	_setup_noise()
	_generate()

func _regenerate() -> void:
	_clear_all()
	_scene_cache.clear()
	_setup_noise()
	_generate()

func _clear_all() -> void:
	if _terrain_root != null:
		_terrain_root.queue_free()
		_terrain_root = null

# ---------------------------------------------------------------- шум

func _setup_noise() -> void:
	_elevation_noise = FastNoiseLite.new()
	_elevation_noise.seed = world_seed
	_elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_elevation_noise.frequency = elevation_frequency
	_elevation_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_elevation_noise.fractal_octaves = 4
	_elevation_noise.fractal_gain = 0.5

	_density_noise = FastNoiseLite.new()
	_density_noise.seed = world_seed + 777
	_density_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_density_noise.frequency = density_frequency
	_density_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_density_noise.fractal_octaves = 2

	_color_noise = FastNoiseLite.new()
	_color_noise.seed = world_seed + 555
	_color_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_color_noise.frequency = color_frequency

	_blob_noise = FastNoiseLite.new()
	_blob_noise.seed = world_seed + 999
	_blob_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_blob_noise.frequency = 1.0
	_blob_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_blob_noise.fractal_octaves = 3

# ---------------------------------------------------------------- BLOB

func _blob_radius(angle: float) -> float:
	var cx := cos(angle) * blob_frequency
	var cz := sin(angle) * blob_frequency
	var n := _blob_noise.get_noise_2d(cx, cz)
	return blob_radius * (1.0 + n * blob_amplitude)

func _is_inside_blob(world_x: float, world_z: float) -> bool:
	var dist := sqrt(world_x * world_x + world_z * world_z)
	var angle := atan2(world_z, world_x)
	return dist <= _blob_radius(angle)

# ---------------------------------------------------------------- высота и цвет

func _height_at(world_x: float, world_z: float) -> float:
	var n := _elevation_noise.get_noise_2d(world_x, world_z)
	var normalized := (n + 1.0) * 0.5
	var shaped := smoothstep(0.2, 0.8, normalized)
	return shaped * height_scale

func _forest_density_at(world_x: float, world_z: float) -> float:
	var n := _density_noise.get_noise_2d(world_x, world_z)
	return clampf((n + 1.0) * 0.5, 0.0, 1.0)

func _vertex_color(world_x: float, world_z: float, h: float) -> Color:
	var shade := _color_noise.get_noise_2d(world_x, world_z) * 0.5 + 0.5
	var base := Color(0.20, 0.38, 0.16).lerp(Color(0.30, 0.48, 0.20), shade)
	var high_t := clampf(h / height_scale, 0.0, 1.0)
	return base.lerp(Color(0.42, 0.52, 0.26), high_t * 0.6)

func _slope_at(world_x: float, world_z: float, r: float) -> float:
	var h0 := _height_at(world_x, world_z)
	var h1 := _height_at(world_x + r, world_z)
	var h2 := _height_at(world_x - r, world_z)
	var h3 := _height_at(world_x, world_z + r)
	var h4 := _height_at(world_x, world_z - r)
	var m := 0.0
	m = maxf(m, absf(h1 - h0))
	m = maxf(m, absf(h2 - h0))
	m = maxf(m, absf(h3 - h0))
	m = maxf(m, absf(h4 - h0))
	return m

# ---------------------------------------------------------------- генерация

func _generate() -> void:
	_res = world_resolution
	_step = world_size / float(_res - 1)
	_heights = PackedFloat32Array()
	_heights.resize(_res * _res)
	var half := world_size * 0.5
	for j in _res:
		for i in _res:
			var wx := i * _step - half
			var wz := j * _step - half
			_heights[j * _res + i] = _height_at(wx, wz)

	_terrain_root = Node3D.new()
	_terrain_root.name = "World"
	add_child(_terrain_root)

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.material_override = _resolve_terrain_material()
	mi.mesh = _build_mesh()
	_terrain_root.add_child(mi)

	var sb := StaticBody3D.new()
	sb.name = "TerrainCollision"
	_terrain_root.add_child(sb)
	var shape := HeightMapShape3D.new()
	shape.map_width = _res
	shape.map_depth = _res
	shape.map_data = _heights
	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = Vector3(_step, 1.0, _step)
	sb.add_child(col)

	_build_fence()

	var decor_root := Node3D.new()
	decor_root.name = "Decor"
	_terrain_root.add_child(decor_root)
	_place_from_table(decor_root)

func _resolve_terrain_material() -> Material:
	if terrain_material != null:
		return terrain_material
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _build_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := world_size * 0.5
	for j in _res - 1:
		for i in _res - 1:
			var idx00 := j * _res + i
			var idx10 := j * _res + (i + 1)
			var idx01 := (j + 1) * _res + i
			var idx11 := (j + 1) * _res + (i + 1)
			var x0 := i * _step - half
			var x1 := (i + 1) * _step - half
			var z0 := j * _step - half
			var z1 := (j + 1) * _step - half
			var h00 := _heights[idx00]
			var h10 := _heights[idx10]
			var h01 := _heights[idx01]
			var h11 := _heights[idx11]
			var v00 := Vector3(x0, h00, z0)
			var v10 := Vector3(x1, h10, z0)
			var v01 := Vector3(x0, h01, z1)
			var v11 := Vector3(x1, h11, z1)
			var c00 := _vertex_color(x0, z0, h00)
			var c10 := _vertex_color(x1, z0, h10)
			var c01 := _vertex_color(x0, z1, h01)
			var c11 := _vertex_color(x1, z1, h11)
			_emit(st, v00, c00); _emit(st, v01, c01); _emit(st, v10, c10)
			_emit(st, v10, c10); _emit(st, v01, c01); _emit(st, v11, c11)
	st.generate_normals()
	var mesh := st.commit()
	_apply_normals(mesh)
	return mesh

func _emit(st: SurfaceTool, v: Vector3, c: Color) -> void:
	st.set_color(c)
	st.add_vertex(v)

func _apply_normals(mesh: ArrayMesh) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var new_normals := PackedVector3Array()
	new_normals.resize(verts.size())
	var tri_count := verts.size() / 3
	for t in tri_count:
		var a := verts[t * 3 + 0]
		var b := verts[t * 3 + 1]
		var c := verts[t * 3 + 2]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			n = Vector3.UP
		else:
			n = n.normalized()
		if n.y < 0.0:
			n = -n
			var tmp := verts[t * 3 + 1]
			verts[t * 3 + 1] = verts[t * 3 + 2]
			verts[t * 3 + 2] = tmp
		new_normals[t * 3 + 0] = n
		new_normals[t * 3 + 1] = n
		new_normals[t * 3 + 2] = n
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = new_normals
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func _chunk_height(world_x: float, world_z: float) -> float:
	var half := world_size * 0.5
	var fx := clampf((world_x + half) / _step, 0.0, float(_res - 1.001))
	var fz := clampf((world_z + half) / _step, 0.0, float(_res - 1.001))
	var i := int(fx); var j := int(fz)
	var tx := fx - i; var tz := fz - j
	var i1 := mini(i + 1, _res - 1)
	var j1 := mini(j + 1, _res - 1)
	var h00 := _heights[j * _res + i]
	var h10 := _heights[j * _res + i1]
	var h01 := _heights[j1 * _res + i]
	var h11 := _heights[j1 * _res + i1]
	return lerp(lerp(h00, h10, tx), lerp(h01, h11, tx), tz)

# ---------------------------------------------------------------- резолвер сцен

func _pick_scene(paths) -> PackedScene:
	var list: Array = []
	if paths is Array:
		for p in paths:
			list.append(str(p))
	elif paths is String:
		if (paths as String).is_empty():
			return null
		list.append(paths)
	else:
		return null
	if list.is_empty():
		return null
	return _load_scene_or_folder(list.pick_random())

func _load_scene_or_folder(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path]
	var result: PackedScene = null
	if path.ends_with("/"):
		var files := _list_scenes_in_dir(path)
		if not files.is_empty():
			result = load(files.pick_random()) as PackedScene
	else:
		result = load(path) as PackedScene
	_scene_cache[path] = result
	return result

func _list_scenes_in_dir(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if dir.current_is_dir():
			if not f.begins_with("."):
				out.append_array(_list_scenes_in_dir(dir_path + f + "/"))
		else:
			var lower := f.to_lower()
			if lower.ends_with(".tscn") or lower.ends_with(".scn") or lower.ends_with(".glb"):
				out.append(dir_path + f)
		f = dir.get_next()
	dir.list_dir_end()
	return out

func _make_fallback_scene(id: String) -> PackedScene:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var mesh: Mesh
	match id:
		"tree_pine", "tree_birch":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.0
			cyl.bottom_radius = 0.45
			cyl.height = 4.0
			cyl.radial_segments = 8
			mesh = cyl
		"rock_small":
			var sph := SphereMesh.new()
			sph.radius = 0.5
			sph.height = 1.0
			sph.radial_segments = 6
			sph.rings = 3
			mesh = sph
		"stump":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.4
			cyl.bottom_radius = 0.45
			cyl.height = 0.5
			cyl.radial_segments = 8
			mesh = cyl
		"bush":
			var sph := SphereMesh.new()
			sph.radius = 0.6
			sph.height = 0.8
			sph.radial_segments = 6
			sph.rings = 3
			mesh = sph
		_:
			var box := BoxMesh.new()
			box.size = Vector3(4, 3, 5)
			mesh = box
	mi.mesh = mesh
	root.add_child(mi)
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	return ps

func _resolve_scene(entry: Dictionary) -> PackedScene:
	var scene := _pick_scene(entry.get("scene", ""))
	if scene == null:
		scene = _make_fallback_scene(str(entry.get("id", "")))
	return scene

func _spawn(entry: Dictionary, scene: PackedScene, parent: Node3D, world_pos: Vector3, yaw: float, rng: RandomNumberGenerator) -> Node3D:
	var node := scene.instantiate()
	node.name = "%s_%d" % [entry.get("id", "obj"), rng.randi()]
	if node is Node3D:
		var n3 := node as Node3D
		n3.position = world_pos
		if entry.get("random_yaw", false):
			n3.rotation.y = yaw
		var s := rng.randf_range(entry.get("scale_min", 1.0), entry.get("scale_max", 1.0))
		n3.scale = Vector3(s, s, s)
		n3.set_meta("is_structure", entry.get("kind", "") == "structure")
	parent.add_child(node)
	return node

func _scene_world_aabb(node: Node3D) -> AABB:
	var meshes := node.find_children("*", "MeshInstance3D", true, false)
	if meshes.is_empty():
		return AABB(node.global_position, Vector3.ZERO)
	var result := AABB()
	var first := true
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var local_aabb := mi.get_aabb()
		var xform := node.global_transform.affine_inverse() * mi.global_transform
		var world_aabb := xform * local_aabb
		if first:
			result = world_aabb
			first = false
		else:
			result = result.merge(world_aabb)
	return node.global_transform * result

func _clear_objects_around(struct_node: Node3D, decor_root: Node3D, clear_radius: float) -> void:
	if clear_radius <= 0.0:
		return
	var aabb := _scene_world_aabb(struct_node)
	var center := aabb.get_center()
	# BLOB-зона вокруг центра структуры: радиус модулируется шумом по углу
	var to_remove: Array[Node] = []
	for child in decor_root.get_children():
		if not (child is Node3D):
			continue
		if child.get_meta("is_structure", false):
			continue
		var pos := (child as Node3D).global_position
		# 1) Внутри AABB структуры — удаляем
		if aabb.has_point(pos):
			to_remove.append(child)
			continue
		# 2) Внутри BLOB-зоны вокруг центра структуры — удаляем
		var dx := pos.x - center.x
		var dz := pos.z - center.z
		var d := sqrt(dx * dx + dz * dz)
		var angle := atan2(dz, dx)
		# BLOB: радиус по углу модулируется шумом
		var cx := cos(angle) * blob_frequency
		var cz := sin(angle) * blob_frequency
		var n := _blob_noise.get_noise_2d(cx + center.x * 0.01, cz + center.z * 0.01)
		var edge := clear_radius * (1.0 + n * blob_amplitude)
		if d < edge:
			to_remove.append(child)
	for n in to_remove:
		n.queue_free()

# ---------------------------------------------------------------- таблица

func _place_from_table(root: Node3D) -> void:
	var table := ForestObjects.get_table()
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed

	var half := world_size * 0.5
	var samples := int(world_size / 2.0)
	var step := world_size / float(samples)

	# 1) Объекты — по всему квадрату террейна
	for entry in table:
		if entry.get("kind", "") != "object":
			continue
		var e_count: int = int(entry.get("count", 0))
		var target := 0
		if e_count > 0:
			target = rng.randi_range(1, e_count)
		var placed := 0
		var e_density: float = float(entry.get("density", 0.0))
		var e_min_slope: float = float(entry.get("min_slope", 0.0))
		var e_max_slope: float = float(entry.get("max_slope", 2.0))
		var e_rule: String = str(entry.get("rule", "anywhere"))
		var e_id: String = str(entry.get("id", ""))

		for sz in samples:
			if e_count > 0 and placed >= target:
				break
			for sx in samples:
				if e_count > 0 and placed >= target:
					break
				var wx := (sx + 0.5) * step - half
				var wz := (sz + 0.5) * step - half
				if _is_in_fence_zone(wx, wz):
					continue
				var y := _chunk_height(wx, wz)
				var slope := _slope_at(wx, wz, 1.5)
				var fdensity := _forest_density_at(wx, wz)
				if slope < e_min_slope or slope > e_max_slope:
					continue
				if e_rule == "clearing" and (fdensity >= 0.35 or slope >= 0.7):
					continue
				var chance: float = e_density if e_count == 0 else 1.0
				if e_id.begins_with("tree_"):
					chance *= fdensity
				if rng.randf() >= chance:
					continue
				var scene := _resolve_scene(entry)
				if scene == null:
					continue
				var y_off: float = float(entry.get("y_offset", 0.0))
				var pos := Vector3(wx, y + y_off, wz)
				_spawn(entry, scene, root, pos, rng.randf_range(0, TAU), rng)
				placed += 1

	# 2) Структуры — всегда внутри BLOB
	for entry in table:
		if entry.get("kind", "") != "structure":
			continue
		var has_fixed: bool = entry.has("ang") and entry.has("dist")
		var cnt: int = 1 if has_fixed else maxi(int(entry.get("count", 1)), 1)
		var e_min_slope: float = float(entry.get("min_slope", 0.0))
		var e_max_slope: float = float(entry.get("max_slope", 2.0))
		var e_rule: String = str(entry.get("rule", "anywhere"))
		var y_off: float = float(entry.get("y_offset", 0.0))
		var base_x := 0.0
		var base_z := 0.0

		if has_fixed:
			var ang_rad := deg_to_rad(float(entry.get("ang", 0.0)))
			var r := _blob_radius(ang_rad)
			var dist_m := clampf(float(entry.get("dist", 0.5)), 0.0, 0.95) * r
			base_x = cos(ang_rad) * dist_m
			base_z = sin(ang_rad) * dist_m
		elif cnt == 1:
			var world_rng := RandomNumberGenerator.new()
			world_rng.seed = world_seed ^ hash(str(entry.get("id", "")))
			var ang := world_rng.randf_range(0, TAU)
			var r := _blob_radius(ang) * world_rng.randf_range(0.1, 0.9)
			base_x = cos(ang) * r
			base_z = sin(ang) * r
		else:
			var ang := rng.randf_range(0, TAU)
			var r := _blob_radius(ang) * rng.randf_range(0.1, 0.9)
			base_x = cos(ang) * r
			base_z = sin(ang) * r

		for k in cnt:
			var wx := base_x
			var wz := base_z
			if not _is_inside_blob(wx, wz):
				continue
			if _is_in_fence_zone(wx, wz):
				continue
			var y := _chunk_height(wx, wz)
			var slope := _slope_at(wx, wz, 4.0)
			var fdensity := _forest_density_at(wx, wz)
			if slope < e_min_slope or slope > e_max_slope:
				continue
			if e_rule == "clearing" and (fdensity >= 0.35 or slope >= 0.7):
				continue
			var scene := _resolve_scene(entry)
			if scene == null:
				continue
			var pos := Vector3(wx, y + y_off, wz)
			var spawned := _spawn(entry, scene, root, pos, rng.randf_range(0, TAU), rng)
			var clear_r: float = float(entry.get("clear_radius", 0.0))
			if clear_r > 0.0 and spawned != null:
				_clear_objects_around(spawned, root, clear_r)
			if has_fixed:
				break

# ---------------------------------------------------------------- забор

func _is_in_fence_zone(wx: float, wz: float) -> bool:
	var dist := sqrt(wx * wx + wz * wz)
	var angle := atan2(wz, wx)
	var r := _blob_radius(angle)
	return absf(dist - r) < 2.0

func _build_fence() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var angle_step := 0.01
	var steps := int(TAU / angle_step)
	var prev_x := cos(0.0) * _blob_radius(0.0)
	var prev_z := sin(0.0) * _blob_radius(0.0)
	var has_any := false
	for k in range(1, steps + 1):
		var angle := k * angle_step
		var r := _blob_radius(angle)
		var wx := cos(angle) * r
		var wz := sin(angle) * r
		var y1 := _chunk_height(prev_x, prev_z)
		var y2 := _chunk_height(wx, wz)
		var y1_top := y1 + fence_height
		var y2_top := y2 + fence_height
		var bl := Vector3(prev_x, y1, prev_z)
		var br := Vector3(wx, y2, wz)
		var tl := Vector3(prev_x, y1_top, prev_z)
		var tr := Vector3(wx, y2_top, wz)
		_emit_fence(st, bl); _emit_fence(st, tl); _emit_fence(st, br)
		_emit_fence(st, br); _emit_fence(st, tl); _emit_fence(st, tr)
		has_any = true
		prev_x = wx
		prev_z = wz
	if not has_any:
		return
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Fence"
	if fence_material != null:
		mi.material_override = fence_material
	else:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.4, 0.3, 0.2)
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = m
	mi.mesh = st.commit()
	_terrain_root.add_child(mi)

	var sb := StaticBody3D.new()
	sb.name = "FenceCollision"
	_terrain_root.add_child(sb)
	var col := CollisionShape3D.new()
	col.shape = mi.mesh.create_trimesh_shape()
	sb.add_child(col)

func _emit_fence(st: SurfaceTool, v: Vector3) -> void:
	st.add_vertex(v)
