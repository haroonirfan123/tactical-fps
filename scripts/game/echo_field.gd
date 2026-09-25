extends Node3D
class_name EchoField
## The Echo Field - a tactical reconnaissance mechanic (Chapter 6).
##
## When deployed, creates a temporary field that detects and records
## relevant activity (movement, shooting, objective interaction) within
## its radius. The field then produces short-lived "echo" indicators
## showing approximate location and type of activity.
##
## Server-authoritative: all detection logic runs on the host.

## Emitted when an echo event is recorded (for UI/haptic feedback).
signal echo_detected(event_type: int, position: Vector3, timestamp: float)

## Emitted when the field expires naturally.
signal field_expired

## Emitted when the field is deployed.
signal field_deployed(position: Vector3, owner_peer_id: int)


## How long the field stays active, in seconds.
@export_range(2.0, 30.0) var duration: float = 8.0

## Detection radius, in metres.
@export_range(3.0, 20.0) var detection_radius: float = 10.0

## Cooldown between deployments, in seconds.
@export_range(5.0, 60.0) var cooldown: float = 25.0

## How long each echo marker remains visible, in seconds.
@export_range(0.5, 5.0) var echo_lifetime: float = 2.0

## Team that owns this field (for filtering).
var owning_team: int = 0

## Peer ID of the player who deployed this field.
var owner_peer_id: int = 0

## Whether the field is currently active.
var is_active: bool = false

## Remaining time on the field.
var time_remaining: float = 0.0

## Cooldown timer.
var _cooldown_remaining: float = 0.0

## Detected echo events waiting to be displayed.
var _pending_echoes: Array[Dictionary] = []

## Visual representation.
var _field_mesh: MeshInstance3D = null
var _detection_area: Area3D = null
var _pulse_phase: float = 0.0


func _ready() -> void:
	name = "EchoField"
	_build_field()


func _build_field() -> void:
	# Visual field boundary
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "FieldMesh"
	
	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = detection_radius
	cylinder_mesh.bottom_radius = detection_radius
	cylinder_mesh.height = 0.2
	mesh_instance.mesh = cylinder_mesh
	
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.8, 1.0, 0.3)
	material.transparency = 0
	material.render_priority = 1
	material.cull_mode = StandardMaterial3D.CULL_BACK
	mesh_instance.material_override = material
	mesh_instance.position = Vector3(0.0, 0.1, 0.0)
	add_child(mesh_instance)
	_field_mesh = mesh_instance
	
	# Detection area (invisible, larger than visual for buffer)
	_detection_area = Area3D.new()
	_detection_area.name = "DetectionArea"
	_detection_area.collision_layer = 0
	_detection_area.collision_mask = 2  # PLAYER layer = 1 << 1 = 2
	_detection_area.monitoring = false
	_detection_area.monitorable = false
	
	var area_collision = CollisionShape3D.new()
	var area_shape = CylinderShape3D.new()
	area_shape.radius = detection_radius
	area_shape.height = 3.0
	area_collision.shape = area_shape
	_detection_area.add_child(area_collision)
	add_child(_detection_area)
	
	# Initially hidden
	_field_mesh.visible = false
	
	# Connect signals
	_detection_area.body_entered.connect(_on_body_entered)
	_detection_area.body_exited.connect(_on_body_exited)
	
	# Pulse animation
	_pulse_phase = 0.0


func _process(delta: float) -> void:
	if not is_active:
		# Handle cooldown
		if _cooldown_remaining > 0.0:
			_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
		return
	
	# Field active - tick duration
	time_remaining = maxf(time_remaining - delta, 0.0)
	
	# Pulse animation
	_pulse_phase += delta * 3.0
	if _field_mesh != null:
		var pulse = sin(_pulse_phase) * 0.2 + 0.8
		var mat = _field_mesh.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color = Color(0.2, 0.8, 1.0, pulse * 0.3)
			mat.emission_energy_multiplier = pulse * 2.0
	
	# Process pending echoes (fade them out)
	var i = _pending_echoes.size() - 1
	while i >= 0:
		var echo = _pending_echoes[i]
		echo.lifetime -= delta
		if echo.lifetime <= 0.0:
			_pending_echoes.remove_at(i)
		i -= 1
	
	# Check for expiration
	if time_remaining <= 0.0:
		_deactivate()


## Called by a player to deploy the Echo Field.
## Validates on server, then activates. In offline mode, runs locally.
@rpc("any_peer", "call_remote", "reliable")
func request_deploy(position: Vector3) -> void:
	# In offline mode, execute locally instead of via RPC
	if not NetworkManager.is_online:
		_request_deploy_local(position)
		return
	
	if not multiplayer.is_server():
		return
	
	var sender = multiplayer.get_remote_sender_id()
	var player = NetworkManager.get_player_for(sender)
	
	if player == null or not player.state.is_alive:
		return
	
	if _cooldown_remaining > 0.0:
		return
	
	if is_active:
		return
	
	# Validate position is on navmesh/floor
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(position + Vector3(0, 2, 0), position - Vector3(0, 5, 0))
	query.collision_mask = 1  # WORLD layer = 1 << 0 = 1
	var result = space_state.intersect_ray(query)
	if not result:
		return
	
	position = result.position
	
	_activate(position, sender, player.state.team)


## Local deployment for offline mode.
func _request_deploy_local(position: Vector3) -> void:
	var player = NetworkManager.get_local_player()
	if player == null or not player.state.is_alive:
		return
	
	if _cooldown_remaining > 0.0:
		return
	
	if is_active:
		return
	
	# Validate position is on navmesh/floor
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(position + Vector3(0, 2, 0), position - Vector3(0, 5, 0))
	query.collision_mask = 1  # WORLD layer = 1 << 0 = 1
	var result = space_state.intersect_ray(query)
	if not result:
		return
	
	position = result.position
	
	_activate(position, NetworkManager.SERVER_PEER_ID, player.state.team)


func _activate(position: Vector3, peer_id: int, team: int) -> void:
	global_position = position
	owner_peer_id = peer_id
	owning_team = team
	is_active = true
	time_remaining = duration
	_cooldown_remaining = cooldown
	_pending_echoes.clear()
	
	_field_mesh.visible = true
	_detection_area.monitoring = true
	_detection_area.monitorable = true
	
	field_deployed.emit(position, peer_id)
	_sync_field_state.rpc(true, position, peer_id, team, duration)


## Deactivates the field early or on expiration.
func _deactivate() -> void:
	if not is_active:
		return
	
	is_active = false
	time_remaining = 0.0
	_field_mesh.visible = false
	_detection_area.monitoring = false
	_detection_area.monitorable = false
	
	field_expired.emit()
	_sync_field_state.rpc(false, global_position, 0, 0, 0.0)


## Syncs field state to all clients.
@rpc("authority", "call_remote", "reliable")
func _sync_field_state(active: bool, position: Vector3, peer_id: int, team: int, dur: float) -> void:
	if active:
		global_position = position
		owner_peer_id = peer_id
		owning_team = team
		is_active = true
		time_remaining = dur
		_cooldown_remaining = cooldown
		_pending_echoes.clear()
		_field_mesh.visible = true
		_detection_area.monitoring = true
		_detection_area.monitorable = true
	else:
		is_active = false
		time_remaining = 0.0
		_field_mesh.visible = false
		_detection_area.monitoring = false
		_detection_area.monitorable = false


## Detects relevant activity from players inside the field.
func _on_body_entered(body: Node3D) -> void:
	if not is_active or not multiplayer.is_server():
		return
	
	var player = body as Player
	if player == null or not player.state.is_alive:
		return
	
	# Don't detect own team's activity
	if player.state.team == owning_team:
		return
	
	# Determine activity type based on player state
	var activity_type = EchoField.ECHO_MOVEMENT
	if player.get_movement_state() == Player.MovementState.SPRINTING:
		activity_type = EchoField.ECHO_MOVEMENT
	
	var echo = {
		"type": activity_type,
		"position": player.global_position,
		"timestamp": Time.get_ticks_msec() / 1000.0,
		"lifetime": echo_lifetime,
		"player_team": player.state.team
	}
	_pending_echoes.append(echo)
	echo_detected.emit(activity_type, player.global_position, echo.timestamp)


func _on_body_exited(body: Node3D) -> void:
	# Could track when players leave, but echoes persist for their lifetime
	pass


## Public method for external systems to report activity (e.g., Signal Core, shooting).
func report_activity(activity_type: int, position: Vector3, source_team: int) -> void:
	if not is_active or not multiplayer.is_server():
		return
	
	if source_team == owning_team:
		return
	
	var echo = {
		"type": activity_type,
		"position": position,
		"timestamp": Time.get_ticks_msec() / 1000.0,
		"lifetime": echo_lifetime,
		"player_team": source_team
	}
	_pending_echoes.append(echo)
	echo_detected.emit(activity_type, position, echo.timestamp)


## Activity type constants
const ECHO_MOVEMENT = 0
const ECHO_SHOOTING = 1
const ECHO_OBJECTIVE = 2
const ECHO_ABILITY = 3


## Returns all currently visible echoes for UI rendering.
func get_active_echoes() -> Array[Dictionary]:
	var result = []
	for echo in _pending_echoes:
		if echo.lifetime > 0.0:
			result.append(echo.duplicate())
	return result


## Returns whether this field is on cooldown.
func is_on_cooldown() -> bool:
	return _cooldown_remaining > 0.0


## Returns cooldown progress (0.0 to 1.0).
func get_cooldown_progress() -> float:
	if cooldown <= 0.0:
		return 1.0
	return 1.0 - (_cooldown_remaining / cooldown)