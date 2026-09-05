class_name Netlink
extends RefCounted

## builds a `MultiplayerSynchronizer` from a list of property paths.
##
## godot's replication config is an editor resource, and everything in this project is built in code,
## so this is the one place that knows how to write one. Every synchroniser in the game is made here,
## which means the answer to "what actually goes over the wire" is a list of strings at one call site
## rather than a resource nobody can read in a diff.
##
## the paths are relative to the node the synchroniser is put on: `.:position` is that node's own
## position, `Head:rotation` a child's. What is NOT here is as important as what is: velocity, state
## machines, timers and animation are all worked out again on the receiving machine from the few
## values that are, because sending a result is smaller and truer than sending the reasons for it.

## how often, in seconds. zero is every frame, which is what a body somebody is watching wants;
## anything that changes rarely says so with its own interval and costs nothing in between.
static func sync(node: Node, paths: Array, authority := 1, interval := 0.0,
		on_change := false) -> MultiplayerSynchronizer:
	var config := SceneReplicationConfig.new()
	for path in paths:
		var np := NodePath(String(path))
		config.add_property(np)
		config.property_set_spawn(np, true)
		if on_change:
			config.property_set_replication_mode(np, SceneReplicationConfig.REPLICATION_MODE_ON_CHANGE)
	var link := MultiplayerSynchronizer.new()
	link.name = "Netlink"
	link.replication_config = config
	link.replication_interval = interval
	## the visibility of a synchroniser is about who RECEIVES it, and everybody in a co-op mission
	## receives everything: there is no fog of war between two operatives on the same job.
	link.public_visibility = true
	node.add_child(link)
	link.set_multiplayer_authority(authority)
	return link
