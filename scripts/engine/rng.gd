class_name Rng
extends RefCounted
## Small seedable PRNG so battles can be replayed in tests. random16() mirrors Gen 3's 16-bit Random().
## mulberry32 with explicit 32-bit masking (GDScript ints are 64-bit).

const MASK := 0xFFFFFFFF

static var global_rng: Rng = Rng.new()

var s: int

## seed = null picks a random 32-bit seed (TS default argument).
func _init(seed: Variant = null) -> void:
	if seed == null:
		s = randi() & MASK
	else:
		s = int(seed) & MASK

## Math.imul for unsigned 32-bit operands, returning the low 32 bits (unsigned).
static func imul(a: int, b: int) -> int:
	a &= MASK
	b &= MASK
	var a_hi := (a >> 16) & 0xFFFF
	var a_lo := a & 0xFFFF
	var b_hi := (b >> 16) & 0xFFFF
	var b_lo := b & 0xFFFF
	var cross := ((a_hi * b_lo + a_lo * b_hi) & 0xFFFF) << 16
	return (a_lo * b_lo + cross) & MASK

## Float in [0, 1) (TS next()).
func next_float() -> float:
	# mulberry32
	s = (s + 0x6d2b79f5) & MASK
	var t := s
	t = imul(t ^ (t >> 15), t | 1)
	t = (t ^ ((t + imul(t ^ (t >> 7), t | 61)) & MASK)) & MASK
	return float((t ^ (t >> 14)) & MASK) / 4294967296.0

## Integer in [0, n) (TS int(n)).
func int_below(n: int) -> int:
	return int(floor(next_float() * float(n)))

func random16() -> int:
	return int_below(65536)

func u32() -> int:
	return int_below(4294967296) & MASK

func chance(percent: int) -> bool:
	return int_below(100) < percent

func pick(arr: Array) -> Variant:
	return arr[int_below(arr.size())]
