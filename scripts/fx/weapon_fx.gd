class_name WeaponFx
extends Node3D
## Everything about a shot that is only worth showing to the machine that pulled
## the trigger.
##
## [b]This node is the network boundary for weapon presentation.[/b] The weapon
## knows where a round stopped; it emits that as [signal Weapon.impact_requested]
## and stops there. This listens and decides to draw. In Chapter 4, when a
## client's shot is validated by the host, the host re-runs the hitscan and gets
## a position back - and the machine that draws the spark is still the one whose
## input caused it, not the one that happened to be authoritative. Keeping the
## two apart is why the two classes are separate, and it means a future
## "spectator mode shows other players' tracers" feature has somewhere to live
## without either class growing a flag it should not have.
##
## [b]Muzzle flash and tracer are not here yet[/b] and do not need to be: the
## flash is a light on the weapon, driven by the local trigger, and the tracer
## would be spawned the same way as an impact. Chapter 8 replaces this file.

## The effect spawned where a round stops.
@export var impact_scene: PackedScene

## Rejects impacts from further away than this. A round that travelled the
## weapon's whole 45 m range is a legitimate hit and should be marked; this is
## only here so a bad origin from a network message cannot fill the screen with
## effects.
@export var max_impact_distance: float = 100.0

@onready var _weapon: Weapon = get_parent().get_node_or_null(^"Weapon") as Weapon

## Impacts alive at once. A full automatic burst is seven or eight rounds a
## second, and each effect is meant to last a fifth of that, so the cap is
## never reached in normal play - it exists so a pathological frame cannot
## spawn hundreds of nodes and stall the game.
const MAX_LIVE_EFFECTS := 24

var _live: int = 0


func _ready() -> void:
	if _weapon == null:
		push_warning("WeaponFx: no sibling Weapon node; impacts will not be drawn.")
		return
	_weapon.impact_requested.connect(_on_impact_requested)


func _on_impact_requested(at: Vector3, normal: Vector3, zone: int) -> void:
	if impact_scene == null or _live >= MAX_LIVE_EFFECTS:
		return

	var effect := impact_scene.instantiate() as ImpactEffect
	if effect == null:
		return

	# Added to the world rather than to this node, so the effect stays where it
	# was spawned instead of being dragged through the room as the player walks.
	# It removes itself when it expires, so nothing has to remember to clean up.
	get_tree().current_scene.add_child(effect)
	effect.setup(at, normal, zone)

	_live += 1
	effect.tree_exited.connect(_on_effect_freed)


func _on_effect_freed() -> void:
	_live = maxi(0, _live - 1)
