extends RigidBody3D

# --- Drag-and-toss tuning (visible in the inspector) ---------------------------

# Y-plane the die floats along while you drag it. Camera looks down on it.
@export var drag_height: float = 5.0
# How strongly drag motion translates into toss impulse. Scales BOTH linear
# and angular response (since angular comes from off-center impulse, not random).
@export var toss_strength: float = 1.0

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

# Set to false at the start of each toss; flipped to true after roll_finished
# fires, so we emit exactly once per roll even though `sleeping` stays true.
var _emitted_for_current_roll: bool = false

signal roll_finished(value)

# --- Lifecycle ----------------------------------------------------------------

func _ready():
	start_pos = global_position


# Global input — catches release anywhere on screen while dragging.
func _input(event):
	if event.is_action_pressed("ui_accept"):
		_roll()
	elif _dragging and event is InputEventMouseButton:
		if not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_end_drag()
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_drag()


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

func _start_drag(screen_pos: Vector2, hit_world_pos: Vector3):
	# Snapshot where the die was sitting before we grabbed it — right-click
	# cancel restores this transform so the die goes back to its rest pose
	# (full rotation, not just position) without scoring.
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
	_dragging = false
	_toss(_drag_velocity)


# Right-click during a drag: put the die back exactly where it was (full
# transform, frozen), kill the drag state, and ensure no roll_finished
# fires. `freeze = true` keeps the die locked to the rest pose and the
# `not freeze and ... and sleeping` check in _process never matches, so
# the score stays untouched.
func _cancel_drag():
	if not _dragging:
		return
	_dragging = false
	_drag_velocity = Vector3.ZERO
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	# Keep `freeze = true` (it was true during drag) so the body stays locked.
	# Flag the roll as already accounted for so even if the body wakes up
	# briefly on its own, the score isn't re-counted.
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
func _toss(drag_velocity: Vector3):
	freeze = false
	# Wake the body so the new impulse actually takes effect. Without this,
	# `sleeping` carries over from the previous settle and the next-frame
	# settle check fires immediately, double-counting the previous score.
	sleeping = false
	_emitted_for_current_roll = false  # arm the signal for this new toss
	var impulse: Vector3 = drag_velocity * toss_strength
	apply_impulse(impulse, _grab_offset)


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
