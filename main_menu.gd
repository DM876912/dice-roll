extends Control

# Main menu — placeholder for now. Art + polish TBD.
# Built entirely in _ready() (matches the in-game HUD pattern in world.gd)
# so the layout lives in code, not in scattered .tscn nodes. Easier to
# iterate on while the design is in flux.

const GAME_SCENE := "res://World.tscn"

# Size of the custom-art slot placeholder. The real title art will replace
# this rect — leaving it as a clearly-bordered empty zone for now so it's
# obvious where the custom work goes.
const ART_PLACEHOLDER_SIZE := Vector2(220, 130)

# Options sub-menu constants. Section panels share a fixed width so all
# rows align; the panel background matches the secondary-button color
# for visual consistency with the rest of the menu.
const SECTION_PANEL_WIDTH := 460
const PANEL_BG := Color(0.08, 0.08, 0.12, 0.85)
const PANEL_CORNER_RADIUS := 8
const PANEL_PADDING := 16

# --- State ------------------------------------------------------------------
# Each panel (main menu + options) has its own ScrollContainer that fills
# the viewport, so content taller than the screen scrolls instead of being
# clipped. Without this, the QUIT button gets cut off on shorter windows
# and the BACK button inside the options panel becomes unreachable. Both
# scroll containers stay alive in the background; the active panel is
# whichever vbox is set to visible.
var _main_scroll: ScrollContainer
var _options_scroll: ScrollContainer
var _main_vbox: VBoxContainer
var _options_vbox: VBoxContainer


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


# Build the menu — main menu and options panel, each wrapped in its own
# ScrollContainer so content taller than the viewport scrolls instead of
# clipping (QUIT cutoff on shorter windows, BACK unreachable in options).
# Each panel manages its own scroll state; switching is a visible-toggled
# reveal with scroll_vertical reset so the user always lands at the top.
func _build_menu() -> void:
	_main_scroll = _make_scroll_container()
	_options_scroll = _make_scroll_container()
	# Hide the inactive scroll container so its default mouse_filter = STOP
	# can't intercept clicks meant for the visible panel — that's what was
	# making the main menu's buttons unclickable. Both scroll containers
	# fill the viewport, so whichever one is on top wins the input race;
	# hiding the inactive one eliminates the overlap entirely.
	_options_scroll.visible = false

	# --- Main menu content --------------------------------------------------
	# SIZE_EXPAND_FILL makes the vbox match the scroll viewport's width.
	# Combined with alignment = CENTER, children that are smaller than the
	# vbox (buttons, art slot, labels) center horizontally. When content
	# height exceeds the viewport, the scroll engages naturally.
	# (Earlier I tried SIZE_SHRINK_CENTER expecting shrink-to-fit + center
	# inside the scroll viewport — it doesn't reliably center inside a
	# ScrollContainer, the vbox pinned to top-left, and the inactive
	# options scroll on top blocked all input. This combo fixes both.)
	_main_vbox = VBoxContainer.new()
	_main_vbox.add_theme_constant_override("separation", 18)
	_main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_main_scroll.add_child(_main_vbox)

	# --- Title ---------------------------------------------------------------
	# Warm gold matches the win-message color in the game — keeps the menu
	# visually consistent with the rest of the project's palette.
	var title := Label.new()
	title.text = "DICE ROLL"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_vbox.add_child(title)

	# --- Subtitle ------------------------------------------------------------
	var subtitle := Label.new()
	subtitle.text = "A 3D dice-tossing game"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(1, 1, 1, 0.7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_vbox.add_child(subtitle)

	# --- Art placeholder -----------------------------------------------------
	# Where Daniel's custom art will go. Solid border (StyleBoxFlat in Godot 4
	# doesn't natively support dashed patterns — see _make_art_placeholder for
	# the workaround plan) + center label so it still reads as a "slot,"
	# not as a finished UI element.
	_main_vbox.add_child(_make_art_placeholder())

	# --- Buttons -------------------------------------------------------------
	# Primary (PLAY) is bigger + uses the same blue accent as the inventory
	# slot buttons in-world, so the menu feels like part of the same app.
	# OPTIONS (secondary) sits between, sub-leading to the options panel.
	# QUIT is smaller and muted so it doesn't compete.
	var play_btn := _make_button("PLAY", 220, 52, true)
	play_btn.pressed.connect(_on_play_pressed)
	_main_vbox.add_child(play_btn)

	var options_btn := _make_button("OPTIONS", 200, 48, false)
	options_btn.pressed.connect(_show_options)
	_main_vbox.add_child(options_btn)

	var quit_btn := _make_button("QUIT", 160, 42, false)
	quit_btn.pressed.connect(_on_quit_pressed)
	_main_vbox.add_child(quit_btn)

	# --- Footer note ---------------------------------------------------------
	# Subtle reminder that this is a placeholder. Alpha 0.4 keeps it out of
	# the way but visible — Daniel will see it on every playtest until he
	# replaces the menu.
	var footer := Label.new()
	footer.text = "placeholder menu — art and polish TBD"
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_vbox.add_child(footer)

	# --- Options panel content ---------------------------------------------
	# Built once, hidden until OPTIONS is clicked. Sized & centered the same
	# way as _main_vbox so the visual language matches when swapping panels.
	# Visibility is toggled via the scroll container (in _show_options /
	# _show_main_menu), not just the vbox — so the inactive scroll doesn't
	# intercept mouse events.
	_options_vbox = _build_options_panel()
	_options_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_options_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_scroll.add_child(_options_vbox)


func _make_art_placeholder() -> Control:
	var rect := Panel.new()
	rect.custom_minimum_size = ART_PLACEHOLDER_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)  # transparent — just the dashed border
	# Solid border — Godot 4's StyleBoxFlat doesn't expose a dashed-pattern
	# API (set_dash_pattern_all is not a real method on it; mistook the
	# ShapeStyleBox / editor preview quirks for a real feature, my bad).
	# The transparent bg + "[ custom art slot ]" label inside still reads
	# as a placeholder zone; bumping alpha to 0.45 compensates visually for
	# losing the dashed look. If a dashed border is wanted later, two paths:
	#   (a) override _draw() on a custom Control and stroke the rect manually,
	#   (b) swap to StyleBoxTexture with a tiny dashed-line PNG.
	style.border_color = Color(1, 1, 1, 0.45)
	style.set_border_width_all(2)
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


# --- Options panel ---------------------------------------------------------

# Builds the placeholder options sub-menu. Layout mirrors _build_menu —
# title, four section panels (Audio / Graphics / Controls / Gameplay),
# BACK button at the bottom. Controls are visually present (sliders,
# checkboxes, dropdowns) but their value_changed signals don't do anything
# yet — the whole panel is a "see what we'd put here" stub until real
# settings exist. A footer note flags this for anyone testing.
func _build_options_panel() -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER

	# Title — same warm gold as the main menu title for consistency.
	var title := Label.new()
	title.text = "OPTIONS"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Section panels.
	vbox.add_child(_build_audio_panel())
	vbox.add_child(_build_graphics_panel())
	vbox.add_child(_build_controls_panel())
	vbox.add_child(_build_gameplay_panel())

	# BACK button — primary styling (blue accent) so it's the prominent
	# action on this screen. It's the only navigation action the player
	# can take here, so making it muted would be misleading.
	var back := _make_button("BACK", 220, 52, true)
	back.pressed.connect(_show_main_menu)
	vbox.add_child(back)

	# Footer note — same placeholder-flagging pattern as the main menu.
	# Removes ambiguity about whether these sliders actually do anything.
	var footer := Label.new()
	footer.text = "placeholder — settings not yet wired"
	footer.add_theme_font_size_override("font_size", 12)
	footer.add_theme_color_override("font_color", Color(1, 1, 1, 0.4))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(footer)

	return vbox


# Toggle helpers — each panel lives in its own ScrollContainer; flipping
# BOTH the scroll and its vbox swaps the panel. Hiding the inactive scroll
# is the critical part: a scroll container that's "alive" but with no
# visible content still has mouse_filter = STOP and intercepts clicks
# before they reach the visible panel below it. Scroll position is reset
# on each swap so the user always lands at the top of the newly visible
# panel (otherwise the previous panel's offset would carry over visually).
func _show_main_menu() -> void:
	if _main_scroll:
		_main_scroll.visible = true
	if _main_vbox:
		_main_vbox.visible = true
	if _options_scroll:
		_options_scroll.visible = false
	if _options_vbox:
		_options_vbox.visible = false
	if _main_scroll:
		_main_scroll.scroll_vertical = 0


func _show_options() -> void:
	if _main_scroll:
		_main_scroll.visible = false
	if _main_vbox:
		_main_vbox.visible = false
	if _options_scroll:
		_options_scroll.visible = true
	if _options_vbox:
		_options_vbox.visible = true
	if _options_scroll:
		_options_scroll.scroll_vertical = 0


# --- Layout helpers --------------------------------------------------------

# Build a ScrollContainer that fills the viewport with vertical scroll only.
# Used to wrap both the main menu vbox and the options panel vbox so each
# can independently scroll if its content overflows the screen.
func _make_scroll_container() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Only vertical scroll — horizontal would feel wrong for menu content.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# AUTO shows the scrollbar only when needed; SHOWN_ALWAYS would also work.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)
	return scroll


# --- Option section panels (visual scaffolding only) -----------------------

func _build_audio_panel() -> PanelContainer:
	var panel := _make_section_panel("Audio")
	var vbox := panel.get_child(0) as VBoxContainer
	vbox.add_child(_make_slider_row("Master", 0.0, 1.0, 0.8))
	vbox.add_child(_make_slider_row("SFX", 0.0, 1.0, 0.8))
	vbox.add_child(_make_slider_row("Music", 0.0, 1.0, 0.8))
	vbox.add_child(_make_toggle_row("Mute All", false))
	return panel


func _build_graphics_panel() -> PanelContainer:
	var panel := _make_section_panel("Graphics")
	var vbox := panel.get_child(0) as VBoxContainer
	var resolutions: Array[String] = [
		"1280x720",
		"1366x768",
		"1600x900",
		"1920x1080",
		"2560x1440",
		"3840x2160",
	]
	vbox.add_child(_make_dropdown_row("Resolution", resolutions, 3))  # default 1920x1080
	vbox.add_child(_make_toggle_row("Fullscreen", false))
	vbox.add_child(_make_toggle_row("VSync", true))
	var quality: Array[String] = ["Low", "Medium", "High", "Ultra"]
	vbox.add_child(_make_dropdown_row("Quality", quality, 2))  # default High
	return panel


func _build_controls_panel() -> PanelContainer:
	var panel := _make_section_panel("Controls")
	var vbox := panel.get_child(0) as VBoxContainer
	vbox.add_child(_make_slider_row("Mouse Sensitivity", 0.1, 5.0, 1.0))
	vbox.add_child(_make_toggle_row("Invert Y", false))
	# Key-rebinding UI is non-trivial — placeholder label until it exists.
	var hint := Label.new()
	hint.text = "Key bindings — coming soon"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	vbox.add_child(hint)
	return panel


func _build_gameplay_panel() -> PanelContainer:
	var panel := _make_section_panel("Gameplay")
	var vbox := panel.get_child(0) as VBoxContainer
	var difficulties: Array[String] = ["Easy", "Normal", "Hard"]
	vbox.add_child(_make_dropdown_row("Difficulty", difficulties, 1))  # default Normal
	vbox.add_child(_make_toggle_row("Show FPS", false))
	return panel


# --- Option panel / row helpers --------------------------------------------

# Build a styled PanelContainer with a VBoxContainer child ready for rows.
# Returns the panel — get_child(0) is the vbox for adding rows.
func _make_section_panel(title_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SECTION_PANEL_WIDTH, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_corner_radius_all(PANEL_CORNER_RADIUS)
	style.set_content_margin_all(PANEL_PADDING)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title_label := Label.new()
	title_label.text = title_text
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	vbox.add_child(title_label)

	return panel


# Label + HSlider row. Label is fixed-width so sliders align across rows.
# value_changed on the slider isn't connected — placeholder until real
# settings persistence is wired.
func _make_slider_row(label_text: String, min_val: float, max_val: float, default_val: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.value = default_val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	return row


# CheckBox with a label, sized to match the slider-row labels.
func _make_toggle_row(label_text: String, default_val: bool) -> CheckBox:
	var box := CheckBox.new()
	box.text = label_text
	box.button_pressed = default_val
	box.add_theme_font_size_override("font_size", 14)
	box.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	return box


# Label + OptionButton row. Label is fixed-width so dropdowns align.
func _make_dropdown_row(label_text: String, options: Array[String], default_index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(140, 0)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	row.add_child(label)
	var dropdown := OptionButton.new()
	for opt in options:
		dropdown.add_item(opt)
	dropdown.selected = default_index
	dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(dropdown)
	return row
