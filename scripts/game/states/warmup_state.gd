extends GameState
## [b]WARMUP[/b] - the one-off countdown before the very first round, so
## players have a moment to load in and get their bearings.
##
## This only ever runs once per match. Every round after the first goes
## [b]ROUND_END[/b] -> [b]ROUND_START[/b] directly.
##
## Because it is a timed state it exposes [signal countdown_updated] rather
## than making the UI poll it. That is the pattern every timed phase here
## uses: the state owns the clock, the UI just listens.

## Emitted every frame with the seconds left, for the HUD countdown.
signal countdown_updated(remaining: float)

## Seconds spent warming up.
var duration: float = 5.0

var _remaining: float = 0.0


func enter(_previous: GameState) -> void:
	_remaining = duration
	countdown_updated.emit(_remaining)


func exit(_next_state: GameState) -> void:
	_remaining = 0.0


func update(delta: float) -> void:
	_remaining -= delta
	countdown_updated.emit(maxf(_remaining, 0.0))
	if _remaining <= 0.0:
		request_state(GamePhase.Phase.ROUND_START)
