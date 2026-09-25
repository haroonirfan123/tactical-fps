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

## Phase -> screen scene. Phases with no entry fall through to the debug
## overlay plus the placeholder arena, which is correct for every phase until
## each one has a scene of its own.
const SCREENS := {
	GamePhase.Phase.MAIN_MENU: preload("res://scenes/ui/main_menu.tscn"),
}

@onready var _screen_host: Node = %ScreenHost
@onready var _placeholder: Node3D = %PlaceholderEnvironment

## The screen currently in the tree, if any. Freed on every phase change.
var _current_screen: Node = null

## Null when [constant DEV_OVERLAY_ENABLED] is false.
var _dev_overlay: CanvasLayer = null


func _ready() -> void:
	GameManager.state_changed.connect(_on_state_changed)

	if DEV_OVERLAY_ENABLED:
		_dev_overlay = DEV_OVERLAY.instantiate()
		# Assigned before adding, so the overlay's _ready can already read it.
		_dev_overlay.screen_host = _screen_host
		add_child(_dev_overlay)

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
## has a real screen. Hides the placeholder and the overlay when it does.
func _swap_screen(phase: int) -> void:
	if _current_screen != null:
		_current_screen.queue_free()
		_current_screen = null

	if SCREENS.has(phase):
		_current_screen = SCREENS[phase].instantiate()
		_screen_host.add_child(_current_screen)

	# A real screen means a real phase is fully handled, so the placeholder
	# arena and the debug overlay both stand down. They return together for
	# every other phase, which is the correct fallback until each has a scene
	# of its own.
	var showing_fallback: bool = _current_screen == null
	_placeholder.visible = showing_fallback
	if _dev_overlay != null:
		_dev_overlay.visible = showing_fallback
