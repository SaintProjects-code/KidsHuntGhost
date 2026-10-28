class_name MapSpace
extends Resource

@export var id: int
@export var type: StringName  # &"GYM", &"CITY", &"SPIRIT_STAGE1", etc.
@export var label: String
@export var adjacent: Array[int]
