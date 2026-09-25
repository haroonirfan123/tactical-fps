extends GameState
## [b]BUY[/b] - the preparation / buy window at the start of every round.
##
## Round one is reached from [b]WARMUP[/b], and every later round from
## [b]ROUND_END[/b]. Both paths come through here, which is what makes this the
## right place to bump the round counter and tell the rest of the game a round
## is being set up.
##
## This state handles:
## - Round counter increment
## - Player spawn/respawn at team spawn points
## - Health/ammo/equipment reset
## - Buy menu (placeholder for Chapter 8)
## - Countdown to ROUND_ACTIVE
## - Signal Core placement and reset

## Emitted every frame with the seconds left in the buy window.
signal countdown_updated(remaining: float)

## Emitted when all players have been spawned/respawned and are ready.
signal round_ready


func enter(_previous: GameState) -> void:
	_start_countdown(get_rules().round_start_seconds)
	
	var match_data := get_match()
	match_data.start_round()
	EventBus.round_started.emit(match_data.round_number)
	countdown_updated.emit(_remaining)
	
	# Host spawns/respawns all players at their team spawn points
	if NetworkManager.is_host:
		_spawn_all_players()
	else:
		# Client requests spawn when its match scene is ready
		NetworkManager.request_spawn.rpc_id(NetworkManager.SERVER_PEER_ID)


func update(delta: float) -> void:
	countdown_updated.emit(_tick_countdown(delta))
	if _remaining <= 0.0:
		request_state(GamePhase.Phase.ROUND_ACTIVE)


## Host-only: spawn or respawn every alive player at their team's spawn point.
func _spawn_all_players() -> void:
	var players_array := NetworkManager.get_players()
	for player in players_array:
		# Reset player state for new round
		player.state.respawn()
		player.state.kills = 0
		player.state.deaths = 0
		player.state.assists = 0
		
		# Reset weapon ammo
		if player.weapon != null:
			player.weapon.reset_ammo()
		
		# Teleport to team spawn point
		var spawn_pos := _get_team_spawn(player.state.team)
		var spawn_yaw := _get_team_spawn_yaw(player.state.team)
		player.teleport_to(spawn_pos, spawn_yaw)
		
		# Ensure input is enabled for the player this machine owns
		if player.peer_id == NetworkManager.local_peer_id:
			player.set_input_enabled(true)
			player.capture_mouse(true)
		
		# Publish the reset state to network
		player._publish_net_state()
	
	round_ready.emit()


## Returns the spawn position for a team, with collision avoidance.
func _get_team_spawn(team: int) -> Vector3:
	var base := _marker_position(team)
	for attempt in 8:
		if not _occupied(base):
			return base
		base += Vector3(0.0, 0.0, 1.5)
	return base


## Returns the spawn yaw for a team.
func _get_team_spawn_yaw(team: int) -> float:
	var marker := game_manager.get_tree().get_root().get_node_or_null("Environment/%s" % _marker_name(team)) as Marker3D
	if marker == null:
		return 0.0
	var yaw := marker.global_rotation.y
	return yaw if not is_zero_approx(yaw) else 0.0


## Marker name for a team.
func _marker_name(side: int) -> String:
	return "BravoSpawn" if side == Team.Side.BRAVO else "AlphaSpawn"


## Marker position for a team.
func _marker_position(side: int) -> Vector3:
	var marker := game_manager.get_tree().get_root().get_node_or_null("Environment/%s" % _marker_name(side)) as Marker3D
	if marker == null:
		push_warning("BuyState: no '%s' marker under Environment." % _marker_name(side))
		return Vector3(0.0, 0.0, 20.0)
	return marker.global_position


## Checks if a spawn point is occupied.
func _occupied(point: Vector3) -> bool:
	for body in NetworkManager.get_players():
		var flat_a := Vector2(body.global_position.x, body.global_position.z)
		var flat_b := Vector2(point.x, point.z)
		if flat_a.distance_to(flat_b) < 1.5:
			return true
	return false