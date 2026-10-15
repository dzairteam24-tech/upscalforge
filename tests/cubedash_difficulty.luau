-- How hard each Cubedash stage is, measured by bots that play like a pro, a casual player and a novice (see
-- cubedash_bot.luau). Every stage must be fair (a pro nearly always gets through) and they must get harder.
-- Slow (about a minute and a half). Run from the repo root:  lune run tests/cubedash_difficulty.luau

local process = require("@lune/process")
local Loader = require("./loader")
local Bot = require("./cubedash_bot")
local Shared = Loader.root("cubedash/shared", "Shared")
local Stage = Loader.require(Shared.Logic.Stage)
local Speed = Loader.require(Shared.Logic.Speed)
local CourseConfig = Loader.require(Shared.Config.Course)

local RUNS = tonumber(process.args[1]) or 20
local passed, failed = 0, 0
local function check(name: string, ok: boolean, detail: string?)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL: " .. name .. (if detail then " (" .. detail .. ")" else ""))
	end
end

local rates: { [string]: { number } } = { pro = {}, casual = {}, novice = {} }
print("stage length walk obstacles |  pro  casual  novice  (what got the pro)")
for k = 1, CourseConfig.STAGES do
	local stage = Stage.generate(k)
	local line = string.format("%3d %6d %5.1f %5d     |", k, stage.length, Speed.walk(stage.needs), #stage.obstacles)
	local kill = ""
	for _, skill in { Bot.PRO, Bot.CASUAL, Bot.NOVICE } do
		local rate, killers = Bot.rate(stage, skill, RUNS)
		rates[skill.name][k] = rate
		line ..= string.format(" %4.0f%%", rate * 100)
		if skill == Bot.PRO then
			for kind, n in killers do
				kill ..= " " .. kind .. "=" .. n
			end
		end
	end
	print(line .. "  " .. kill)
end

for k = 1, CourseConfig.STAGES do
	check("stage " .. k .. " is fair: a pro gets through", rates.pro[k] >= 0.6, tostring(rates.pro[k]))
end
check("stage 1 is easy for a casual player", rates.casual[1] >= 0.75, tostring(rates.casual[1]))
check("and most novices", rates.novice[1] >= 0.6, tostring(rates.novice[1]))
check("stage 10 is much harder for a casual player", rates.casual[10] <= rates.casual[1] - 0.3)
check("and for a novice", rates.novice[10] <= rates.novice[1] - 0.4)
local function mean(list: { number }, from: number, to: number): number
	local sum = 0
	for k = from, to do
		sum += list[k]
	end
	return sum / (to - from + 1)
end
check("each third of the course is harder than the one before (casual)", mean(rates.casual, 1, 3) > mean(rates.casual, 4, 7) and mean(rates.casual, 4, 7) > mean(rates.casual, 8, 10))
check("each third of the course is harder than the one before (novice)", mean(rates.novice, 1, 3) > mean(rates.novice, 4, 7) and mean(rates.novice, 4, 7) > mean(rates.novice, 8, 10))

print(("%d passed, %d failed"):format(passed, failed))
process.exit(if failed > 0 then 1 else 0)
