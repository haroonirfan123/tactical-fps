class_name PlaceholderEnvironment
extends Node3D
## A throwaway grey-box arena. It exists for one reason: to prove that the
## project renders, lights and simulates before there is a real map to load.
##
## [b]Everything in here is disposable.[/b] Chapter 7 deletes this scene and
## replaces it with the real map. Nothing outside [GameManager] should ever
## reference [PlaceholderEnvironment] by name - the match scene should simply
## be the thing that appears when gameplay starts, with this standing in until
## then.
##
## What lives in the [code].tscn[/code] and what lives here is a deliberate
## split. The ground, walls, sky, light and camera are [b]authored[/b] in the
## scene file so they can be clicked and adjusted in the Inspector. The cover
## blocks are [b]generated[/b] because they are near-identical, and a loop is
## a better home for them than a dozen copy-pasted nodes that all have to be
## deleted again in Chapter 7.

## Cover block layout. Each entry is [code][centre, size, yaw_degrees][/code].
## Positions are metres relative to the centre of the floor, with [code]y = 0[/code]
## being the floor surface. The goal is not good level design - it is to give
## Chapter 3 a player something to walk into, and Chapter 4 something to hide
## behind.
const COVER_BLOCKS := [
	[Vector3(-10.0, 0.0, -8.0), Vector3(6.0, 2.0, 1.0), 0.0],
	[Vector3(8.0, 0.0, -6.0), Vector3(1.0, 2.0, 7.0), 0.0],
	[Vector3(-6.0, 0.0, 4.0), Vector3(1.0, 3.0, 1.0), 25.0],
	[Vector3(6.0, 0.0, 5.0), Vector3(1.0, 3.0, 1.0), -25.0],
	[Vector3(0.0, 0.0, -1.0), Vector3(4.0, 1.2, 4.0), 0.0],
	[Vector3(-14.0, 0.0, 12.0), Vector3(2.0, 4.0, 2.0), 0.0],
	[Vector3(14.0, 0.0, 11.0), Vector3(2.0, 4.0, 2.0), 0.0],
	[Vector3(0.0, 0.0, 16.0), Vector3(8.0, 2.5, 1.0), 0.0],
]

## Shared by every generated block. One material for all of them keeps the
## generated geometry visually distinct from the authored floor and walls,
## which makes it obvious at a glance what was made in code.
const COVER_COLOUR := Color(0.52, 0.54, 0.57)


func _ready() -> void:
	_build_cover()


## Builds one [StaticBody3D] per entry in [constant COVER_BLOCKS]. A
## [StaticBody3D] rather than a bare [MeshInstance3D] because Chapter 3's
## player is a [CharacterBody3D] and would fall straight through a mesh that
## has no collision shape.
func _build_cover() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = COVER_COLOUR
	material.roughness = 1.0

	for i in COVER_BLOCKS.size():
		var block: Array = COVER_BLOCKS[i]
		var centre: Vector3 = block[0]
		var size: Vector3 = block[1]
		var yaw_degrees: float = block[2]

		# Each block is its own StaticBody3D so it can be moved, rotated or
		# deleted on its own later without unpicking a shared parent.
		var body := StaticBody3D.new()
		body.name = "Cover%d" % (i + 1)
		# Lifted by half its height so the box rests on the floor instead of
		# straddling it.
		body.position = centre + Vector3(0.0, size.y * 0.5, 0.0)
		body.rotation.y = deg_to_rad(yaw_degrees)

		var mesh_instance := MeshInstance3D.new()
		# Named explicitly. An unnamed node added at runtime gets an auto
		# generated name like @MeshInstance3D@412, which is unreadable in the
		# remote scene tree and impossible to address with get_node().
		mesh_instance.name = "Mesh"
		var box_mesh := BoxMesh.new()
		box_mesh.size = size
		mesh_instance.mesh = box_mesh
		mesh_instance.material_override = material
		body.add_child(mesh_instance)

		# Mesh and collider are sized separately on purpose. Editing the mesh
		# to look right should never silently change what you can walk into.
		var collision := CollisionShape3D.new()
		collision.name = "Collision"
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		collision.shape = box_shape
		body.add_child(collision)

		add_child(body)
