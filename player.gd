extends Node2D
## A visual avatar. The server owns movement; this node only smooths snapshots.

var target_position := Vector2.ZERO
var tint := Color.WHITE
var is_local := false

@onready var name_label: Label = $NameLabel


func configure(state: Dictionary, local: bool) -> void:
	tint = state.color
	is_local = local
	target_position = state.position
	position = target_position


func _ready() -> void:
	queue_redraw()


func update_state(state: Dictionary) -> void:
	target_position = state.position
	name_label.text = "%s%s" % [state.name, " (you)" if is_local else ""]


func _process(delta: float) -> void:
	position = position.lerp(target_position, 1.0 - exp(-25.0 * delta))


func _draw() -> void:
	draw_circle(Vector2(0, 5), 19, Color(0, 0, 0, 0.2))
	draw_circle(Vector2.ZERO, NetworkManager.PLAYER_RADIUS, tint)
	draw_circle(Vector2(-5, -3), 2, Color("233c35"))
	draw_circle(Vector2(5, -3), 2, Color("233c35"))
	if is_local:
		draw_arc(Vector2.ZERO, 22, 0, TAU, 48, Color.WHITE, 2, true)
