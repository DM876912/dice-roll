extends Control

# Main menu — placeholder for now. Art + polish TBD.
# Built entirely in _ready() (matches the in-game HUD pattern in world.gd)
# so the layout lives in code, not in scattered .tscn nodes. Easier to
# iterate on while the design is in flux.

const GAME_SCENE := "res://World.tscn"

# Size of the custom-art slot placeholder. The real title art will replace
# this rect — leaving it as a clearly-bordered empty zone for now so it's
# obvious where the custom work goes.
const ART_PLACEHOLDER_SIZE := Vector2(320, 200)


func _ready() -> void:
	_build_background()
	_build_menu()


# Solid dark background matching the in-game HUD's color language
# (translucent near-black panels). Fills the full viewport via FULL_RECT
# so the menu looks intentional at any window size.
func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.10, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# IGNORE so clicks on empty area don't get swallowed by the bg rect.
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


# Center the menu content. CenterContainer fills the screen and centers
# its single VBox child, so the layout adapts to any window size without
# per-child anchoring.
func _build_menu() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 28)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	# --- Title ---------------------------------------------------------------
	# Warm gold matches the win-message color in the game — keeps the menu
	# visually consistent with the rest of the project's palette.
	var title := Label.new()
	title.text = "DICE ROLL"
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# --- Subtitle ------------------------------------------------------------
	var subtitle := Label.new()
	subtitle.text = "A 3D dice-tossing game"
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	# --- Art placeholder -----------------------------------------------------
	# Where Daniel's custom art will go. Dashed border + center label so it
	# reads as a "slot," not as a finished UI element.
	vbox.add_child(_make_art_placeholder())

	# --- Buttons -------------------------------------------------------------
	# Primary (PLAY) is bigger + uses the same blue accent as the inventory
	# slot buttons in-world, so the menu feels like part of the same app.
	# Secondary (QUIT) is smaller and muted so it doesn't compete.
	var play_btn := _make_button("PLAY", 280, 64, true)
	play_btn.pressed.connect(_on_play_pressed)
	vbox.add_child(play_btn)

	var quit_btn := _make_button("QUIT", 200, 48, false)
	quit_btn.pressed.connect(_on_quit_pressed)
	vbox.add_child(quit_btn)

	# --- Footer note ---------------------------------------------------------
	# Subtle reminder that this is a placeholder. Alpha 0.4 keeps it out of
	# the way but visible — Daniel will see it on every playtest until he
	# replaces the menu.
	var footer := Label.new()
	footer.text = "placeholder menu — art and polish TBD"
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(footer)


func _make_art_placeholder() -> Control:
	var rect := Panel.new()
	rect.custom_minimum_size = ART_PLACEHOLDER_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)  # transparent — just the dashed border
	style.border_color = Color(1, 1, 1, 0.35)
	style.set_border_width_all(2)
	# Dashed pattern: 8px dash, 4px gap. Reads as a "draft" / placeholder
	# border rather than a finished UI element.
	style.set_dash_pattern_all(PackedInt32Array([8, 4]))
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	rect.add_theme_stylebox_override("panel", style)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = "[ custom art slot ]"
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.add_child(label)
	return rect


func _make_button(text: String, width: int, height: int, primary: bool) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(width, height)
	btn.text = text
	btn.add_theme_font_size_override("font_size", 28 if primary else 18)
	btn.add_theme_color_override("font_color", Color.WHITE)

	# StyleBoxFlat per-state. Primary uses the inventory-slot blue accent;
	# secondary uses a muted gray so it doesn't visually compete with PLAY.
	var normal := StyleBoxFlat.new()
	if primary:
		normal.bg_color = Color(0.2, 0.45, 0.7, 0.9)
	else:
		normal.bg_color = Color(0.18, 0.18, 0.22, 0.85)
	normal.set_corner_radius_all(10)
	normal.set_content_margin_all(12)
	btn.add_theme_stylebox_override("normal", normal)

	var hover := normal.duplicate()
	if primary:
		hover.bg_color = Color(0.35, 0.6, 0.85, 0.9)
	else:
		hover.bg_color = Color(0.28, 0.28, 0.36, 0.9)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed := hover.duplicate()
	if primary:
		pressed.bg_color = Color(0.55, 0.75, 1.0, 0.9)
	else:
		pressed.bg_color = Color(0.38, 0.38, 0.48, 0.9)
	btn.add_theme_stylebox_override("pressed", pressed)

	return btn


# --- Handlers ---------------------------------------------------------------

func _on_play_pressed() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()


# --- Input ------------------------------------------------------------------

# Space or Enter on the menu starts the game. Mirrors the in-game
# "press space to roll" feel — same keyboard, different action. No
# Escape handler: the QUIT button is the explicit quit path, avoids
# accidental exits mid-development.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_on_play_pressed()
		get_viewport().set_input_as_handled()
