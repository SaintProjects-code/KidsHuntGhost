extends CanvasLayer
## The weather over the board (2D and 3D maps alike, drawn by WeatherFX) and a
## badge with what it does and how many rounds are left.

const WeatherData := preload("res://Data/WeatherData.gd")

var _badge: Label

func _ready() -> void:
	layer = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(preload("res://Scenes/Board/WeatherFX.gd").new())
	_badge = UIKit.label("", 18, Color.WHITE)
	_badge.add_theme_stylebox_override("normal", UIKit.box(Color(UIKit.NIGHT, 0.85), 10, 2, Color("9fdcff"), Vector2(12, 6)))
	_badge.position = Vector2(20, 176)
	_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_badge)

func _process(_delta: float) -> void:
	_badge.visible = GameState.weather != ""
	if _badge.visible:
		_badge.text = WeatherData.label()
		_badge.tooltip_text = String(WeatherData.info(GameState.weather).get("desc", ""))
