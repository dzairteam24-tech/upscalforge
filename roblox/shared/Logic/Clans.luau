--!strict
-- Clan rules that don't need Roblox: name checks, the clan document, points and weekly rewards.

local Config = require(script.Parent.Parent.Config.Clans)

export type Member = { name: string, points: number }

export type Clan = {
	id: string,
	name: string,
	tag: string,
	owner: number,
	members: { [string]: Member }, -- user id (as text) -> member
	week: number,
	points: number, -- this week
	created: number,
	kickDay: number?, -- day of the owner's last kick (one a day)
	kicked: { [string]: number }?, -- user id -> week they were kicked (can't rejoin that week)
}

local Clans = {}

function Clans.week(unixTime: number): number
	-- Weeks start on Monday 00:00 UTC (1970-01-01 was a Thursday)
	return math.floor((unixTime / 86400 + 3) / 7)
end

function Clans.checkName(name: string): (boolean, string?)
	local trimmed = string.match(name, "^%s*(.-)%s*$") or ""
	if #trimmed < Config.NAME_MIN or #trimmed > Config.NAME_MAX then
		return false, ("The name needs %d to %d letters"):format(Config.NAME_MIN, Config.NAME_MAX)
	end
	if not string.match(trimmed, "^[%w ]+$") then
		return false, "Use letters, numbers and spaces only"
	end
	return true, nil
end

function Clans.checkTag(tag: string): (boolean, string?)
	if #tag < Config.TAG_MIN or #tag > Config.TAG_MAX or not string.match(tag, "^%w+$") then
		return false, ("The tag needs %d to %d letters or numbers"):format(Config.TAG_MIN, Config.TAG_MAX)
	end
	return true, nil
end

function Clans.new(id: string, name: string, tag: string, ownerId: number, ownerName: string, now: number): Clan
	return {
		id = id,
		name = name,
		tag = string.upper(tag),
		owner = ownerId,
		members = { [tostring(ownerId)] = { name = ownerName, points = 0 } },
		week = Clans.week(now),
		points = 0,
		created = now,
	}
end

function Clans.count(clan: Clan): number
	local n = 0
	for _ in clan.members do
		n += 1
	end
	return n
end

function Clans.addMember(clan: Clan, userId: number, name: string, now: number?): (boolean, string?)
	if clan.members[tostring(userId)] then
		return true, nil
	end
	if now and clan.kicked and clan.kicked[tostring(userId)] == Clans.week(now) then
		return false, "You were removed from this clan. Try again next week."
	end
	if Clans.count(clan) >= Config.MAX_MEMBERS then
		return false, "This clan is full"
	end
	clan.members[tostring(userId)] = { name = name, points = 0 }
	return true, nil
end

-- Removes a member. The owner hands the clan to the member with the most points. Returns false when the
-- clan is now empty (it should be deleted).
function Clans.removeMember(clan: Clan, userId: number): boolean
	clan.members[tostring(userId)] = nil
	if clan.owner == userId then
		local best: string? = nil
		for id, member in clan.members do
			if not best or member.points > clan.members[best].points or (member.points == clan.members[best].points and id < best) then
				best = id
			end
		end
		if not best then
			return false
		end
		clan.owner = tonumber(best) :: number
	end
	return true
end

-- The owner removes a member: one kick a day, so a clan can't swap people in and out for the weekly reward.
-- The member's points stay with the clan.
function Clans.kick(clan: Clan, ownerId: number, targetId: number, now: number): (boolean, string?)
	if clan.owner ~= ownerId then
		return false, "Only the clan owner can remove members"
	end
	if targetId == ownerId then
		return false, "You can't remove yourself"
	end
	local target = tostring(targetId)
	if not clan.members[target] then
		return false, "That player isn't in the clan"
	end
	local day = math.floor(now / 86400)
	if clan.kickDay == day then
		return false, "You can remove one member a day"
	end
	clan.members[target] = nil
	clan.kickDay = day
	local week = Clans.week(now)
	local kicked: { [string]: number } = {}
	local old: { [string]: number } = clan.kicked or {}
	for id, w in old do
		if w == week then
			kicked[id] = w
		end
	end
	kicked[target] = week
	clan.kicked = kicked
	return true, nil
end

-- Adds points earned this week; a new week starts everyone from zero.
function Clans.addPoints(clan: Clan, contributions: { [string]: number }, now: number)
	local week = Clans.week(now)
	if clan.week ~= week then
		clan.week = week
		clan.points = 0
		for _, member in clan.members do
			member.points = 0
		end
	end
	for userId, points in contributions do
		local member = clan.members[userId]
		if member then
			member.points += points
			clan.points += points
		end
	end
end

function Clans.pointsFor(event: string, amount: number): number
	local per = Config.POINTS[event]
	return if per then per * amount else 0
end

-- Points a member can still add today from Break/Hatch (the daily cap). `state` is data.clan.
function Clans.capped(state: { day: number, everyday: number }, event: string, points: number, today: number): number
	if not Config.EVERYDAY_EVENTS[event] then
		return points
	end
	if state.day ~= today then
		state.day = today
		state.everyday = 0
	end
	local allowed = math.max(0, math.min(points, Config.EVERYDAY_CAP - state.everyday))
	state.everyday += allowed
	return allowed
end

-- Gems for a clan's weekly rank (1 = best), or 0.
function Clans.rewardFor(rank: number): number
	for _, tier in Config.REWARDS do
		if rank <= tier.upTo then
			return tier.gems
		end
	end
	return 0
end

return Clans
