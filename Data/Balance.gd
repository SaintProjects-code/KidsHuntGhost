class_name Balance
## Every tuning number in one place, so balance passes don't mean hunting
## through a dozen scripts. Tweak here; nothing else needs to change.

# ── Points (first to the setup's win target wins, unless "No pts" is on) ─────
# static var (not const) so test runs can try other values.
static var PTS_CATCH := 1
static var PTS_GYM := 4                  # (5 let one player snowball in the playtest)
static var PTS_PVP_WIN := 3
static var PTS_ELITE_WIN := 5
static var PTS_CHAMPION := 10
static var PTS_TRAINER_MULT := 1        # × each trainer's listed points
static var PODIUM_POINTS := [3, 2, 1]   # competition 1st / 2nd / 3rd
const RECORD_BONUS := 2                 # beating a minigame's all-time record
const ELITE_WINS_TO_WIN := 2

# ── Gold ──────────────────────────────────────────────────────────────────────
const GOLD_START := 10
const GOLD_CATCH := 10
const GOLD_GYM := 25
const GOLD_PVP_TAKE := 15               # the PvP winner takes this much from the loser

# ── Catching wild ghosts: a dice roll ────────────────────────────────────────
# Roll 1 free die + 1 die per Spirit Lantern (+2 per Grand Lantern) and add
# them up; catch the ghost if the total reaches its target. A Soul Lantern is a
# sure catch. Two tries per ghost — the target rises after a miss — then it
# flees. Lantern cards are spent on the roll, hit or miss.
# Stronger ghosts are out of reach of the free die alone: stage 2 needs 2+
# dice, stage 3 needs 3+, legendaries 3+ (and really 4–5) — so Lanterns
# matter more and more as the hunt moves to Phantom tiles.
const CATCH_TARGET := {1: 4, 2: 7, 3: 11}   # by spirit stage (1 die = 50% on a stage 1)
const LEGEND_TARGET := 15
const CATCH_LURE_BONUS := 2             # a Spooky Lure drew it in: +2 to the roll
const CATCH_FAIL_PENALTY := 1           # target rises after a miss
const CATCH_THROWS := 2                 # tries per ghost, then it flees
const START_LANTERNS := 2               # Spirit Lanterns dealt to every player
# Catching levels your lead up: ½ star (a full star for stage 2+ ghosts).
const CATCH_LEAD_STARS := 0.5
const CATCH_LEAD_STARS_STRONG := 1.0

# ── Cards ─────────────────────────────────────────────────────────────────────
const HAND_SIZE := 7
const START_CARDS := 2                  # dealt to every player at setup
const SHOP_CARD_OFFERS := 4

# ── Board ─────────────────────────────────────────────────────────────────────
const FAST_MODE_TURN := 16              # from this turn everyone rolls 2 dice
const FLY_BADGES := 3                   # default badges to fly / enter the Spectral Trail (Game Settings → GameState.trail_badges)
const TEAM_MAX := 6
static var BATTLE_PICK_MAX := 3         # spirits per side in a battle: 3, 4 or 6 (Game Settings → GameState.battle_size)

# ── Spectral Trail ────────────────────────────────────────────────────────────
# The Haunted Four scale with how far PAST the entry requirement you are:
# entering with the required badges meets their tier-1 teams, 2+ more badges
# their full strength. With fewer players everyone collects more badges before
# reaching the trail, so small games get a bigger offset (weaker phantoms).
# The offsets are written for the default requirement of 3 (see trail_tier).
const TRAIL_BADGE_OFFSET := {1: 3, 2: 3, 3: 2, 4: 2, 5: 2, 6: 2}   # by player count

# ── Battles ───────────────────────────────────────────────────────────────────
const MAX_KO_STARS := 2.0               # per spirit per battle
const WARDEN_LOSS_STARS := 0.5          # each spirit that fought a town Warden and lost
const PVP_WIN_STARS := 1.0              # the PvP winner's lead
const PVP_STEAL_CARDS := 1              # cards the PvP winner takes from the loser
const FATIGUE_START := 15
const MAX_ROUNDS := 60

# ── battle pacing ─────────────────────────────────────────────────────────────
# Damage per ATK point (DamageCalculator). Tuned so a spirit usually lasts long
# enough to fire its charge move at least once (moves cost 1–4 charge).
static var DAMAGE_PER_ATK := 15.0
# The charge gauge also fills by 1 when a spirit takes a hit and survives.
static var CHARGE_ON_HIT := true
# Charge a spirit already has when it first takes the field.
static var START_CHARGE := 1

