extends RigidBody3D

# --- Drag-and-toss tuning (visible in the inspector) ---------------------------

# Y-plane the die floats along while you drag it. Camera looks down on it.
@export var drag_height: float = 5.0
# How strongly drag motion translates into toss impulse. Scales BOTH linear
# and angular response (since angular comes from off-center impulse, not random).
@export var toss_strength: float = 1.0
# Below this drag-end speed (cursor units/sec), treat the release as "drop in
# place" — apply a minimum impulse so the die still tumbles from the residual
# pressure of a hand releasing it, instead of dropping flat onto the same face
# it was picked up on.
@export var min_release_speed: float = 50.0
# Magnitude of the downward impulse used when the release is below
# `min_release_speed`. Combined with `grab_offset` via apply_impulse, this
# produces torque proportional to where you grabbed — a top-corner grab
# flips the die around a horizontal axis onto a new face.
@export var min_release_force: float = 5.0

# --- Inventory throw feel ----------------------------------------------------
# Inventory-spawned dice have _grab_offset = Vector3.ZERO (the cursor can't
# "grab off-axis" from a 2D slot button), so apply_impulse gives them zero
# torque and they just slide straight down. Instead, we set linear + angular
# velocity directly on release:
#   - inventory_lift: upward velocity bump (units/sec) so the die pops off
#     the drag plane and has air time to tumble.
#   - inventory_spin_scale: multiplier from drag_speed to angular velocity
#     (rad/sec). Spin axis is perpendicular to drag in the XZ plane — the
#     natural end-over-end tumble axis for a horizontal throw.
#   - inventory_spin_cap: angular velocity ceiling so accidental mouse-snap
#     throws don't spin the die into orbit.
@export_group("Inventory throw feel")
@export var inventory_lift: float = 4.0
@export var inventory_spin_scale: float = 0.3
@export var inventory_spin_cap: float = 18.0

# --- Face values --------------------------------------------------------------
# Each face of your dice model has a number. Match these to whichever face
# of the GLB points in that local direction. Defaults assume:
#   1 on top (+Y), 3 on +X, 5 on +Z (the three visible in your screenshot
#   meeting at the top corner), with opposites summing to 7.
# If `get_top_value()` ever reports the wrong face, swap values here.
@export_group("Face Values")
@export var face_pos_y: int = 1   # +Y direction (top of die)
@export var face_neg_y: int = 6   # -Y direction (bottom)
@export var face_pos_x: int = 3   # +X direction
@export var face_neg_x: int = 4   # -X direction
@export var face_pos_z: int = 5   # +Z direction
@export var face_neg_z: int = 2   # -Z direction

# --- State --------------------------------------------------------------------

var start_pos
var roll_strength = 30

var _dragging: bool = false
var _drag_velocity: Vector3 = Vector3.ZERO
var _prev_grab_pos: Vector3 = Vector3.ZERO
# 3D world-space offset from die center to the player's "grab point" —
# captured at the moment of grab. Used as the torque arm on release so the
# spin comes from real off-center impulse physics. Y component matters:
# a click above/below center is what gives pitch/roll (X/Z) spin, not just yaw.
var _grab_offset: Vector3 = Vector3.ZERO
# Where the die was sitting just before we picked it up. Restored exactly
# (position + rotation) when the player cancels the throw with right-click —
# so the die goes back to where it was, frozen, and no score is awarded.
var _pre_drag_transform: Transform3D = Transform3D.IDENTITY

# Inventory-drag tracking: which HUD slot spawned this die. -1 means the die
# was picked up from the arena via _input_event (the original path).
# The world marks this on spawn; on right-click cancel during an inventory
# drag, world refunds the slot and frees the die.
var _inventory_slot_index: int = -1

# Set to false at the start of each toss; flipped to true after roll_finished
# fires, so we emit exactly once per roll even though `sleeping` stays true.
var _emitted_for_current_roll: bool = false

signal roll_finished(value)
# Fired when an inventory-origin drag is canceled (right-click). The world
# handler frees this die and refunds the slot.
signal inventory_drag_canceled(slot_index: int)

# --- Lifecycle ----------------------------------------------------------------

func _ready():
	start_pos = global_position


# Global input — catches left-release anywhere on screen while dragging,
# and right-click for cancel (mid-drag only). Post-release right-click
# is intentionally a no-op: once you let go, the throw is committed and
# whatever the die lands on is the roll.
func _input(event):
	if event.is_action_pressed("ui_accept"):
		_roll()
	elif _dragging and event is InputEventMouseButton:
		if not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_end_drag()
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_on_right_click()


# Fires only when the click actually hits the die's collision shape — use for grab.
# `position` here is the world-space hit point on the collision shape; we need
# it (not just screen coords) so the grab offset can keep its Y component.
func _input_event(_camera, event, position, _normal, _shape_idx):
	if event is InputEventMouseButton \
			and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_start_drag(event.position, position)


func _process(delta):
	if _dragging:
		_update_drag(delta)
	elif not freeze and not _emitted_for_current_roll and sleeping:
		# Die has settled after a toss — emit the value exactly once.
		_emitted_for_current_roll = true
		var value := get_top_value()
		roll_finished.emit(value)
		print("[die] rolled ", value)

# --- Drag ---------------------------------------------------------------------

# Called by world.gd when the player click+drags on an inventory slot button.
# Spawns the die under the cursor at drag_height, follows the mouse like an
# arena drag, and releases via the normal _end_drag() path. Right-click cancel
# refunds the slot via inventory_drag_canceled (the die is freed by world).
#
# Inventory throws use _grab_offset = Vector3.ZERO because there's no way to
# "grab off-center" from a 2D slot — the cursor already spawned the die at
# its center. Pure linear impulse on release, no torque from offset. Tumbling
# comes from the impact with the floor when the die falls from drag_height.
func start_inventory_drag(screen_pos: Vector2, slot_index: int) -> void:
	_inventory_slot_index = slot_index
	_pre_drag_transform = global_transform
	_grab_offset = Vector3.ZERO

	var mouse_world: Vector3 = _screen_to_drag_plane(screen_pos)
	_dragging = true
	_drag_velocity = Vector3.ZERO
	_prev_grab_pos = mouse_world
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	# Arm the "don't auto-emit" flag. The die is frozen and never settles on
	# its own during a drag, so this is mostly consistency with the post-toss
	# invariant — but if a future refactor unfreezes mid-drag, this keeps the
	# score safe.
	_emitted_for_current_roll = true

	# Clamp spawn into arena bounds so the die can't appear outside the walls
	# when the cursor is over a HUD panel (which projects behind/over the walls).
	var clamped := _clamp_to_arena(mouse_world)
	global_position = Vector3(
		clamped.x - _grab_offset.x,
		drag_height,
		clamped.z - _grab_offset.z
	)


func _start_drag(screen_pos: Vector2, hit_world_pos: Vector3):
	_inventory_slot_index = -1  # arena origin, not inventory-spawned
	_pre_drag_transform = global_transform
	# Full 3D offset from die center to the actual hit point on the collision
	# shape. Y is preserved — that's what produces pitch/roll torque later.
	_grab_offset = hit_world_pos - global_position

	var mouse_world: Vector3 = _screen_to_drag_plane(screen_pos)
	_dragging = true
	_drag_velocity = Vector3.ZERO
	_prev_grab_pos = mouse_world
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	# Snap die up to drag plane, trailing the cursor by the XZ component
	# of the grab offset (Y is overridden so the die floats at drag_height).
	global_position = Vector3(
		mouse_world.x - _grab_offset.x,
		drag_height,
		mouse_world.z - _grab_offset.z
	)


func _end_drag():
	if not _dragging:
		return
	var was_inventory := _inventory_slot_index >= 0
	_dragging = false
	_inventory_slot_index = -1  # drag is over; right-click is no-op from here on
	var impulse: Vector3
	if _drag_velocity.length() >= min_release_speed:
		impulse = _drag_velocity * toss_strength
	else:
		impulse = Vector3.DOWN * min_release_force
	if was_inventory:
		# Inventory throws use a dedicated path that synthesizes lift + tumble
		# directly. See _toss_inventory for why a regular apply_impulse doesn't
		# work for them (and why both feel "physical" without any randomness).
		_toss_inventory(_drag_velocity)
	else:
		_toss(impulse)


# Right-click handler. ONLY meaningful during a drag — once the left mouse
# has released (_end_drag ran), the throw is committed: whatever the die
# lands on is the roll. Refusing post-release refund intentionally makes
# that commitment feel real (no "I tossed too early" undo).
# Mid-drag: inventory dice get freed + slot refunds; arena dice snap
# back to pre-drag pose. See _cancel_drag for the actual cancellation.
func _on_right_click() -> void:
	if _dragging:
		_cancel_drag()


# Right-click during a drag: either restore the die (arena drag) or refund
# the inventory slot + free the die (inventory drag). Both paths keep the
# score untouched. Called only from _on_right_click when _dragging is true.
func _cancel_drag():
	if not _dragging:
		return
	var was_inventory: bool = _inventory_slot_index >= 0
	var slot_index: int = _inventory_slot_index
	_inventory_slot_index = -1
	_dragging = false
	_drag_velocity = Vector3.ZERO
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	if was_inventory:
		# Inventory cancel: die disappears, slot refunds. The world handler
		# (connected to inventory_drag_canceled) frees this node. We stay
		# frozen and emission-suppressed so we can't spuriously fire
		# roll_finished before being freed.
		freeze = true
		_emitted_for_current_roll = true
		inventory_drag_canceled.emit(slot_index)
		return

	# Arena cancel: restore the die to its exact pre-drag pose, locked.
	freeze = true
	_emitted_for_current_roll = true
	global_transform = _pre_drag_transform


func _update_drag(delta: float):
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var grab_world: Vector3 = _screen_to_drag_plane(mouse_pos)
	# Die center trails the cursor by the XZ component of the grab offset,
	# so the grab point (not the center) follows the mouse — like a real
	# finger on the die. Y is forced to drag_height.
	var die_pos: Vector3 = Vector3(
		grab_world.x - _grab_offset.x,
		drag_height,
		grab_world.z - _grab_offset.z
	)
	if delta > 0:
		_drag_velocity = (grab_world - _prev_grab_pos) / delta
	_prev_grab_pos = grab_world
	global_position = die_pos


# Project a screen-space mouse position onto the horizontal Y = drag_height plane.
func _screen_to_drag_plane(screen_pos: Vector2) -> Vector3:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if not camera:
		return global_position
	var origin: Vector3 = camera.project_ray_origin(screen_pos)
	var dir: Vector3 = camera.project_ray_normal(screen_pos)
	if abs(dir.y) < 0.001:
		return global_position
	var t: float = (drag_height - origin.y) / dir.y
	return origin + dir * t


# Clamp an XZ point into the playable arena so an inventory drag can't dump
# the die outside the walls (e.g., when the cursor is over a HUD panel and
# the ray misses the play area). Bounds are loose — the 2u die can't quite
# touch the walls even at these clamps.
func _clamp_to_arena(p: Vector3) -> Vector3:
	return Vector3(
		clamp(p.x, -6.5, 7.5),
		p.y,
		clamp(p.z, -9.5, 10.0)
	)

# --- Score detection ----------------------------------------------------------

# Returns the value of the face currently pointing world-up.
# Uses face normals — one dot product per face, no raycasts/physics queries.
# `global_transform.basis` rotates each face's LOCAL normal into world space.
func get_top_value() -> int:
	var world_up := Vector3.UP
	var best_dot := -2.0
	var best_value := 0
	var faces: Array = [
		[face_pos_y, Vector3.UP],
		[face_neg_y, Vector3.DOWN],
		[face_pos_x, Vector3.RIGHT],
		[face_neg_x, Vector3.LEFT],
		[face_pos_z, Vector3.FORWARD],
		[face_neg_z, Vector3.BACK],
	]
	for entry in faces:
		var value: int = entry[0]
		var local_normal: Vector3 = entry[1]
		var world_normal: Vector3 = global_transform.basis * local_normal
		var dot: float = world_normal.dot(world_up)
		if dot > best_dot:
			best_dot = dot
			best_value = value
	return best_value

# --- Toss / Roll --------------------------------------------------------------

# Apply impulse at the grab point (full 3D offset from die center) — pure physics.
# Godot computes both linear AND angular momentum from the offset, so the
# spin emerges naturally from r × F. Click above the center → pitch/roll
# torque. Click on a side → yaw. Click near center → mostly linear, little spin.
# No randomness anywhere.
func _toss(impulse: Vector3):
	freeze = false
	# Wake the body so the new impulse actually takes effect. Without this,
	# `sleeping` carries over from the previous settle and the next-frame
	# settle check fires immediately, double-counting the previous score.
	sleeping = false
	_emitted_for_current_roll = false  # arm the signal for this new toss
	apply_impulse(impulse, _grab_offset)


# Inventory throw path. Replaces _toss for inventory-origin drags because
# _grab_offset = Vector3.ZERO would give us a pure-linear apply_impulse (zero
# torque) and the die would slide instead of tumble. Instead, set linear +
# angular velocity directly:
#   - linear: drag_velocity * toss_strength + upward lift. The lift ensures
#     the die pops off the drag plane and has air time; without it the die
#     never gets above drag_height.
#   - angular: perpendicular to drag in XZ, scaled by drag speed and capped.
#     Spin perpendicular to throw direction = end-over-end tumble, which is
#     what makes a tossed die feel like a tossed die.
# Drop-in-place (tiny drag): lift is still added; tumble defaults to a forward
# flip around +X so the die pitches toward the camera and gives some visual
# motion. Both paths are fully deterministic — no randomness anywhere.
func _toss_inventory(drag_velocity: Vector3) -> void:
	freeze = false
	sleeping = false
	_emitted_for_current_roll = false

	var drag_xz := Vector3(drag_velocity.x, 0, drag_velocity.z)
	var drag_speed := drag_xz.length()

	# Linear motion: scaled drag + lift.
	linear_velocity = drag_velocity * toss_strength + Vector3.UP * inventory_lift

	# Tumble axis + spin magnitude. If there's a meaningful drag direction,
	# spin perpendicular to it; otherwise fall back to a default forward flip.
	var tumble_axis: Vector3
	var spin: float
	if drag_speed > 0.01:
		tumble_axis = Vector3.UP.cross(drag_xz).normalized()
		spin = clamp(drag_speed * inventory_spin_scale, 0.0, inventory_spin_cap)
	else:
		# Drop-in-place (no drag). With no drag there's no user-input source
		# of variation, so inject subtle randomness across axis / spin / lift
		# so consecutive taps don't deterministically land on the same face
		# (the prior fixed-Vector3.RIGHT + fixed-spin + fixed-lift combo
		# always landed on 5 — same spin → same rotations in air → same
		# landing face). Tight ranges so the throw still feels physical.
		var axis_perturbation := Vector3(
			randf_range(-0.3, 0.3),
			0.0,
			randf_range(-0.3, 0.3)
		)
		tumble_axis = (Vector3.RIGHT + axis_perturbation).normalized()
		spin = randf_range(inventory_spin_cap * 0.4, inventory_spin_cap * 0.7)
		# Small lift variance so flight time varies slightly — different
		# rotations in air → different landing faces.
		linear_velocity.y += randf_range(-inventory_lift * 0.15, inventory_lift * 0.15)
	angular_velocity = tumble_axis * spin


func _roll():
	# Keyboard "press Space to roll in place" — kept as a quick test alternate.
	_emitted_for_current_roll = false
	sleeping = false
	freeze = false
	transform.origin = start_pos
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO

	# random die rotation
	transform.basis = Basis(Vector3.RIGHT , randf_range(0,2 * PI)) * transform.basis
	transform.basis = Basis(Vector3.UP , randf_range(0,2 * PI)) * transform.basis
	transform.basis = Basis(Vector3.FORWARD , randf_range(0,2 * PI)) * transform.basis

	var throw_vector = Vector3(randf_range(-1,1), 0, randf_range(-1,1)).normalized()
	angular_velocity = throw_vector * roll_strength / 2
	apply_central_impulse(throw_vector * roll_strength)
