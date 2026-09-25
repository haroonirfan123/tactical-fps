extends Node
## Boot scene. Set as the project's main scene, so this is the first thing
## that runs, and it is never freed for the rest of the session.
##
## Its only job is routing: listen to [GameManager] and put the screen that
## belongs to the current phase under [member %ScreenHost]. It owns no game
## state of its own.
##
## [b]Why this scene never changes:[/b] routing has to outlive whatever it is
## routing to. If the router swapped itself out with the menu scene, there
## would be nothing left to handle the phase change that took the player out
## of the menu, and the game would need a second router. So the screens come
## and go as children of this node, which stays put.
##
## Nothing in this file is temporary. The grey box is a separate scene, and the
## debug overlay is a separate scene behind [constant DEV_OVERLAY_ENABLED], so
## both can be deleted for a release without touching the router.

## Set false to drop the debug overlay from a build, or delete
## [code]scenes/ui/dev_overlay.tscn[/code] and [code]scripts/ui/dev_overlay.gd[/code]
## and the four lines below that use them. That is the entire removal procedure.
const DEV_OVERLAY_ENABLED := true

const DEV_OVERLAY := preload("res://scenes/ui/dev_overlay.tscn")

## Chapter 2 boots straight into the playtest, because there is no real game to
## go to yet: no lobby, no team select, nothing to choose. The main menu still
## exists and still works, it is simply not the front door for now.
##
## This is the whole of the temporary arrangement. Set it to false and the game
## opens on the Chapter 1 main menu again; Chapter 4 does exactly that, once
## there is a real lobby worth entering.
const BOOT_INTO_PLAYTEST := true

## Phase -> screen scene. Phases with no entry fall through to the debug
## overlay plus the placeholder arena, which is correct for every phase until
## each one has a scene of its own.
##
## All five gameplay phases deliberately share one scene. They are different
## phases of the same thing - a match with a player in it - and none of them has
## its own presentation yet, so there is nothing to distinguish between them.
## Once rounds have a real round-start screen, that phase gets its own entry
## here and the rest stay pointed at the playtest.
const SCREENS := {
	GamePhase.Phase.MAIN_MENU: preload("res://scenes/ui/main_menu.tscn"),
	GamePhase.Phase.LOBBY: preload("res://scenes/game/playtest.tscn"),
	GamePhase.Phase.WARMUP: preload("res://scenes/game/playtest.tscn"),
	GamePhase.Phase.ROUND_START: preload("res://scenes/game/playtest.tscn"),
	GamePhase.Phase.ROUND_ACTIVE: preload("res://scenes/game/playtest.tscn"),
	GamePhase.Phase.ROUND_END: preload("res://scenes/game/playtest.tscn"),
}

## Screens that bring their own complete interface, where the debug overlay
## would only get in the way. Every other screen keeps the overlay up, which is
## what lets the playtest report FPS, player position and movement state while
## it is being played.
const SCREENS_WITHOUT_OVERLAY := [
	GamePhase.Phase.MAIN_MENU,
]

@onready var _screen_host: Node = %ScreenHost
@onready var _placeholder: Node3D = %PlaceholderEnvironment

## The screen currently in the tree, if any. Freed on every phase change.
var _current_screen: Node = null

## Which [PackedScene] [member _current_screen] was built from, so a phase
## change between two phases that share a screen can be recognised and ignored.
var _current_screen_scene: PackedScene = null

## Null when [constant DEV_OVERLAY_ENABLED] is false.
var _dev_overlay: CanvasLayer = null


func _ready() -> void:
	GameManager.state_changed.connect(_on_state_changed)

	if DEV_OVERLAY_ENABLED:
		_dev_overlay = DEV_OVERLAY.instantiate()
		# Assigned before adding, so the overlay's _ready can already read it.
		_dev_overlay.screen_host = _screen_host
		add_child(_dev_overlay)

	# Done before the first render below, so the main menu is never even
	# instantiated on the way into the playtest. GameManager has already run
	# its own _ready by now, because autoloads are set up before the main scene.
	if BOOT_INTO_PLAYTEST:
		GameManager.change_state(GamePhase.Phase.LOBBY)

	# The game is already in a phase by the time this scene loads, so render
	# once here instead of only reacting to future changes.
	_show_phase(GameManager.current_phase)

	# The overlay's own _ready ran before the menu above was routed into place,
	# so it needs one explicit refresh. Without this it reports "no scene" until
	# the next phase change.
	if _dev_overlay != null:
		_dev_overlay.refresh()


## The one place a phase becomes a screen. Adding a real menu, HUD or match
## scene later means adding a line to [constant SCREENS] and nothing else.
func _on_state_changed(_previous_phase: int, current_phase: int) -> void:
	_show_phase(current_phase)


func _show_phase(phase: int) -> void:
	_swap_screen(phase)
	# The overlay refreshes itself off the same signal, so there is nothing else
	# to do here.


## Removes the outgoing screen and instantiates the incoming one, if this phase
## has a real screen.
func _swap_screen(phase: int) -> void:
	var wanted: PackedScene = SCREENS.get(phase, null)

	# Several phases share one screen on purpose. Rebuilding it between them
	# would throw away live state for nothing - most visibly the player, who
	# would respawn at the top of the map on every round transition. Keeping
	# the live instance is also the behaviour a real game wants: the match does
	# not restart because the round counter moved.
	if wanted != null and wanted == _current_screen_scene and is_instance_valid(_current_screen):
		_apply_screen_mode(phase)
		return

	if _current_screen != null:
		_current_screen.queue_free()
		_current_screen = null
	_current_screen_scene = null

	if wanted != null:
		_current_screen = wanted.instantiate()
		_current_screen_scene = wanted
		_screen_host.add_child(_current_screen)

	_apply_screen_mode(phase)


## Decides which development scaffolding is on screen.
func _apply_screen_mode(phase: int) -> void:
	# [member PlaceholderEnvironment] is the fallback for phases with no screen
	# of their own. Note that the playtest brings its own copy of the same
	# environment, so while a screen is showing this one is hidden rather than
	# absent. That is deliberate: it keeps the Chapter 1 fallback intact for
	# phases nothing has been written for yet, instead of every new screen
	# having to own the arena.
	_placeholder.visible = _current_screen == null

	if _dev_overlay != null:
		_dev_overlay.visible = not SCREENS_WITHOUT_OVERLAY.has(phase)
