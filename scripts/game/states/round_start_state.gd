extends GameState
## [b]ROUND_START[/b] - the freeze / buy window at the start of every round.
##
## Round one is reached from [b]WARMUP[/b], and every later round from
## [b]ROUND_END[/b]. Both paths come through here, which is what makes this the
## right place to bump the round counter and tell the rest of the game a round
## is being set up.
##
## When this is fleshed out in Chapter 5 it also owns spawn locking and the
## buy phase. The countdown and the round counter are the parts that other
## systems already need, so they are the parts that exist.

## Emitted every frame with the seconds left in the buy window.
signal countdown_updated(remaining: float)

## Seconds before combat begins.
var duration: float = 3.0

var _remaining: float = 0.0


func enter(_previous: GameState) -> void:
	_remaining = duration

	var match_data := get_match()
	match_data.start_round()
	EventBus.round_started.emit(match_data.round_number)
	countdown_updated.emit(_remaining)


func exit(_next_state: GameState) -> void:
	_remaining = 0.0


func update(delta: float) -> void:
	_remaining -= delta
	countdown_updated.emit(maxf(_remaining, 0.0))
	if _remaining <= 0.0:
		request_state(GamePhase.Phase.ROUND_ACTIVE)
