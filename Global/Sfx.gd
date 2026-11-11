extends Node
## Autoloaded as `Sfx`. Short sound effects, synthesized in code on first use
## (no audio files needed). Sfx.play("coin"), Sfx.play("hit", 0.9) for pitch.
##
## Each sound is a list of SEGMENTS played back to back:
##   wave:  "sine" | "square" | "tri" | "noise"
##   f0/f1: start/end frequency in Hz (a sweep when they differ)
##   dur:   seconds        vol: 0..1        vib: [rate Hz, depth Hz] (optional)
## Segments with "rest": true are silence.

const MIX_RATE := 22050
const VOICES := 10

const SOUNDS := {
	"click":   [{"wave": "square", "f0": 880, "f1": 660, "dur": 0.04, "vol": 0.25}],
	"tick":    [{"wave": "tri", "f0": 1400, "dur": 0.022, "vol": 0.3}],
	"dice":    [{"wave": "noise", "dur": 0.05, "vol": 0.45}, {"wave": "sine", "f0": 190, "f1": 90, "dur": 0.12, "vol": 0.6}],
	"step":    [{"wave": "noise", "dur": 0.025, "vol": 0.18}],
	"jump":    [{"wave": "square", "f0": 300, "f1": 720, "dur": 0.11, "vol": 0.25}],
	"land":    [{"wave": "sine", "f0": 170, "f1": 80, "dur": 0.08, "vol": 0.5}],
	"crash":   [{"wave": "noise", "dur": 0.22, "vol": 0.55}, {"wave": "square", "f0": 200, "f1": 60, "dur": 0.2, "vol": 0.3}],
	"hit":     [{"wave": "noise", "dur": 0.06, "vol": 0.5}, {"wave": "square", "f0": 230, "f1": 110, "dur": 0.07, "vol": 0.25}],
	"crit":    [{"wave": "square", "f0": 990, "dur": 0.05, "vol": 0.3}, {"wave": "square", "f0": 660, "f1": 330, "dur": 0.1, "vol": 0.3}],
	"heal":    [{"wave": "sine", "f0": 523, "dur": 0.07, "vol": 0.4}, {"wave": "sine", "f0": 659, "dur": 0.07, "vol": 0.4},
				{"wave": "sine", "f0": 784, "dur": 0.12, "vol": 0.4}],
	"coin":    [{"wave": "square", "f0": 988, "dur": 0.06, "vol": 0.25}, {"wave": "square", "f0": 1319, "dur": 0.14, "vol": 0.25}],
	"card":    [{"wave": "noise", "dur": 0.09, "vol": 0.25}, {"wave": "tri", "f0": 500, "f1": 900, "dur": 0.08, "vol": 0.35}],
	"draw":    [{"wave": "tri", "f0": 600, "f1": 1000, "dur": 0.09, "vol": 0.35}],
	"wobble":  [{"wave": "sine", "f0": 420, "f1": 360, "dur": 0.12, "vol": 0.4}],
	"caught":  [{"wave": "square", "f0": 523, "dur": 0.08, "vol": 0.25}, {"wave": "square", "f0": 659, "dur": 0.08, "vol": 0.25},
				{"wave": "square", "f0": 784, "dur": 0.08, "vol": 0.25}, {"wave": "square", "f0": 1047, "dur": 0.22, "vol": 0.25}],
	"escape":  [{"wave": "square", "f0": 420, "f1": 180, "dur": 0.3, "vol": 0.25}],
	"win":     [{"wave": "square", "f0": 523, "dur": 0.1, "vol": 0.25}, {"wave": "square", "f0": 659, "dur": 0.1, "vol": 0.25},
				{"wave": "square", "f0": 784, "dur": 0.1, "vol": 0.25}, {"wave": "square", "f0": 1047, "dur": 0.35, "vol": 0.25}],
	"lose":    [{"wave": "tri", "f0": 392, "dur": 0.15, "vol": 0.4}, {"wave": "tri", "f0": 330, "dur": 0.15, "vol": 0.4},
				{"wave": "tri", "f0": 262, "dur": 0.35, "vol": 0.4}],
	"boo":     [{"wave": "sine", "f0": 230, "f1": 120, "dur": 0.45, "vol": 0.5, "vib": [9.0, 25.0]}],
	"shutter": [{"wave": "noise", "dur": 0.025, "vol": 0.5}, {"rest": true, "dur": 0.04}, {"wave": "noise", "dur": 0.04, "vol": 0.4}],
	"pop":     [{"wave": "sine", "f0": 600, "f1": 1300, "dur": 0.06, "vol": 0.4}],
	"beep":    [{"wave": "square", "f0": 660, "dur": 0.1, "vol": 0.2}],
	"go":      [{"wave": "square", "f0": 990, "dur": 0.25, "vol": 0.22}],
	"faint":   [{"wave": "tri", "f0": 620, "f1": 140, "dur": 0.4, "vol": 0.4}],
	"points":  [{"wave": "tri", "f0": 784, "dur": 0.07, "vol": 0.4}, {"wave": "tri", "f0": 1047, "dur": 0.12, "vol": 0.4}],
	"error":   [{"wave": "square", "f0": 150, "dur": 0.15, "vol": 0.25}],
	"whoosh":  [{"wave": "noise", "dur": 0.18, "vol": 0.3}],
	"collect": [{"wave": "sine", "f0": 880, "f1": 1760, "dur": 0.08, "vol": 0.35}],
}

var _cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0

const START_VOLUME := 0.10   # the whole game (menus + board) opens at 10%

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # plays while events pause the board
	AudioServer.set_bus_volume_db(0, linear_to_db(START_VOLUME))
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		_players.append(p)

func play(sound: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not SOUNDS.has(sound):
		return
	if not _cache.has(sound):
		_cache[sound] = _render(SOUNDS[sound])
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _cache[sound]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()

# ── synthesis ─────────────────────────────────────────────────────────────────

func _render(segments: Array) -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	for seg in segments:
		_append_segment(samples, seg)
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	return wav

func _append_segment(out: PackedFloat32Array, seg: Dictionary) -> void:
	var n := int(float(seg.get("dur", 0.1)) * MIX_RATE)
	if seg.get("rest", false):
		for i in n:
			out.append(0.0)
		return
	var wave := String(seg.get("wave", "sine"))
	var f0 := float(seg.get("f0", 440.0))
	var f1 := float(seg.get("f1", f0))
	var vol := float(seg.get("vol", 0.4))
	var vib: Array = seg.get("vib", [0.0, 0.0])
	var phase := 0.0
	var attack := mini(n, int(0.004 * MIX_RATE))   # tiny fade-in: no clicks
	for i in n:
		var t := float(i) / float(maxi(1, n - 1))
		var freq := lerpf(f0, f1, t) + sin(TAU * float(vib[0]) * float(i) / MIX_RATE) * float(vib[1])
		phase = fmod(phase + freq / MIX_RATE, 1.0)
		var v: float
		match wave:
			"square": v = 1.0 if phase < 0.5 else -1.0
			"tri":    v = 4.0 * absf(phase - 0.5) - 1.0
			"noise":  v = randf_range(-1.0, 1.0)
			_:        v = sin(TAU * phase)
		var env := (1.0 - t) * (1.0 - t)                     # quick decay
		if i < attack:
			env *= float(i) / float(maxi(1, attack))
		out.append(v * vol * env)
