-- Glowspire's stacking loop: the whole-number simulation, replays, tiers, and skill bots that show how hard each
-- feel preset is. Run from the repo root:  lune run tests/glowspire.luau

local process = require("@lune/process")
local Loader = require("./loader")

local Shared = Loader.root("glowspire/shared", "Shared")
local StackSim = Loader.require(Shared.Logic.StackSim)
local Stack = Loader.require(Shared.Config.Stack)

local passed, failed = 0, 0
local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail then " (" .. detail .. ")" else ""))
	end
end

-- a seeded generator (Park-Miller) and a normal draw
local function rng(seed: number)
	local s = seed % 2147483646 + 1
	local function unit(): number
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
	return {
		unit = unit,
		normal = function(): number
			local u1, u2 = math.max(unit(), 1e-12), unit()
			return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
		end,
	}
end

-- A bot aiming at dead center, off by a normal timing error of `sigma` ms
local function botRun(preset: string, sigma: number, seed: number): (any, { number })
	local r = rng(seed)
	local state = StackSim.new(preset)
	local taps = {}
	while not state.over and state.layer < 400 do
		local t = math.max(0, math.floor(StackSim.idealTime(state) + r.normal() * sigma + 0.5))
		table.insert(taps, t)
		StackSim.tap(state, t)
	end
	return state, taps
end

-- The slide: starts one span to the side, passes center, turns at the far side
do
	local s = StackSim.new("A")
	local span = s.preset.span
	check("starts a span to the side", StackSim.offset(s, 0) == -span)
	check("passes center at the ideal time", math.abs(StackSim.offset(s, StackSim.idealTime(s))) <= 1)
	local turn = (2 * span * 1000) // StackSim.speed(s)
	check("turns at the far side", math.abs(StackSim.offset(s, turn) - span) <= 1)
	check("comes back", StackSim.offset(s, turn * 2) <= -span + 2)
	check("first block slides along x, next along z", StackSim.axis(s) == "x")
end

-- Perfect, cut, miss
do
	local s = StackSim.new("A")
	local o = StackSim.tap(s, StackSim.idealTime(s))
	check("a dead-center tap is perfect", o.kind == "perfect" and s.layer == 1 and s.w == s.preset.start and s.perfects == 1)
	check("then z", StackSim.axis(s) == "z")
	-- past the easy layers, an off-center tap cuts
	local s2 = StackSim.new("A")
	for _ = 1, s2.preset.easyLayers do
		StackSim.tap(s2, StackSim.idealTime(s2))
	end
	local ideal = StackSim.idealTime(s2)
	local axis = StackSim.axis(s2)
	local before = if axis == "x" then s2.w else s2.d
	local late = ideal + 200
	local delta = StackSim.offset(s2, late)
	local cut = StackSim.tap(s2, late)
	local after = if axis == "x" then s2.w else s2.d
	check("a late tap cuts the overhang", cut.kind == "cut" and after == before - math.abs(delta), cut.kind .. " " .. after .. " vs " .. before .. "-" .. delta)
	check("the cut piece is the overhang", cut.cut ~= nil and cut.cut.size == math.abs(delta) and cut.cut.axis == axis)
	local center = if axis == "x" then s2.cx else s2.cz
	check("the kept part moved half the offset", center == (delta > 0 and 1 or -1) * (math.abs(delta) // 2))
	-- the kept and cut parts touch: kept edge == cut edge
	local keptEdge = center + (delta > 0 and 1 or -1) * after / 2
	local cutEdge = cut.cut.center - (delta > 0 and 1 or -1) * cut.cut.size / 2
	check("kept and cut parts meet", math.abs(keptEdge - cutEdge) <= 1, keptEdge .. " vs " .. cutEdge)
	check("combo reset by a cut", s2.combo == 0)
	-- a tap at the far end misses
	local s3 = StackSim.new("A")
	for _ = 1, s3.preset.easyLayers do
		StackSim.tap(s3, StackSim.idealTime(s3))
	end
	local miss = StackSim.tap(s3, 0)
	check("a tap a full span off misses and ends the run", miss.kind == "miss" and s3.over and s3.layer == s3.preset.easyLayers)
	check("nothing after the end", StackSim.tap(s3, StackSim.idealTime(s3)).kind == "miss" and s3.layer == s3.preset.easyLayers)
end

-- Easy first layers: a sloppy first tap still lands perfect
do
	local s = StackSim.new("A")
	local sloppy = StackSim.idealTime(s) + s.preset.perfectMs * 2
	check("the first blocks forgive a sloppy tap", StackSim.tap(s, sloppy).kind == "perfect")
end

-- Regrow after a streak of perfects
do
	local s = StackSim.new("A")
	for _ = 1, s.preset.easyLayers do
		StackSim.tap(s, StackSim.idealTime(s))
	end
	-- shrink both sides once, then streak
	StackSim.tap(s, StackSim.idealTime(s) + 150)
	StackSim.tap(s, StackSim.idealTime(s) + 150)
	local w0, d0 = s.w, s.d
	for _ = 1, s.preset.regrowEvery do
		StackSim.tap(s, StackSim.idealTime(s))
	end
	check("a streak of perfects grows a side back", s.w + s.d == w0 + d0 + s.preset.regrow, (s.w + s.d) .. " vs " .. (w0 + d0))
	check("never past the start size", s.w <= s.preset.start and s.d <= s.preset.start)
end

-- Replays: the same taps give the same run, every time
do
	local identical = true
	for seed = 1, 300 do
		for _, key in { "A", "B", "C" } do
			local played, taps = botRun(key, 60, seed)
			local again = StackSim.replay(key, taps)
			if again.layer ~= played.layer or again.perfects ~= played.perfects or again.w ~= played.w or again.d ~= played.d or again.cx ~= played.cx or again.cz ~= played.cz then
				identical = false
			end
		end
	end
	check("900 replays match the runs exactly", identical)
	local _, taps = botRun("A", 60, 7)
	table.insert(taps, 0)
	table.insert(taps, 0)
	check("extra taps after the end change nothing", StackSim.replay("A", taps).layer == botRun("A", 60, 7).layer)
	check("an unknown preset falls back to the default", StackSim.new("Z").preset == Stack.PRESETS[Stack.DEFAULT])
end

-- Tiers
do
	check("below 10: no Spire", StackSim.tier(9) == nil)
	check("10: Dim", StackSim.tier(10) == "Dim")
	check("80: Prismatic", StackSim.tier(80) == "Prismatic")
	check("500: Celestial", StackSim.tier(500) == "Celestial")
end

-- Skill bots: how hard is each preset? (timing error 20 ms = expert ... 120 ms = a young child, assumed)
do
	local RUNS = 300
	print("")
	print("preset  error  median  >=10 (Spire)  >=35 (Bright)  >=80 (Prismatic)  >=120 (Celestial)")
	local medians = {}
	for _, key in { "A", "B", "C" } do
		medians[key] = {}
		for _, sigma in { 20, 40, 80, 120 } do
			local layers = {}
			for seed = 1, RUNS do
				local s = botRun(key, sigma, seed * 7919 + sigma)
				table.insert(layers, s.layer)
			end
			table.sort(layers)
			local function share(min: number): string
				local n = 0
				for _, l in layers do
					if l >= min then
						n += 1
					end
				end
				return string.format("%5.1f%%", n / RUNS * 100)
			end
			local median = layers[RUNS // 2]
			medians[key][sigma] = median
			print(string.format("  %s     %3d ms  %5d   %s        %s         %s            %s", key, sigma, median, share(10), share(35), share(80), share(120)))
		end
		check("preset " .. key .. ": more skill, taller towers", medians[key][20] > medians[key][120])
	end
	check("gentle preset C is easier than fast B for a child", medians.C[120] >= medians.B[120])
end

print(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	process.exit(1)
end
