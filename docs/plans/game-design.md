# This Goblin's World - Game Design Document

**Working Title:** This Goblin's World
**Engine:** Godot 4 (GDScript)
**Genre:** 2D side-view exploration / mining / building / combat adventure
**Art Style:** 16-bit (SNES era) pixel art, 16x16 or 32x32 tiles, character sprites ~32x48
**Platform:** PC (Steam target)
**Players:** Single-player first, multiplayer-ready architecture for future co-op

---

## Core Pillars

1. **Exploration** - Terraria-style open world, procedurally generated with structured biomes. Multiple realms as late-game content, unlocked via portals to new dimensions. These are destinations to explore, not colonies to manage.

2. **Combat** - Hollow Knight inspired, skill-based with depth. Dodging, abilities, enemy pattern recognition. More involved than Terraria's combat.

3. **Mining / Resource Gathering** - Dig deep, find ores, discover secrets and hidden areas. The core gameplay loop that ties exploration to progression.

4. **Building** - Base building with optional automation following the Minecraft modded philosophy: encouraged but never required. Outposts can be established in any realm.

5. **Discovery** - Hidden areas, secrets, lore, rare finds. Exploration-driven progression rewards curiosity.

---

## Game Loop

### Minute-to-Minute
The core loop the player repeats constantly:
1. **Explore/Mine** - Dig into caves, discover new areas, fight enemies encountered along the way
2. **Collect** - Gather ores, find rare loot, uncover secrets and lore
3. **Return when ready** - No timers, no urgency. The player decides when to head back
4. **Build/Craft/Upgrade** - Improve gear, expand the base, craft new items, set up automation
5. **Go deeper/further** - New tier of content beckons, repeat

The player is never punished for exploring too long. The world does not degrade or attack aggressively while they are away.

### Session-to-Session
Medium-term goals that drive a play session:
- "I need to find enough ore to craft the next pickaxe tier"
- "I want to reach that biome I glimpsed at the edge of the caves"
- "I'm going to fight the boss I've been preparing for"
- "I want to set up automation for my iron supply"
- "I need to explore the new realm I just unlocked"

### Long-Term Progression Arc
The journey from start to credits:
- Ore tiers gate deeper mining (need better pickaxe to mine harder materials)
- Bosses gate major milestones (defeating a boss evolves the world or unlocks new biomes/realms)
- Key items and abilities unlock new traversal options (wall climb, lava immunity, realm portals)
- The chicken conspiracy breadcrumbs build throughout, culminating in a final revelation
- After the "ending," the world persists for continued sandbox play

---

## Progression System

### Gating Model
Progression uses a combination of three gating types, similar to Terraria:

1. **Resource Gates** - Higher tier ores require better tools to mine. Finding new materials unlocks new crafting recipes.
2. **Boss Gates** - Major bosses mark progression milestones. Defeating them transforms the world, unlocks new biomes, or opens access to new realms. Bosses are sought out by the player, not forced.
3. **Ability Gates** - Key traversal abilities discovered through exploration open previously inaccessible areas (think Hollow Knight's dash, wall jump, double jump).

### How the Player Gets Stronger
- **Gear tiers** - Mining better ores → crafting better weapons/armor/tools
- **Ability unlocks** - Found through exploration, permanently expand movement/combat options
- **Crafting progression** - New stations unlock new recipe categories
- **Optional automation** - Frees the player from repetitive gathering to focus on exploration and combat

---

## Skill System

### Learn by Doing
There are no skill point menus, no character creation choices. The goblin becomes what the player does. Swing a sword for 40 hours and you're a swordsman. Cast spells all game and you're a mage. Mine obsessively and you're a master miner.

Every skill levels up independently through use. There are no hard locks - skills enhance and improve what you can already do, they don't gate access.

### Soft Cap by Environment
Skill progression is tied to the challenge level of what you're doing:
- Mining basic stone at skill level 50? Barely any XP. You've outgrown it.
- Mining iron at skill level 50? Good XP. Appropriate challenge.
- Mining crystal at skill level 50? Great XP. Pushing your limits.
- Fighting cave bats at combat level 80? Basically zero progression.
- Fighting deep realm enemies at combat level 80? Meaningful gains.

You cannot grind to max level in the starter caves. The world's difficulty IS the progression gate. Higher levels require exponentially more challenging content, eventually requiring millions of trivial actions to gain a level - or appropriate-challenge content for reasonable progression.

### Skills Are Perks, Not Requirements
Nothing is locked behind "need level X." Skills make you more efficient, more effective, and occasionally unlock bonus perks at milestones:
- A level 1 goblin can swing any sword. A level 50 swordsman swings faster, hits harder, and has unlocked a special move.
- A level 1 goblin can mine anything their pickaxe allows. A level 50 miner is faster, more efficient, and occasionally finds bonus ore.
- A level 1 goblin can cast a spell the moment they find it. A level 50 mage casts cheaper, faster, and with wider effect.

Perks at milestones are bonus rewards - nice to have, never required.

### Skill Categories
Broadly split into combat and life skills (specific trees to be designed):

**Combat skills** (leveled by fighting):
- Melee (swords, hammers, axes, etc.)
- Magic (offensive, defensive, utility)
- Stealth/Rogue (daggers, traps, evasion)
- Defense (blocking, armor proficiency, damage reduction)

**Life skills** (leveled by doing):
- Mining (speed, efficiency, bonus yields)
- Smithing (weapon/armor/tool crafting quality)
- Alchemy (potions, enchantments)
- Engineering (automation, machines, traps)
- Construction (building speed, structural integrity, defense quality)
- Survival (cooking, healing, environmental resistance)

### Relics and Training
Perks are not chosen from a menu - they are discovered in the world:

**Relics:** Found in hidden rooms, boss drops, ancient ruins, and locked chests. Each grants a permanent ability or enhancement. "You find a strange glowing stone... your pickaxe swings feel lighter." Some relics bear suspicious chicken motifs, feeding the conspiracy.

**NPC Training:** Seek out masters hidden in the world. A master swordsman teaches a combat technique. A village elder shows how to brew a new potion. A hermit engineer demonstrates auto-miner construction. Training may cost resources, time, or completing a task.

Relics and training are separate from the class system - they stack on top of whatever class build the player has chosen.

### Multiplayer Synergy
Because you can't realistically max everything, co-op players naturally complement each other. A warrior goblin and a crafter goblin working together are more effective than either alone. This is the "optional but beneficial" multiplayer philosophy built into the character system.

---

## Class System

### Start Classless
The goblin begins with nothing - no class, no identity, just a scared creature with a dead miner's pickaxe. The early game is pure survival. RPG systems layer in naturally as the player settles into a playstyle.

### Classes Are Earned, Not Chosen
The game watches what the player does. Behind the scenes, it tracks behaviors and conditions. When thresholds are met, a class is **offered** - never forced. The player's first class offer is a milestone moment: the game recognizing "you've become something."

### Class Rarity
Rarity reflects how difficult a class is to unlock:

- **Common:** Simple to unlock through basic activity. Swordsman (swing swords), Miner (mine ore), Healer (use healing items). Just do the thing.
- **Uncommon:** Requires combining behaviors. Warrior (fight + take lots of damage), Scrappy Mechanic (craft + repair + improvise).
- **Rare:** Requires extreme or unusual behaviors. Berserker (nearly die 100 times while fighting), Flame Walker (survive repeated fire damage).
- **Epic/Legendary:** Knowledge-found, quest-gated, or absurdly specific requirements. Secret classes the community discovers and shares. Perhaps one with suspicious chicken connections.

### Behavior-Unlocked Classes
Emerge naturally from how the player plays:
- Spend hours swinging swords → Swordsman offered
- Swing swords AND absorb lots of damage → Warrior offered
- Cast fire spells AND survive lava → Flame Adept offered
- Mine obsessively AND rarely fight → Deep Delver offered
- Use stealth AND poison → Shadow Blade offered

### Knowledge-Unlocked Classes
Discovered through exploration and NPCs:
- Find an ancient tome describing "The Crystal Warden" → requirements revealed: mine 500 crystal, survive the deep realm, defeat a crystal enemy bare-handed
- An NPC mentions a legendary "Beast Tamer" → quest chain to unlock
- Some knowledge is hidden in ruins, some traded by NPCs, some pieced together from lore fragments

### Two Class Slots
- Main class + secondary class
- They can complement (Berserker + Flame Walker) or diversify (Swordsman + Engineer)
- Hints of a third slot as endgame or sequel content

### Class Skills
Each class has a skill pool of active and passive skills (roughly 2-3 active + 2-3 passive slots available, with more skills in the pool than can be slotted at once, tuned through playtesting):
- Skills are **unlocked permanently** into the class's skill pool when conditions are met - leveling the class, having other skills at certain levels, or specific in-game actions
- The player chooses which unlocked skills to **slot** into their limited active and passive slots. Not every skill fits at once - choices must be made.
- Skills can be **swapped freely** at any time, but slotting in a new skill resets that skill's progress to zero - it must be leveled up again through use. The old skill retains its progress in the pool and can be slotted back later at full strength.
- The skill pool itself becomes a collection: unlocking more skills gives more strategic flexibility, even if you can only use a few at a time.
- Tension comes from **investment**: "which skills do I pour time into leveling?" rather than a binary take-or-leave decision.
- Skills within a class are influenced by HOW you played that class. A Berserker who fights with hammers unlocks different skills than a Berserker who uses fists.
- Active skills are usable abilities in combat/gameplay. Passive skills are always-on enhancements.

### Swapping Classes
- A class can be changed when a new class is offered and the player accepts it as a replacement
- Swapping resets that class slot to zero - all progress and skills from the old class are lost
- This makes class choice meaningful: switching has a real cost
- Encourages commitment while still allowing course correction

### The Full Character Identity Stack
Four layers, all earned through play:
1. **Skills (learn by doing)** - Gradual passive improvement, always happening
2. **Classes (behavior/knowledge unlocked)** - Two slots, shape the goblin's identity
3. **Class skills (unlocked into skill pool, slotted by choice)** - Active and passive abilities unique to each class, swappable but requiring investment to level
4. **Relics and training (found/given)** - Permanent perks from exploration and NPCs, independent of class

---

## Base Defense

### Philosophy
Base defense exists to give building purpose and create occasional excitement, NOT to punish exploration or create constant urgency. The player should never feel anxious about being away from base.

### Immediate but Simple
- Basic defenses (wooden walls, doors, simple barricades) are available from the start of the game
- Even crude defenses are effective against early-game threats
- This teaches the player that building has defensive value without overwhelming them

### Opt-In Escalation
The player's actions trigger escalation, never a timer:
- **Mining rare ore veins** awakens something nearby
- **Breaking seals in dungeons** sends enemies toward the surface
- **Killing major bosses** causes a world response ("the depths are angry")
- **Activating realm portals** draws attention from hostile forces

A player who wants to chill and build stays relatively safe. A player pushing progression gets the intensity they're looking for.

### Scaling with Progression
- **Early game:** Wooden walls/doors keep out basic critters. Minimal threat - serves as a building tutorial
- **Mid game:** Stronger enemies appear, but stone/metal walls and basic traps handle them. Occasional events test defenses
- **Late game:** Breaching new realms or defeating major bosses triggers retaliations and real sieges, but the player has powerful tools and defenses to match

### Key Rules
- The player's progression triggers escalation, never a timer
- The base can survive without the player present for minor threats
- Major events are telegraphed well in advance ("the ground is rumbling...")
- No coming home to a destroyed base. At worst: cosmetic damage, some stolen resources
- Defenses are functional and meaningful, not just decorative

---

## Narrative and Identity

### The Opening
The goblin discovers something curious - a strange mine entrance, a glowing cave, an unusual structure. Curiosity takes over. They go in. Something goes wrong. A collapse, a fall into a deep pit. The goblin wakes up injured and scared at the bottom of a cavern. They can sense the way out is above, but it's impossibly far.

Nearby: the remains of a dead miner, a pickaxe, some basic supplies. Ahead: an obstruction between the goblin and the only path forward. There is no choice but to pick up the pickaxe and dig.

### The Day-1 Driver
1. **Immediate (first minutes):** Survive. You're trapped, injured, with nothing but a dead miner's pickaxe. Find shelter, find food, stay alive.
2. **Short-term (first sessions):** Find a way out. Mine through obstacles, build a shelter, explore for any path upward.
3. **Mid-term (the shift):** "Getting out" quietly becomes "understanding this place." The underground world is too vast, too interesting, too rewarding to rush through. The goal doesn't disappear - it recedes.
4. **Long-term (the arc):** Unravel the mysteries of the deep. Defeat what lurks below. Gain the power and knowledge to finally escape.
5. **Endgame (the revelation):** The goblin finally has the means to return home - but now knows the truth about the chickens. Credits roll. The sequel begins.

### The Chicken Conspiracy
Throughout the game, chickens appear where they shouldn't:
- Deep underground, standing calmly in dangerous caverns
- In other realms, seemingly unbothered by alien environments
- Near ancient carvings and artifacts that bear suspicious chicken-shaped motifs
- NPCs mention the oddity but dismiss it: "Those chickens are weird, right? Anyway..."
- Chicken footprints lead to sealed doors the player can't open yet

This is treated as flavor and curiosity for most of the game. Players who pay attention will piece together that something is deeply wrong. The endgame revelation confirms it: chickens have been orchestrating everything. This directly sets up "Dungeon Chicken," where the goblin - now home and armed with the truth - is conscripted as an agent of the chicken overlords.

### Tone
Dark comedy with heart. The premise is absurdist (goblin trapped underground, chickens secretly ruling the world) but played with enough sincerity that the world feels real and the goblin's journey feels earned. Think Dungeon Keeper's humor meets Hollow Knight's atmosphere.

### Starting Underground
The game begins below the surface. The player's first experience is dark, confined, and tense. The surface is not the default - it's a reward. When the player finally breaks through to open sky, it should feel like a genuine achievement and a dramatic shift in the game's scope and tone.

---

## World Structure

### Underground (Starting Area)
The game begins here. Layered cave systems with increasing danger and reward the deeper you go. Early areas are relatively safe - basic ores, minor enemies, simple navigation. Deeper layers introduce harder materials, dangerous creatures, environmental hazards, and increasingly strange chicken sightings.

### The Surface
Reached through upward exploration - not available at game start. Breaking through to the surface is a milestone moment. The overworld is procedurally generated with biomes (forests, mountains, deserts, coastlines). It provides new resources, different enemies, building space for a proper base, and access to new underground biomes beneath different surface regions.

### The Deep Realm
Far below the starting caves. Alien, crystalline, wrong-feeling. The rules change here - new physics, new threats, high-value resources. This is late-game content that rewards players who push past the comfortable depths.

### Additional Realms
Unlocked through progression via portals found or constructed. Each realm has unique biomes, resources, enemies, and chicken conspiracy clues. These are destinations for exploration, not colonies to manage. Think Terraria's Underworld/Hallow or Minecraft's Nether/End. Realms serve as natural content expansion points for future updates.

### Outposts
The player can build outposts anywhere - underground, on the surface, in other realms. These serve as fast travel points, storage, and forward operating bases. Not required, but rewarding for players who invest in infrastructure.

---

## Combat System

Combat draws from Hollow Knight's philosophy: skill-based, pattern-recognition gameplay where the player improves through learning, not just through gear.

- **Dodge/roll mechanics** with invincibility frames. Positioning matters.
- **Multiple weapon types** with distinct movesets. A sword doesn't play like a hammer doesn't play like a spear.
- **Abilities and skills** that unlock through progression. These expand the combat vocabulary over time.
- **Boss encounters** gate major progression points. Each boss teaches the player something and tests a specific skill set.
- **Enemy variety per biome** with unique behaviors. Surface enemies are different from cave dwellers are different from deep realm horrors.

Combat should feel tight and responsive. The goblin is small and fast. Use that.

---

## Crafting System

### Station-Based and Gated
All meaningful crafting requires a station. Stations are the primary gate for what you can craft:
- **Hand-crafting:** Limited to survival basics - torches, crude bandages, campfires, simple tools. Available immediately.
- **Stations gate recipe categories:** Workbench for basic items, furnace for smelting, anvil for weapons/armor, alchemy table for potions, engineering bench for automation components.
- **Station progression chain:** Higher-tier stations require materials and lower-tier stations to build. The anvil needs smelted iron, which needs a furnace, which needs a workbench to build.

### Crafting Quality
The same recipe can produce different quality results. Quality is determined by a weighted random roll influenced by three factors:

**Skill level (base chance):** Higher crafting skill shifts the probability curve toward better quality tiers.

**Station and tool quality:** A crude stone anvil holds you back. A masterwork steel anvil with fine tools pushes the curve up. Crafting stations aren't just "have it or don't" - they have their own quality that matters.

**Material difficulty:** Different materials are harder to work with. Iron is forgiving. Mithril is not. The same smith producing Fine quality iron gear might only manage Standard quality mithril. Material difficulty shifts what quality tiers are realistically reachable.

### Quality Tiers
Six tiers from worst to best:
1. **Crude** - Poorly made. Lower stats, less durability.
2. **Standard** - Base stats. What the recipe promises.
3. **Fine** - Above average. Bonus stats, better durability.
4. **Masterwork** - Exceptional. Significant stat bonuses, may have a perk slot.
5. **Legendary** - Near-perfect craft. Powerful bonuses and perks.
6. **Ancient** - The pinnacle. Requires mastery of skill, top-tier station, fine tools, and favorable odds. These feel mythical.

### Material Efficiency
Crafting skill also affects how many materials you use:
- **Low skill:** Recipe calls for 5 iron bars, you waste materials and need 7.
- **Average skill:** You use the listed amount.
- **High skill:** Efficient crafting, only need 4. Occasionally salvage scraps back.

### Interesting Player Choices
The quality system creates meaningful decisions:
- "Do I craft a Fine iron sword now, or a Crude mithril sword? Which is actually better?"
- A well-crafted lower-tier material can outperform a poorly-crafted higher-tier material.
- Players who invest in crafting skills extract more value from rare materials.
- Recrafting old items with improved skill feels rewarding, not wasteful.

### The Crafting Endgame
Reaching the highest quality tiers isn't just about skill level. It's about building the perfect workshop:
- Max out the relevant crafting skill
- Build top-tier stations
- Craft or find the best tools
- Work with the rarest materials
- And still get a favorable roll

This gives base building deep purpose and creates a satisfying long-term crafting progression.

## Building and Automation

### Building
- Terraria-style block placement for structures
- Background wall layer for enclosed rooms
- Functional furniture: crafting stations, storage chests, doors, lighting
- Building has defensive purpose (see Base Defense)
- Outposts can be built anywhere across all realms

### Automation (Optional)
- Conveyor belts, auto-miners, sorting systems, processing chains
- Machines need fuel or power sources
- Philosophy: rewarding to set up, never required to progress
- Frees the player from repetitive gathering to focus on exploration and combat
- Ties into the Engineering skill - higher skill means more efficient machines

---

## Economy and Trade

### Philosophy
Crafting is the core of progression. Trade exists as a supplementary layer that rewards exploration and gives excess resources purpose, but the player can never buy their way past crafting.

### Crafting is King
- All gear, tools, weapons, building materials, and automation components are crafted from mined/gathered resources
- Crafting progression is tied to discovering new materials and unlocking new crafting stations
- This is the primary economy of the game and never changes

### Trade as Discovery
NPCs and civilizations are found through exploration, not summoned or attracted:
- A lone goblin survivor camped in a cave
- A mushroom village of strange underground creatures
- An ancient civilization in the deep realm that has been there for millennia
- Merchants in other realms with exotic goods
- Each discovery is a moment - "I'm not alone down here"

### What Trade Offers
Trade provides things the player cannot craft:
- Unique items and blueprints unavailable through crafting
- Lore books and maps that reveal secrets and hidden areas
- Cosmetics and decorations for building
- Specialty goods unique to each civilization's culture
- Hints and clues about the chicken conspiracy
- The occasional peculiar egg from a suspicious merchant...

### Currency
- A universal currency (gold/coins found through mining and selling excess resources) handles common trades
- Barter for rare/unique items - civilizations want specific resources in exchange for their best goods
- This keeps trade simple while giving each civilization a distinct identity

### Open Questions
- Whether NPCs can move into the player's base or remain in their own settlements (to be determined - want to differ from Terraria's approach)
- Depth of NPC relationships (simple merchants vs quest givers vs allies)
- Whether civilizations have faction reputation systems

---

## Multiplayer Architecture

### Design Principles

All systems are designed with a client-server model from day one. This doesn't mean multiplayer ships on day one; it means the architecture doesn't need to be rewritten to support it later.

### Rollout Plan

- **Phase 1:** Ship single-player with multiplayer-ready architecture under the hood.
- **Phase 2:** Add drop-in/drop-out co-op multiplayer.

### Multiplayer Philosophy

"Optional but beneficial." The game is complete as a solo experience. Playing with friends makes it more fun, not easier. Same world, shared progression when playing together. No content is gated behind multiplayer.

---

## Development Phases

| Phase | Focus | Description |
|-------|-------|-------------|
| 1 | **Foundation** | Core movement, basic mining/block placement, tilemap system, world generation prototype |
| 2 | **Combat Core** | Player combat mechanics, basic enemy AI, weapon system |
| 3 | **World Gen** | Biome generation, cave systems, ore distribution, structure placement |
| 4 | **Building** | Base building, crafting system, furniture and stations |
| 5 | **Content** | Enemies, items, biomes, bosses, lore and chicken conspiracy elements |
| 6 | **Automation** | Optional automation systems |
| 7 | **Realms** | Portal system, additional dimensions |
| 8 | **Multiplayer** | Networking layer, co-op support |
| 9 | **Polish** | UI, sound, music, tutorials, Steam integration |

---

## Art Production

- 16-bit pixel art keeps asset creation manageable for a small team or solo dev.
- Tile-based world allows heavy reuse and variation through palette swaps and modular pieces.
- Character sprites at ~32x48 provide enough detail for combat readability. The player needs to read enemy wind-ups and attack patterns clearly.
- AI tools can assist with base sprite generation for rapid iteration, with manual cleanup and refinement for final assets.

---

## References

| Game | What We Take From It |
|------|---------------------|
| **Terraria** | World structure, building, exploration scope |
| **Hollow Knight** | Combat depth, discovery, world atmosphere |
| **Dome Keeper / Wall World** | Mining loop feel, tension |
| **Craft the World** | Base building with personality |
| **Minecraft (modded)** | Automation philosophy - optional but rewarding |
