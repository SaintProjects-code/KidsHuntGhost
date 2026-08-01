class_name EventsData
## Authored EVENT-tile encounters + spirit TRAITS. Edit everything here —
## SpiritEventWindow just plays whatever this file describes.
##
## ── EVENT format ──────────────────────────────────────────────────────────────
##   kind:     "trainer" or "spirit" — who you meet
##   portrait: trainer events: sprite-name candidates from Assets/Trainer
##             (first file that exists wins). Spirit events: the spirit's
##             name ("" = a random wild spirit).
##   title:    short name, shown in the game log
##   desc:     one String, or an Array of Strings = multiple PAGES (the window
##             shows "Next ▶" between pages). "{lead}" = your lead spirit's
##             name, "{spirit}" = the event spirit's name.
##   options:  the choices, each:
##     label: button text
##     stat:  "atk" / "def" / "spd" / "hp_stat" — a CONTEST: your lead's stat
##            + 🎲d6  vs  the option's power + 🎲d6 (ties go to the player).
##            "luck" = pure roll-off (stat counts as 0). "" = no contest, the
##            "win" outcome just happens (safe or priced choices).
##     power: the event's contest strength (default 3).
##     win / lose: outcome dicts. Any mix of:
##       text: message ("{lead}" / "{spirit}" work here too)
##       gold: +/- N                 item: "potion" / "super_potion" /
##       damage: N (hits your lead)         "revive" / "ball" / "held_random"
##       heal: N or "full" (lead)    lose_item: true (a random bag item)
##       heal_team: true (everyone)  lose_spirit: true (a random non-lead)
##       join: true (the event spirit joins your team)
##       fight: true (battle the event spirit when the window closes)
##       battle_mod: +1 / -1 (next battle ATK blessing / curse)
##       star: true (lead gains a star)
##       trait: a key from TRAIT_DATA (a PERMANENT quirk for your lead)
##
## ── TRAITS ────────────────────────────────────────────────────────────────────
## Live on the spirit as spirit["traits"] (Array of keys) and are implemented
## in BattleScreen. "good" only affects display colour.
const TRAIT_DATA := {
	"sleepyhead":    {"name": "Sleepyhead",    "good": false, "desc": "Sleeps through round 1 of every battle"},
	"swift_soul":    {"name": "Swift Soul",    "good": true,  "desc": "Starts every battle with +3 SPD"},
	"heavy_boots":   {"name": "Heavy Boots",   "good": false, "desc": "Starts every battle with −3 SPD"},
	"brave_heart":   {"name": "Brave Heart",   "good": true,  "desc": "Starts every battle with +2 ATK"},
	"timid":         {"name": "Timid",         "good": false, "desc": "Starts every battle with −2 ATK"},
	"stone_skin":    {"name": "Stone Skin",    "good": true,  "desc": "Starts every battle with +2 DEF"},
	"brittle_bones": {"name": "Brittle Bones", "good": false, "desc": "Starts every battle with −2 DEF"},
	"cursed_wound":  {"name": "Cursed Wound",  "good": false, "desc": "Loses 3 HP at the start of each round"},
	"regrowth":      {"name": "Regrowth",      "good": true,  "desc": "Heals 3 HP at the start of each round"},
}

static func trait_of(key: String) -> Dictionary:
	return TRAIT_DATA.get(key, {"name": key, "good": false, "desc": ""})

# A spirit can carry at most this many traits.
const TRAIT_LIMIT := 2
# Traits are TEMPORARY: they wear off after this many of the owner's turns.
const TRAIT_DURATION := 4

# Turns left on a trait (for display).
static func trait_turns_left(spirit: Dictionary, key: String) -> int:
	return int(spirit.get("trait_turns", {}).get(key, TRAIT_DURATION))

# Count one turn off every trait this spirit carries and drop the expired
# ones. Returns the display names that just wore off (for the log).
static func tick_traits(spirit: Dictionary) -> Array:
	var traits: Array = spirit.get("traits", [])
	if traits.is_empty():
		return []
	var timers: Dictionary = spirit.get("trait_turns", {})
	var gone: Array = []
	for key in traits.duplicate():
		var left: int = int(timers.get(key, TRAIT_DURATION)) - 1
		if left <= 0:
			traits.erase(key)
			timers.erase(key)
			gone.append(String(trait_of(String(key))["name"]))
		else:
			timers[key] = left
	spirit["traits"] = traits
	spirit["trait_turns"] = timers
	return gone

# The ONE way to give a spirit a trait (events, dev tools, anything later).
# Enforces the limit and duplicates. At the limit, a GOOD trait pushes out a
# bad one — but a bad trait can never displace anything. Returns a message.
static func grant_trait(spirit: Dictionary, key: String) -> String:
	var info := trait_of(key)
	var traits: Array = spirit.get("traits", [])
	if traits.has(key):
		return "%s already has ✦%s." % [spirit.get("name", "?"), info["name"]]
	if traits.size() >= TRAIT_LIMIT:
		if info.get("good", false):
			for held in traits:
				var old := trait_of(String(held))
				if not old.get("good", false):
					traits.erase(held)
					traits.append(key)
					spirit["traits"] = traits
					_start_timer(spirit, key, String(held))
					return "%s shakes off ✦%s — replaced by ✦%s (%s) for %d turns!" % [
						spirit.get("name", "?"), old["name"], info["name"], info["desc"], TRAIT_DURATION]
		return "%s already carries %d traits — ✦%s doesn't stick." % [
			spirit.get("name", "?"), TRAIT_LIMIT, info["name"]]
	traits.append(key)
	spirit["traits"] = traits
	_start_timer(spirit, key)
	return "%s gains the trait ✦%s for %d turns — %s." % [
		spirit.get("name", "?"), info["name"], TRAIT_DURATION, info["desc"]]

# Start a fresh countdown on `key` (and clear a replaced trait's timer).
static func _start_timer(spirit: Dictionary, key: String, replaced: String = "") -> void:
	var timers: Dictionary = spirit.get("trait_turns", {})
	if replaced != "":
		timers.erase(replaced)
	timers[key] = TRAIT_DURATION
	spirit["trait_turns"] = timers

const EVENTS := [
	{
		"kind": "trainer", "portrait": ["hiker", "brock", "acetrainer"],
		"title": "The Toll Bridge",
		"desc": "A burly hiker blocks the bridge. \"This is MY bridge! Pay 20 gold… or prove you deserve to cross!\"",
		"options": [
			{ "label": "💪 Arm-wrestle him", "stat": "atk", "power": 4,
				"win":  {"text": "He slams the table laughing — \"STRONG!\" He pays YOU.", "gold": 30},
				"lose": {"text": "Wham! {lead}'s paw gets squashed.", "damage": 20} },
			{ "label": "💨 Dash past him", "stat": "spd", "power": 3,
				"win":  {"text": "Zoom! He never saw you. You snatch a dropped coin purse.", "gold": 15},
				"lose": {"text": "He grabs {lead} mid-dash — that ankle twist won't heal right.", "trait": "heavy_boots"} },
			{ "label": "🪙 Just pay the toll", "stat": "",
				"win":  {"text": "You pay up. He waves you through cheerfully.", "gold": -20} },
		],
	},
	{
		"kind": "spirit", "portrait": "Jigglypuff",
		"title": "Haunted Lullaby",
		"desc": [
			"A soft song drifts through the fog… A wild {spirit} is singing on a tree stump.",
			"Your eyelids feel heavy. The song is getting LOUDER. What now?",
		],
		"options": [
			{ "label": "💚 Listen politely", "stat": "hp_stat", "power": 3,
				"win":  {"text": "{spirit} loves an audience! It pats {lead}, and the nap is WONDERFUL.", "heal": "full"},
				"lose": {"text": "{lead} dozes off mid-song… and now naps at the worst times.", "trait": "sleepyhead"} },
			{ "label": "⚔ Interrupt the show", "stat": "atk", "power": 4,
				"win":  {"text": "{spirit} is furious… then impressed. It joins the tour!", "join": true},
				"lose": {"text": "{spirit} puffs up and attacks!", "fight": true} },
			{ "label": "💨 Cover your ears and run", "stat": "spd", "power": 3,
				"win":  {"text": "You escape with your ears — and find a Potion a fleeing camper dropped.", "item": "potion"},
				"lose": {"text": "Too slow — the last verse catches {lead}.", "trait": "sleepyhead"} },
		],
	},
	{
		"kind": "trainer", "portrait": ["gambler", "gentleman", "acetrainer"],
		"title": "High-Stakes Dice",
		"desc": "A grinning gambler rattles a dice cup. \"Double or nothing, kid. 25 gold says my roll beats yours.\"",
		"options": [
			{ "label": "🎲 Take the bet", "stat": "luck", "power": 0,
				"win":  {"text": "You roll high! He pays up through gritted teeth.", "gold": 40},
				"lose": {"text": "He cackles and scoops your coins.", "gold": -25} },
			{ "label": "🚶 Walk away", "stat": "",
				"win":  {"text": "You keep your gold. He boos loudly."} },
		],
	},
	{
		"kind": "spirit", "portrait": "Gastly",
		"title": "The Old Shrine",
		"desc": [
			"Deep in the woods you find a crumbling shrine. Something cold brushes the back of your neck…",
			"A {spirit} seeps out of the stones, guarding the offering bowl. Your team shivers.",
		],
		"options": [
			{ "label": "🛡 Stand firm and pray", "stat": "def", "power": 3,
				"win":  {"text": "The shrine approves. Stone-grey light wraps {lead} like armor.", "trait": "stone_skin"},
				"lose": {"text": "Icy fingers close around {lead}… the chill never quite leaves.", "trait": "cursed_wound"} },
			{ "label": "⚔ Drive it off", "stat": "atk", "power": 4,
				"win":  {"text": "{spirit} flees! A star falls from the offering bowl into {lead}'s paws.", "star": true},
				"lose": {"text": "{spirit} grins wide — battle!", "fight": true} },
			{ "label": "💨 Back away slowly", "stat": "",
				"win":  {"text": "You leave the shrine in peace. Nothing follows. Probably."} },
		],
	},
	{
		"kind": "spirit", "portrait": "Rattata",
		"title": "Berry Thief",
		"desc": "A purple blur! A wild {spirit} has its teeth in your bag and it is NOT letting go.",
		"options": [
			{ "label": "💨 Chase it down", "stat": "spd", "power": 4,
				"win":  {"text": "Caught it! It surrenders the bag — plus a Potion and 10 gold from its cheeks.", "gold": 10, "item": "potion"},
				"lose": {"text": "It vanishes into the grass with a prize.", "lose_item": true} },
			{ "label": "⚔ Roar at it", "stat": "atk", "power": 3,
				"win":  {"text": "It drops everything — including loot it stole from someone else!", "gold": 20},
				"lose": {"text": "It bites {lead}'s nose and keeps the bag. Ow.", "damage": 15} },
			{ "label": "💚 Offer it a snack", "stat": "hp_stat", "power": 3,
				"win":  {"text": "It munches, blinks… and climbs onto {lead}'s head. New friend!", "join": true},
				"lose": {"text": "It takes the snack AND some coins.", "gold": -10} },
		],
	},
	{
		"kind": "spirit", "portrait": "Snorlax",
		"title": "Napping Giant",
		"desc": "A {spirit} is asleep across the whole road. The ground rumbles with every snore.",
		"options": [
			{ "label": "⚔ Shove it awake", "stat": "atk", "power": 5,
				"win":  {"text": "It blinks, chuckles, and pats {lead} flat. Respect earned!", "trait": "brave_heart"},
				"lose": {"text": "It rolls over. Onto you.", "damage": 25} },
			{ "label": "💚 Join the nap", "stat": "hp_stat", "power": 3,
				"win":  {"text": "Best. Nap. Ever. {lead} wakes up feeling like it could regrow a tail.", "trait": "regrowth"},
				"lose": {"text": "{lead} oversleeps HARD… and picks up the habit.", "trait": "sleepyhead"} },
			{ "label": "💨 Tiptoe around it", "stat": "spd", "power": 3,
				"win":  {"text": "You slip past — and find 15 gold stuck in its fur.", "gold": 15},
				"lose": {"text": "You step on its tail. It is NOT happy.", "fight": true} },
		],
	},
	{
		"kind": "trainer", "portrait": ["blue", "gary", "acetrainer-gen1"],
		"title": "Rival Roast",
		"desc": "\"Smell ya later — oh wait, you're still here?\" A rival trainer starts roasting {lead} in front of everyone.",
		"options": [
			{ "label": "⚔ Challenge him!", "stat": "",
				"win":  {"text": "\"Finally, some action!\" He sends out his spirit!", "fight": true} },
			{ "label": "🛡 Let it wash over you", "stat": "def", "power": 3,
				"win":  {"text": "{lead} doesn't even blink. The crowd's cheers pump your team up!", "battle_mod": 1},
				"lose": {"text": "{lead} takes it personally…", "trait": "timid"} },
			{ "label": "💨 Fire back a comeback", "stat": "spd", "power": 4,
				"win":  {"text": "Your comeback is LEGENDARY. He pays 20 gold to make you stop.", "gold": 20},
				"lose": {"text": "The comeback dies in your throat. {lead} cringes.", "trait": "timid"} },
		],
	},
	{
		"kind": "spirit", "portrait": "Chansey",
		"title": "The Hidden Spring",
		"desc": [
			"You hear water… a hidden spring glitters in a mossy grove. A {spirit} seems to be its keeper.",
			"The water sparkles invitingly. {spirit} watches you very closely.",
		],
		"options": [
			{ "label": "💚 Ask to bathe", "stat": "hp_stat", "power": 2,
				"win":  {"text": "{spirit} beams! The whole team soaks — everyone fully healed!", "heal_team": true},
				"lose": {"text": "{spirit} shoos you off, and you drop your pouch in the mud.", "gold": -10} },
			{ "label": "🫙 Sneak a bottleful", "stat": "spd", "power": 3,
				"win":  {"text": "Got it — it fizzes like a Super Potion!", "item": "super_potion"},
				"lose": {"text": "{spirit} catches you mid-scoop. SLAP.", "damage": 15} },
			{ "label": "⚔ Take the spring gem", "stat": "atk", "power": 5,
				"win":  {"text": "You pry the gem loose — it's worth a fortune!", "gold": 50},
				"lose": {"text": "{spirit}'s SLAP sends you flying. And now it's mad.", "fight": true} },
		],
	},
	{
		"kind": "spirit", "portrait": "Onix",
		"title": "Cave-In!",
		"desc": "The tunnel shakes — an {spirit} crashes through the ceiling! Rocks rain down everywhere.",
		"options": [
			{ "label": "🛡 Shield the team", "stat": "def", "power": 4,
				"win":  {"text": "{lead} holds the rubble off everyone. What a wall!", "trait": "stone_skin"},
				"lose": {"text": "A rock clips {lead} hard.", "damage": 25} },
			{ "label": "💨 Sprint for daylight", "stat": "spd", "power": 4,
				"win":  {"text": "You outrun the collapse — {lead}'s legs feel springier than ever!", "trait": "swift_soul"},
				"lose": {"text": "{lead} gets clipped and limps out.", "trait": "brittle_bones"} },
			{ "label": "⚔ Punch through the rocks", "stat": "atk", "power": 4,
				"win":  {"text": "Smash! Inside the rubble: someone's lost coin stash.", "gold": 30},
				"lose": {"text": "The rocks win. Ow. And your pouch tore.", "damage": 15, "gold": -10} },
		],
	},
	{
		"kind": "spirit", "portrait": "@legendary", "min_badges": 2,  # gated behind 2+ badges
		"title": "A Legend Stirs",
		"desc": [
			"The air crackles with ancient power. Something LEGENDARY has awoken…",
			"A wild {spirit} — a legendary spirit — appears before {lead}! This may be your only chance.",
		],
		"options": [
			{ "label": "💚 Earn its respect", "stat": "hp_stat", "power": 5,
				"win":  {"text": "{spirit} judges {lead} worthy — the legend joins you!", "join": true},
				"lose": {"text": "{spirit} deems you unready and vanishes in a flash of light."} },
			{ "label": "⚔ Prove your strength", "stat": "atk", "power": 6,
				"win":  {"text": "An epic clash — {spirit} bows to your power and joins your team!", "join": true},
				"lose": {"text": "The legend's might is overwhelming — battle!", "fight": true} },
			{ "label": "🎲 Reach out to it", "stat": "luck", "power": 0,
				"win":  {"text": "Against all odds, {spirit} takes a shine to {lead} and joins!", "join": true},
				"lose": {"text": "{spirit} slips away into legend once more."} },
		],
	},
	{
		"kind": "trainer", "portrait": ["rocketgrunt", "rocket", "teamrocketgrunt", "acetrainer"],
		"title": "The Mystery Box",
		"desc": "A shady merchant flips open his coat. \"Psst. Mystery box. 25 gold. Could be ANYTHING in there.\"",
		"options": [
			{ "label": "🪙 Buy the box", "stat": "luck", "power": 0,
				"win":  {"text": "Inside: a genuine battle item! Jackpot!", "gold": -25, "item": "held_random"},
				"lose": {"text": "Inside: a rock. A very ordinary rock.", "gold": -25} },
			{ "label": "⚔ Shake him down", "stat": "atk", "power": 4,
				"win":  {"text": "A Revive falls out of his sleeve. \"T-take it and go!\"", "item": "revive"},
				"lose": {"text": "He mutters a hex as he scurries off… {lead} feels jittery.", "trait": "timid"} },
			{ "label": "🚶 Not today", "stat": "",
				"win":  {"text": "He shrugs. \"Your loss, kid.\""} },
		],
	},
]
