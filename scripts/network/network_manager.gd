extends Node
## Owns the multiplayer peer and all connection state. Registered as the
## [code]NetworkManager[/code] autoload.
##
## Everything netcode-related goes through here, and nothing else in the game
## touches [ENetMultiplayerPeer] directly. Two reasons: the rest of the game
## can then ask simple questions ("am I the host?", "who is connected?")
## without caring about ENet, and there is exactly one place to look when
## connections misbehave.
##
## Scope note: this covers session setup and peer bookkeeping only. It does
## not yet sync gameplay - player spawning, ownership and authority all arrive
## in Chapter 4, which is also where team assignment belongs. Keeping those
## out for now is deliberate; half-built replication is much harder to untangle
## than a clean gap.

# --- Signals ------------------------------------------------------------

## This machine started a server.
signal hosting_started(port: int)

## We are now connected to a server as a client.
signal join_succeeded

## Joining failed. [param reason] is safe to show in the UI.
signal join_failed(reason: String)

## A peer connected. [param peer_id] is 0 for the host itself on a client.
signal peer_connected(peer_id: int)

## A peer disconnected.
signal peer_disconnected(peer_id: int)

## We lost the server we were connected to.
signal server_disconnected

# --- Session configuration ----------------------------------------------

## Default port for a local or LAN match.
const DEFAULT_PORT := 27015

## Loopback, for testing two instances on one machine.
const DEFAULT_ADDRESS := "127.0.0.1"

## Hard ceiling on a session, whatever the rules ask for. A mistyped
## [code]match_rules.tres[/code] should not be able to open a server for a
## thousand players. This is a transport safety limit, not a game rule - the
## actual cap comes from [method get_max_players].
const ABSOLUTE_MAX_PLAYERS := 16

var _peer: ENetMultiplayerPeer = null
var _is_online: bool = false
var _is_host: bool = false


func _ready() -> void:
	# Connection teardown must still run if the tree is paused mid-round.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Connected once, here, rather than on every join: `multiplayer` outlives
	# any individual peer, so these fire correctly across reconnects.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- State --------------------------------------------------------------

## Whether we are connected to a session at all.
var is_online: bool:
	get: return _is_online

## Whether this machine is the server. Clients must never run authoritative
## game logic, so this gates most decisions in Chapters 4 and 5.
var is_host: bool:
	get: return _is_host

## Our own network id, or 0 when offline.
var local_peer_id: int:
	get: return _peer.get_unique_id() if _peer != null else 0

## Every connected peer including us.
func get_connected_peers() -> PackedInt32Array:
	if not _is_online:
		return PackedInt32Array()
	return multiplayer.get_peers()


## Session size implied by the match rules: two teams of
## [member MatchRules.players_per_team]. "3v3" is therefore stated once, in
## [code]data/match_rules.tres[/code], rather than as a 6 here and a 3 there.
## Clamped so a bad rules file cannot produce an absurd session.
func get_max_players() -> int:
	return clampi(GameManager.match_rules.get_team_size(), 2, ABSOLUTE_MAX_PLAYERS)


## Total connected players, including us. Capped by ENet to whatever was passed
## to [method host_game], so this can be trusted as a player count.
func get_player_count() -> int:
	return get_connected_peers().size()


## Whether the session has room for another player.
func has_open_slot() -> bool:
	return get_player_count() < get_max_players()


# --- Session control ----------------------------------------------------

## Starts a server and waits for players to connect.
## [param max_players] of 0 means "use the session size from the match rules".
## Returns [constant OK] on success, or an [enum Error] to pass to
## [method @GlobalScope.error_string].
func host_game(port: int = DEFAULT_PORT, max_players: int = 0) -> Error:
	leave_game()

	var cap := mini(max_players if max_players > 0 else get_max_players(), ABSOLUTE_MAX_PLAYERS)

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, cap)
	if error != OK:
		push_error("NetworkManager: could not host on port %d (%s)" % [port, error_string(error)])
		return error

	multiplayer.multiplayer_peer = peer
	_peer = peer
	_is_online = true
	_is_host = true

	print("[Network] Hosting on port %d for up to %d players" % [port, cap])
	hosting_started.emit(port)
	return OK


## Connects to a server. Use [signal join_succeeded] or [signal join_failed]
## to find out how it went - this returns before the attempt completes.
func join_game(address: String = DEFAULT_ADDRESS, port: int = DEFAULT_PORT) -> Error:
	leave_game()

	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		var reason := "Could not reach %s:%d (%s)" % [address, port, error_string(error)]
		push_error("NetworkManager: " + reason)
		join_failed.emit(reason)
		return error

	multiplayer.multiplayer_peer = peer
	_peer = peer
	_is_online = true
	_is_host = false

	print("[Network] Joining %s:%d" % [address, port])
	return OK


## Disconnects and returns to a fully offline state. Safe to call when
## already offline, and safe to call mid-round.
func leave_game() -> void:
	if _peer == null:
		_is_online = false
		_is_host = false
		return

	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer.close()
	_peer = null
	_is_online = false
	_is_host = false
	print("[Network] Left the session")


# --- Peer callbacks -----------------------------------------------------

func _on_peer_connected(id: int) -> void:
	# The roster and the ready-up check land in Chapter 4; the signal is
	# already public so the UI can show a count from day one.
	peer_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	peer_disconnected.emit(id)


func _on_connected_to_server() -> void:
	join_succeeded.emit()


func _on_connection_failed() -> void:
	# ENet leaves the peer half-open on failure, so clean up here rather than
	# leaving is_online true with nothing behind it.
	var reason := "The host did not respond."
	push_warning("NetworkManager: " + reason)
	leave_game()
	join_failed.emit(reason)


func _on_server_disconnected() -> void:
	leave_game()
	server_disconnected.emit()
