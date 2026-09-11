extends Node3D

const DIE_SCENE = preload("res://die.tscn")
const TARGET_SCORE := 20
const WIN_FADE_IN := 0.4
const WIN_FADE_OUT := 4.0

# Where the die respawns. Tweak in the inspector if you want a new spot.
@export var spawn_position: Vector3 = Vector3(0, 1.7, 0)

var _current_die: RigidBody3D
var _total_score: int = 0
var _last_roll: int = 0
var _won: bool = false
var _total_label: Label
var _last_label: Label
var _target_label: Label
var _win_label: Label


func _ready() -> void:
	_build_hud()
	_spawn_die()


# --- HUD ----------------------------------------------------------------------

func _build_hud() -> void:
	# CanvasLayer renders independently of the 3D camera, so the HUD
	# sits on top of everything regardless of where the die is in the scene.
	var hud_layer := CanvasLayer.new()
	add_child(hud_layer)

	# --- Score panel (top-left) ----------------------------------------------
	var score_panel := _create_panel(Control.PRESET_TOP_LEFT, Vector2(16, 16))
	hud_layer.add_child(score_panel)

	var score_vbox := VBoxContainer.new()
	score_vbox.add_theme_constant_override("separation", 4)
	score_panel.add_child(score_vbox)

	_total_label = Label.new()
	_total_label.text = "Score: 0"
	_total_label.add_theme_font_size_override("font_size", 28)
	_total_label.add_theme_color_override("font_color", Color.WHITE)
	score_vbox.add_child(_total_label)

	_last_label = Label.new()
	_last_label.text = "Last roll: —"
	_last_label.add_theme_font_size_override("font_size", 16)
	_last_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	score_vbox.add_child(_last_label)

	# --- Target panel (top-right) --------------------------------------------
	# For PRESET_TOP_RIGHT, both anchors are 1.0 so the panel grows leftward
	# from the right edge — `offset_right = -margin.x` is the margin.
	var target_panel := _create_panel(Control.PRESET_TOP_RIGHT, Vector2(16, 16))
	hud_layer.add_child(target_panel)

	_target_label = Label.new()
	_target_label.text = "Target: %d" % TARGET_SCORE
	_target_label.add_theme_font_size_override("font_size", 28)
	_target_label.add_theme_color_override("font_color", Color.WHITE)
	target_panel.add_child(_target_label)

	# --- Win message (centered, starts invisible) ----------------------------
	# CenterContainer anchored to FULL_RECT keeps the label dead-centered at
	# any window size. MOUSE_FILTER_IGNORE so clicks pass through to the scene.
	var win_container := CenterContainer.new()
	win_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(win_container)

	_win_label = Label.new()
	_win_label.text = "You win this round!"
	_win_label.add_theme_font_size_override("font_size", 56)
	_win_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))  # warm gold
	_win_label.modulate.a = 0.0  # hidden until win
	win_container.add_child(_win_label)


# Helper: create a styled PanelContainer anchored to the given preset.
# `margin` is read as (horizontal_offset, top_offset) — applied to offset_left
# for TOP_LEFT or offset_right for TOP_RIGHT.
func _create_panel(preset: int, margin: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(preset)
	if preset == Control.PRESET_TOP_LEFT:
		panel.offset_left = margin.x
		panel.offset_top = margin.y
	elif preset == Control.PRESET_TOP_RIGHT:
		# Both horizontal anchors land at 1.0 (right edge), so we have to
		# set offset_left to a negative value explicitly — otherwise the
		# panel's computed width is (offset_right - offset_left) = (-16 - 0)
		# = -16 and it collapses off-screen. PanelContainer doesn't auto-size
		# cleanly when both anchors share a value. Same for offset_bottom.
		panel.offset_left = -250.0
		panel.offset_top = margin.y
		panel.offset_right = -margin.x
		panel.offset_bottom = 90.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)

	return panel


# --- Input --------------------------------------------------------------------

# Press R to delete the current die and spawn a fresh one at spawn_position.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey \
			and event.pressed \
			and not event.echo \
			and event.keycode == KEY_R:
		_respawn()
		get_viewport().set_input_as_handled()


# --- Die lifecycle ------------------------------------------------------------

func _respawn() -> void:
	if _current_die:
		_current_die.queue_free()
	_spawn_die()


func _spawn_die() -> void:
	var die: RigidBody3D = DIE_SCENE.instantiate()
	add_child(die)
	die.global_position = spawn_position
	_current_die = die
	die.roll_finished.connect(_on_die_rolled)


func _on_die_rolled(value: int) -> void:
	_total_score += value
	_last_roll = value
	_total_label.text = "Score: %d" % _total_score
	_last_label.text = "Last roll: %d" % _last_roll

	# Trigger the win fade once, the first time we cross the target.
	if not _won and _total_score >= TARGET_SCORE:
		_won = true
		_show_win_message()


func _show_win_message() -> void:
	# Quick fade-in then slow fade-out. Two chained tweens on a single tween
	# handle both — the second tween starts automatically when the first ends.
	var tween := create_tween()
	tween.tween_property(_win_label, "modulate:a", 1.0, WIN_FADE_IN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_win_label, "modulate:a", 0.0, WIN_FADE_OUT) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
