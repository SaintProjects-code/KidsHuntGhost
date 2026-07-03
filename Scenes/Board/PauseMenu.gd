extends Control
## Pause + settings overlay for the board, plus a dedicated "View Map" mode.
## Runs with process_mode = Always so it keeps working while the tree is paused.

const PAN_SPEED := 900.0
const ZOOM_MIN := 0.1
const ZOOM_MAX := 3.0

@onready var menu: Panel = $SettingsMenu
@onready var sound_slider: HSlider = $SettingsMenu/Margin/VBox/SoundRow/SoundSlider
# lives on the always-on-top TopUI layer so it can be pressed at any time
@onready var settings_button: Button = get_node("../../TopUI/SettingsButton")
@onready var action_bar: HBoxContainer = $ActionBar
@onready var util_row: HBoxContainer = $UtilRow
@onready var info_label: Label = $InfoLabel
@onready var view_hint: Label = $ViewHint
@onready var back_button: Button = $BackButton
@onready var zoom_label: Label = $ZoomLabel

var _view_mode: bool = false
var _saved_pos: Vector2 = Vector2.ZERO
var _saved_zoom: Vector2 = Vector2.ONE

func _ready() -> void:
	menu.hide()
	view_hint.hide()
	back_button.hide()
	zoom_label.hide()
	sound_slider.min_value = 0
	sound_slider.max_value = 100
	sound_slider.value = roundf(db_to_linear(AudioServer.get_bus_volume_db(0)) * 100.0)
	sound_slider.value_changed.connect(_on_sound_changed)

func _on_settings_pressed() -> void:
	menu.show()
	get_tree().paused = true

func _on_close_pressed() -> void:
	menu.hide()
	get_tree().paused = false

func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/Menu/MainMenu.tscn")

func _on_sound_changed(value: float) -> void:
	var pct: float = value / 100.0
	AudioServer.set_bus_mute(0, pct <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(pct, 0.0001)))

# ---------------- View Map mode ----------------

func _on_view_map_pressed() -> void:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null:
		_saved_pos = cam.position
		_saved_zoom = cam.zoom
	_view_mode = true
	# Pause the board while viewing: stops the camera-follow from dragging
	# the view back to the active player's token while you pan around.
	# (The MAP button path arrives here unpaused; Settings arrives paused.)
	get_tree().paused = true
	# hide everything else; the board stays paused underneath
	menu.hide()
	settings_button.hide()
	action_bar.hide()
	util_row.hide()
	var hud := get_node_or_null("HUD")
	if hud != null:
		hud.hide()
	info_label.hide()
	view_hint.show()
	back_button.show()
	zoom_label.show()
	_update_zoom_label()

func _update_zoom_label() -> void:
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null:
		zoom_label.text = "Zoom: %d%%" % roundi(cam.zoom.x * 100.0)

func _on_back_pressed() -> void:
	_exit_view()

func _exit_view() -> void:
	if not _view_mode:
		return
	_view_mode = false
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam != null:
		cam.position = _saved_pos
		cam.zoom = _saved_zoom
	view_hint.hide()
	back_button.hide()
	zoom_label.hide()
	settings_button.show()
	action_bar.show()
	util_row.show()
	var hud := get_node_or_null("HUD")
	if hud != null:
		hud.show()
	info_label.show()
	# straight back to the game — no settings menu, unpause
	menu.hide()
	get_tree().paused = false

func _unhandled_input(event: InputEvent) -> void:
	if _view_mode and event.is_action_pressed("ui_cancel"):
		_exit_view()

func _process(delta: float) -> void:
	# Pan/zoom only while in View Map mode.
	if not _view_mode:
		return
	var cam: Camera2D = get_viewport().get_camera_2d()
	if cam == null:
		return
	var dir: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("ui_left") or _held(KEY_LEFT) or _held(KEY_A):
		dir.x -= 1.0
	if Input.is_action_pressed("ui_right") or _held(KEY_RIGHT) or _held(KEY_D):
		dir.x += 1.0
	if Input.is_action_pressed("ui_up") or _held(KEY_UP) or _held(KEY_W):
		dir.y -= 1.0
	if Input.is_action_pressed("ui_down") or _held(KEY_DOWN) or _held(KEY_S):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		# divide by zoom so panning feels the same speed at any zoom level
		cam.position += dir.normalized() * PAN_SPEED * delta / cam.zoom.x
		# The camera is paused, so push the new position to the screen now;
		# otherwise a position change only shows when the zoom also changes.
		cam.force_update_scroll()

	var zdir: float = 0.0
	if _held(KEY_Q) or _held(KEY_MINUS):
		zdir -= 1.0
	if _held(KEY_E) or _held(KEY_EQUAL):
		zdir += 1.0
	if zdir != 0.0:
		var z: float = clampf(cam.zoom.x * (1.0 + zdir * 1.2 * delta), ZOOM_MIN, ZOOM_MAX)
		cam.zoom = Vector2(z, z)
		_update_zoom_label()

func _held(keycode: int) -> bool:
	return Input.is_key_pressed(keycode) or Input.is_physical_key_pressed(keycode)
