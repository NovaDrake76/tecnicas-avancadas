class_name LobbyPanel
extends Control

## the co-op page: host a game, find one on this network, or type an address.
##
## the SEARCH is why there is a beacon. Two people on the same wifi should not have to read an ip
## address out loud to each other, so the host answers a broadcast with its name and the client
## lists what answered; typing an address is still there for the case where the network will not
## carry a broadcast, which is most university wifi.
##
## once a game is up this is also the lobby: who is in, and the one button only the host has.

signal back_pressed()

const WIDTH := 900.0

var _column: VBoxContainer
var _address: LineEdit
var _found: VBoxContainer
var _roster: VBoxContainer
var _message: Label
var _start: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(140, 106)
	custom_minimum_size = Vector2(WIDTH, 0)
	Net.peers_changed.connect(_refresh)
	Net.state_changed.connect(func(_s: int) -> void: _refresh())
	Net.failed.connect(_on_failed)
	Net.servers_found.connect(_on_found)
	_build()
	_refresh()


func _build() -> void:
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", 14)
	_column.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(_column)

	MenuStyle.title(_column, "CO-OP", MenuStyle.T_HEADING)
	MenuStyle.label(_column, "Two operatives, one compound. Same network.", MenuStyle.T_LABEL)
	MenuStyle.spacer(_column, 10)

	MenuStyle.button(_column, "HOST A GAME", _on_host)
	MenuStyle.button(_column, "FIND A GAME", _on_search)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_column.add_child(row)
	_address = LineEdit.new()
	_address.placeholder_text = "192.168.0.10"
	_address.custom_minimum_size = Vector2(360, 56)
	_address.add_theme_font_size_override("font_size", MenuStyle.T_LABEL)
	row.add_child(_address)
	MenuStyle.sheet_solid(row, "JOIN BY ADDRESS", _on_join)

	_found = VBoxContainer.new()
	_found.add_theme_constant_override("separation", 6)
	_column.add_child(_found)

	MenuStyle.spacer(_column, 10)
	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 6)
	_column.add_child(_roster)

	_message = MenuStyle.label(_column, "", MenuStyle.T_LABEL)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(WIDTH, 0)

	MenuStyle.spacer(_column, 10)
	_start = MenuStyle.button(_column, "DEPLOY TOGETHER", _on_start)
	MenuStyle.button(_column, "BACK", func() -> void:
		Net.leave()
		back_pressed.emit())


func _on_host() -> void:
	if Net.host(Net.PORT):
		_say("Hosting on port %d. Anyone on this network can find you." % Net.PORT)


func _on_search() -> void:
	_say("Looking for a game...")
	Net.search()


func _on_join() -> void:
	var where := _address.text.strip_edges()
	if where == "":
		_say("Type the host's address, or press FIND A GAME.")
		return
	if Net.join(where):
		_say("Reaching %s..." % where)


func _on_found(servers: Array) -> void:
	MenuStyle.sheet_clear(_found)
	if servers.is_empty():
		_say("Nothing answered. The network may block broadcasts: type the address instead.")
		return
	_say("")
	for server in servers:
		var line: String = "%s  -  %s" % [String(server["name"]), String(server["address"])]
		var where: String = String(server["address"])
		MenuStyle.button(_found, line, func() -> void:
			_address.text = where
			_on_join())


## the one button that is not everybody's: the host decides when the run starts, because the run is
## one run. everyone else is told, by the same call.
func _on_start() -> void:
	if not Net.is_host():
		return
	Net.begin_game.rpc()


func _refresh() -> void:
	if _roster == null:
		return
	MenuStyle.sheet_clear(_roster)
	var everyone := Net.roster()
	if Net.state == Net.State.OFFLINE:
		_start.visible = false
		return
	MenuStyle.sheet_section(_roster, "IN THE TEAM")
	for who in everyone:
		var tag: String = " (host)" if int(who["id"]) == 1 else ""
		MenuStyle.sheet_text(_roster, String(who["name"]) + tag, 22, MenuStyle.BRIGHT)
	_start.visible = Net.is_host() and Net.state == Net.State.HOSTING
	if Net.state == Net.State.CONNECTED:
		_say("In. Waiting for the host to deploy.")


func _on_failed(reason: String) -> void:
	_say(reason)


func _say(text: String) -> void:
	if _message != null:
		_message.text = text
