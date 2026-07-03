extends MenuWindow
## "A wild <spirit> appeared!" — Fight or Catch. Shown via UIManager.
## present(spirit); emits chose("fight" | "catch").

signal chose(action: String)

var _title: Label
var _sprite: TextureRect
var _info: Label

func _ready() -> void:
	var col := _init_window(480, 400)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)

	_sprite = TextureRect.new()
	_sprite.custom_minimum_size = Vector2(120, 120)
	_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_sprite)

	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_info)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(buttons)
	buttons.add_child(_big_btn("⚔ Fight", func(): chose.emit("fight")))
	buttons.add_child(_big_btn("🎯 Catch", func(): chose.emit("catch")))
	hide()

func _big_btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(160, 54)
	b.pressed.connect(cb)
	return b

func present(spirit: Dictionary) -> void:
	_title.text = "A wild %s appeared!" % spirit.get("name", "?")
	_sprite.texture = SpiritsData.sprite_tex(spirit.get("name", ""), "front")
	_info.text = "Type: %s   |   HP: %d   |   ATK: %d" % [
		spirit.get("type", ""), spirit.get("hp", 0), spirit.get("atk", 0)]
