extends "res://Scenes/UI/Battle/BattleRules.gd"
## Battle screen, layer 3 of 3: the FLOW. present() a fight, then rounds run
## on Next Round (or by themselves for CPU fights). Reused for wild spirits,
## trainers, gyms, the Haunted Four, the Champion and PvP.
##
## AUTO: human battles start on Auto — rounds play by themselves (1x / 3x).
## Auto NEVER picks your cards: arm one and it plays at the next round.
## The Auto button pauses; Next Round plays a round now and resumes Auto.
## TACTIC CARDS: each side may play ONE tactic card per round. A human clicks a
## card (or presses 1–5) to arm it; it plays at the start of the next round.
## CPUs and NPC leaders pick with CardSystem.pick_tactic. A CHARM card puts its
## charm on your lead for the rest of the battle (one use, then it's gone).
##
## 📱 PHONES: a side played from a phone keeps its cards face-down on the TV and
## plays them from the phone (remote_view). Phone players who aren't in the
## fight VOTE on who wins during the first VOTE_ROUNDS rounds; a right guess
## earns a card (or a star when their hand is full) — see _pay_votes.
##
## present(setup) — setup keys:
##   team, opp            Arrays of spirit dicts (yours / theirs)
##   title, color         window title, your trainer colour
##   atk_mod              event blessing/curse for this battle (+1 / -1)
##   trainer, foe_trainer portrait candidate lists
##   pvp_names            [your name, their name] in PvP
##   hand / opp_hand      the tactic cards each side brought (2 each)
##   hand_source / opp_source  the player's real hand (a used card leaves it too)
##   hand_owner / opp_owner  player index (for hand_changed) or -1 for NPCs
##   human / opp_human    whether that side picks its own cards
##   stakes               0..1, how hard the CPU side spends cards
## Fights run on copies (buffs don't stick) but DAMAGE is real: HP is written
## back to the caller's team when the battle ends.

var _src_team: Array = []
var _hand: Array = []
var _opp_hand: Array = []
var _hand_src: Array = []
var _opp_src: Array = []
var _hand_owner := -1
var _opp_owner := -1
var _human := true
var _opp_human := false
var _stakes := 0.5
var _armed := ""          # your card queued (plays before the next attacks)
var _attacking := false   # this round's attacks have begun (a card now waits for the next round)
var _played := [false, false]   # [you, them]: a tactic already used this round (one each)
var _auto_gen := 0        # bumped per battle so an old auto loop stops
var _opp_armed := ""
var _votes := {}          # player index -> 0 (the left side wins) / 1 (the right side wins)
var _vote_paid := {}      # player index -> what they won ("" = guessed wrong)

const VOTE_ROUNDS := 2    # voting closes when this round starts

# 📱 The players whose phones drive this battle (see Remote): the human side(s).
func remote_owners() -> Array:
	var out: Array = []
	if _human and _hand_owner >= 0:
		out.append(_hand_owner)
	if _opp_human and _opp_owner >= 0:
		out.append(_opp_owner)
	return out

func present(setup: Dictionary) -> void:
	var team: Array = setup.get("team", [])
	var color: Color = setup.get("color", Color.WHITE)
	_pvp_names = setup.get("pvp_names", [])
	_team_disc.set_data(GameData.trainer_texture(setup.get("trainer", [])), color)
	_opp_disc.set_data(GameData.trainer_texture(setup.get("foe_trainer", [])), ENEMY_RED)
	_team_name_lbl.text = _pvp_names[0] if _pvp_names.size() == 2 else String(setup.get("my_name", "YOU"))
	_opp_name_lbl.text = _pvp_names[1] if _pvp_names.size() == 2 else "ENEMY"
	_src_team = team
	_team = _copy_team(team)
	_opp = _copy_team(setup.get("opp", []))
	_hand = setup.get("hand", [])
	_opp_hand = setup.get("opp_hand", [])
	_hand_src = setup.get("hand_source", [])
	_opp_src = setup.get("opp_source", [])
	_hand_owner = setup.get("hand_owner", -1)
	_opp_owner = setup.get("opp_owner", -1)
	_human = setup.get("human", true)
	_opp_human = setup.get("opp_human", false)
	_stakes = setup.get("stakes", 0.5)
	_armed = ""
	_opp_armed = ""
	_votes = {}
	_vote_paid = {}
	_attacking = false
	_played = [false, false]
	var atk_mod: int = setup.get("atk_mod", 0)
	if atk_mod != 0:
		for m in _team:
			m["atk"] = clampi(int(m.get("atk", 1)) + atk_mod, 1, 6)
	_active = 0
	_opp_active = 0
	_over = false
	_won = false
	_skipping = false
	_speed = 1.0
	_speed_btn.text = "1x"
	_auto = _human or _opp_human   # humans start on Auto; CPU-only fights use autoplay()
	_auto_gen += 1
	_auto_btn.visible = _auto
	_update_auto_btn()
	_round_num = 0
	_star_credits = {}
	_ko_stars = {}
	_log.clear()
	_continue_btn.hide()
	_skip_btn.show()
	_next_btn.disabled = false
	_skip_btn.disabled = false
	_title.text = String(setup.get("title", "Battle"))
	_busy = false
	if atk_mod > 0:
		_logln("[color=#9f9]Blessed! ATK +%d this battle.[/color]" % atk_mod)
	elif atk_mod < 0:
		_logln("[color=#f99]Spooked! ATK %d this battle.[/color]" % atk_mod)
	_build_cards()
	_refresh()
	_refresh_hands()
	if visible:
		call_deferred("_opening")   # gauntlets re-present while already shown
	else:
		_opening_pending = true
	_fit_to_screen()

# Stars earned during the battle, keyed by index into the team passed to
# present(). Cleared on read.
func take_star_credits() -> Dictionary:
	var out := _star_credits
	_star_credits = {}
	return out

func won() -> bool:
	return _won

func _copy_team(src: Array) -> Array:
	var out: Array = []
	for i in src.size():
		var c: Dictionary = src[i].duplicate(true)
		c["current_hp"] = clampi(int(src[i].get("current_hp", c.get("hp", 1))), 0, int(c.get("hp", 1)))
		c["_oi"] = i
		for key in ["atk", "def", "spd"]:
			c["_base_" + key] = int(c.get(key, 1))
		out.append(c)
	return out

# ---------------- card hands ----------------

func _refresh_hands() -> void:
	_fill_hand(_hand_box, _hand, _human, true)
	_fill_hand(_opp_hand_box, _opp_hand, _opp_human, false)

func _fill_hand(box: HBoxContainer, hand: Array, interactive: bool, mine: bool) -> void:
	UIKit.clear(box)
	var tactics: Array = hand.filter(func(k): return CardsData.kind_of(k) == "tactic")
	if not interactive:
		# the other side's cards stay face-down
		for i in tactics.size():
			box.add_child(CardView.new("", Vector2(28, 38) if not mine else HAND_CARD))
		return
	var on_phone := Remote.has_phone(_hand_owner if mine else _opp_owner)
	for key in tactics:
		var cv := CardView.new(key, HAND_CARD)
		cv.face_down = on_phone   # the phone shows this hand; the TV doesn't
		cv.armed = (_armed if mine else _opp_armed) == key
		cv.disabled = _over
		cv.pressed.connect(_arm.bind(key, mine))
		box.add_child(cv)
	if tactics.is_empty() and mine:
		var none := UIKit.label("no tactic cards", 11)
		none.modulate = Color(1, 1, 1, 0.5)
		box.add_child(none)

# Tapping a tactic card USES it as soon as it can:
#   • between rounds → right now (its effect covers the coming round)
#   • a round is starting but nobody has attacked yet → just before the attacks
#   • the attacks already began → at the start of the next round
# Tapping the waiting card again takes it back. One card per side per round.
func _arm(key: String, mine: bool) -> void:
	if _over:
		return
	var was: String = _armed if mine else _opp_armed
	var now := "" if was == key else key
	if mine:
		_armed = now
	else:
		_opp_armed = now
	Sfx.play("card", 1.2)
	_refresh_hands()
	if now == "":
		return
	var side := 0 if mine else 1
	if not _busy and not _played[side]:
		_play_now(mine)
	elif _attacking or _played[side]:
		_tactic_banner(CardsData.card(key).get("icon", "🃏"), "%s is ready" % CardsData.card_name(key),
			"plays at the start of the next round", Color("8fd6ff"))
	# otherwise the round in progress picks it up just before the attacks

# Between rounds: play the armed card straight away.
func _play_now(mine: bool) -> void:
	var key: String = _armed if mine else _opp_armed
	if key == "":
		return
	if mine:
		_armed = ""
	else:
		_opp_armed = ""
	_busy = true   # the Auto loop waits for the card to finish
	_played[0 if mine else 1] = true
	await _play_tactic(key, mine)
	_refresh_hands()
	_busy = false

# Keyboard: Space/Enter = Next Round / Continue; 1-5 arm your tactic cards.
func _unhandled_key_input(ev: InputEvent) -> void:
	if not visible:
		return
	if Controls.confirm_pressed(ev):
		get_viewport().set_input_as_handled()
		if _continue_btn.visible:
			finished.emit(_won)
		elif not _next_btn.disabled:
			_on_next()
		return
	var n := Controls.number_pressed(ev)
	if n >= 0 and _human:
		var tactics: Array = _hand.filter(func(k): return CardsData.kind_of(k) == "tactic")
		if n < tactics.size():
			get_viewport().set_input_as_handled()
			_arm(tactics[n], true)

# The card each side plays this round ("" = none).
func _choose_cards() -> Array:
	var me: Dictionary = _team[_active]
	var op: Dictionary = _opp[_opp_active]
	var mine := _armed if _human and not _skipping and not _played[0] else ""
	if not _human and not _played[0]:
		mine = CardSystem.pick_tactic(_hand, me, op, DamageCalculator.calculate(op, me),
			DamageCalculator.calculate(me, op), _stakes)
	var theirs := _opp_armed if _opp_human and not _skipping and not _played[1] else ""
	if not _opp_human and not _played[1]:
		theirs = CardSystem.pick_tactic(_opp_hand, op, me, DamageCalculator.calculate(me, op),
			DamageCalculator.calculate(op, me), _stakes)
	if mine != "":
		_armed = ""
	if theirs != "":
		_opp_armed = ""
	return [mine, theirs]

func _use_card(hand: Array, source: Array, owner: int, key: String) -> void:
	hand.erase(key)
	source.erase(key)
	if owner >= 0:
		EventBus.hand_changed.emit(owner)
		EventBus.card_played.emit(owner, key)

# Resolve one tactic card for one side at the start of the round.
func _play_tactic(key: String, is_me: bool) -> void:
	var mine: Array = _team if is_me else _opp
	var theirs: Array = _opp if is_me else _team
	var me: Dictionary = mine[_active if is_me else _opp_active]
	var foe: Dictionary = theirs[_opp_active if is_me else _active]
	_use_card(_hand if is_me else _opp_hand, _hand_src if is_me else _opp_src, _hand_owner if is_me else _opp_owner, key)
	if not _quiet():
		Sfx.play("card")
		Juice.pop(_card_of(me), 1.12)
	_logln("[color=#7fe0d0]%s plays %s![/color]" % [
		(_team_name_lbl.text if is_me else _opp_name_lbl.text), CardsData.card_name(key)])
	var info := CardsData.card(key)
	_tactic_banner(String(info.get("icon", "🃏")), "%s used %s!" % [
		(_team_name_lbl.text if is_me else _opp_name_lbl.text).capitalize(), info.get("name", key)],
		String(info.get("desc", "")), Color("7be0a0") if is_me else Color("ff9a7a"))
	match key:
		"spirit_shield": me["_r_shield"] = true
		"battle_cry":
			_buff(me, "atk", 3)
			me["_r_cry"] = true
		"haste": me["_r_haste"] = true
		"fury": me["_r_fury"] = true
		"hold_on": me["_r_hold"] = true
		"mirror_veil": me["_r_mirror"] = true
		"ecto_patch": _heal_mon(me, 60)
		"purify":
			me.erase("_status")
			me["_r_immune"] = true
		"boo":
			foe["_r_boo"] = true
			_anim_shake(foe)
			if not _quiet():
				Sfx.play("boo")
		"soul_siphon":
			_chip(foe, 40)
			_heal_mon(me, 40)
		"rally":
			for a in mine.filter(_alive):
				_buff(a, "atk", 1)
				_buff(a, "def", 1)
		"switcheroo":
			await _switch_lead(is_me)
		_:
			if CardsData.is_charm(key):
				me["charm"] = key   # on the battle copy: it ends with the battle
				_charm_entry(is_me)
	await _beat(0.45)

# Swap the lead with the healthiest living ally waiting behind it.
func _switch_lead(is_me: bool) -> void:
	var side: Array = _team if is_me else _opp
	var active: int = _active if is_me else _opp_active
	var best := -1
	for j in range(active + 1, side.size()):
		if _alive(side[j]) and (best == -1 or int(side[j]["current_hp"]) > int(side[best]["current_hp"])):
			best = j
	if best == -1:
		_logln("…but nobody is free to switch in.")
		return
	var lead: Dictionary = side[active]
	side[active] = side[best]
	side[best] = lead
	_build_cards()
	_logln("%s swaps in for %s!" % [_who(side[active]), _who(lead)])
	await _on_entry(is_me)

func _clear_round_flags() -> void:
	for m in _team + _opp:
		if m.get("_r_cry", false):
			_buff(m, "atk", -3)
		for f in ["_r_shield", "_r_shield_logged", "_r_cry", "_r_haste", "_r_fury", "_r_hold", "_r_mirror", "_r_immune", "_r_boo"]:
			m.erase(f)

# ---------------- flow ----------------

func _on_next() -> void:
	if _over:
		return
	Sfx.play("click")
	_auto = true   # Next Round also (re)starts Auto
	_update_auto_btn()
	if not _busy:
		_round()

func _on_auto_toggle() -> void:
	if _over:
		return
	_auto = not _auto
	Sfx.play("click")
	_update_auto_btn()

func _update_auto_btn() -> void:
	_auto_btn.text = "⏸ Auto" if _auto else "▶ Auto"
	_auto_btn.modulate = Color(1.2, 1.15, 0.7) if _auto else Color.WHITE

# Runs while the battle window is up: plays a round whenever Auto is on and
# nothing else is playing. A short pause between rounds keeps it readable.
func _auto_loop(gen: int) -> void:
	while gen == _auto_gen and not _over and is_inside_tree():
		await get_tree().create_timer(0.9 / _speed).timeout
		if gen == _auto_gen and _auto and not _busy and not _over and visible:
			await _round()

# CPU fights: plays the whole battle on screen at a watchable pace.
func autoplay() -> void:
	_auto_gen += 1   # the CPU loop below drives this one
	_auto_btn.hide()
	_next_btn.disabled = true
	_skip_btn.disabled = true
	while not _over:
		await get_tree().create_timer(0.5).timeout
		if not _busy and not _over:
			await _round()
	_continue_btn.hide()   # no button — the caller closes the window
	await get_tree().create_timer(1.8).timeout

# Resolve the whole battle instantly (no animations, no beats, no cards).
func _on_skip() -> void:
	_skip_btn.disabled = true
	_skipping = true
	while _busy:
		await get_tree().process_frame
	while not _over:
		await _round()
	_skipping = false

# "Go, X!" — or in PvP, both trainers announce their picks by name.
func _sendout_line(is_me: bool) -> String:
	var mon: Dictionary = _team[_active] if is_me else _opp[_opp_active]
	if _pvp_names.size() == 2:
		return "%s chooses %s!" % [_pvp_names[0] if is_me else _pvp_names[1], _who(mon)]
	return ("Go, %s!" if is_me else "Opponent sends out %s!") % _who(mon)

func _opening() -> void:
	_busy = true
	_logln("Battle start! " + _sendout_line(true))
	await _beat(0.5)
	if _pvp_names.size() == 2:
		_logln(_sendout_line(false))
		await _beat(0.5)
	await _apply_traits()
	await _apply_match_start()
	await _on_entry(true)
	await _on_entry(false)
	_refresh()
	_busy = false
	if _auto:
		_auto_loop(_auto_gen)

func _round() -> void:
	if _over or _busy:
		return
	_busy = true
	_round_num += 1
	_logln("[color=#a89ae0]— Round %d —[/color]" % _round_num)
	# tactic cards come first (Purify can cure before statuses tick)
	var picks := _choose_cards()
	if picks[0] != "":
		_played[0] = true
		await _play_tactic(picks[0], true)
	if picks[1] != "":
		_played[1] = true
		await _play_tactic(picks[1], false)
	_refresh_hands()
	var me: Dictionary = _team[_active]
	var op: Dictionary = _opp[_opp_active]
	var me_acts: bool = await _process_status(me)
	var op_acts: bool = await _process_status(op)
	me_acts = await _trait_tick(me, me_acts) and not me.get("_r_boo", false)
	op_acts = await _trait_tick(op, op_acts) and not op.get("_r_boo", false)
	if me.get("_r_boo", false):
		_logln("%s is too scared to move!" % _who(me))
		_tactic_banner("👻", "Boo!", "%s is too scared to move" % me.get("name", "?"), Color("c8a8ff"))
	if op.get("_r_boo", false):
		_logln("%s is too scared to move!" % _who(op))
		_tactic_banner("👻", "Boo!", "%s is too scared to move" % op.get("name", "?"), Color("c8a8ff"))
	# round-start abilities fire "at the same time" → faster spirit first
	var me_first := _goes_first(me, op)
	if me.get("_r_haste", false) != op.get("_r_haste", false):
		_tactic_banner("⚡", "Haste!", "%s moves first this round" % (me if me_first else op).get("name", "?"), Color("ffd24d"))
	for actor in ([me, op] if me_first else [op, me]):
		for slot in 2:
			await _round_start_abilities(actor, op if actor == me else me, slot)
	await _bench_round_abilities(_team, _active)
	await _bench_round_abilities(_opp, _opp_active)
	# last call: a card tapped while the round was starting plays now, before
	# anyone attacks (no await between this check and _attacking = true)
	for side in 2:
		var late: String = _armed if side == 0 else _opp_armed
		if late != "" and not _played[side] and not _skipping:
			if side == 0:
				_armed = ""
			else:
				_opp_armed = ""
			_played[side] = true
			await _play_tactic(late, side == 0)
	me = _team[_active]   # a Switcheroo may have changed the leads
	op = _opp[_opp_active]
	_attacking = true
	if me_first:
		await _attack_turn(me, op, true, me_acts)
		await _attack_turn(op, me, false, op_acts)
	else:
		await _attack_turn(op, me, false, op_acts)
		await _attack_turn(me, op, true, me_acts)
	await _helping_hand(_team, _active)
	await _helping_hand(_opp, _opp_active)
	me = _team[_active]
	op = _opp[_opp_active]
	# EXHAUSTION: from FATIGUE_START, both fighters lose escalating HP each round
	# so heal-loop stalemates always end.
	if _round_num >= Balance.FATIGUE_START:
		var burn: int = (_round_num - Balance.FATIGUE_START + 1) * 5
		for m in [me, op]:
			if _alive(m):
				m["current_hp"] = maxi(0, int(m["current_hp"]) - burn)
		_logln("[color=#e0b060]Exhaustion sets in — both fighters lose %d HP![/color]" % burn)
		await _beat(0.35)
	if not _alive(me):
		await _vengeance(_team, op)
	if not _alive(op):
		await _vengeance(_opp, me)
	_clear_round_flags()
	_attacking = false
	_played = [false, false]
	# independent checks: Destiny Bond / Explosion can drop both at once
	if not _alive(op):
		await _faint(op, false)
	if not _over and not _alive(me):
		await _faint(me, true)
	if not _over and _round_num >= Balance.MAX_ROUNDS:
		_logln("[color=#e0b060]The battle drags on too long — judged by remaining HP![/color]")
		_end(_side_hp(_team) >= _side_hp(_opp))
	_refresh()
	_refresh_hands()
	_busy = false

func _goes_first(me: Dictionary, op: Dictionary) -> bool:
	var mh: bool = me.get("_r_haste", false)
	var oh: bool = op.get("_r_haste", false)
	if mh != oh:
		return mh
	return int(me.get("spd", 0)) >= int(op.get("spd", 0))

# One fighter's attack — or its signature move when charged — twice with Fury.
func _attack_turn(att: Dictionary, def_: Dictionary, is_me: bool, acts: bool) -> void:
	if not acts or not _alive(att) or not _alive(def_):
		return
	await _attack_or_move(att, def_, is_me)
	if att.get("_r_fury", false) and _alive(att) and _alive(def_):
		_logln("💢 Fury! %s strikes again!" % _who(att))
		_tactic_banner("💢", "Fury!", "%s strikes again" % att.get("name", "?"), Color("ff7a5a"))
		await _strike(att, def_, is_me)

func _side_hp(side: Array) -> int:
	var n := 0
	for m in side:
		n += maxi(0, int(m.get("current_hp", 0)))
	return n

# A fainted spirit leaves only AFTER its damage shake has played.
func _faint(mon: Dictionary, is_me: bool) -> void:
	_logln("%s fainted!" % _who(mon))
	if not _quiet():
		Sfx.play("faint")
	await _beat(0.45)
	# Fallen: surviving allies grow stronger with every loss
	for a in _side_of(mon):
		if a != mon and _alive(a) and _has(a, "fallen"):
			_buff(a, "atk", 1)
			_buff(a, "def", 1)
			await _ability_line("Passive", a, "Fallen", "avenges the fallen — ATK/DEF +1")
	# Last Stand: the final spirit standing rallies
	var allies: Array = _side_of(mon).filter(_alive)
	if allies.size() == 1 and _has(allies[0], "monument"):
		await _entry_ability(allies[0], _side_of(mon), _foes_of(mon), 0, "monument")
	mon["_gone"] = true
	_refresh()
	await _beat(0.35)
	if is_me:
		_active += 1
		if _active >= _team.size():
			_end(false)
			return
	else:
		_opp_active += 1
		if _opp_active >= _opp.size():
			_end(true)
			return
	_logln(_sendout_line(is_me))
	await _beat(0.4)
	await _on_entry(is_me)

func _end(player_won: bool) -> void:
	_over = true
	_won = player_won
	_next_btn.disabled = true
	_skip_btn.hide()
	_auto_btn.hide()
	# battle damage is real: write HP back (clamped to the true max)
	for m in _team:
		var oi: int = int(m.get("_oi", -1))
		if oi >= 0 and oi < _src_team.size():
			var orig: Dictionary = _src_team[oi]
			orig["current_hp"] = clampi(int(m.get("current_hp", 0)), 0, int(orig.get("hp", 1)))
	if player_won:
		_logln("[color=#9f9]You won the battle![/color]")
		var survivors: Array = []
		for m in _team.filter(_alive):
			_credit_stars(m, 0.5, false)   # survival isn't KO-capped
			survivors.append(m.get("name", "?"))
		if not survivors.is_empty():
			_logln("[color=#d3a8ff]%s earn%s half a star for surviving![/color]" % [
				", ".join(survivors), "s" if survivors.size() == 1 else ""])
	else:
		_logln("[color=#f99]Your team was defeated…[/color]")
	if not _skipping and visible:
		Sfx.play("win" if player_won else "lose")
		Juice.pop(_title, 1.3, 0.4)
	_refresh_hands()
	_pay_votes(player_won)
	_continue_btn.show()

# ---------------- 📱 phones ----------------

func _side_name(side: int) -> String:
	if side == 0:
		return _team_name_lbl.text
	if _pvp_names.size() == 2:
		return _opp_name_lbl.text
	return "%s (%s)" % [_title.text, String(_opp[0].get("name", "?"))] if not _opp.is_empty() else _title.text

func _lead_line(side: Array, active: int) -> String:
	if active >= side.size():
		return "—"
	var m: Dictionary = side[active]
	return "%s  ❤ %d/%d  (%d left)" % [m.get("name", "?"), int(m.get("current_hp", 0)), int(m.get("hp", 1)),
		side.filter(_alive).size()]

# A fighter's phone: the battle state, ITS OWN cards (the TV shows them
# face-down), and the battle buttons. Spectators get {} → Remote's idle menu,
# with the vote from spectator_view on top.
func remote_view(idx: int) -> Dictionary:
	var mine := idx == _hand_owner and _human
	var theirs := idx == _opp_owner and _opp_human
	if idx < 0 or not (mine or theirs):
		return {}
	var buttons: Array = []
	var actions: Array = []
	var hand: Array = (_hand if mine else _opp_hand).filter(func(k): return CardsData.kind_of(k) == "tactic")
	var armed: String = _armed if mine else _opp_armed
	if not _over:
		for key in hand:
			buttons.append({"label": "%s%s" % [CardsData.card_name(key), "  ✓ next" if armed == key else ""],
				"desc": String(CardsData.card(key).get("desc", "")), "card": true})
			actions.append(_arm.bind(key, mine))
	for b in [_continue_btn, _next_btn, _auto_btn, _speed_btn, _skip_btn]:
		if b.is_visible_in_tree() and not b.disabled:
			buttons.append({"label": String(b.text).get_slice("  [", 0), "gold": b == _continue_btn})
			actions.append(Remote.press_action(b))
	var lines: Array = [
		"🟢 You: " + _lead_line(_team if mine else _opp, _active if mine else _opp_active),
		"🔴 Foe: " + _lead_line(_opp if mine else _team, _opp_active if mine else _active)]
	if not _over:
		lines.append("Tap a card to read it, tap again to play it next round (one per round)." if not hand.is_empty()
			else "No tactic cards in this battle.")
	else:
		lines.append("🏆 You won!" if _won == mine else "💀 You lost…")
	return {"screen": "buttons", "title": "⚔ %s — round %d" % [_title.text, _round_num], "lines": lines,
		"buttons": buttons, "_actions": actions}

# A spectator's vote on this battle (Remote puts it above the idle menu).
func spectator_view(idx: int) -> Dictionary:
	if not visible or idx < 0 or idx == _hand_owner or idx == _opp_owner:
		return {}
	var names := [_side_name(0), _side_name(1)]
	if _over:
		if not _votes.has(idx):
			return {}
		var got: String = _vote_paid.get(idx, "")
		return {"title": "🗳 You picked %s" % names[_votes[idx]],
			"lines": ["✅ Right! You get %s." % got if got != "" else "❌ Wrong guess this time."]}
	if _votes.has(idx):
		return {"title": "🗳 You picked %s" % names[_votes[idx]], "lines": ["Right guess = +1 card (★ if your hand is full)."]}
	if _round_num >= VOTE_ROUNDS:
		return {"title": "🗳 Voting closed", "lines": ["%s vs %s" % names]}
	return {"title": "🗳 Who wins this battle?", "lines": ["Votes close at round %d. Right guess = +1 card (★ if your hand is full)." % VOTE_ROUNDS],
		"buttons": [{"label": "🟢 " + names[0], "gold": true}, {"label": "🔴 " + names[1], "gold": true}],
		"_actions": [_vote.bind(idx, 0), _vote.bind(idx, 1)]}

func _vote(idx: int, side: int) -> void:
	if _over or _round_num >= VOTE_ROUNDS or _votes.has(idx):
		return
	_votes[idx] = side
	Sfx.play("pop")
	_logln("[color=#c8a8ff]🗳 %s votes![/color]" % GameState.players[idx].player_name)

# Right guesses: a random card, or a star on a spirit when the hand is full.
func _pay_votes(left_won: bool) -> void:
	for idx in _votes:
		if idx >= GameState.players.size() or (int(_votes[idx]) == 0) != left_won:
			_vote_paid[idx] = ""
			continue
		var p: PlayerData = GameState.players[idx]
		var prize := ""
		if not p.inventory.hand_full():
			var key := CardsData.random_card()
			CardSystem.give(idx, key)   # not full → no discard popup
			prize = CardsData.card_name(key)
		else:
			# a star on the spirit furthest from 3★ (3★ would start the bonus flow mid-turn)
			var best: Dictionary = {}
			for m in p.team:
				if float(m.get("stars", 0)) <= 1.5 and (best.is_empty() or float(m.get("stars", 0)) < float(best.get("stars", 0))):
					best = m
			if not best.is_empty():
				SpiritsProgressionSystem.award_star(idx, best)
				prize = "a ★ for %s" % best.get("name", "?")
			else:
				p.inventory.gold += 20
				prize = "20 gold"
		_vote_paid[idx] = prize
		_logln("[color=#c8a8ff]🗳 %s guessed right: %s![/color]" % [p.player_name, prize])
		EventBus.log_entry.emit(idx, "🗳 %s guessed the battle right: %s!" % [p.player_name, prize], "#c8a8ff")

