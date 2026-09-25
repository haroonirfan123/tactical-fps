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
## The panel below is a development harness, not a menu. It exists so the state
## machine can be driven and checked in Chapter 2, before there is a player, a
## weapon or a HUD to show. It is hidden whenever a real screen is registered
## for the phase. Chapter 8 replaces the harness; nothing else should ever
## come to depend on it.

## Phase -> screen scene. Phases with no entry fall through to the dev harness,
## which is correct for every phase until Chapter 8.
const SCREENS := {
	GamePhase.Phase.MAIN_MENU: preload("res://scenes/ui/main_menu.tscn"),
}

## One line explaining what each phase is for, shown under the phase name.
const PHASE_NOTES := {
	GamePhase.Phase.MAIN_MENU: "Nobody connected, nothing loaded. This is the only phase you start in.",
	GamePhase.Phase.LOBBY: "A fresh match. Peers show up here; the host starts the warm-up.",
	GamePhase.Phase.WARMUP: "One-off countdown before the very first round. Only runs once per match.",
	GamePhase.Phase.ROUND_START: "Freeze / buy window. The round counter ticks up here, not when combat starts.",
	GamePhase.Phase.ROUND_ACTIVE: "Live round. Weapons and damage arrive in Chapter 3.",
	GamePhase.Phase.ROUND_END: "Round resolved: score credited, then next round or the match result.",
	GamePhase.Phase.MATCH_END: "Match won. Stays here until someone picks a rematch or quits.",
}

@onready var _dev_panel: Control = %DevPanel
@onready var _phase_label: Label = %PhaseLabel
@onready var _note_label: Label = %NoteLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _net_label: Label = %NetLabel
@onready var _transition_box: HBoxContainer = %TransitionBox
@onready var _screen_host: Node = %ScreenHost

## The screen currently in the tree, if any. Freed on every phase change.
var _current_screen: Node = null

## Buttons built for the current phase, so they can be cleared each refresh.
var _transition_buttons: Array[Button] = []


func _ready() -> void:
	GameManager.state_changed.connect(_on_state_changed)
	EventBus.player_joined.connect(_on_player_joined)
	EventBus.player_left.connect(_on_player_left)

	# The game is already in a phase by the time this scene loads, so render
	# once here instead of only reacting to future changes.
	_show_phase(GameManager.current_phase)


## The one place a phase becomes a screen. Adding a real menu, HUD or match
## scene later means adding a line to [constant SCREENS] and nothing else.
func _on_state_changed(_previous_phase: int, current_phase: int) -> void:
	_show_phase(current_phase)


func _show_phase(phase: int) -> void:
	_swap_screen(phase)

	# The harness still refreshes while a real screen is up, so the numbers
	# underneath are current if it is ever shown again.
	_phase_label.text = GamePhase.phase_name(phase)
	_note_label.text = PHASE_NOTES.get(phase, "")
	_refresh_score()
	_refresh_network()
	_build_transition_buttons(phase)


## Removes the outgoing screen and instantiates the incoming one, if this phase
## has a real screen. Hides the harness when it does.
func _swap_screen(phase: int) -> void:
	if _current_screen != null:
		_current_screen.queue_free()
		_current_screen = null

	if SCREENS.has(phase):
		_current_screen = SCREENS[phase].instantiate()
		_screen_host.add_child(_current_screen)

	_dev_panel.visible = _current_screen == null


# --- Dev harness --------------------------------------------------------

func _build_transition_buttons(phase: int) -> void:
	for button in _transition_buttons:
		button.queue_free()
	_transition_buttons.clear()

	# Built from the same ALLOWED_TRANSITIONS table the machine enforces, so
	# the harness can never offer a move that would be refused. If a phase
	# looks stuck, the bug is in the table rather than here.
	for next_phase in GameManager.get_allowed_transitions(phase):
		var button := Button.new()
		button.text = GamePhase.phase_name(next_phase)
		button.pressed.connect(_on_transition_pressed.bind(next_phase))
		_transition_box.add_child(button)
		_transition_buttons.append(button)


func _on_transition_pressed(phase: int) -> void:
	GameManager.change_state(phase)


func _refresh_score() -> void:
	var match := GameManager.match_state
	_score_label.text = "Round %d   |   %s" % [match.round_number, match.score_line()]


func _refresh_network() -> void:
	if not NetworkManager.is_online:
		_net_label.text = "Offline"
		return

	var role := "Host" if NetworkManager.is_host else "Client"
	_net_label.text = "%s  |  %d / %d players  |  peer %d" % [
		role,
		NetworkManager.get_player_count(),
		NetworkManager.MAX_PLAYERS,
		NetworkManager.local_peer_id,
	]


# --- EventBus demo ------------------------------------------------------
# The only EventBus listeners in the project so far. They exist to show the
# pattern: the network layer raises the event and anything that cares can react
# without holding a reference to it.

func _on_player_joined(peer_id: int, player_name: String) -> void:
	print("[Harness] %s (peer %d) joined" % [player_name, peer_id])
	_refresh_network()


func _on_player_left(peer_id: int) -> void:
	print("[Harness] peer %d left" % peer_id)
	_refresh_network()
