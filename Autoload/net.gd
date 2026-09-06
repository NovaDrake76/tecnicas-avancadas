extends Node


signal state_changed(state: int)
signal peers_changed()
signal failed(reason: String)
signal local_player_ready(player: Node)
signal servers_found(servers: Array)

enum State { OFFLINE, HOSTING, JOINING, CONNECTED }

const MENU_SCENE := "res://UI/main_menu.tscn"
const GAME_SCENE := "res://main.tscn"
const PORT := 24545
const BEACON_PORT := 24546
const BEACON_ASK := "KIWI?"
const BEACON_SAY := "KIWI!"
const MAX_PLAYERS := 4
const SEARCH_TIME := 1.2

var state := State.OFFLINE
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


func leave() -> void:
	_stop_beacon()
	if multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peers = {}
	if state != State.OFFLINE:
		_set_state(State.OFFLINE)
		peers_changed.emit()


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


func _start_beacon() -> void:
	_beacon = PacketPeerUDP.new()
	_beacon.bind(BEACON_PORT)


func _stop_beacon() -> void:
	if _beacon != null:
		_beacon.close()
		_beacon = null


func search() -> void:
	_found.clear()
	_search = PacketPeerUDP.new()
	_search.bind(0)
	_search.set_broadcast_enabled(true)
	var ask := (BEACON_ASK + "|" + player_name).to_utf8_buffer()
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
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path != MENU_SCENE:
		await Fade.cover()
		get_tree().change_scene_to_file(MENU_SCENE)


@rpc("authority", "call_local", "reliable")
func begin_game() -> void:
	await Fade.cover()
	get_tree().change_scene_to_file(GAME_SCENE)


func announce_local(who: Node) -> void:
	local_player_ready.emit(who)


func _set_state(value: int) -> void:
	if state == value:
		return
	@warning_ignore("int_as_enum_without_cast")
	state = value
	state_changed.emit(state)
