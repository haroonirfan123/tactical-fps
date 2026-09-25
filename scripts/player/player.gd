class_name Player
extends CharacterBody3D
## The first-person player. One scene, instantiated once per player - a local
## player in the playtest now, up to six copies in a 3v3 match later.
##
## [b]Where the seams are, on purpose.[/b]
##
## - [b]All movement is inside this node.[/b] Nothing asks GameManager to move
##   anyone, and there is no "the player" singleton. Every other player in the
##   match will be another instance of this same scene.
## - [b]Input is optional, not assumed.[/b] [member input_enabled] is the single
##   switch between "this player listens to the keyboard" and "this player's
##   transform is set by the network". A remote player is the same scene with
##   input off, so Chapter 4 adds replication without a second controller.
## - [b]Identity is data, not node state.[/b] [member state] is a Chapter 1
##   [PlayerState], so health and team already have somewhere to live without
##   this script growing fields for them.
##
## [b]Node layout and why:[/b]
## [codeblock]
## Player (CharacterBody3D)   - yaw only, never pitched
##  |- Collision              - capsule, resized for crouch
##  |- Head (Node3D)          - pitch pivot, sits at eye height
##      |- Camera3D           - the only thing that should ever be "current"
## [/codeblock]
## Yaw lives on the body and pitch on the head so that movement is always
## computed from a level heading. If the body were pitched, walking downhill
## would steer you into the ground.

# --- Body dimensions ---------------------------------------------------
# Metres. The capsule's origin is at the player's feet, so a shape of height h
# sits with its centre at y = h / 2.

## Collision height while standing. Also the default value for the scene.
@export var stand_height: float = 1.8

## Collision height while crouched. Must stay above 2x [member body_radius] or
## Godot will not accept it as a capsule.
@export var crouch_height: float = 1.1

@export var body_radius: float = 0.35

# --- Speeds ------------------------------------------------------------
# Deliberately not copied from any existing game. These are tuned to feel
# deliberate rather than floaty: enough acceleration to stop instantly on a
# dime, not so much that the player skates.

@export_group("Speeds")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var crouch_speed: float = 2.6

@export_group("Acceleration")
## How fast horizontal speed is gained on the ground, in m/s^2.
@export var ground_acceleration: float = 55.0

## How fast horizontal speed is lost on the ground with no input. Higher than
## [member ground_acceleration] so releasing a key stops the player crisply
## instead of sliding.
@export var ground_deceleration: float = 70.0

## Air control, as a fraction of [member ground_acceleration]. Low on purpose:
## a tactical shooter should reward committing to a jump rather than let the
## player steer freely in mid-air.
@export_range(0.0, 1.0) var air_control: float = 0.22

## Horizontal speed lost per second while airborne with no input. Also low, so
## a jump keeps its momentum.
@export var air_deceleration: float = 2.0

@export_group("Vertical")
## Downward acceleration. Higher than Earth's 9.8 so jumps feel snappy and
## falls resolve quickly.
@export var gravity: float = 18.0

## Upward speed applied by a jump. With the default gravity this clears about
## 0.84 m, which is enough to get onto a waist-high crate and not much else.
@export var jump_velocity: float = 5.5

## Downward speed cap, so a long fall does not turn into tunnelling.
@export var terminal_fall_speed: float = 40.0

## Grace period after walking off a ledge during which a jump still works.
## Without it, walking down a slope can drop the floor for a frame and eat the
## jump. Set to 0 to disable.
@export var coyote_time: float = 0.12

## How far the body may snap downwards to stay in contact with a slope is
## [member CharacterBody3D.floor_snap_length], set on the node in
## [code]player.tscn[/code]. It is deliberately not declared here: a script
## variable of that name shadows the engine's own property, so the number
## would appear in the Inspector looking configurable while the real value
## stayed at the engine default and the controller quietly failed to follow
## slopes down.

## Tallest ledge the player walks up without jumping, in metres. Uses a real
## overlap test rather than a raycast, so it cannot lift the player into a
## ceiling.
@export var step_height: float = 0.4

## Clearance required around the lifted position before a step is taken.
## Without it the lifted capsule can pass a ledge corner by a millimetre and
## then snag on it, which reads as the player stuttering against the stair.
const STEP_CLEARANCE := 0.02

# --- Camera ------------------------------------------------------------

@export_group("Camera")
## Multiplier turning the 0..1 setting in GameConfig into radians per pixel of
## mouse movement. A raw sensitivity number is meaningless without it, so the
## two are kept apart: the player owns this, the player-facing option does not.
@export var sensitivity_scale: float = 0.003

## How far up or down the head can look, in degrees. Just under 90 so the view
## can reach straight up and down without ever passing through the poles and
## flipping, which is the classic way an FPS camera breaks.
@export var pitch_limit_degrees: float = 89.0

## Eye height above the feet while standing, and while crouched. The camera
## interpolates between them rather than snapping, so crouching does not jolt.
@export var stand_eye_height: float = 1.62
@export var crouch_eye_height: float = 0.95

## How quickly the body and camera move between the two stances, in units per
## second. Shared by the collision shape and the camera so they can never
## disagree about how far through the transition the player is.
@export var stance_change_speed: float = 9.0

## Whether this player reads the keyboard. See the class docs: this is the
## switch Chapter 4 flips for remote players.
@export var input_enabled: bool = true

## Whether gameplay starts with the mouse captured.
@export var capture_mouse_on_ready: bool = true

## Coarse states the controller can be in. Enough for the HUD, the debug
## overlay and later combat logic to reason about, without a state machine
## that Chapter 3 would have to unpick.
enum MovementState {
	NORMAL,
	SPRINTING,
	CROUCHING,
	AIRBORNE,
	DEAD,
}

## Identity, health and team. Owned by this node rather than being global,
## because there is one per player. Chapter 3 reads health from here.
var state: PlayerState = PlayerState.new()

@onready var _collision: CollisionShape3D = $Collision
@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D

## Optional translucent capsule used only to make the collider visible while
## developing. Hidden by default, and parented to the collision shape so it
## can never drift away from the thing it is showing.
@onready var _body_mesh: MeshInstance3D = $Collision/BodyMesh

## 0.0 = fully crouched, 1.0 = fully standing. The single source of truth for
## "how crouched am I", read by the camera, the collider and the state getter.
var _stance: float = 1.0

## Seconds left of the coyote window.
var _coyote_left: float = 0.0

var _sprint_held: bool = false
var _crouch_held: bool = false

## Horizontal speed the player is *trying* to travel at, kept separately from
## [member CharacterBody3D.velocity] and never written by the physics engine.
##
## This split is not cosmetic. [method CharacterBody3D.move_and_slide] overwrites
## [code]velocity[/code] with the velocity the body actually ended up with, which
## is zero along any axis it collided on. Seeding acceleration from that means a
## player pressed against a step or a wall starts every frame from standstill,
## so they can never build enough speed to climb back out - and, worse, the
## step-up test gets handed a near-zero distance and decides nothing is in the
## way. Keeping the player's intent here means the two stay independent: intent
## is what the player asked for, velocity is what the world permitted.
var _move_velocity: Vector3 = Vector3.ZERO

## Set when a jump is refused because the player is not grounded, so the
## refusal can be reported rather than silently ignored.
var _last_jump_was_refused: bool = false


func _ready() -> void:
	add_to_group(&"players")

	_apply_stance()

	# Mouse look belongs to whichever camera this player owns, so a second
	# player in the match does not fight the first one for the pointer.
	_camera.current = true
	_camera.fov = GameConfig.field_of_view

	if capture_mouse_on_ready and input_enabled:
		capture_mouse(true)


# --- Public API --------------------------------------------------------
# Chapter 3+ and the network layer talk to the player through these, not by
# reaching into its internals.

## Current coarse state, derived rather than stored. Deriving it means it can
## never disagree with what the body is actually doing.
func get_movement_state() -> MovementState:
	if not state.is_alive:
		return MovementState.DEAD
	if not is_on_floor():
		return MovementState.AIRBORNE
	if _stance < 0.5:
		return MovementState.CROUCHING
	if _sprint_held and _is_moving():
		return MovementState.SPRINTING
	return MovementState.NORMAL


## Human-readable name for [method get_movement_state], for the debug overlay.
static func state_name(movement_state: MovementState) -> String:
	return MovementState.keys()[movement_state]


## Current collision height, interpolated between crouch and stand.
func get_current_height() -> float:
	return lerpf(crouch_height, stand_height, _stance)


## Eye height, for anything that needs to know where this player is looking
## from - a weapon muzzle in Chapter 3, a spawn point in Chapter 4.
func get_eye_position() -> Vector3:
	return _head.global_position


## Forward direction including pitch, which is where a shot should go.
func get_look_direction() -> Vector3:
	return -_camera.global_transform.basis.z


func is_sprinting() -> bool:
	return get_movement_state() == MovementState.SPRINTING


func is_crouching() -> bool:
	return get_movement_state() == MovementState.CROUCHING


## Turns keyboard and mouse control on or off. Chapter 4 calls this with
## false for every player it is not authoritative for.
func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	if not enabled:
		capture_mouse(false)


## Shows or hides the mouse. While visible the player stops looking around, so
## this doubles as the pause-for-development affordance the brief asks for.
func capture_mouse(captured: bool) -> void:
	if not input_enabled:
		captured = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func is_mouse_captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Drops the player at a point, clearing momentum. Chapter 4's spawn path
## calls this rather than setting position directly, so a respawn never
## inherits the velocity of the death.
func teleport_to(point: Vector3, facing_yaw: float = 0.0) -> void:
	velocity = Vector3.ZERO
	_move_velocity = Vector3.ZERO
	rotation.y = facing_yaw
	_head.rotation.x = 0.0
	global_position = point
	# Cleared deliberately. The floor flag still reads true for one frame after
	# the move, and _apply_vertical_motion would spend that frame refilling the
	# coyote window - which would hand a player dropped into mid-air a free jump.
	_coyote_left = 0.0
	move_and_slide()


# --- Input -------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return

	if event.is_action_pressed(&"toggle_mouse_capture"):
		capture_mouse(not is_mouse_captured())
		get_viewport().set_input_as_handled()
		return

	# Looking around only makes sense with the mouse captured. Checking here
	# rather than trusting the mouse mode means an alt-tab back into the
	# window does not immediately start spinning the camera.
	if event is InputEventMouseMotion and is_mouse_captured():
		_look(event as InputEventMouseMotion)


func _look(motion: InputEventMouseMotion) -> void:
	var sensitivity: float = GameConfig.mouse_sensitivity * sensitivity_scale
	# An unconfigured sensitivity must not make the camera unusable.
	if sensitivity <= 0.0:
		sensitivity = sensitivity_scale

	var delta := motion.relative * sensitivity

	# Yaw on the body so movement follows where the player is facing.
	rotate_y(-delta.x)

	# Pitch on the head, clamped every frame. Clamping the absolute angle
	# rather than the increment is what makes it impossible to flip: past the
	# limit the value stops, it does not wrap.
	#
	# The invert setting flips this frame's delta, never the accumulated angle.
	# Negating the total instead would send a view already tilted 30 degrees to
	# -30 on the first inverted mouse movement, rather than mirroring it.
	var pitch_delta := -delta.y
	if GameConfig.invert_mouse_y:
		pitch_delta = -pitch_delta

	var limit := deg_to_rad(pitch_limit_degrees)
	_head.rotation.x = clampf(_head.rotation.x + pitch_delta, -limit, limit)


# --- Movement ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	_read_input()

	_apply_horizontal_motion(delta)
	_apply_vertical_motion(delta)
	_update_stance(delta)

	# A ledge is only stepped over while actually trying to move into it.
	# Stepping while stationary would lift the player onto whatever they are
	# standing next to.
	#
	# Fed from _move_velocity, not velocity: a player walking into a step has
	# velocity zeroed along that axis by the collision that has just happened,
	# and a zero-length sweep reports the ledge as absent.
	#
	# The vertical cancel matters as much as the horizontal input. The step is
	# tested against horizontal motion alone, so the frame has to resolve as
	# horizontal motion alone too; leaving the usual downward push in place
	# sinks the freshly lifted body straight back into the ledge and the player
	# stalls against the step forever.
	if is_on_floor() and _try_step_up(Vector3(_move_velocity.x, 0.0, _move_velocity.z) * delta):
		velocity.y = 0.0

	move_and_slide()

	_track_floor(delta)


func _read_input() -> void:
	if not input_enabled:
		_sprint_held = false
		_crouch_held = false
		return
	_sprint_held = Input.is_action_pressed(&"sprint")
	_crouch_held = Input.is_action_pressed(&"crouch")


## Current movement input in world space, already rotated into the player's
## heading. [member _head] holds all the pitch, so the body basis is yaw-only
## and this cannot tilt the player off vertical.
func _wish_direction() -> Vector3:
	if not input_enabled:
		return Vector3.ZERO
	var input := Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_backward")
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var direction := transform.basis * Vector3(input.x, 0.0, input.y)
	direction.y = 0.0
	return direction.normalized()


func _is_moving() -> bool:
	return _wish_direction() != Vector3.ZERO


func _target_speed() -> float:
	# Crouch wins over sprint. A player holding both is crouched, because the
	# slower speed is the one that must not be bypassed.
	if _stance < 0.5:
		return crouch_speed
	if _sprint_held:
		return sprint_speed
	return walk_speed


## Steers horizontal velocity toward the target speed. One place decides how
## fast the player speeds up and slows down, so acceleration and deceleration
## can never disagree.
func _apply_horizontal_motion(delta: float) -> void:
	var direction := _wish_direction()
	var target := direction * _target_speed()

	var rate: float
	if is_on_floor():
		rate = ground_acceleration if direction != Vector3.ZERO else ground_deceleration
	else:
		rate = ground_acceleration * air_control if direction != Vector3.ZERO else air_deceleration

	# Accelerated from [member _move_velocity], not from the engine's reported
	# velocity, so brushing a wall does not erase the player's momentum.
	_move_velocity = _move_velocity.move_toward(target, rate * delta)
	velocity.x = _move_velocity.x
	velocity.z = _move_velocity.z


func _apply_vertical_motion(delta: float) -> void:
	if is_on_floor():
		_coyote_left = coyote_time
		# A small constant downward push rather than exactly zero, so the
		# controller keeps testing for floor on slopes instead of drifting off
		# them. This is what floor_snap_length then holds the player to.
		velocity.y = -2.0
	else:
		velocity.y = maxf(velocity.y - gravity * delta, -terminal_fall_speed)

	# Applies the jump itself, or does nothing. Refusals are recorded on
	# [member _last_jump_was_refused] rather than returned, because nothing
	# branches on them yet.
	_try_jump()


func _try_jump() -> void:
	_last_jump_was_refused = false
	if not input_enabled or not Input.is_action_just_pressed(&"jump"):
		return
	# Grounded, or still inside the coyote window. Never both, so there is no
	# way to get a second jump out of one press.
	if not is_on_floor() and _coyote_left <= 0.0:
		_last_jump_was_refused = true
		return

	velocity.y = jump_velocity
	_coyote_left = 0.0


func _track_floor(delta: float) -> void:
	if is_on_floor():
		_coyote_left = coyote_time
	else:
		_coyote_left = maxf(_coyote_left - delta, 0.0)


## Lifts the body over a ledge no taller than [member step_height].
##
## [param horizontal] is the distance this frame's movement is about to cover.
## Both tests below sweep the body that distance rather than testing a point,
## and that detail is the whole reason this works:
##
## - Asking "is anything in the way?" with a [constant] Vector3.ZERO
##   [method] sweep does not work. A zero-length sweep is degenerate, so it
##   reports clear no matter what is overhead, and the body gets lifted on open
##   ground. On a low ceiling that lift walks the player straight into the slab
##   and they stall short of it.
## - The lift is only considered when the movement is genuinely blocked, so
##   walking on the flat and following a shallow slope - both of which
##   [method move_and_slide] already handles - are left completely alone.
## - The raised test uses the same horizontal sweep, so it answers "could I
##   both be up there and still make this move?". A wall taller than
##   [member step_height] fails it and is left alone, which is what stops a
##   player climbing a wall they should have to jump.
## Returns whether a step was actually taken.
func _try_step_up(horizontal: Vector3) -> bool:
	if horizontal.length_squared() <= 0.0:
		return false

	# Free to move at the current height: there is nothing to step over. On open
	# ground and on shallow slopes this is always the answer, so the controller
	# is left entirely to move_and_slide.
	if not test_move(global_transform, horizontal):
		return false

	# Blocked, so there is a ledge. The only question left is whether it is a
	# step or a wall: the full capsule has to fit one step_height up, and this
	# frame's movement has to still be possible from there.
	#
	# The whole step_height is lifted in one go rather than a measured minimum.
	# A minimum search looks tempting - it would avoid overshooting a low tread -
	# but the thing it can actually ask is "is this one frame's move clear if
	# raised a little", and the answer stays yes for a few centimetres over
	# every ledge. The player then creeps up a stair in 0.05 m increments over
	# several frames instead of stepping. Lifting decisively puts the body
	# above the tread, and floor snapping settles the small remainder within a
	# frame or two, which reads as a step rather than a scramble.
	var raised := global_transform
	raised.origin.y += step_height

	# Third argument is the collision output, passed null because only the
	# yes/no answer is wanted; the margin is the fourth.
	if test_move(raised, horizontal, null, STEP_CLEARANCE):
		return false

	global_position.y += step_height
	return true


# --- Crouch ------------------------------------------------------------

## Moves the body between standing and crouched, and refuses to stand up if
## there is a ceiling in the way.
func _update_stance(delta: float) -> void:
	if _crouch_held and _stance > 0.0:
		_stance = move_toward(_stance, 0.0, stance_change_speed * delta)
	elif not _crouch_held and _stance < 1.0:
		# Only grow back if the standing capsule fits. Checked every frame
		# while held down, so walking out from under a low passage resumes the
		# stand automatically without the player pressing anything.
		if _can_stand():
			_stance = move_toward(_stance, 1.0, stance_change_speed * delta)

	_apply_stance()


## Resizes the collision shape and moves the camera to match the stance. The
## shape's [member CollisionShape3D.position] is what keeps the player's feet
## planted: the capsule is anchored at the origin, so a shorter capsule has to
## drop by half the difference or the player sinks into the floor.
func _apply_stance() -> void:
	var height := get_current_height()
	var shape := _collision.shape as CapsuleShape3D
	shape.height = maxf(height, body_radius * 2.0 + 0.001)
	_collision.position.y = shape.height * 0.5
	_head.position.y = lerpf(crouch_eye_height, stand_eye_height, _stance)

	# Keep the development capsule the same size as the collider, so it is
	# still an honest picture of the collision when someone enables it.
	var mesh := _body_mesh.mesh as CapsuleMesh
	if mesh != null:
		mesh.height = shape.height


## Whether a standing player would fit at the current position.
func _can_stand() -> bool:
	var shape := _collision.shape as CapsuleShape3D
	var saved_height := shape.height

	shape.height = maxf(stand_height, body_radius * 2.0 + 0.001)
	_collision.position.y = shape.height * 0.5
	var blocked := test_move(global_transform, Vector3.ZERO)

	shape.height = saved_height
	_apply_stance()
	return not blocked


# --- Debug support -----------------------------------------------------

## One-line summary for the debug overlay.
func debug_line() -> String:
	return "%s  %s  v=%5.1f m/s  y=%5.2f" % [
		state_name(get_movement_state()),
		"h=%4.2f" % get_current_height(),
		Vector2(velocity.x, velocity.z).length(),
		global_position.y,
	]
