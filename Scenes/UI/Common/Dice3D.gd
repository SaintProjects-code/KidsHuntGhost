extends SubViewportContainer
## Two (or more) real 3D dice — the same white dice the 3D board throws —
## tumbling in onto a transparent background. await roll([4, 2]).

const BuilderScript := preload("res://Scenes/Board/View3D/MapMeshBuilder.gd")
const SPACING := 3.2
const ROLL_TIME := 0.8

var _vp: SubViewport
var _dice: Array = []
var _mesh: ArrayMesh
var _mat: Material

func _init(box := Vector2(260, 130)) -> void:
	stretch = true
	custom_minimum_size = box
	size = box
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	add_child(_vp)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	_vp.add_child(light)
	var cam := Camera3D.new()
	cam.fov = 30
	cam.transform = Transform3D(Basis(), Vector3(0, 0, 11))
	_vp.add_child(cam)
	var b = BuilderScript.new()
	_mesh = b.die_mesh()
	_mat = b.die_material()

# Throw one die per value; they tumble in from above, spinning, and land
# showing their value to the camera.
func roll(values: Array) -> void:
	for d in _dice:
		d.queue_free()
	_dice.clear()
	Sfx.play("dice")
	var last: Tween
	for k in values.size():
		var die := MeshInstance3D.new()
		die.mesh = _mesh
		die.material_override = _mat
		_vp.add_child(die)
		_dice.append(die)
		var spot := Vector3((k - (values.size() - 1) * 0.5) * SPACING, 0, 0)
		var start := spot + Vector3(randf_range(-1.5, 1.5), 5.0, 0)
		var final: Basis = BuilderScript.die_face_toward(int(values[k]), Vector3(0, 0, 1))
		var axis := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		var spin := TAU * 3.0 + randf() * PI
		var tw := create_tween()
		tw.tween_method(_tumble.bind(die, start, spot, final, axis, spin), 0.0, 1.0, ROLL_TIME + k * 0.12)
		last = tw
	await last.finished
	Sfx.play("land", 1.3)

func _tumble(t: float, die: Node3D, start: Vector3, end: Vector3, final: Basis, axis: Vector3, spin: float) -> void:
	var fall := 1.0 - pow(1.0 - t, 3.0)
	die.position = start.lerp(end, fall) + Vector3(0, absf(sin(t * PI * 2.0)) * (1.0 - t) * 1.2, 0)   # a bounce
	die.basis = (Basis(axis, spin * pow(1.0 - t, 2.0)) * final).scaled(Vector3.ONE * 2.3)

func clear() -> void:
	for d in _dice:
		d.queue_free()
	_dice.clear()
