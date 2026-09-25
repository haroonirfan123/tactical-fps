class_name GameState
extends RefCounted
## Base class for every phase of the game. One instance of a subclass exists
## for the active phase; [GameManager] creates it, ticks it, and throws it away.
##
## The point of this pattern is that [GameManager] never contains a chain of
## [code]if phase == ...[/code] branches. Each phase owns its own enter, tick
## and exit behaviour, so adding one is a new file rather than an edit to a
## switch statement that six other systems have to be read alongside.
##
## [b]Adding a phase:[/b]
## [codeblock]
## 1. Create a script in res://scripts/game/states/ extending this class.
## 2. Override enter() / update() / exit() with whatever the phase needs.
## 3. Add the phase to GamePhase.Phase.
## 4. Register the script and its transitions in GameManager.
## [/codeblock]
##
## [b]Note:[/b] states are plain objects, not nodes. They cannot own children,
## run their own [code]_process[/code], or create timers by themselves. Anything
## that needs to spawn something should ask [member game_manager], which is the
## one place allowed to touch the scene tree. Keeping states node-free is what
## lets the tick stay in one predictable place.

## The active [GameManager].
##
## Deliberately left untyped. Two obvious alternatives both fail: typing it as
## [GameManager] is a circular reference, because [GameManager] preloads every
## state script; typing it as [Node] makes the compiler reject reads such as
## [code]game_manager.match_state[/code], since [Node] has no such property.
## An untyped reference resolves at runtime, and [method get_match] hands back
## a properly typed result so nothing downstream has to care.
var game_manager


func _init(manager = null) -> void:
	game_manager = manager


## Called once, when this state becomes the active phase.
## [param previous] is the state being left, or [code]null[/code] on the very
## first transition. Use it for teardown-order-sensitive logic; normal cleanup
## belongs in [method exit].
func enter(_previous: GameState) -> void:
	pass


## Called once, when this state stops being the active phase.
## [param next_state] is the state being entered, or [code]null[/code] if the
## game is shutting down. Always release timers and connections here.
func exit(_next_state: GameState) -> void:
	pass


## Called every frame by [GameManager] while this state is active, including
## while the tree is paused - that is what makes buy-phase and round-end
## countdowns keep running when gameplay is frozen.
func update(_delta: float) -> void:
	pass


## The match in progress. This is the single accessor states need for it, so
## the untyped [member game_manager] is reached through in exactly one place.
func get_match() -> MatchState:
	return game_manager.match_state as MatchState


## Asks [GameManager] to move to [param phase]. Always go through this rather
## than calling [code]change_state[/code] yourself, so the transition table is
## enforced in one place. Returns false if the move was rejected.
func request_state(phase: int) -> bool:
	if game_manager == null:
		push_error("GameState.request_state() called before a GameManager was attached.")
		return false
	return game_manager.change_state(phase)
