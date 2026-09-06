class_name Netlink
extends RefCounted


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
	link.public_visibility = true
	node.add_child(link)
	link.set_multiplayer_authority(authority)
	return link
