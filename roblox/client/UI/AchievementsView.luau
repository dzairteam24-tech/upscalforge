-- The Awards tab of the Quests window: Rank, its perks, the creature index count and every achievement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AchievementConfig = require(Shared.Config.Achievements)
local Cosmetics = require(Shared.Config.Cosmetics)
local Achievements = require(Shared.Logic.Achievements)
local Format = require(Shared.Logic.Format)
local World1 = require(Shared.Config.World1)
local Variants = require(Shared.Config.Variants)

local Theme = require(script.Parent.Theme)

local AchievementsView = {}

local ROMAN = { "I", "II", "III", "IV", "V" }

local function bar(parent: Instance, fraction: number, position: UDim2, size: UDim2, color: Color3?)
	local back = Theme.frame({ Position = position, Size = size, BackgroundColor3 = Color3.fromRGB(20, 24, 38) })
	Theme.corner(back, 6)
	local fill = Theme.frame({ Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1), BackgroundColor3 = color or Theme.green })
	Theme.corner(fill, 6)
	fill.Parent = back
	back.Parent = parent
end

function AchievementsView.build(body: Instance, data: { [string]: any })
	local done: { [string]: number } = data.achievements or {}
	local stars = Achievements.stars(done)
	local rank = Achievements.rank(stars)
	local nextPerk = Achievements.nextPerk(rank)
	local perRank = AchievementConfig.STARS_PER_RANK

	-- Rank header
	local header = Theme.frame({ Size = UDim2.new(1, -12, 0, 96), BackgroundColor3 = Theme.card, LayoutOrder = 1 })
	Theme.corner(header, 10)
	Theme.stroke(header, Theme.gold, 2)
	local title = Theme.label({
		Text = ("⭐ Rank %d · %d/%d stars"):format(rank, stars, Achievements.maxStars()),
		Font = Theme.titleFont,
		TextColor3 = Theme.gold,
		Size = UDim2.new(0.7, 0, 0, 28),
		Position = UDim2.fromOffset(12, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
	})
	title.Parent = header
	bar(header, (stars % perRank) / perRank, UDim2.fromOffset(12, 40), UDim2.new(0.6, 0, 0, 14), Theme.gold)
	local nextText = Theme.label({
		Text = if nextPerk
			then ("Next perk at Rank %d: %s · every %d stars = 1 Rank"):format(nextPerk.rank, nextPerk.text, perRank)
			else "Every Rank perk unlocked!",
		Font = Enum.Font.Gotham,
		TextColor3 = Theme.muted,
		Size = UDim2.new(1, -24, 0, 22),
		Position = UDim2.fromOffset(12, 62),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 15,
	})
	nextText.Parent = header
	local total = 0
	for _ in World1.species do
		total += 1
	end
	local index = Theme.label({
		Text = ("📖 %d/%d discovered"):format(Achievements.discovered(data.index), total * #Variants.list),
		Size = UDim2.new(0.3, -12, 0, 28),
		Position = UDim2.new(0.7, 0, 0, 6),
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxTextSize = 16,
	})
	index.Parent = header
	header.Parent = body

	-- Achievements: unfinished first, then finished
	local order = 1
	local sorted = table.clone(AchievementConfig.list)
	local position = {}
	for i, achievement in AchievementConfig.list do
		position[achievement.id] = i
	end
	table.sort(sorted, function(a, b)
		local fa = (done[a.id] or 0) >= #a.goals
		local fb = (done[b.id] or 0) >= #b.goals
		if fa ~= fb then
			return not fa
		end
		return position[a.id] < position[b.id] -- stable: keep the config order
	end)
	for _, achievement in sorted do
		order += 1
		local tier = done[achievement.id] or 0
		local finished = tier >= #achievement.goals
		local nextTier = math.min(tier + 1, #achievement.goals)
		local goal = achievement.goals[nextTier]
		local value = Achievements.value(data :: any, achievement.stat)

		local row = Theme.frame({ Size = UDim2.new(1, -12, 0, 66), BackgroundColor3 = Theme.card, LayoutOrder = order })
		Theme.corner(row, 10)
		local tierStars = string.rep("★", tier) .. string.rep("☆", #achievement.goals - tier)
		local name = Theme.label({
			Text = ("%s %s  %s"):format(achievement.icon, achievement.name, tierStars),
			Font = Theme.titleFont,
			Size = UDim2.new(0.66, 0, 0, 24),
			Position = UDim2.fromOffset(10, 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if finished then Theme.gold else Theme.text,
			MaxTextSize = 18,
		})
		name.Parent = row
		local text = Theme.label({
			Text = if finished
				then "Complete!"
				else ("%s (%s)"):format((achievement.text:gsub("{goal}", Format.abbrev(goal))), ROMAN[nextTier]),
			Font = Enum.Font.Gotham,
			TextColor3 = Theme.muted,
			Size = UDim2.new(0.66, 0, 0, 18),
			Position = UDim2.fromOffset(10, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 14,
		})
		text.Parent = row
		if not finished then
			bar(row, value / math.max(1, goal), UDim2.fromOffset(10, 50), UDim2.new(0.5, 0, 0, 10))
			local count = Theme.label({
				Text = ("%s / %s"):format(Format.abbrev(math.min(value, goal)), Format.abbrev(goal)),
				Size = UDim2.new(0.14, 0, 0, 14),
				Position = UDim2.new(0.52, 14, 0, 48),
				TextXAlignment = Enum.TextXAlignment.Left,
				MaxTextSize = 12,
			})
			count.Parent = row
		end
		local rewardParts = {}
		if not finished then
			table.insert(rewardParts, "💎 " .. Format.abbrev(achievement.gems[nextTier] or 0))
			local titleId = achievement.titles and achievement.titles[nextTier]
			local titleDef = titleId and Cosmetics.titleById[titleId]
			if titleDef then
				table.insert(rewardParts, "Title: " .. titleDef.text)
			end
			table.insert(rewardParts, "+1 ⭐")
		end
		local reward = Theme.label({
			Text = if finished then "✓" else table.concat(rewardParts, "\n"),
			TextColor3 = if finished then Theme.green else Theme.gold,
			Size = UDim2.new(0.3, 0, 1, -12),
			Position = UDim2.new(0.69, 0, 0, 6),
			MaxTextSize = if finished then 28 else 15,
		})
		reward.Parent = row
		row.Parent = body
	end
end

return AchievementsView
