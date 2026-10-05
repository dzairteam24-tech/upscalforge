--!strict
-- Cube Stack rules shared by the client (to play) and the server (to check and reward).

local Config = require(script.Parent.Parent.Config.Minigame)

local Minigame = {}

-- Where the new cube lands over the one below: the overlap stays, the rest falls. Positions are the left edge.
-- Returns the new left edge and width (width 0 = missed, game over).
function Minigame.place(belowLeft: number, belowWidth: number, left: number, width: number): (number, number)
	local newLeft = math.max(belowLeft, left)
	local newRight = math.min(belowLeft + belowWidth, left + width)
	return newLeft, math.max(0, newRight - newLeft)
end

-- A score the server accepts: not above the cap, and not faster than a person can play.
function Minigame.plausible(score: number, seconds: number): boolean
	return score >= 0 and score == math.floor(score) and score <= Config.MAX_SCORE and seconds >= score * Config.SECONDS_PER_CUBE
end

function Minigame.reward(score: number): { gems: number, tickets: number }
	return {
		gems = math.min(Config.MAX_GEMS, score * Config.GEMS_PER_CUBE),
		tickets = math.min(Config.MAX_TICKETS, score // Config.TICKETS_EVERY),
	}
end

return Minigame
