class_name EventsData
## Authored EVENT-tile encounters + spirit TRAITS. Edit everything here —
## SpiritEventWindow just plays whatever this file describes.
##
## ── EVENT format ──────────────────────────────────────────────────────────────
##   kind:     "trainer" or "spirit" — who you meet
##   portrait: trainer events: sprite candidates from Assets/Trainer. Spirit
##             events: the spirit's name ("" = random, "@legendary" = a legend)
##   title:    short name, shown in the game log
##   min_badges: (optional) only drawn once you have this many badges
##   desc:     one String, or an Array of Strings = pages ("Next ▶" between).
##             "{lead}" = your lead spirit, "{spirit}" = the event spirit.
##   options:  the choices. Your LEAD spirit always takes the challenge:
##     label:  button text
##     stat:   "atk" / "def" / "spd" / "hp_stat" — a CONTEST: your lead's stat
##             + 🎲d6 vs the option's power + 🎲d6 (ties go to you). "luck" =
##             pure roll-off. "" = no contest, the win outcome just happens.
##     power:  the event's strength (default 3)
##     type_bonus: {"Fire": 2} — extra points if your lead is that type
##     cost:   gold paid up front (the option is locked if you can't pay)
##     need_card: a card key — only offered if you hold it; spends it and
##             wins automatically
##     win / lose: outcome dicts. Any mix of:
##       text   message                   gold     +/- N
##       damage N to your lead             heal     N or "full" (lead)
##       heal_team true                    join     true (the spirit joins you)
##       fight  true (battle it after)     battle_mod +1 / -1 (next battle ATK)
##       star   true (lead gains a star)   trait    a TRAIT_DATA key
##       card   "random"/"field"/"tactic"/"charm" or a card key
##       lanterns N Spirit Lanterns (−1 = lose one)   lose_card true (a random hand card)
##       lose_spirit true (a random non-lead runs off)
##       next   {desc, options} — the story continues (push-your-luck!)
##
## ── TRAITS ────────────────────────────────────────────────────────────────────
## Live on the spirit as spirit["traits"] (Array of keys) and are implemented
## in BattleRules. They wear off after TRAIT_DURATION turns. "good" only
## affects display colour.
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
		"kind": "trainer", "portrait": ["hiker", "acetrainer"],
		"title": "The Toll Bridge",
		"desc": "A see-through hiker blocks the old rope bridge. \"Nobody crosses MY bridge! Pay 20 gold… or prove you deserve to!\"",
		"options": [
			{ "label": "💪 Arm-wrestle the ghost", "stat": "atk", "power": 4, "type_bonus": {"Fighting": 2},
				"win":  {"text": "His hand goes right through yours… but he respects the effort. He pays YOU.", "gold": 30},
				"lose": {"text": "Wham! {lead}'s paw gets squashed.", "damage": 20} },
			{ "label": "💨 Dash past him", "stat": "spd", "power": 3,
				"win":  {"text": "Zoom! He never saw you. You snatch a dropped coin purse.", "gold": 15},
				"lose": {"text": "He grabs {lead} mid-dash and flings you back down the road!", "trait": "heavy_boots", "move": -3} },
			{ "label": "🪙 Pay the toll", "stat": "", "cost": 20,
				"win":  {"text": "He waves you through and tosses you something for being polite.", "card": "field"} },
		],
	},
	{
		"kind": "spirit", "portrait": "Lullaboo",
		"title": "Haunted Lullaby",
		"desc": [
			"A soft song drifts through the fog… a wild {spirit} is singing on a tree stump.",
			"Your eyelids feel heavy. The song is getting LOUDER. What now?",
		],
		"options": [
			{ "label": "💚 Listen politely", "stat": "hp_stat", "power": 3,
				"win":  {"text": "{spirit} loves an audience! The nap is WONDERFUL.", "heal_team": true},
				"lose": {"text": "{lead} dozes off mid-song… and now naps at the worst times.", "trait": "sleepyhead"} },
			{ "label": "🎤 Sing along!", "stat": "luck",
				"win":  {"text": "A perfect duet! {spirit} joins the tour!", "join": true},
				"lose": {"text": "OFF-KEY! The cursed song echoes across the whole valley…", "all_trait": "sleepyhead"} },
			{ "label": "💨 Cover your ears and run", "stat": "spd", "power": 3,
				"win":  {"text": "You escape — and find a tonic a fleeing camper dropped.", "card": "glow_tonic"},
				"lose": {"text": "Too slow — the last verse catches {lead}.", "trait": "sleepyhead"} },
		],
	},
	{
		"kind": "trainer", "portrait": ["gambler", "gentleman", "acetrainer"],
		"title": "Skeleton's Dice",
		"desc": "A grinning skeleton rattles a dice cup. \"Double or nothing, kid. 15 gold says my roll beats yours.\"",
		"options": [
			{ "label": "🎲 Take the bet (15g)", "stat": "luck", "cost": 15,
				"win":  {"text": "You roll high! He rattles angrily and pays up.", "gold": 30, "next": {
					"desc": "\"Again! DOUBLE again!\" He slaps 60 gold on the table. Your heart pounds…",
					"options": [
						{ "label": "🎲 Let it ride!", "stat": "luck",
							"win":  {"text": "JACKPOT! His jaw falls off — and every player chips in to the pot!", "gold": 40, "gold_from_all": 15},
							"lose": {"text": "Snake eyes. He scoops up everything you just won.", "gold": -30} },
						{ "label": "🚶 Quit while you're ahead", "stat": "",
							"win":  {"text": "Smart. You jingle your winnings all the way down the road."} },
					]}},
				"lose": {"text": "He cackles and scoops your coins." } },
			{ "label": "🃏 Bet a card instead", "stat": "luck", "need_card": "lucky_coin",
				"win":  {"text": "He can't resist a Lucky Coin. He hands over a real prize.", "card": "tactic", "gold": 25} },
			{ "label": "🚶 Walk away", "stat": "",
				"win":  {"text": "You keep your gold. He boos loudly."} },
		],
	},
	{
		"kind": "spirit", "portrait": "Wispy",
		"title": "The Old Shrine",
		"desc": [
			"Deep in the woods you find a crumbling shrine. Something cold brushes the back of your neck…",
			"A {spirit} seeps out of the stones, guarding the offering bowl. Your team shivers.",
		],
		"options": [
			{ "label": "🛡 Stand firm and pray", "stat": "def", "power": 3, "type_bonus": {"Psychic": 2},
				"win":  {"text": "The shrine approves. Stone-grey light wraps {lead} — and a ghostly mist rolls out over the land.", "trait": "stone_skin", "weather": "mist"},
				"lose": {"text": "Icy fingers close around {lead}… the chill never quite leaves.", "trait": "cursed_wound"} },
			{ "label": "⚔ Drive it off", "stat": "atk", "power": 4, "type_bonus": {"Dark": 2},
				"win":  {"text": "{spirit} flees! A star falls from the offering bowl into {lead}'s paws.", "star": true},
				"lose": {"text": "{spirit} grins wide — battle!", "fight": true} },
			{ "label": "🧂 Draw a salt circle", "stat": "", "need_card": "salt_circle",
				"win":  {"text": "The salt glows. {spirit} bows and leaves you its offering.", "card": "random", "lanterns": 1} },
			{ "label": "💨 Back away slowly", "stat": "",
				"win":  {"text": "You leave the shrine in peace. Nothing follows. Probably."} },
		],
	},
	{
		"kind": "spirit", "portrait": "Squeakle",
		"title": "Berry Thief",
		"desc": "A purple blur! A wild {spirit} has its teeth in your bag and it is NOT letting go.",
		"options": [
			{ "label": "💨 Chase it down", "stat": "spd", "power": 4, "type_bonus": {"Electric": 1},
				"win":  {"text": "Caught it! It coughs up 10 gold and a card it pinched from someone else.", "gold": 10, "card": "random"},
				"lose": {"text": "It vanishes with a prize — straight to the Grim Gang's hideout.", "lose_card": true} },
			{ "label": "⚔ Roar at it", "stat": "atk", "power": 3,
				"win":  {"text": "It drops everything — including loot from someone else!", "gold": 20},
				"lose": {"text": "It bites {lead}'s nose and keeps the bag. Ow.", "damage": 15} },
			{ "label": "💚 Offer it a snack", "stat": "hp_stat", "power": 3,
				"win":  {"text": "It munches, blinks… and climbs onto {lead}'s head. New friend!", "join": true},
				"lose": {"text": "It takes the snack AND some coins.", "gold": -10} },
		],
	},
	{
		"kind": "spirit", "portrait": "Slumberghast",
		"title": "Napping Giant",
		"desc": "A {spirit} is asleep across the whole road. The ground rumbles with every snore.",
		"options": [
			{ "label": "⚔ Shove it awake", "stat": "atk", "power": 5, "type_bonus": {"Fighting": 2},
				"win":  {"text": "It blinks, chuckles, and pats {lead} flat. Respect earned!", "trait": "brave_heart"},
				"lose": {"text": "It rolls over. Onto you.", "damage": 25} },
			{ "label": "💚 Join the nap", "stat": "hp_stat", "power": 3,
				"win":  {"text": "Best. Nap. Ever. {lead} wakes up feeling like it could regrow a tail.", "trait": "regrowth"},
				"lose": {"text": "{lead} oversleeps HARD… and picks up the habit.", "trait": "sleepyhead"} },
			{ "label": "💨 Tiptoe around it", "stat": "spd", "power": 3,
				"win":  {"text": "You slip past — and find 15 gold stuck in its fur.", "gold": 15},
				"lose": {"text": "You step on its tail — it rolls down the road and flattens everyone!", "others_move": -2, "damage": 10} },
		],
	},
	{
		"kind": "trainer", "portrait": ["blue-gen1", "acetrainer-gen1"],
		"title": "Rival Roast",
		"desc": "\"Is that your best spirit? It looks like a wet sock!\" A rival hunter starts roasting {lead} in front of everyone.",
		"options": [
			{ "label": "⚔ Challenge him!", "stat": "",
				"win":  {"text": "\"Finally, some action!\" He sends out his spirit!", "fight": true} },
			{ "label": "🫵 Make the leader fight him instead", "stat": "spd", "power": 3,
				"win":  {"text": "You point at the points leader. \"THEY said it!\" Now you two settle it.", "challenge": "leader"},
				"lose": {"text": "Nobody buys it. {lead} slinks off red-faced.", "trait": "timid"} },
			{ "label": "🛡 Let it wash over you", "stat": "def", "power": 3,
				"win":  {"text": "{lead} doesn't even blink. The crowd cheers you on!", "battle_mod": 1},
				"lose": {"text": "{lead} takes it personally…", "trait": "timid"} },
			{ "label": "💨 Fire back a comeback", "stat": "spd", "power": 4,
				"win":  {"text": "Your comeback is LEGENDARY. He pays 20 gold to make you stop.", "gold": 20},
				"lose": {"text": "The comeback dies in your throat. {lead} cringes.", "trait": "timid"} },
		],
	},
	{
		"kind": "spirit", "portrait": "Mendie",
		"title": "The Hidden Spring",
		"desc": [
			"You hear water… a hidden spring glitters in a mossy grove. A {spirit} seems to be its keeper.",
			"The water sparkles invitingly. {spirit} watches you very closely.",
		],
		"options": [
			{ "label": "💚 Ask to bathe", "stat": "hp_stat", "power": 2, "type_bonus": {"Water": 2},
				"win":  {"text": "{spirit} beams! The team soaks and the clouds part — blazing sun!", "heal_team": true, "weather": "sun"},
				"lose": {"text": "{spirit} shoos you off, and you drop your pouch in the mud.", "gold": -10} },
			{ "label": "🫙 Sneak a bottleful", "stat": "spd", "power": 3,
				"win":  {"text": "Got it — it fizzes like a Mega Tonic!", "card": "mega_tonic"},
				"lose": {"text": "{spirit} catches you mid-scoop. SLAP.", "damage": 15} },
			{ "label": "⚔ Take the spring gem", "stat": "atk", "power": 5,
				"win":  {"text": "You pry the gem loose — it's worth a fortune!", "gold": 50},
				"lose": {"text": "{spirit}'s SLAP sends you flying. And now it's mad.", "fight": true} },
		],
	},
	{
		"kind": "spirit", "portrait": "Cryptcoil",
		"title": "Cave-In!",
		"desc": "The tunnel shakes — a {spirit} crashes through the ceiling! Rocks rain down everywhere.",
		"options": [
			{ "label": "🛡 Shield the team", "stat": "def", "power": 4, "type_bonus": {"Fighting": 1, "Water": 1},
				"win":  {"text": "{lead} holds the rubble off everyone. What a wall!", "trait": "stone_skin"},
				"lose": {"text": "A rock clips {lead} — you stagger all the way back to town.", "damage": 25, "warp": "home"} },
			{ "label": "💨 Sprint for daylight", "stat": "spd", "power": 4,
				"win":  {"text": "You outrun the collapse — {lead}'s legs feel springier than ever!", "trait": "swift_soul"},
				"lose": {"text": "{lead} gets clipped and limps out.", "trait": "brittle_bones"} },
			{ "label": "🚪 Step through a Warp Door", "stat": "", "need_card": "warp_door",
				"win":  {"text": "You pop out safe on the other side — next to a forgotten stash!", "gold": 30, "card": "random"} },
			{ "label": "⚔ Punch through the rocks", "stat": "atk", "power": 4,
				"win":  {"text": "Smash! Inside the rubble: someone's lost coin stash.", "gold": 30},
				"lose": {"text": "The rocks win. Ow. And your pouch tore.", "damage": 15, "gold": -10} },
		],
	},
	{
		"kind": "spirit", "portrait": "@legendary", "min_badges": 2,
		"title": "A Legend Stirs",
		"desc": [
			"The air crackles with ancient power. Something LEGENDARY has awoken…",
			"A wild {spirit} — a legendary spirit — appears before {lead}! This may be your only chance.",
		],
		"options": [
			{ "label": "💚 Earn its respect", "stat": "hp_stat", "power": 5,
				"win":  {"text": "{spirit} judges {lead} worthy — the legend joins you, and the sky answers!", "join": true, "weather": "@spirit"},
				"lose": {"text": "{spirit} deems you unready and vanishes in a flash of light."} },
			{ "label": "⚔ Prove your strength", "stat": "atk", "power": 6,
				"win":  {"text": "An epic clash — {spirit} bows to your power and joins your team!", "join": true},
				"lose": {"text": "The legend's might is overwhelming — battle!", "fight": true} },
			{ "label": "🎲 Reach out to it", "stat": "luck",
				"win":  {"text": "Against all odds, {spirit} takes a shine to {lead} and joins!", "join": true},
				"lose": {"text": "{spirit} slips away into legend once more."} },
		],
	},
	{
		"kind": "trainer", "portrait": ["rocketgrunt", "rocket", "acetrainer"],
		"title": "The Mystery Box",
		"desc": "A shady merchant flips open his coat. \"Psst. Mystery box. 25 gold. Could be ANYTHING in there.\"",
		"options": [
			{ "label": "🪙 Buy the box (25g)", "stat": "luck", "cost": 25,
				"win":  {"text": "Inside: a Weather Charm! Now you control the sky.", "card": "weather_charm"},
				"lose": {"text": "Inside: a Grim Hex! It goes off — on the points leader.", "hex": true} },
			{ "label": "⚔ Shake him down", "stat": "atk", "power": 4,
				"win":  {"text": "A Wake Bell falls out of his sleeve. \"T-take it and go!\"", "card": "wake_bell"},
				"lose": {"text": "He mutters a hex as he scurries off… {lead} feels jittery.", "trait": "timid"} },
			{ "label": "🚶 Not today", "stat": "",
				"win":  {"text": "He shrugs. \"Your loss, kid.\""} },
		],
	},
	# ── new ──────────────────────────────────────────────────────────────────
	{
		"kind": "spirit", "portrait": "",
		"title": "The Haunted Well",
		"desc": "An old well. Coins glint at the bottom… and something down there is whispering your name.",
		"options": [
			{ "label": "🪣 Lower the bucket", "stat": "hp_stat", "power": 2,
				"win":  {"text": "Up comes a bucket of coins! The whisper says: \"…deeper…\"", "gold": 15, "next": {
					"desc": "The whisper grows louder. \"Deeper… there's MORE down here…\" Lower it again?",
					"options": [
						{ "label": "🪣 Deeper!", "stat": "hp_stat", "power": 4,
							"win":  {"text": "A heavy chest! Gold AND a card!", "gold": 30, "card": "random", "next": {
								"desc": "\"DEEPER…\" The rope is fraying. One last time?",
								"options": [
									{ "label": "🪣 All the way down!", "stat": "hp_stat", "power": 6,
										"win":  {"text": "A star rises out of the dark — and the well swallows you up and spits you out ahead!", "star": true, "swap": "leader"},
										"lose": {"text": "The rope snaps — and something grabs {lead}'s tail!", "fight": true} },
									{ "label": "🚶 That's enough", "stat": "",
										"win":  {"text": "You leave with your treasure. The well sighs."} },
								]}},
							"lose": {"text": "The bucket comes up empty — and icy water splashes {lead}.", "damage": 20} },
						{ "label": "🚶 Walk away rich", "stat": "",
							"win":  {"text": "You pocket the coins. The well grumbles behind you."} },
					]}},
				"lose": {"text": "A wet hand pulls the bucket away. Spooky!", "damage": 10} },
			{ "label": "🪙 Toss in a coin (5g)", "stat": "luck", "cost": 5,
				"win":  {"text": "Your wish comes true! Something appears in your hand.", "card": "random"},
				"lose": {"text": "Plop. Nothing happens. The well giggles."} },
			{ "label": "🚶 Not touching THAT", "stat": "",
				"win":  {"text": "Wise. The whispering fades as you leave."} },
		],
	},
	{
		"kind": "trainer", "portrait": ["lass", "beauty", "acetrainerf"],
		"title": "Lantern Festival",
		"desc": "Paper lanterns bob over the town square. Ghost kids are dancing, and there's a raffle booth!",
		"options": [
			{ "label": "🏮 Help light the lanterns", "stat": "hp_stat", "power": 3, "type_bonus": {"Fire": 3},
				"win":  {"text": "The square glows! Every hunter gets a Spirit Lantern — you get the credit.", "all_lantern": true, "points": 1},
				"lose": {"text": "You singe {lead}'s whiskers. Everyone pretends not to notice.", "damage": 10} },
			{ "label": "💃 Enter the dance-off", "stat": "spd", "power": 4, "type_bonus": {"Electric": 2},
				"win":  {"text": "{lead} wins the dance-off! First prize!", "gold": 25, "card": "tactic"},
				"lose": {"text": "{lead} trips over its own tail. The crowd still claps."} },
			{ "label": "🎟 Buy a raffle ticket (10g)", "stat": "luck", "cost": 10,
				"win":  {"text": "Your number comes up! A shiny prize!", "card": "charm"},
				"lose": {"text": "So close! You win a consolation lollipop. It's… okay."} },
		],
	},
	{
		"kind": "trainer", "portrait": ["channeler", "psychic", "acetrainerf"],
		"title": "The Fortune Teller",
		"desc": "A veiled ghost gazes into a crystal ball. \"I see your future, little hunter… for a price.\"",
		"options": [
			{ "label": "🔮 Pay for a reading (10g)", "stat": "", "cost": 10,
				"win":  {"text": "\"Your next roll will be LUCKY.\" She hands you a strange die.", "card": "loaded_die"} },
			{ "label": "🌦 Pay her to change the sky (10g)", "stat": "", "cost": 10,
				"win":  {"text": "She waves her hands. The sky obeys!", "weather": "random"} },
			{ "label": "✋ Read my palm", "stat": "luck",
				"win":  {"text": "\"A bright star shines over your lead!\" And it really does!", "star": true},
				"lose": {"text": "\"Oh no. OH no.\" She won't say more. {lead} feels uneasy.", "battle_mod": -1} },
			{ "label": "🧠 Out-stare the crystal ball", "stat": "def", "power": 4, "type_bonus": {"Psychic": 3},
				"win":  {"text": "The ball cracks first! She gives you her best tactic, impressed.", "card": "tactic"},
				"lose": {"text": "{lead} stares so long it gets a headache.", "trait": "timid"} },
		],
	},
	{
		"kind": "spirit", "portrait": "",
		"title": "Campfire Stories",
		"desc": "Spirits sit around a crackling campfire telling scary stories. A {spirit} pats the log next to it.",
		"options": [
			{ "label": "🔥 Tell the scariest story", "stat": "atk", "power": 4, "type_bonus": {"Dark": 2, "Fire": 1},
				"win":  {"text": "Everyone SCREAMS. A ghostly mist rolls in off the campfire!", "battle_mod": 1, "gold": 10, "weather": "mist"},
				"lose": {"text": "The story is… about a sandwich. Nobody is scared.", "trait": "timid"} },
			{ "label": "🛡 Stay brave all night", "stat": "def", "power": 3,
				"win":  {"text": "{lead} doesn't flinch once. Tough as stone!", "trait": "stone_skin"},
				"lose": {"text": "{lead} hides under a log until morning.", "damage": 10} },
			{ "label": "🍡 Share a snack", "stat": "hp_stat", "power": 3,
				"win":  {"text": "{spirit} loves your snack and follows you home!", "join": true},
				"lose": {"text": "It eats ALL the snacks. And nibbles a lantern.", "lanterns": -1} },
		],
	},
	{
		"kind": "spirit", "portrait": "",
		"title": "A Lost Little Ghost",
		"desc": "A tiny {spirit} is crying by the road. \"I can't find my way home…\"",
		"options": [
			{ "label": "🧭 Walk it home", "stat": "spd", "power": 3, "type_bonus": {"Psychic": 2},
				"win":  {"text": "Its family is SO grateful — they give you a gift and a ride across the map!", "card": "random", "gold": 10, "warp": "random"},
				"lose": {"text": "You get lost too. It takes ages to find the road again."} },
			{ "label": "🧪 Cheer it up with a Glow Tonic", "stat": "", "need_card": "glow_tonic",
				"win":  {"text": "It glows happily and decides YOU are its family now!", "join": true} },
			{ "label": "💚 Give it a hug", "stat": "hp_stat", "power": 4,
				"win":  {"text": "It stops crying and joins your team!", "join": true},
				"lose": {"text": "It wails even LOUDER and floats off."} },
		],
	},
	{
		"kind": "trainer", "portrait": ["scientist", "gentleman", "acetrainer"],
		"title": "The Mirror Maze",
		"desc": "You wander into a funhouse full of mirrors. Hundreds of {lead}s stare back… one of them winks.",
		"options": [
			{ "label": "⚔ Smash the winking mirror", "stat": "atk", "power": 4,
				"win":  {"text": "CRASH! A mirror ghost flees and drops a Mirror Veil card.", "card": "mirror_veil"},
				"lose": {"text": "Wrong mirror. Seven years' bad luck… or at least a bad day.", "battle_mod": -1} },
			{ "label": "💨 Find the exit fast", "stat": "spd", "power": 3,
				"win":  {"text": "You zip out the back door — with a prize from the counter.", "gold": 20},
				"lose": {"text": "You bonk into a mirror. Twice.", "damage": 15} },
			{ "label": "🎲 Follow your reflection", "stat": "luck",
				"win":  {"text": "Your reflection steps out of the glass and trades places with a rival!", "star": true, "swap": "random"},
				"lose": {"text": "Your reflection leads you in circles and steals a card!", "lose_card": true} },
		],
	},
	# ── the Grim Gang (on the road) ──────────────────────────────────────────
	{
		"kind": "gang", "title": "Grim Gang Ambush",
		"desc": "Black hoods drop from the trees! \"The Grim Gang wants your best spirit, kid. Hand it over!\"",
		"options": [
			{ "label": "⚔ Fight them off", "stat": "",
				"win":  {"text": "\"Get 'em!\" Two grunts send out their spirits!", "gang_fight": true} },
			{ "label": "🛡 Stare them down", "stat": "def", "power": 4,
				"win":  {"text": "They blink first and scatter, dropping a Grim Hex.", "card": "hex"},
				"lose": {"text": "They laugh at {lead} — and attack!", "gang_fight": true} },
			{ "label": "🪙 Pay them off (20g)", "stat": "", "cost": 20,
				"win":  {"text": "They pocket the gold… and slip you a curse for the leader.", "hex": true} },
		],
	},
	{
		"kind": "gang", "title": "Grim Gang Brawl",
		"desc": "A grunt cracks his knuckles. \"No talking. Your spirit versus mine. Winner takes the loser's lead!\"",
		"options": [
			{ "label": "⚔ Bring it on!", "stat": "",
				"win":  {"text": "Battle!", "gang_fight": true} },
			{ "label": "💨 Run for it", "stat": "spd", "power": 5,
				"win":  {"text": "You're GONE. He's still flexing at nothing.", "move": 2},
				"lose": {"text": "He blocks the road. No way out — battle!", "gang_fight": true} },
		],
	},
	{
		"kind": "gang", "title": "Grim Gang Shakedown",
		"desc": "\"Nice hand of cards. Be a shame if something… happened to it.\" A grunt blocks your path.",
		"options": [
			{ "label": "⚔ Refuse!", "stat": "atk", "power": 4,
				"win":  {"text": "He backs off — and drops his loot!", "gold": 20, "card": "random"},
				"lose": {"text": "He snatches a card and calls his friends!", "lose_card": true, "gang_fight": true} },
			{ "label": "🃏 Hand over a card", "stat": "",
				"win":  {"text": "He takes it and runs… right past the points leader, cursing them!", "lose_card": true, "hex": true} },
		],
	},
	{
		"kind": "gang", "title": "Grim Gang Roadblock",
		"desc": "Barrels, skull flags, grunts. \"This road is Grim Gang property. 15 gold to pass.\"",
		"options": [
			{ "label": "🪙 Pay the toll (15g)", "stat": "", "cost": 15,
				"win":  {"text": "They wave you through. \"Pleasure doing business.\"", "move": 2} },
			{ "label": "⚔ Smash the barrels", "stat": "atk", "power": 5, "type_bonus": {"Fighting": 2},
				"win":  {"text": "Barrels everywhere! You find their stash.", "gold": 30},
				"lose": {"text": "The whole gang turns around…", "gang_fight": true} },
			{ "label": "🔙 Take the long way", "stat": "",
				"win":  {"text": "You turn back. It's a long walk.", "move": -3} },
		],
	},
	# ── board shake-ups ──────────────────────────────────────────────────────
	{
		"kind": "spirit", "portrait": "", "title": "Ghost Portal", "needs_rival": true,
		"desc": "A swirling purple portal opens in the road. Through it you can see… another hunter's back!",
		"options": [
			{ "label": "🌀 Swap with the leader", "stat": "spd", "power": 4,
				"win":  {"text": "WHOOSH — you're where the leader was. They're where you were!", "swap": "leader"},
				"lose": {"text": "The portal spits you out backwards.", "move": -2} },
			{ "label": "🎲 Jump in blind", "stat": "luck",
				"win":  {"text": "You pop out somewhere new — with 15 gold stuck to your shoe!", "swap": "random", "gold": 15},
				"lose": {"text": "You pop out in a random town, dizzy.", "warp": "random"} },
			{ "label": "🚶 Walk around it", "stat": "",
				"win":  {"text": "Nope. Not today."} },
		],
	},
	{
		"kind": "trainer", "portrait": ["acetrainer", "acetrainerf"], "title": "Bounty Board", "needs_rival": true,
		"desc": "A board in the square: \"WANTED — a duel! Winner takes the bounty.\" Who will you challenge?",
		"options": [
			{ "label": "⚔ Challenge the points leader", "stat": "",
				"win":  {"text": "You pin the leader's name on the board. DUEL!", "challenge": "leader"} },
			{ "label": "⚔ Challenge a random rival", "stat": "",
				"win":  {"text": "You throw a dart at the board… DUEL!", "challenge": "random"} },
			{ "label": "📜 Take the reward money", "stat": "luck",
				"win":  {"text": "Someone already claimed it — but left a tip.", "gold": 20},
				"lose": {"text": "It was a fake poster."} },
		],
	},
	{
		"kind": "spirit", "portrait": "", "title": "Storm Caller",
		"desc": "A {spirit} dances on a hilltop, arms raised to the sky. The clouds swirl to its rhythm. How do you join in?",
		"options": [
			{ "label": "💃 Dance with it", "stat": "spd", "power": 3,
				"win":  {"text": "Thunder rolls — a STORM!", "weather": "storm", "gold": 10},
				"lose": {"text": "You trip. The storm comes anyway.", "weather": "storm", "damage": 10} },
			{ "label": "☀ Shield your eyes", "stat": "def", "power": 3,
				"win":  {"text": "The clouds part — blazing SUN!", "weather": "sun", "card": "random"},
				"lose": {"text": "Sun's out — and it burns!", "weather": "sun", "damage": 10} },
			{ "label": "🤫 Whisper to it", "stat": "hp_stat", "power": 3,
				"win":  {"text": "It whispers back. A thick MIST rolls in.", "weather": "mist", "card": "weather_charm"},
				"lose": {"text": "It shrieks — and the mist rolls in anyway.", "weather": "mist"} },
			{ "label": "⚔ Chase it off", "stat": "atk", "power": 4,
				"win":  {"text": "It flees in a whirl of SAND!", "weather": "sand", "gold": 15},
				"lose": {"text": "It kicks up a SANDSTORM in your face.", "weather": "sand", "damage": 15} },
		],
	},
	{
		"kind": "spirit", "portrait": "", "title": "The Haunted Carriage",
		"desc": "A phantom coach rattles up. The headless driver tips his hat. \"Going somewhere?\"",
		"options": [
			{ "label": "🪙 Buy a ticket (10g)", "stat": "", "cost": 10,
				"win":  {"text": "Off you go — next stop, anywhere!", "warp": "random"} },
			{ "label": "🦘 Hitch a free ride", "stat": "spd", "power": 4,
				"win":  {"text": "You cling on for dear life — 5 spaces ahead!", "move": 5},
				"lose": {"text": "You fall off. Backwards.", "move": -3} },
			{ "label": "🚶 Walk", "stat": "",
				"win":  {"text": "The carriage rattles off without you."} },
		],
	},
	{
		"kind": "spirit", "portrait": "", "title": "Ghost Parade", "needs_rival": true,
		"desc": "Drums! Banners! A ghost parade comes marching down the road straight at everyone.",
		"options": [
			{ "label": "🥁 Lead the parade", "stat": "spd", "power": 3,
				"win":  {"text": "You march out front — 3 spaces ahead!", "move": 3},
				"lose": {"text": "You get swept up and carried backwards.", "move": -2} },
			{ "label": "⚔ Scatter it", "stat": "atk", "power": 4,
				"win":  {"text": "The parade stampedes over everyone else!", "others_move": -2},
				"lose": {"text": "It tramples you instead.", "damage": 15} },
		],
	},
	{
		"kind": "trainer", "portrait": ["gentleman", "acetrainer"], "title": "The Ghost Tax", "needs_rival": true,
		"desc": "A ghost in a top hat unrolls a long scroll. \"TAX DAY! The richest hunter pays everyone else.\"",
		"options": [
			{ "label": "📜 Point him at the leader", "stat": "",
				"win":  {"text": "He floats straight to the points leader…", "leader_pays_all": 10} },
			{ "label": "🫢 Bribe him (10g)", "stat": "", "cost": 10,
				"win":  {"text": "He 'forgets' you — and taxes everyone else for you!", "gold_from_all": 8} },
		],
	},
	{
		"kind": "spirit", "portrait": "", "title": "Quicksand Bog",
		"desc": "Squelch. {lead} is sinking into a ghostly bog — fast!",
		"options": [
			{ "label": "💪 Pull yourself out", "stat": "atk", "power": 4,
				"win":  {"text": "SPLORCH! You launch out — 3 spaces ahead!", "move": 3},
				"lose": {"text": "Stuck tight. You'll miss your next turn.", "skip": true} },
			{ "label": "🏮 Hook out with a Lantern", "stat": "", "need_card": "spirit_lantern",
				"win":  {"text": "The lantern handle makes a great hook. Out you come!", "move": 1} },
			{ "label": "😌 Stay calm and float", "stat": "hp_stat", "power": 3,
				"win":  {"text": "Floating works! You drift out the far side.", "move": 2},
				"lose": {"text": "Glub. You're stuck for a turn.", "skip": true} },
		],
	},
	# ── the Grim Gang HIDEOUT (only when you stop at their ☠ town) ───────────
	{
		"kind": "gang_hideout", "title": "The Hideout Gate",
		"desc": "Skull flags and a heavy iron gate. Two grunts guard it, half asleep.",
		"options": [
			{ "label": "🤫 Sneak past", "stat": "spd", "power": 5,
				"win":  {"text": "You slip inside and loot their supply room!", "gold": 30, "card": "random"},
				"lose": {"text": "A grunt wakes up. \"INTRUDER!\"", "gang_fight": true} },
			{ "label": "⚔ Kick the gate down", "stat": "",
				"win":  {"text": "BANG! The whole gang comes running!", "gang_fight": true} },
			{ "label": "🎭 Pretend to be a new recruit", "stat": "def", "power": 4,
				"win":  {"text": "They buy it and hand you a Grim Hex to 'practice' with.", "card": "hex"},
				"lose": {"text": "\"Nice try.\" They toss you out of town.", "warp": "random"} },
		],
	},
	{
		"kind": "gang_hideout", "title": "The Training Room",
		"desc": "Inside, grunts drill their spirits. One spots you. \"You! Spar with us!\"",
		"options": [
			{ "label": "⚔ Spar for real", "stat": "",
				"win":  {"text": "A grunt steps up — winner keeps the loser's lead!", "gang_fight": true} },
			{ "label": "👀 Watch and learn", "stat": "hp_stat", "power": 4,
				"win":  {"text": "{lead} copies their moves. Ready for anything!", "battle_mod": 1, "trait": "brave_heart"},
				"lose": {"text": "{lead} gets hit by a stray attack.", "damage": 20} },
			{ "label": "🌦 Swipe their Weather Charm", "stat": "spd", "power": 4,
				"win":  {"text": "Got it! Now YOU control the sky.", "card": "weather_charm"},
				"lose": {"text": "Caught red-handed!", "gang_fight": true} },
		],
	},
	{
		"kind": "gang_hideout", "title": "The Vault",
		"desc": "A huge vault door with a skull-shaped lock. Gold glints through the keyhole.",
		"options": [
			{ "label": "🎲 Crack the lock", "stat": "luck",
				"win":  {"text": "CLICK. Gold everywhere!", "gold": 45, "points": 1},
				"lose": {"text": "An alarm blares — grunts pour in!", "gang_fight": true} },
			{ "label": "🧤 Use Sticky Fingers", "stat": "", "need_card": "sticky_fingers",
				"win":  {"text": "Your nimble fingers empty half the vault.", "gold": 40, "card": "random"} },
			{ "label": "💪 Force the door", "stat": "atk", "power": 6,
				"win":  {"text": "The door groans open. Jackpot!", "gold": 50},
				"lose": {"text": "It won't budge — and now your arms hurt.", "damage": 15} },
		],
	},
	{
		"kind": "gang_hideout", "title": "The Boss's Office",
		"desc": "The Grim Boss is out. His desk is covered in maps, curses and a big red button.",
		"options": [
			{ "label": "🗺 Read his plans", "stat": "def", "power": 4, "type_bonus": {"Psychic": 2},
				"win":  {"text": "A secret shortcut! You take it straight to the leader's spot.", "swap": "leader"},
				"lose": {"text": "You hear footsteps — RUN!", "move": -2} },
			{ "label": "☠ Grab his curses", "stat": "spd", "power": 4,
				"win":  {"text": "A fistful of Grim Hexes! One goes off on the leader already.", "hex": true, "card": "hex"},
				"lose": {"text": "A guard catches you!", "gang_fight": true} },
			{ "label": "🔴 Press the red button", "stat": "luck",
				"win":  {"text": "The hideout's weather machine roars to life!", "weather": "random", "gold": 20},
				"lose": {"text": "A trapdoor! You land in the moat — back to town.", "warp": "home"} },
		],
	},
	{
		"kind": "gang_hideout", "title": "Recruitment Drive",
		"desc": "\"Join the Grim Gang! Free hoodie! Free curses!\" A grunt shoves a form at you.",
		"options": [
			{ "label": "✍ Join for a day", "stat": "",
				"win":  {"text": "Free hoodie, a curse and some 'wages'. You feel a bit guilty.", "gold": 20, "card": "hex", "points": -1} },
			{ "label": "⚔ Tear up the form", "stat": "atk", "power": 4,
				"win":  {"text": "They cheer your nerve — and pay you to leave.", "gold": 25, "points": 1},
				"lose": {"text": "\"How RUDE.\" Battle!", "gang_fight": true} },
			{ "label": "🚶 Walk out", "stat": "",
				"win":  {"text": "You leave. They call you a chicken."} },
		],
	},
]
