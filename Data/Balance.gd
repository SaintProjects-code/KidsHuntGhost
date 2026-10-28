class_name Balance
## Every tuning number in one place, so balance passes don't mean hunting
## through a dozen scripts. Tweak here; nothing else needs to change.

# ── Points (first to WIN_POINTS wins, unless "No pts" is on) ──────────────────
const PTS_CATCH := 1
const PTS_GYM := 3
const PTS_PVP_WIN := 4
const PTS_ELITE_WIN := 5
const PTS_CHAMPION := 10
const PODIUM_POINTS := [3, 2, 1]        # competition 1st / 2nd / 3rd
const RECORD_BONUS := 2                 # beating a minigame's all-time record
const ELITE_WINS_TO_WIN := 2

# ── Gold ──────────────────────────────────────────────────────────────────────
const GOLD_START := 10
const GOLD_CATCH := 10
const GOLD_WILD_WIN := 10
const GOLD_GYM := 25

# ── Capture: roll d100 + bonuses ≥ target ─────────────────────────────────────
# Target by spirit stage (legendaries use LEGEND_TARGET). With a plain Ghost
# Jar and no badges that's 75% / 60% / 45%.
const CATCH_TARGET := {1: 26, 2: 41, 3: 56}
const LEGEND_TARGET := 80
const CATCH_BADGE_BONUS := 2            # per badge…
const CATCH_BADGE_CAP := 3              # …counting at most this many badges
const CATCH_FOUGHT_BONUS := 15          # the spirit was worn down in battle first
const CATCH_LURE_BONUS := 10            # a Spooky Lure drew it in
const CATCH_FAIL_PENALTY := 10          # target rises after each escape
const CATCH_MAX_FAILS := 3              # then it flees

# ── Cards ─────────────────────────────────────────────────────────────────────
const HAND_SIZE := 5
const START_CARDS := 2                  # dealt to every player at setup
const START_JARS := 5
const SHOP_CARD_OFFERS := 4

# ── Board ─────────────────────────────────────────────────────────────────────
const FAST_MODE_TURN := 24              # from this turn everyone rolls 2 dice
const FLY_BADGES := 3                   # badges needed to fly / enter the Spectral Trail
const TEAM_MAX := 6
const BATTLE_PICK_MAX := 4

# ── Spectral Trail ────────────────────────────────────────────────────────────
# Wardens scale with how far PAST the entry requirement you are: entering with
# 3 badges meets their tier-1 teams, 5+ badges their full strength.
const TRAIL_BADGE_OFFSET := 2

# ── Battles ───────────────────────────────────────────────────────────────────
const MAX_KO_STARS := 2.0               # per spirit per battle
const FATIGUE_START := 15
const MAX_ROUNDS := 60
