class_name Balance
## Every tuning number in one place, so balance passes don't mean hunting
## through a dozen scripts. Tweak here; nothing else needs to change.

# ── Points (first to the setup's win target wins, unless "No pts" is on) ─────
# static var (not const) so test runs can try other values.
static var PTS_CATCH := 1
static var PTS_GYM := 3
static var PTS_PVP_WIN := 4
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

# ── Wild ghosts: Spook Duel, then capture ─────────────────────────────────────
# A wild ghost is never fought. First your lead stares it down: lead power +
# 🎲d6 vs the ghost's power + 🎲d6 (ties to you; power = rounded average of
# ATK/DEF/SPD + stars, ±1 for type advantage). Lose and it runs away. Win and
# you get CATCH_THROWS throws: roll d100 + bonuses ≥ the target.
# Target by stage (legendaries: LEGEND_TARGET). Plain Ghost Jar, no badges,
# duel won: 90% / 75% / 60%.
const CATCH_TARGET := {1: 26, 2: 41, 3: 56}
const LEGEND_TARGET := 80
const CATCH_BADGE_BONUS := 2            # per badge…
const CATCH_BADGE_CAP := 3              # …counting at most this many badges
const DUEL_BONUS := 15                  # the ghost is spooked (you won the duel)
const CATCH_LURE_BONUS := 10            # a Spooky Lure drew it in
const CATCH_FAIL_PENALTY := 15          # target rises after a missed throw
const CATCH_THROWS := 2                 # throws per encounter, then it flees
# Catching levels your lead up: ½ star (a full star for stage 2+ ghosts).
const CATCH_LEAD_STARS := 0.5
const CATCH_LEAD_STARS_STRONG := 1.0

# ── Cards ─────────────────────────────────────────────────────────────────────
const HAND_SIZE := 5
const START_CARDS := 2                  # dealt to every player at setup
const START_JARS := 5
const SHOP_CARD_OFFERS := 4

# ── Board ─────────────────────────────────────────────────────────────────────
const FAST_MODE_TURN := 24              # from this turn everyone rolls 2 dice
const FLY_BADGES := 3                   # badges needed to fly / enter the Spectral Trail
const TEAM_MAX := 6
const BATTLE_PICK_MAX := 3              # 3v3 battles

# ── Spectral Trail ────────────────────────────────────────────────────────────
# Wardens scale with how far PAST the entry requirement you are: entering with
# 3 badges meets their tier-1 teams, 5+ badges their full strength.
const TRAIL_BADGE_OFFSET := 2

# ── Battles ───────────────────────────────────────────────────────────────────
const MAX_KO_STARS := 2.0               # per spirit per battle
const FATIGUE_START := 15
const MAX_ROUNDS := 60
