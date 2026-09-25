extends GameState
## [b]ROUND_ACTIVE[/b] - live combat.
##
## There is no combat system yet, so this state does the two things that are
## genuinely its job and no one else's: it owns the round clock, and it is the
## single place a round is allowed to end.
##
## Note that [method end_round] does not award the win. It records who won and
## hands over to [b]ROUND_END[/b], which resolves the round in one place.
## That means the score, the [signal EventBus.round_ended] event and the
## next-phase decision all happen together and cannot drift apart.

## Emitted every frame with the seconds left in the round.
signal round_time_updated(remaining: float)

## Length of a round in seconds.
var duration: float = 90.0

var _remaining: float = 0.0


func enter(_previous: GameState) -> void:
	_remaining = duration


func exit(_next_state: GameState) -> void:
	_remaining = 0.0


func update(delta: float) -> void:
	_remaining -= delta
	round_time_updated.emit(maxf(_remaining, 0.0))
	if _remaining <= 0.0:
		# Time ran out. Passing NONE means "no team won this round", which is
		# different from a draw between two teams and must not be scored.
		end_round(Team.Side.NONE)


## Ends the current round and moves to [b]ROUND_END[/b].
## [param winner] is a [enum Team.Side]; pass [constant Team.Side.NONE] when
## nobody won. Returns false if the transition was rejected.
func end_round(winner: int) -> bool:
	get_match().last_round_winner = winner
	return request_state(GamePhase.Phase.ROUND_END)
