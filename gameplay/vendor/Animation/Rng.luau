--!strict
--[[
	Rng: a small seeded generator (xorshift32 over exact 32-bit integer arithmetic).

	Every random choice in a bake (hold drift phases, which side of a symmetric pair leads, the
	creature generator in the tests) comes from here and never from math.random, so the same
	clip, seed and rig bake to the same numbers on the server, every client and under Lune.
	bit32 works on exact integers in a double, so the sequence is identical everywhere Luau runs.
]]

local Rng = {}

export type Rng = { s: number }

local band, bxor, lshift, rshift = bit32.band, bit32.bxor, bit32.lshift, bit32.rshift

-- Exact 32-bit multiply (a double cannot hold the full 64-bit product, so split into halves).
local function imul(a: number, b: number): number
	local ah, al = rshift(a, 16), band(a, 0xFFFF)
	local bh, bl = rshift(b, 16), band(b, 0xFFFF)
	local lo = al * bl
	local mid = band(ah * bl + al * bh, 0xFFFF)
	return band(lo + lshift(mid, 16), 0xFFFFFFFF)
end

-- FNV-1a over a string, or a mix of a number's bits: a 32-bit seed from anything.
function Rng.hash(value: any): number
	local h = 2166136261
	local text = if type(value) == "string" then value else string.format("%.17g", tonumber(value) or 0)
	for i = 1, #text do
		h = bxor(h, string.byte(text, i))
		h = imul(h, 16777619)
	end
	-- xorshift needs a non-zero state
	if h == 0 then
		h = 0x9E3779B9
	end
	return h
end

function Rng.new(seed: any): Rng
	return { s = Rng.hash(if seed == nil then 1 else seed) }
end

local function step(r: Rng): number
	local x = r.s
	x = bxor(x, lshift(x, 13))
	x = bxor(x, rshift(x, 17))
	x = bxor(x, lshift(x, 5))
	x = band(x, 0xFFFFFFFF)
	if x == 0 then
		x = 0x9E3779B9
	end
	r.s = x
	return x
end

-- Uniform in [0, 1).
function Rng.next(r: Rng): number
	return step(r) / 4294967296
end

function Rng.range(r: Rng, lo: number, hi: number): number
	return lo + (hi - lo) * Rng.next(r)
end

-- Uniform integer in [lo, hi].
function Rng.int(r: Rng, lo: number, hi: number): number
	if hi <= lo then
		return lo
	end
	return lo + math.floor(Rng.next(r) * (hi - lo + 1))
end

function Rng.chance(r: Rng, p: number): boolean
	return Rng.next(r) < p
end

function Rng.pick<T>(r: Rng, list: { T }): T
	return list[Rng.int(r, 1, #list)]
end

-- A generator whose stream depends on this one's state and a label, so adding a draw in one
-- subsystem does not reshuffle another's.
function Rng.fork(r: Rng, label: any): Rng
	return { s = bxor(Rng.hash(label), step(r)) }
end

return Rng
