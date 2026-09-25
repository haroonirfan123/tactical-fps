class_name Playtest
extends Node3D
## The screen shown while there is no real game to get into: the grey box with
## one controllable player in it.
##
## [b]This is a development harness, not a level and not a match.[/b] It exists
## so the player controller can be walked around and broken on purpose. Chapter
## 7 replaces the environment and Chapter 8 replaces the presentation; the
## player scene itself survives both, untouched.
##
## Everything the player does stays inside the [Player] scene. This node's only
## jobs are choosing a spawn point, handing control to the player, and making
## sure the grey box's Chapter 1 overview camera does not fight it for the
## screen.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")

## Which of the grey box's spawn markers to use. The grey box authors two,
## one per side, because Chapter 4 will need both. A solo playtest has no sides
## yet, so it just picks one.
const SPAWN_MARKER_NAME := "AlphaSpawn"

## Used only if the marker is missing, so a renamed node in the environment
## degrades into a slightly odd spawn rather than a null reference crash in the
## middle of [method _ready].
const FALLBACK_SPAWN := Vector3(0.0, 0.0, 20.0)

## The live player, exposed so the debug overlay can read its position and
## movement state without searching the tree for it.
var player: Player = null


func _ready() -> void:
	_step_aside_from_overview_camera()
	_spawn_player()


## The grey box keeps the elevated camera it needed in Chapter 1, to prove the
## scene rendered at all. Godot would hand the screen to the player anyway on
## its own, but doing it here in the right order means the frame is never drawn
## with two cameras both claiming to be current.
func _step_aside_from_overview_camera() -> void:
	var overview := find_child("OverviewCamera", true, false) as Camera3D
	if overview != null:
		overview.current = false


func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate() as Player
	player.name = "Player"
	add_child(player)

	# Added to the tree first, so the player's own _ready has run - it is what
	# applies the standing collider and captures the mouse - before it is moved
	# into place.
	player.teleport_to(_spawn_point(), 0.0)


func _spawn_point() -> Vector3:
	var marker := get_node_or_null("Environment/%s" % SPAWN_MARKER_NAME) as Marker3D
	if marker == null:
		push_warning("Playtest: no '%s' marker under Environment." % SPAWN_MARKER_NAME)
		return FALLBACK_SPAWN
	return marker.global_position
