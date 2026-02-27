extends Node

## SkillSystem - Learn-by-doing skill system.
##
## Manages skill progression, XP, leveling, and perks.
## General skills (proficiency + resistance) auto-acquire on first relevant action.
## Class skills (deferred to M10) stay locked until class system exists.

# --- Signals ---
signal skill_xp_gained(skill_id: String, amount: float, new_total: float)
signal skill_leveled(skill_id: String, new_level: int)
signal perk_unlocked(skill_id: String, perk_id: String, skill_level: int)

# --- Enums ---
enum SkillCategory { PROFICIENCY, RESISTANCE, CLASS }
enum SkillStatus { LOCKED, ACTIVE }

# --- Constants ---
const SAVE_VERSION: int = 1
const XP_BASE: float = 100.0
const XP_EXPONENT: float = 1.5
const MAX_LEVEL: int = 50

# --- Skill definitions (static data) ---
# skill_id -> {name, category, description, perks: Array[perk_id]}
const SKILL_DEFS: Dictionary = {
	"mining": {
		"name": "Mining",
		"category": 0,  # PROFICIENCY
		"description": "Skill at breaking tiles. Improves speed and ore yield.",
		"perks": ["mining_speed_1", "bonus_ore_1", "mining_speed_2", "ore_sense", "mining_speed_3"],
	},
	"construction": {
		"name": "Construction",
		"category": 0,
		"description": "Building proficiency. Faster placement.",
		"perks": [],
	},
	"smithing": {
		"name": "Smithing",
		"category": 0,
		"description": "Metalworking proficiency.",
		"perks": [],
	},
	# Resistances — defined but no gameplay effect until combat
	"resist_physical": {
		"name": "Physical Resistance",
		"category": 1,  # RESISTANCE
		"description": "Reduces physical damage taken.",
		"perks": [],
	},
	"resist_fire": {
		"name": "Fire Resistance",
		"category": 1,
		"description": "Reduces fire damage taken.",
		"perks": [],
	},
	"resist_ice": {
		"name": "Ice Resistance",
		"category": 1,
		"description": "Reduces ice damage taken.",
		"perks": [],
	},
}

# --- Perk definitions (static data) ---
# perk_id -> {name, description, skill_id, required_level, effect_type, effect_value}
const PERK_DEFS: Dictionary = {
	"mining_speed_1": {
		"name": "Keen Strikes",
		"description": "+15% mining speed",
		"skill_id": "mining",
		"required_level": 5,
		"effect_type": "mining_speed",
		"effect_value": 0.15,
	},
	"bonus_ore_1": {
		"name": "Lucky Strikes",
		"description": "8% chance for bonus ore drop",
		"skill_id": "mining",
		"required_level": 10,
		"effect_type": "bonus_ore_chance",
		"effect_value": 0.08,
	},
	"mining_speed_2": {
		"name": "Rock Breaker",
		"description": "+15% mining speed",
		"skill_id": "mining",
		"required_level": 15,
		"effect_type": "mining_speed",
		"effect_value": 0.15,
	},
	"ore_sense": {
		"name": "Ore Sense",
		"description": "+12% bonus ore chance",
		"skill_id": "mining",
		"required_level": 25,
		"effect_type": "bonus_ore_chance",
		"effect_value": 0.12,
	},
	"mining_speed_3": {
		"name": "Master Miner",
		"description": "+20% mining speed",
		"skill_id": "mining",
		"required_level": 30,
		"effect_type": "mining_speed",
		"effect_value": 0.20,
	},
}

# --- Player skill state ---
# skill_id -> {category: int, xp: float, level: int, status: int, perks_unlocked: Array}
var skills: Dictionary = {}


func _ready() -> void:
	# Connect to GameServer signals for XP triggers
	GameServer.tile_mined.connect(_on_tile_mined)
	print("[SkillSystem] Initialized with %d skill definitions, %d perk definitions." % [SKILL_DEFS.size(), PERK_DEFS.size()])


## Reset all skill data (called on new game if needed).
func reset_state() -> void:
	skills.clear()


# --- XP Processing ---

## Award XP to a skill. Applies challenge multiplier based on difficulty vs skill level.
## Auto-acquires the skill if not yet active.
func award_xp(skill_id: String, base_amount: float, difficulty: int) -> void:
	if not SKILL_DEFS.has(skill_id):
		push_warning("[SkillSystem] Unknown skill_id: %s" % skill_id)
		return

	# Auto-acquire if not yet active
	_try_acquire_skill(skill_id)

	var skill_data: Dictionary = skills[skill_id]
	if skill_data["level"] >= MAX_LEVEL:
		return  # Already maxed

	var multiplier: float = _calculate_challenge_multiplier(skill_data["level"], difficulty)
	var xp_amount: float = base_amount * multiplier

	if xp_amount < 0.01:
		return  # Too trivial to bother

	skill_data["xp"] += xp_amount
	skill_xp_gained.emit(skill_id, xp_amount, skill_data["xp"])

	# Check for level-ups (loop handles multi-level gains)
	_check_level_up(skill_id)


## Calculate challenge multiplier using smooth lerp curve.
## Maps skill level (1-50) to difficulty scale (1-10) for comparison.
func _calculate_challenge_multiplier(skill_level: int, difficulty: int) -> float:
	# Convert skill level to comparable difficulty scale
	var level_equivalent: float = 1.0 + (float(skill_level) - 1.0) * 9.0 / 49.0
	var gap: float = float(difficulty) - level_equivalent

	if gap <= -3.0:
		return 0.01  # Trivial
	elif gap <= -1.0:
		return lerpf(0.01, 0.3, inverse_lerp(-3.0, -1.0, gap))
	elif gap <= 1.0:
		return lerpf(0.3, 1.0, inverse_lerp(-1.0, 1.0, gap))
	else:
		return lerpf(1.0, 1.5, clampf(inverse_lerp(1.0, 3.0, gap), 0.0, 1.0))


## Check if skill has enough XP to level up. Handles multi-level gains.
func _check_level_up(skill_id: String) -> void:
	var skill_data: Dictionary = skills[skill_id]
	while skill_data["level"] < MAX_LEVEL:
		var xp_needed: float = xp_for_level(skill_data["level"] + 1)
		if skill_data["xp"] < xp_needed:
			break
		skill_data["xp"] -= xp_needed
		skill_data["level"] += 1
		skill_leveled.emit(skill_id, skill_data["level"])
		print("[SkillSystem] %s leveled up to %d!" % [SKILL_DEFS[skill_id]["name"], skill_data["level"]])
		_check_perks(skill_id)


## Check and award any perks earned at current level.
func _check_perks(skill_id: String) -> void:
	var skill_data: Dictionary = skills[skill_id]
	var def: Dictionary = SKILL_DEFS[skill_id]
	for perk_id in def["perks"]:
		if perk_id in skill_data["perks_unlocked"]:
			continue
		var perk_def: Dictionary = PERK_DEFS[perk_id]
		if skill_data["level"] >= perk_def["required_level"]:
			skill_data["perks_unlocked"].append(perk_id)
			perk_unlocked.emit(skill_id, perk_id, skill_data["level"])
			print("[SkillSystem] Perk unlocked: %s (%s)" % [perk_def["name"], perk_def["description"]])


## XP required to reach a given level.
static func xp_for_level(level: int) -> float:
	return XP_BASE * pow(float(level), XP_EXPONENT)


# --- Auto-acquisition ---

## Initialize a skill as active if it doesn't exist yet.
func _try_acquire_skill(skill_id: String) -> void:
	if skills.has(skill_id):
		return
	var def: Dictionary = SKILL_DEFS[skill_id]
	skills[skill_id] = {
		"category": def["category"],
		"xp": 0.0,
		"level": 1,
		"status": 1,  # ACTIVE
		"perks_unlocked": [],
	}
	print("[SkillSystem] Skill acquired: %s" % def["name"])


# --- Queries ---

## Get the level of a skill. Returns 0 if not acquired.
func get_skill_level(skill_id: String) -> int:
	if not skills.has(skill_id):
		return 0
	return skills[skill_id]["level"]


## Get current XP of a skill.
func get_skill_xp(skill_id: String) -> float:
	if not skills.has(skill_id):
		return 0.0
	return skills[skill_id]["xp"]


## Get XP required for next level.
func get_xp_for_next_level(skill_id: String) -> float:
	var level: int = get_skill_level(skill_id)
	if level >= MAX_LEVEL:
		return 0.0
	return xp_for_level(level + 1)


## Get XP progress as 0.0 to 1.0 ratio.
func get_xp_progress_ratio(skill_id: String) -> float:
	var xp_needed: float = get_xp_for_next_level(skill_id)
	if xp_needed <= 0.0:
		return 1.0
	return clampf(get_skill_xp(skill_id) / xp_needed, 0.0, 1.0)


## Check if a specific perk is unlocked.
func has_perk(perk_id: String) -> bool:
	if not PERK_DEFS.has(perk_id):
		return false
	var skill_id: String = PERK_DEFS[perk_id]["skill_id"]
	if not skills.has(skill_id):
		return false
	return perk_id in skills[skill_id]["perks_unlocked"]


## Get the total effect value of all unlocked perks of a given effect type.
## Used by gameplay systems: e.g. get_total_perk_effect("mining_speed") -> 0.30
func get_total_perk_effect(effect_type: String) -> float:
	var total: float = 0.0
	for skill_id in skills:
		var skill_data: Dictionary = skills[skill_id]
		for perk_id in skill_data["perks_unlocked"]:
			if PERK_DEFS.has(perk_id):
				var perk_def: Dictionary = PERK_DEFS[perk_id]
				if perk_def["effect_type"] == effect_type:
					total += perk_def["effect_value"]
	return total


## Get all acquired skills, sorted by category.
func get_all_active_skills() -> Array:
	var result: Array = []
	for skill_id in skills:
		var skill_data: Dictionary = skills[skill_id]
		if skill_data["status"] == 1:  # ACTIVE
			var entry: Dictionary = skill_data.duplicate()
			entry["id"] = skill_id
			entry["name"] = SKILL_DEFS[skill_id]["name"]
			entry["description"] = SKILL_DEFS[skill_id]["description"]
			result.append(entry)
	return result


## Get acquired skills filtered by category.
func get_skills_by_category(category: int) -> Array:
	var result: Array = []
	for skill_id in skills:
		var skill_data: Dictionary = skills[skill_id]
		if skill_data["category"] == category and skill_data["status"] == 1:
			var entry: Dictionary = skill_data.duplicate()
			entry["id"] = skill_id
			entry["name"] = SKILL_DEFS[skill_id]["name"]
			entry["description"] = SKILL_DEFS[skill_id]["description"]
			result.append(entry)
	return result


# --- Signal Handlers ---

## Mining XP from tile_mined signal.
func _on_tile_mined(position: Vector2i, tile_type: int, _tool_used: String) -> void:
	var difficulty: int = TileDatabase.get_difficulty(tile_type)
	if difficulty <= 0:
		return  # WATER or EMPTY, no XP
	# Base XP scales with difficulty: harder tiles = more base XP
	var base_xp: float = 10.0 * float(difficulty)
	award_xp("mining", base_xp, difficulty)


# --- Serialization ---

## Get skill data for saving.
func get_save_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"skills": skills.duplicate(true),
	}


## Load skill data from save.
func load_save_data(data: Dictionary) -> void:
	if data.is_empty():
		return
	var version = data.get("version", 0)
	if version >= 1:
		skills = data.get("skills", {})
	print("[SkillSystem] Loaded %d skills from save." % skills.size())
