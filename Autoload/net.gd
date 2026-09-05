extends Node

## the session. who is connected, who is host, and how a second machine finds the first one.
##
## THE GAME IS ALWAYS A HOST. godot hands out an OfflineMultiplayerPeer when nothing is connected, so
## a solo run is a host with nobody else on it: `multiplayer.is_server()` is true and the id is 1,
## measured in the engine before any of this was written. Nothing in the game asks "are we in
## multiplayer", it asks "am I the host", and offline the answer is yes. That is what keeps one code
## path instead of two, and it is why the solo game cannot rot while this is built.
##
## the peer is ENet over UDP: a LAN needs no more than that. Over the internet it works the same way
## the moment the host forwards the port, which is a thing a router does and not a thing this can do.

signal state_changed(state: int)
## somebody joined or left, or their name arrived.
signal peers_changed()
## a host or a join did not work, in words the menu can show.
signal failed(reason: String)
## the operative this machine drives has entered the tree. everything that draws for the player --
## the hud, the reticle, the health bar, the camera -- binds on this rather than looking for a node
## that may not have been spawned yet.
signal local_player_ready(player: Node)
## the answers to a search of the local network: [{"name": String, "address": String}, ...]
signal servers_found(servers: Array)

enum State { OFFLINE, HOSTING, JOINING, CONNECTED }

const PORT := 24545
## the beacon is a second, tiny socket: the host answers "who is there" so a client on the same
## network never has to be told an address. it is separate from the game port on purpose, because a
## broadcast arriving on the ENet socket is not something ENet should have to think about.
const BEACON_PORT := 24546
const BEACON_ASK := "KIWI?"
const BEACON_SAY := "KIWI!"
const MAX_PLAYERS := 4
## how long a search listens before it gives up and lets the player type an address.
const SEARCH_TIME := 1.2

var state := State.OFFLINE
## peer id -> the name that peer goes by. the host's own id is always 1.
var peers := {}
var player_name := "OPERATIVE"

var _beacon: PacketPeerUDP
var _search: PacketPeerUDP
var _searching := 0.0
var _found := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player_name = _default_name()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_gone)


## the machine's own user name, so two people on a LAN are told apart without either of them typing
## anything. it is only a label: nothing is keyed on it.
func _default_name() -> String:
	for key in ["USERNAME", "USER", "LOGNAME"]:
		var found := OS.get_environment(key)
		if found != "":
			return found.substr(0, 12).to_upper()
	return "OPERATIVE"


func is_host() -> bool:
	return multiplayer.is_server()


func is_online() -> bool:
	return state == State.HOSTING or state == State.CONNECTED


func local_id() -> int:
	return multiplayer.get_unique_id()


## everybody in the session including this machine, host first. the menu and the hud read this.
func roster() -> Array:
	var out: Array = []
	var ids := peers.keys()
	ids.sort()
	for id in ids:
		out.append({"id": id, "name": String(peers[id])})
	return out


func name_of(id: int) -> String:
	return String(peers.get(id, "OPERATIVE"))


func host(port := PORT) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		failed.emit("Could not open port %d (error %d). Is another copy already hosting?" % [port, err])
		return false
	multiplayer.multiplayer_peer = peer
	peers = {1: player_name}
	_set_state(State.HOSTING)
	_start_beacon()
	peers_changed.emit()
	return true


func join(address: String, port := PORT) -> bool:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		failed.emit("Could not reach %s:%d (error %d)." % [address, port, err])
		return false
	multiplayer.multiplayer_peer = peer
	peers = {}
	_set_state(State.JOINING)
	return true


## back to a solo game. the peer is dropped rather than left half open, and the offline peer takes
## over again, which is what makes every "am I the host" answer true once more.
func leave() -> void:
	_stop_beacon()
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peers = {}
	if state != State.OFFLINE:
		_set_state(State.OFFLINE)
		peers_changed.emit()


## ---------------------------------------------------------------- names
## a peer announces itself to everyone once it is connected. the host is the only one that keeps the
## whole list, so it answers by sending the list back.
@rpc("any_peer", "call_local", "reliable")
func _tell_name(who: int, called: String) -> void:
	peers[who] = called
	peers_changed.emit()
	if multiplayer.is_server():
		_share_roster.rpc(peers)


@rpc("authority", "call_remote", "reliable")
func _share_roster(everyone: Dictionary) -> void:
	peers = everyone.duplicate()
	peers_changed.emit()


## ---------------------------------------------------------------- the beacon
func _start_beacon() -> void:
	_beacon = PacketPeerUDP.new()
	_beacon.bind(BEACON_PORT)


func _stop_beacon() -> void:
	if _beacon != null:
		_beacon.close()
		_beacon = null


## look for a host on this network. the reply carries the host's name and its address comes off the
## packet itself, so nobody has to read an ip out loud.
func search() -> void:
	_found.clear()
	_search = PacketPeerUDP.new()
	_search.bind(0)
	_search.set_broadcast_enabled(true)
	var ask := (BEACON_ASK + "|" + player_name).to_utf8_buffer()
	## the broadcast is for the LAN, and the loopback is for one machine running two copies of the
	## game -- which is how this gets tested and how one person tries co-op on their own. windows
	## does not hand a machine its own broadcast, so without the second packet a host and a client
	## on the same computer would never see each other.
	for where in ["255.255.255.255", "127.0.0.1"]:
		_search.set_dest_address(where, BEACON_PORT)
		_search.put_packet(ask)
	_searching = SEARCH_TIME


func searching() -> bool:
	return _searching > 0.0


func _process(delta: float) -> void:
	if _beacon != null:
		while _beacon.get_available_packet_count() > 0:
			var ask := _beacon.get_packet().get_string_from_utf8()
			if not ask.begins_with(BEACON_ASK):
				continue
			_beacon.set_dest_address(_beacon.get_packet_ip(), _beacon.get_packet_port())
			_beacon.put_packet((BEACON_SAY + "|" + player_name).to_utf8_buffer())
	if _searching <= 0.0:
		return
	_searching -= delta
	if _search != null:
		while _search.get_available_packet_count() > 0:
			var say := _search.get_packet().get_string_from_utf8()
			var from := _search.get_packet_ip()
			if say.begins_with(BEACON_SAY) and not _found.has(from):
				_found[from] = say.split("|")[-1]
	if _searching <= 0.0:
		var out: Array = []
		for address in _found:
			out.append({"name": String(_found[address]), "address": String(address)})
		if _search != null:
			_search.close()
			_search = null
		servers_found.emit(out)


## ---------------------------------------------------------------- the wire's own events
func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		peers[id] = "OPERATIVE"
		peers_changed.emit()


func _on_peer_disconnected(id: int) -> void:
	peers.erase(id)
	peers_changed.emit()


func _on_connected() -> void:
	_set_state(State.CONNECTED)
	peers[multiplayer.get_unique_id()] = player_name
	_tell_name.rpc(multiplayer.get_unique_id(), player_name)
	peers_changed.emit()


func _on_connect_failed() -> void:
	failed.emit("The host did not answer.")
	leave()


func _on_server_gone() -> void:
	failed.emit("The host closed the game.")
	leave()


## the host said go. every machine leaves the menu for the same scene on the same call, which is
## what makes the two of them arrive in the safe house together rather than one waiting on a screen
## it has no way to leave. it lives on an autoload because the node that sends it is about to be
## freed by the scene change.
@rpc("authority", "call_local", "reliable")
func begin_game() -> void:
	await Fade.cover()
	get_tree().change_scene_to_file("res://main.tscn")


## called by a player node the moment it knows it is ours.
func announce_local(who: Node) -> void:
	local_player_ready.emit(who)


func _set_state(value: int) -> void:
	if state == value:
		return
	@warning_ignore("int_as_enum_without_cast")
	state = value
	state_changed.emit(state)
