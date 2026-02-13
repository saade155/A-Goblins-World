## BehaviorTracker - Player action observer.
##
## This system watches what the player does from the very first session. It
## NEVER modifies game state — it only observes by listening to GameServer signals.
##
## Tracked data feeds into:
## - Skill XP calculations (Milestone 5)
## - Class unlock evaluation (Milestone 10)
## - Dynamic difficulty awareness
## - Analytics
##
## Storage is lightweight: dictionaries of counters, serialized with save data.
## Actions are recorded as cumulative counters and a rolling window of recent
## actions (recent behavior matters for class offers, lifetime totals matter
## for unlock thresholds).

extends Node

## Maximum number of recent actions to keep in the rolling window.
const MAX_RECENT_ACTIONS: int = 1000

## Lifetime counters: action_type (String) -> count (int).
## Example: { "tile_mined": 47, "item_collected": 23 }
var lifetime_counters: Dictionary = {}

## Filtered lifetime counters: "action_type:key=value" -> count.
## Example: { "tile_mined:tile_type=dirt": 30, "tile_mined:tile_type=stone": 17 }
var filtered_counters: Dictionary = {}

## Rolling window of recent actions, newest at the end.
## Each entry: { "type": String, "metadata": Dictionary, "timestamp": float }
var recent_actions: Array[Dictionary] = []

## Stat values (non-counter data like max_depth_reached).
var stats: Dictionary = {}

## Ore tile types for tracking first discoveries.
const ORE_TYPES: Array[int] = [3, 5, 6, 7, 18, 19]  # IRON_ORE, COPPER_ORE, GOLD_ORE, CRYSTAL, RUBY_ORE, EMERALD_ORE


func _ready() -> void:
	print("[BehaviorTracker] Initialized — recording all player actions.")
	# Connect to GameServer signals once they start firing (Milestone 2+).
	# For now GameServer is a stub, but the wiring is in place.
	if GameServer:
		GameServer.tile_mined.connect(_on_tile_mined)
		GameServer.tile_placed.connect(_on_tile_placed)
		GameServer.item_collected.connect(_on_item_collected)
		GameServer.damage_dealt.connect(_on_damage_dealt)
		GameServer.entity_killed.connect(_on_entity_killed)


## Record a player action. This is the primary entry point.
## action_type: A string key like "tile_mined", "jump", "item_crafted".
## metadata: Optional dictionary of context, e.g. { "tile_type": "stone", "depth": 42 }.
func record_action(action_type: String, metadata: Dictionary = {}) -> void:
	# Update lifetime counter.
	if action_type in lifetime_counters:
		lifetime_counters[action_type] += 1
	else:
		lifetime_counters[action_type] = 1

	# Update filtered counters for each metadata key-value pair.
	for key in metadata:
		var filter_key := "%s:%s=%s" % [action_type, str(key), str(metadata[key])]
		if filter_key in filtered_counters:
			filtered_counters[filter_key] += 1
		else:
			filtered_counters[filter_key] = 1

	# Add to rolling window.
	var entry: Dictionary = {
		"type": action_type,
		"metadata": metadata,
		"timestamp": Time.get_ticks_msec() / 1000.0,
	}
	recent_actions.append(entry)

	# Cap the rolling window.
	while recent_actions.size() > MAX_RECENT_ACTIONS:
		recent_actions.pop_front()


## Get the lifetime count for an action type.
func get_count(action_type: String) -> int:
	return lifetime_counters.get(action_type, 0)


## Get the lifetime count for an action filtered by a metadata key-value pair.
## Example: get_count_filtered("tile_mined", "tile_type", "stone")
func get_count_filtered(action_type: String, metadata_key: String, metadata_value) -> int:
	var filter_key := "%s:%s=%s" % [action_type, metadata_key, str(metadata_value)]
	return filtered_counters.get(filter_key, 0)


## Get a stat value (non-counter data).
func get_stat(stat_name: String):
	return stats.get(stat_name, null)


## Set a stat value. Used for things like max_depth_reached.
func set_stat(stat_name: String, value) -> void:
	stats[stat_name] = value


## Update a stat only if the new value is greater (useful for "max" stats).
func update_stat_max(stat_name: String, value: float) -> void:
	var current = stats.get(stat_name, -INF)
	if value > current:
		stats[stat_name] = value


# --- Signal handlers (wired to GameServer) ---

func _on_tile_mined(position: Vector2i, tile_type: int, tool_used: String) -> void:
	record_action("tile_mined", {
		"tile_type": tile_type,
		"tool_used": tool_used,
		"position_x": position.x,
		"position_y": position.y,
	})

	# Track ore types encountered (first discovery)
	if tile_type in ORE_TYPES:
		_record_ore_encountered(tile_type)


## Record the first time a player mines a specific ore type.
func _record_ore_encountered(tile_type: int) -> void:
	var encountered: Dictionary = stats.get("ore_types_encountered", {})
	if not encountered.has(tile_type):
		encountered[tile_type] = Time.get_ticks_msec() / 1000.0
		stats["ore_types_encountered"] = encountered
		var props: Dictionary = TileDatabase.tile_properties.get(tile_type, {})
		var ore_name: String = props.get("name", "Unknown")
		print("[BehaviorTracker] New ore discovered: %s" % ore_name)


func _on_tile_placed(position: Vector2i, tile_type: int) -> void:
	record_action("tile_placed", {
		"tile_type": tile_type,
		"position_x": position.x,
		"position_y": position.y,
	})


func _on_item_collected(item_type: String, amount: int) -> void:
	record_action("item_collected", {
		"item_type": item_type,
		"amount": amount,
	})


func _on_damage_dealt(source: Node, target: Node, amount: float, damage_type: String, weapon: String) -> void:
	record_action("damage_dealt", {
		"source": source.name if source else "unknown",
		"target": target.name if target else "unknown",
		"amount": amount,
		"damage_type": damage_type,
		"weapon": weapon,
	})


func _on_entity_killed(source: Node, target: Node, weapon: String) -> void:
	record_action("entity_killed", {
		"source": source.name if source else "unknown",
		"target": target.name if target else "unknown",
		"weapon": weapon,
	})
