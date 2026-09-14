extends Node3D

const DIE_SCENE = preload("res://die.tscn")
const TARGET_SCORE := 20
const WIN_FADE_IN := 0.4
const WIN_FADE_OUT := 4.0
const INVENTORY_SIZE := 6

# --- Inventory configuration --------------------------------------------------

# Positions in the arena where each inventory-spawned die first appears before
# the cursor takes over. 2-unit dice on a 4-unit XZ grid, parked near the back
# of the arena so all six are visible from the camera and the player has room
# to throw them forward. Slot 0 = leftmost HUD button = -5,0; slot 5 = +5,0.
@export var inventory_drop_positions: Array[Vector3] = [
	Vector3(-5.0, 5.0, -5.0),
	Vector3(-3.0, 5.0, -5.0),
	Vector3(-1.0, 5.0, -5.0),
	Vector3(+1.0, 5.0, -5.0),
	Vector3(+3.0, 5.0, -5.0),
	Vector3(+5.0, 5.0, -5.0),
]

# slot_index → true if the slot still has a die to give. Marked false on
# use (in _spawn_die_for_inventory) and restored to true when an inventory
# drag is canceled with right-click (slot refund).
var _inventory_available: Array[bool] = []
# HUD button refs, in slot-index order. Set in _build_hud.
var _inventory_buttons: Array[Button] = []

# --- Arena state -------------------------------------------------------------

# All dice currently in the arena. Score derives from per-die roll_finished
# signals — this list is mainly so we can cancel-drag cleanup removes the
# right node. Dice are not removed when they settle; they stay in the arena
# and can be picked up + re-tossed indefinitely.
var _arena_dice: Array[RigidBody3D] = []

var _total_score: int = 0
var _last_roll: int = 0
var _won: bool = false
var _total_label: Label
var _last_label: Label
var _target_label: Label
var _win_label: Label


func _ready() -> void:
	for i in INVENTORY_SIZE:
		_inventory_available.append(true)
	_build_hud()
	# Note: no auto-spawn — arena starts empty. Dice enter the arena only
	# through inventory slot clicks.


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

	# --- Controls panel (top-center, just above inventory) ------------------
	# Moved here from bottom-left now that the inventory strip occupies the
	# bottom of the screen. Centering keeps it readable without crowding a side.
	var controls_panel := _create_panel(Control.PRESET_TOP_LEFT, Vector2(16, 110))
	hud_layer.add_child(controls_panel)

	var controls_vbox := VBoxContainer.new()
	controls_vbox.add_theme_constant_override("separation", 2)
	controls_panel.add_child(controls_vbox)
	for line in [
		"Click + drag an inventory slot to throw",
		"Left click pick up a die in the arena",
		"Right click cancel throw (refunds slot)",
		"R to refill inventory",
	]:
		var lbl := Label.new()
		lbl.text = line
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
		controls_vbox.add_child(lbl)

	# --- Inventory strip (bottom-center) -------------------------------------
	# Six slot buttons that spawn arena dice. Filled slots show their slot
	# number on a colored panel; empty slots (after use) switch to a faded
	# outline style via `disabled`. Click + drag on a slot starts an inventory
	# drag (see _on_inventory_slot_pressed → die.start_inventory_drag).
	var inventory_panel := PanelContainer.new()
	inventory_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	inventory_panel.anchor_left = 0.5
	inventory_panel.anchor_right = 0.5
	# Sized for 6 × 80px slots + 5 × 8px gaps + 2 × 16px content margin = 552 wide.
	# Anchored on the horizontal center so the strip stays centered at any window size.
	inventory_panel.offset_left = -276.0
	inventory_panel.offset_right = 276.0
	inventory_panel.offset_top = -112.0
	inventory_panel.offset_bottom = -16.0
	hud_layer.add_child(inventory_panel)

	var inventory_container := HBoxContainer.new()
	inventory_container.add_theme_constant_override("separation", 8)
	inventory_panel.add_child(inventory_container)

	var inv_style := StyleBoxFlat.new()
	inv_style.bg_color = Color(0, 0, 0, 0.55)
	inv_style.set_corner_radius_all(10)
	inv_style.set_content_margin_all(16)
	inventory_panel.add_theme_stylebox_override("panel", inv_style)

	for i in INVENTORY_SIZE:
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(80, 80)
		slot.text = str(i + 1)
		slot.add_theme_font_size_override("font_size", 36)
		slot.add_theme_color_override("font_color", Color.WHITE)
		slot.add_theme_color_override("font_hover_color", Color.WHITE)
		slot.add_theme_color_override("font_pressed_color", Color.WHITE)
		# Filled slot style — solid colored panel.
		var filled := StyleBoxFlat.new()
		filled.bg_color = Color(0.2, 0.45, 0.7, 0.85)
		filled.set_corner_radius_all(8)
		filled.set_content_margin_all(8)
		slot.add_theme_stylebox_override("normal", filled)
		var hover := filled.duplicate()
		hover.bg_color = Color(0.35, 0.6, 0.85, 0.85)
		slot.add_theme_stylebox_override("hover", hover)
		var pressed := hover.duplicate()
		pressed.bg_color = Color(0.55, 0.75, 1.0, 0.85)
		slot.add_theme_stylebox_override("pressed", pressed)
		# Empty slot style — outline only, transparent fill, hidden number.
		var empty := StyleBoxFlat.new()
		empty.bg_color = Color(0, 0, 0, 0)
		empty.border_color = Color(1, 1, 1, 0.3)
		empty.set_border_width_all(2)
		empty.set_corner_radius_all(8)
		empty.set_content_margin_all(8)
		slot.add_theme_stylebox_override("disabled", empty)
		# Hide the disabled state text rather than letting it draw at default alpha.
		slot.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0))
		inventory_container.add_child(slot)
		_inventory_buttons.append(slot)
		# button_down fires on press (without waiting for release inside the button),
		# which is exactly the hook we want for inventory-drag start. The release
		# is captured globally by die.gd._input on the next mouse-up event.
		slot.button_down.connect(_on_inventory_slot_pressed.bind(i))

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
	# PRESET_BOTTOM_LEFT is unused now (inventory strip took that corner),
	# but kept here as a defensive default so a stray preset doesn't 0-width.

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.55)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)

	return panel


# --- Input --------------------------------------------------------------------

# Press R to refill the inventory. Arena dice + score are untouched.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey \
			and event.pressed \
			and not event.echo \
			and event.keycode == KEY_R:
		_respawn_inventory()
		get_viewport().set_input_as_handled()


# --- Inventory slot interactions ---------------------------------------------

# Called on button_down for any inventory slot. Spawns a die in the arena and
# hands it off to the inventory-drag start path. The slot is marked empty
# immediately; if the player cancels the drag with right-click, the slot is
# refunded by _on_inventory_drag_canceled.
func _on_inventory_slot_pressed(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= INVENTORY_SIZE:
		return
	if not _inventory_available[slot_index]:
		return  # disabled, but defensive — should be unreachable
	_spawn_die_for_inventory(slot_index)


# Spawn a die for the given inventory slot, wire its signals, and start the
# inventory drag. Returns the die in case future code wants to do anything
# else with it before handing control to the cursor.
func _spawn_die_for_inventory(slot_index: int) -> RigidBody3D:
	var die: RigidBody3D = DIE_SCENE.instantiate()
	add_child(die)
	# Position the die at its slot's drop point initially; start_inventory_drag
	# will snap it to the cursor in the same frame.
	die.global_position = inventory_drop_positions[slot_index]
	_arena_dice.append(die)
	die.roll_finished.connect(_on_die_rolled)
	# Connect the cancel callback. The signal `inventory_drag_canceled(slot_index)`
	# emits the slot index as its one argument, and we bind only the die ref —
	# so the actual call shape is (slot_index_emitted, die_bound) = two args
	# to the handler's two parameters. Earlier code bound both die AND
	# slot_index (3 args to a 2-param handler), which Godot 4 mostly drops
	# silently but is the wrong shape regardless.
	die.inventory_drag_canceled.connect(
		_on_inventory_drag_canceled.bind(die)
	)
	# Slot is now considered "used" — refund happens via the cancel signal.
	_inventory_available[slot_index] = false
	_update_slot_ui(slot_index)
	# Start the cursor-following drag with the current mouse position. We
	# pass the slot index so the die knows where it came from (used for the
	# cancel signal payload).
	die.start_inventory_drag(get_viewport().get_mouse_position(), slot_index)
	return die


# Right-click cancel during an inventory drag: die disappears, slot refunds.
# Connected with bind(die, slot_index) on the cancel signal so we know which
# node to free and which slot to mark available again.
func _on_inventory_drag_canceled(slot_index: int, die: RigidBody3D) -> void:
	if is_instance_valid(die):
		_arena_dice.erase(die)
		die.queue_free()
	_inventory_available[slot_index] = true
	_update_slot_ui(slot_index)


# Update a single slot's appearance to match its availability. Filled slots
# are interactive and show their number; empty slots are disabled and outline-
# only with hidden text.
func _update_slot_ui(slot_index: int) -> void:
	var slot := _inventory_buttons[slot_index]
	if _inventory_available[slot_index]:
		slot.disabled = false
		slot.text = str(slot_index + 1)
	else:
		slot.disabled = true
		slot.text = ""


# R-key: refill the inventory. Arena dice and score keep going — this is a
# pure resource reset, not a round reset.
func _respawn_inventory() -> void:
	for i in INVENTORY_SIZE:
		_inventory_available[i] = true
		_update_slot_ui(i)


# --- Score / win --------------------------------------------------------------

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
