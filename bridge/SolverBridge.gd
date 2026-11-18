# SolverBridge.gd: sends the current table state to the local Buckshot Roulette
# solver (http://127.0.0.1:8000/live.php) on the player's turn, and shows the
# solver's hint on top of the game.
#
# SINGLE-PLAYER ONLY: it works only when a RoundManager (the single-player
# game) is in the scene tree. Multiplayer uses different scripts, so the
# bridge stays idle there.
#
# Only information the PLAYER has is sent: how many live / blank shells are
# left, items on the table, health, handcuffs, the saw, and what the player
# learned with their own Magnifying Glass / Burner Phone / Inverter.
# The actual hidden shell order is never sent.
#
# Hook up via Project Settings -> Autoload (already added to project.godot).
extends CanvasLayer

const SERVER_URL := "http://127.0.0.1:8000/live.php"
const ITEM_MAP := {
	"handsaw": "handSaw",
	"magnifying glass": "magnifyingGlass",
	"beer": "beer",
	"cigarettes": "cigarettePack",
	"handcuffs": "handcuffs",
	"expired medicine": "expiredMedicine",
	"burner phone": "burnerPhone",
	"adrenaline": "adrenaline",
	"inverter": "inverter",
}

var rm = null  # RoundManager
var http := HTTPRequest.new()
var label := Label.new()
var busy := false
var queued_body := ""
var last_sent := ""
var hint_text := ""
var enabled := true  # F8 toggles the bridge
var search_cooldown := 0.0

# --- What the player knows (tracked by watching the table) ---
var prev_size := 0
var known_chamber = null        # "live" / "blank" / null: seen with the Magnifying Glass
var chamber_inverted := false   # player flipped an UNKNOWN chambered shell
var phone_index := -1           # player's Burner Phone: index from the chambered shell
var phone_type := ""
var dealer_phone := false       # the dealer used a Burner Phone this round
var adrenaline_pending := false # next dealer item that disappears was stolen by the player
var prev_player_items := {}
var prev_dealer_items := {}

func _ready() -> void:
	layer = 127
	label.position = Vector2(16, 470)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	add_child(label)
	http.timeout = 60
	add_child(http)
	http.request_completed.connect(_on_request_completed)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		enabled = not enabled
		hint_text = "" if enabled else "Solver: off (F8)"
		last_sent = ""

func _reset_knowledge() -> void:
	known_chamber = null
	chamber_inverted = false
	phone_index = -1
	phone_type = ""
	dealer_phone = false
	adrenaline_pending = false

func _process(_delta: float) -> void:
	if rm == null or not is_instance_valid(rm):
		search_cooldown -= _delta
		if search_cooldown > 0:
			return
		search_cooldown = 1.0
		rm = _find_round_manager(get_tree().root)
		if rm == null:
			label.text = ""
			_reset_knowledge()
			prev_size = 0
			return

	var seq: Array = rm.shellSpawner.sequenceArray
	var size := seq.size()

	# --- Shells loaded / consumed ---
	if size == 0 or size > prev_size:
		_reset_knowledge()
		prev_player_items = _items(true)
		prev_dealer_items = _items(false)
	elif size < prev_size:
		var consumed := prev_size - size
		known_chamber = null
		chamber_inverted = false
		if phone_index >= 0:
			phone_index -= consumed
			if phone_index == 0:
				known_chamber = phone_type
			if phone_index <= 0:
				phone_index = -1
				phone_type = ""
	prev_size = size

	# --- The player's Burner Phone (BurnerPhone.gd stores what it said) ---
	if rm.shellSpawner.has_meta("solver_phone"):
		var m = rm.shellSpawner.get_meta("solver_phone")
		rm.shellSpawner.remove_meta("solver_phone")
		if int(m[0]) >= 1:
			phone_index = int(m[0])
			phone_type = str(m[1])

	# --- Item usage ---
	var player_items := _items(true)
	var dealer_items := _items(false)
	if size > 0:
		for iname in prev_player_items:
			var used: int = prev_player_items[iname] - player_items.get(iname, 0)
			for i in range(used):
				_on_player_used(iname, seq)
		for iname in prev_dealer_items:
			var used: int = prev_dealer_items[iname] - dealer_items.get(iname, 0)
			for i in range(used):
				if adrenaline_pending:
					adrenaline_pending = false
					_on_player_used(iname, seq)
				else:
					_on_dealer_used(iname)
	prev_player_items = player_items
	prev_dealer_items = dealer_items

	# --- Send on the player's turn ---
	var players_turn: bool = size > 0 and rm.deskUI_parent.visible
	if enabled and players_turn and rm.health_player > 0 and rm.health_opponent > 0:
		var body := JSON.stringify({"opponent": "game", "game": _build_game(seq, player_items, dealer_items)})
		if body != last_sent:
			last_sent = body
			_send(body)

	label.text = hint_text if players_turn or not enabled else ""

func _on_player_used(iname: String, seq: Array) -> void:
	match iname:
		"magnifying glass":
			if seq.size() > 0:
				known_chamber = seq[0]
				chamber_inverted = false
		"inverter":
			if known_chamber != null:
				known_chamber = "blank" if known_chamber == "live" else "live"
			else:
				chamber_inverted = not chamber_inverted
		"adrenaline":
			adrenaline_pending = true

func _on_dealer_used(iname: String) -> void:
	match iname:
		"burner phone":
			dealer_phone = true
		"inverter":
			if known_chamber != null:
				known_chamber = "blank" if known_chamber == "live" else "live"

func _build_game(seq: Array, player_items: Dictionary, dealer_items: Dictionary) -> Dictionary:
	var live: int = seq.count("live")
	var blank: int = seq.count("blank")
	var inverted_unknown: bool = chamber_inverted and known_chamber == null
	if inverted_unknown and seq.size() > 0:
		# Report the counts the player knows (before their own flip).
		if seq[0] == "live":
			live -= 1; blank += 1
		else:
			blank -= 1; live += 1
	var shells := []
	for i in range(live): shells.append("live")
	for i in range(blank): shells.append("blank")
	while shells.size() < 8: shells.append(null)

	var game := {
		"currentTurn": "player",
		"shells": shells.slice(0, 8),
		"nextShell": known_chamber,
		"items": [_item_slots(player_items), _item_slots(dealer_items)],
		"health": [clampi(rm.health_player, 1, 4), clampi(rm.health_opponent, 1, 4)],
		"handcuffs": [
			(("willBreak" if rm.playerAboutToBreakFree else "willSkip") if rm.playerCuffed else null),
			(("willBreak" if rm.dealerAI.dealerAboutToBreakFree else "willSkip") if rm.dealerCuffed else null),
		],
		"shotgunSawedOff": rm.barrelSawedOff,
		"chamberInverted": inverted_unknown,
	}
	if phone_index >= 1:
		game["futureShell"] = phone_type
		game["futureShellCountdown"] = phone_index + (1 if known_chamber == null else 0)
	if dealer_phone and seq.size() > 1:
		game["dealerPhoneCandidates"] = seq.size() - 1
	return game

func _item_slots(counts: Dictionary) -> Array:
	var slots := []
	for iname in counts:
		if not ITEM_MAP.has(iname):
			continue
		var n: int = counts[iname]
		if iname == "cigarettes":
			n = mini(n, 2)  # the solver allows at most 2
		for i in range(n):
			slots.append(ITEM_MAP[iname])
	slots = slots.slice(0, 8)
	while slots.size() < 8: slots.append(null)
	return slots

func _send(body: String) -> void:
	if busy:
		queued_body = body
		return
	busy = true
	hint_text = "Solver: calculating..."
	var err := http.request(SERVER_URL, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body)
	if err != OK:
		busy = false
		hint_text = "Solver: cannot connect (is the server running?)"

func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		hint_text = "Solver: no connection to %s" % SERVER_URL
	else:
		var data = JSON.parse_string(body.get_string_from_utf8())
		hint_text = "Solver: " + (str(data.get("hint", "?")) if data is Dictionary else "bad reply")
	if queued_body != "":
		var b := queued_body
		queued_body = ""
		_send(b)

func _items(player_side: bool) -> Dictionary:
	var out := {}
	var parent = rm.itemManager.itemSpawnParent
	if parent == null:
		return out
	for item in parent.get_children():
		if item.is_queued_for_deletion() or item.get_child_count() < 2:
			continue
		var ib = item.get_child(1)
		if ib is InteractionBranch and ib.isPlayerSide == player_side and ib.itemName != "":
			var iname: String = ib.itemName.to_lower()
			out[iname] = out.get(iname, 0) + 1
	return out

func _find_round_manager(node: Node):
	if node is RoundManager:
		return node
	for c in node.get_children():
		var r = _find_round_manager(c)
		if r != null:
			return r
	return null
