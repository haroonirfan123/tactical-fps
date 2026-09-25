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


func enter(_previous: GameState) -> void:
	_start_countdown(get_rules().round_start_seconds)

	var match_data := get_match()
	match_data.start_round()
	EventBus.round_started.emit(match_data.round_number)
	countdown_updated.emit(_remaining)


func update(delta: float) -> void:
	countdown_updated.emit(_tick_countdown(delta))
	if _remaining <= 0.0:
		request_state(GamePhase.Phase.ROUND_ACTIVE)
