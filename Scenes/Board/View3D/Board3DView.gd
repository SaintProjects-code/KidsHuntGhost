extends CanvasLayer
## The 3D picture of the board, drawn behind all the 2D UI.
##
## This is display only. Board still moves its (now hidden) 2D tokens and
## Camera2D exactly as before, and every frame this node copies them into 3D.
## So turns, saves, View Map and the phone controls need no changes.

const MeshBuilder := preload("res://Scenes/Board/View3D/MapMeshBuilder.gd")

const RENDER_SIZE := Vector2i(640, 360)   # scales up by whole numbers on 720p / 1080p / 4K
const TILE_PX := 16.0
const TILT := deg_to_rad(45.0)
const FOV := 30.0                         # narrow, so tiles keep their size across the screen
const VIEW_DISTANCE := 52.0               # camera distance at the board's normal zoom
const NORMAL_ZOOM := 1.5
const BACKGROUND := Color("2c6a58")
const FEET_LIFT := 0.05                   # keeps feet and shadow from flickering into the ground
const SHEET_FEET_ROW := 20                # the art fills rows 0-19 of each 32 px frame

const LABEL_MIN_ZOOM := 0.55              # zoomed out further, names turn into clutter
const LABEL_FONT_SIZE := 13
const TOWN_FONT_SIZE := 16
const LABEL_OUTLINE := 4
const LABEL_TOKEN_CLEARANCE := 1.3        # hide a tile's name while someone stands on it

var _map
var _builder
var _camera_2d: Camera2D
var _tokens_2d: Array = []
var _tokens_3d: Array = []
var _camera: Camera3D
var _viewport: SubViewport
var _overlay: Control
var _bushes: Dictionary = {}   # space index -> MeshInstance3D

func _init() -> void:
	layer = -1
	process_mode = Node.PROCESS_MODE_ALWAYS   # View Map pans while the tree is paused

## `options`: the map's GameData entry ("villages", "avenues"; see MapMeshBuilder.build).
func setup(map, camera_2d: Camera2D, tokens: Array, options: Dictionary = {}) -> void:
	_map = map
	_camera_2d = camera_2d
	_tokens_2d = tokens
	_build_viewport()
	_builder = MeshBuilder.new()
	_viewport.add_child(_builder.build(map, options))
	_build_camera()
	for token in tokens:
		_tokens_3d.append(_make_token(token))
	_build_bushes()
	_build_overlay()
	_sync()

func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = RENDER_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var picture := TextureRect.new()
	picture.texture = _viewport.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture)
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.near = 1.0
	_camera.far = 2500.0
	_camera.rotation = Vector3(-TILT, 0.0, 0.0)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	_camera.environment = env
	_viewport.add_child(_camera)
	_camera.make_current()

func _make_token(token: AnimatedSprite2D) -> AnimatedSprite3D:
	var spr := AnimatedSprite3D.new()
	spr.sprite_frames = token.sprite_frames
	spr.animation = token.animation
	spr.modulate = token.modulate
	spr.pixel_size = token.scale.x / TILE_PX
	var frame_h: int = token.sprite_frames.get_frame_texture(token.animation, 0).get_height()
	spr.offset = Vector2(0.0, SHEET_FEET_ROW - frame_h * 0.5)   # feet on the node's origin
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	spr.shaded = false
	_viewport.add_child(spr)
	var shadow := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.8
	disc.bottom_radius = 0.8
	disc.height = 0.01
	disc.radial_segments = 14
	disc.rings = 0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.05, 0.05, 0.12, 0.4)
	disc.material = mat
	shadow.mesh = disc
	spr.add_child(shadow)
	return spr

func _build_overlay() -> void:
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.draw.connect(_draw_labels)

func _process(_delta: float) -> void:
	_sync()

func _sync() -> void:
	if not is_instance_valid(_camera_2d):
		return
	var center := _camera_2d.global_position
	var distance := VIEW_DISTANCE * NORMAL_ZOOM / _camera_2d.zoom.x
	_camera.position = _to_3d(center, 0.0) + Vector3(0.0, sin(TILT), cos(TILT)) * distance
	for i in _tokens_2d.size():
		_copy_token(_tokens_2d[i], _tokens_3d[i])
	_overlay.queue_redraw()

func _to_3d(world: Vector2, height: float) -> Vector3:
	return Vector3(world.x / TILE_PX, height, world.y / TILE_PX)

func _copy_token(from: AnimatedSprite2D, to: AnimatedSprite3D) -> void:
	to.position = _to_3d(from.global_position, _builder.surface_height(from.global_position) + FEET_LIFT)
	to.flip_h = from.flip_h
	if to.animation != from.animation:
		to.animation = from.animation
	if to.frame != from.frame:
		to.frame = from.frame

# Tile and town names are drawn crisp over the low-res picture, so they stay
# readable from across the room.
func _draw_labels() -> void:
	var zoom := _camera_2d.zoom.x
	if zoom < LABEL_MIN_ZOOM:
		return
	var scale_up := _overlay.size / Vector2(RENDER_SIZE)
	var text_scale := clampf(zoom / NORMAL_ZOOM, 0.7, 1.4)
	for i in _map.spaces.size():
		var world: Vector2 = _map.spaces[i]
		if not _token_near(world):
			_label(world, _map.space_type_name(_map.space_types[i]), scale_up, int(LABEL_FONT_SIZE * text_scale), Vector2.ZERO)
	for node_name in _map.NODES:
		if _map.CITIES.has(node_name):
			var world: Vector2 = _map._cell_to_world(_map.NODES[node_name])
			_label(world, _map.NAMES.get(node_name, node_name), scale_up, int(TOWN_FONT_SIZE * text_scale), Vector2(0.0, 44.0 * text_scale))

func _token_near(world: Vector2) -> bool:
	for token in _tokens_2d:
		if token.global_position.distance_to(world) < LABEL_TOKEN_CLEARANCE * TILE_PX:
			return true
	return false

func _label(world: Vector2, text: String, scale_up: Vector2, font_size: int, nudge: Vector2) -> void:
	var at := _to_3d(world, 0.2)
	if _camera.is_position_behind(at):
		return
	var screen := _camera.unproject_position(at) * scale_up + nudge
	if not _overlay.get_rect().grow(80.0).has_point(screen):
		return
	var font: Font = _map.LABEL_FONT
	var width := 160.0
	var pos := screen + Vector2(-width * 0.5, font_size * 0.35)
	_overlay.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, LABEL_OUTLINE, Color(0, 0, 0, 0.9))
	_overlay.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, Color.WHITE)

# ─── Landing shows ───────────────────────────────────────────────────────────
# On boards with "landing_shows", landing on a Ghost / Event / Item / Clash
# tile first plays a little scene: the bush beside the tile rustles, something
# pops out and hops over to the player, then the tile's window opens.

const SHAKE_TIME := 0.5
const HOP_TIME := 0.5
const HOVER_TIME := 0.45
const BUSH_FIND_RADIUS := 5.0   # tiles: how far to look for a bush when not standing on a tile

func _build_bushes() -> void:
	var meshes := {}
	for spec in _builder.bushes:
		var planter: bool = spec["planter"]
		if not meshes.has(planter):
			meshes[planter] = _builder.bush_mesh(planter)
		var bush := MeshInstance3D.new()
		bush.mesh = meshes[planter]
		bush.material_override = _builder.props_material()
		bush.position = spec["pos"]
		bush.rotation.y = float(spec["space"] % 7) * 0.4   # not every bush the same way round
		_viewport.add_child(bush)
		_bushes[spec["space"]] = bush

## Plays the scene for player `token_i` standing on road tile `space` (-1 if
## not on a tile) and returns when it's done. Does nothing on boards without
## bushes. `spirit` is the wild spirit for Ghost tiles.
func play_landing(token_i: int, space: int, type: StringName, spirit: Dictionary = {}) -> void:
	if _bushes.is_empty() or token_i >= _tokens_3d.size():
		return
	var token: AnimatedSprite3D = _tokens_3d[token_i]
	var bush: MeshInstance3D = _bushes.get(space)
	if bush == null:
		bush = _nearest_bush(token.position)
		if bush == null:
			return
	# the thing lands beside the player (on the bush's side), a little toward
	# the camera, so neither hides the other; the player turns to face it
	var side := signf(bush.position.x - token.position.x)
	if absf(bush.position.x - token.position.x) < 0.3:
		side = 1.0
	_face_side(token_i, side)
	await _rustle(bush)
	var thing := _make_popper(type, spirit, token)
	_viewport.add_child(thing)
	var start := bush.position + Vector3(0, 1.2, 0)
	var end := token.position + Vector3(side * 2.1, 1.7, 0.6)
	thing.position = start
	thing.scale = Vector3.ONE * 0.3
	Sfx.play(_pop_sound(type), 1.1)
	var hop := create_tween().set_parallel(true)
	hop.tween_method(func(t: float): thing.position = start.lerp(end, t) + Vector3(0, sin(t * PI) * 1.6, 0), 0.0, 1.0, HOP_TIME)
	hop.tween_property(thing, "scale", Vector3.ONE, HOP_TIME * 0.6)
	if type == &"ITEM":
		hop.tween_property(thing, "rotation:y", TAU, HOP_TIME + HOVER_TIME)
	await hop.finished
	var hover := create_tween()
	hover.tween_property(thing, "position:y", end.y + 0.3, HOVER_TIME * 0.5).set_trans(Tween.TRANS_SINE)
	hover.tween_property(thing, "position:y", end.y, HOVER_TIME * 0.5).set_trans(Tween.TRANS_SINE)
	await hover.finished
	var out := create_tween()
	out.tween_property(thing, "scale", Vector3.ONE * 0.05, 0.15)
	await out.finished
	thing.queue_free()

# Turn player `token_i` to look left (side < 0) or right. Set on the board's
# 2D token, which this view copies every frame; the sheet's side pose faces left.
func _face_side(token_i: int, side: float) -> void:
	var t: AnimatedSprite2D = _tokens_2d[token_i]
	t.stop()
	t.animation = "side"
	t.frame = 0
	t.flip_h = side > 0.0

func _nearest_bush(at: Vector3) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_d := BUSH_FIND_RADIUS
	for bush in _bushes.values():
		var d: float = Vector2(bush.position.x - at.x, bush.position.z - at.z).length()
		if d < best_d:
			best_d = d
			best = bush
	return best

func _rustle(bush: MeshInstance3D) -> void:
	Sfx.play("whoosh", 0.7)
	var base_rot := bush.rotation
	var tw := create_tween()
	for k in 6:
		var lean := deg_to_rad(9.0) * (1.0 - k / 6.0) * (1.0 if k % 2 == 0 else -1.0)
		tw.tween_property(bush, "rotation", base_rot + Vector3(lean * 0.6, 0, lean), SHAKE_TIME / 6.0)
	tw.tween_property(bush, "rotation", base_rot, 0.05)
	await tw.finished

func _pop_sound(type: StringName) -> String:
	match type:
		&"CLASH": return "whoosh"
		&"EVENT": return "wobble"
	return "pop"

# What jumps out: the wild spirit itself, a gift box, a "?" or a rival.
func _make_popper(type: StringName, spirit: Dictionary, token: AnimatedSprite3D) -> Node3D:
	match type:
		&"ITEM":
			var holder := Node3D.new()   # the hop tweens the holder's scale; the gift stays big
			var gift := MeshInstance3D.new()
			gift.mesh = _builder.gift_mesh()
			gift.material_override = _builder.props_material()
			gift.scale = Vector3.ONE * 1.4
			holder.add_child(gift)
			return holder
		&"EVENT":
			return _big_mark("?", Color("ffe08a"))
		&"CLASH":
			var rival := _flat_sprite(token.sprite_frames.get_frame_texture("down", 0), token.pixel_size)
			rival.modulate = Color(0.22, 0.16, 0.42)
			var mark := _big_mark("!", Color("ff6a6a"))
			mark.position = Vector3(0.9, 1.6, 0)
			mark.scale = Vector3.ONE * 0.7
			rival.add_child(mark)
			return rival
	var tex: Texture2D = SpiritsData.sprite_tex(spirit.get("name", ""), "front") if not spirit.is_empty() else null
	if tex == null:
		return _big_mark("!", Color("c8b0f0"))   # no sprite for this spirit
	return _flat_sprite(tex, 0.05)

func _flat_sprite(tex: Texture2D, px: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = px
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = false
	return s

func _big_mark(text: String, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 96
	l.pixel_size = 0.023
	l.modulate = col
	l.outline_size = 24
	l.outline_modulate = Color("20242e")
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return l

# ─── 3D dice ─────────────────────────────────────────────────────────────────
# On 3D boards, big dice pop up over the player's head instead of the HUD's
# flat dice tray, spin, and stop with their number facing the camera. The
# numbers are already decided (TurnSystem); each spin is worked backwards so
# it comes to rest on its number.

const DIE_SCALE := 2.2                 # the mesh is 0.9 across; this makes it ~2 tiles
const ABOVE_HEAD := 5.2                # die centre above the player's feet
const ROLL_TIME := 1.0
const DIE_STAGGER := 0.1               # each extra die stops a touch later
const DIE_SPACING := 2.5
const DICE_HOLD := 0.7                 # how long the total stays before walking

var _dice: Array = []
var _dice_label: Label3D
var _die_mesh: Mesh
var _die_mat: Material

## Spins one die per entry of `faces` above player `token_i`'s head, shows the
## total (plus `bonus`), and returns once it's been seen. The dice then pop
## away on their own while the player walks.
func roll_dice(token_i: int, faces: Array, bonus: int) -> void:
	_clear_dice()
	if _die_mesh == null:
		_die_mesh = _builder.die_mesh()
		_die_mat = _builder.die_material()
	var token: AnimatedSprite3D = _tokens_3d[token_i]
	var count := faces.size()
	Sfx.play("dice")
	var last: Tween
	var spots: Array = []
	for k in count:
		var die := MeshInstance3D.new()
		die.mesh = _die_mesh
		die.material_override = _die_mat
		_viewport.add_child(die)
		_dice.append(die)
		var spot := token.position + Vector3((k - (count - 1) * 0.5) * DIE_SPACING, ABOVE_HEAD, 0.4)
		spots.append(spot)
		var start := token.position + Vector3(0, 2.5, 0.4)   # out of the top of their head
		var final: Basis = MeshBuilder.die_face_toward(int(faces[k]), _to_camera())
		var axis := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-0.4, 0.4)).normalized()
		var spin := TAU * 3.0 + randf() * PI
		var time := ROLL_TIME + k * DIE_STAGGER
		die.position = start
		die.scale = Vector3.ONE * DIE_SCALE * 0.3
		var tw := create_tween()
		tw.tween_method(_tumble.bind(die, start, spot, final, axis, spin), 0.0, 1.0, time)
		tw.parallel().tween_callback(Sfx.play.bind("land", 1.4)).set_delay(time * 0.98)
		last = tw
	await last.finished   # the last die is the slowest
	_show_total(faces, bonus, spots)
	await get_tree().create_timer(DICE_HOLD).timeout
	_sink_dice()

# Shoots up out of the player's head, overshoots a little and settles, growing
# to full size while the spin unwinds to the final rotation.
func _tumble(t: float, die: Node3D, start: Vector3, end: Vector3, final: Basis, axis: Vector3, spin: float) -> void:
	var rise := 1.0 - pow(1.0 - t, 3.0)
	die.position = start.lerp(end, rise) + Vector3(0, sin(t * PI) * 0.9, 0)
	var size := DIE_SCALE * lerpf(0.3, 1.0, minf(t * 2.5, 1.0))
	die.basis = (Basis(axis, spin * pow(1.0 - t, 2.0)) * final).scaled(Vector3.ONE * size)

# Unit vector from the board toward the camera (the way faces should point).
func _to_camera() -> Vector3:
	return Vector3(0.0, sin(TILT), cos(TILT))

func _show_total(faces: Array, bonus: int, spots: Array) -> void:
	var total := bonus
	for f in faces:
		total += int(f)
	var text := ("%d" % total) if bonus == 0 and faces.size() == 1 else \
		"%s%s = %d" % [" + ".join(faces.map(func(f): return str(f))), (" + %d" % bonus) if bonus != 0 else "", total]
	var mid := Vector3.ZERO
	for s in spots:
		mid += s
	mid /= float(spots.size())
	_dice_label = _big_mark(text, Color("ffd24d"))
	_dice_label.font_size = 72
	_dice_label.position = mid + Vector3(0, DIE_SCALE * 0.5 + 1.1, 0)   # just above the dice
	_viewport.add_child(_dice_label)
	_dice_label.scale = Vector3.ONE * 0.4
	Sfx.play("pop", 1.2)
	var tw := create_tween()
	tw.tween_property(_dice_label, "scale", Vector3.ONE * 1.15, 0.12)
	tw.tween_property(_dice_label, "scale", Vector3.ONE, 0.1)
	for die in _dice:   # a little hop when the total shows
		var hop := create_tween()
		hop.tween_property(die, "scale", Vector3.ONE * DIE_SCALE * 1.15, 0.1)
		hop.tween_property(die, "scale", Vector3.ONE * DIE_SCALE, 0.12)

# The dice pop away and the total fades while the player walks.
func _sink_dice() -> void:
	var dice := _dice.duplicate()
	var label := _dice_label
	_dice.clear()
	_dice_label = null
	var tw := create_tween().set_parallel(true)
	for die in dice:
		tw.tween_property(die, "position:y", (die as Node3D).position.y + 0.8, 0.35)
		tw.tween_property(die, "scale", Vector3.ONE * 0.05, 0.35)
	if label:
		tw.tween_property(label, "modulate:a", 0.0, 0.35)
		tw.tween_property(label, "outline_modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(func():
		for n in dice + ([label] if label else []):
			if is_instance_valid(n):
				n.queue_free())

func _clear_dice() -> void:
	for n in _dice + ([_dice_label] if _dice_label else []):
		if is_instance_valid(n):
			n.queue_free()
	_dice.clear()
	_dice_label = null
