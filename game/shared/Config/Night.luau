--!strict
-- Night (Logic/Night), as in Steal an Egg: on the clock, the same in every server, night falls for a short
-- while every few minutes, and every egg on the grass or in an incubator grows SPEED times as fast meanwhile.

return {
	CYCLE = 10 * 60, -- a night comes this often (seconds, on the clock: :00, :10, :20...)...
	LENGTH = 20, -- ...and lasts this long, at the end of each cycle
	SPEED = 30, -- eggs grow this many times as fast at night
	WARNING = 60, -- the HUD counts down to the night from this long before
}
