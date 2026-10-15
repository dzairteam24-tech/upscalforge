--!strict
-- Starts Cubedash's services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared.Net)

local CourseService = require(script.Parent.Services.CourseService)
local DataService = require(script.Parent.Services.DataService)
local EconomyService = require(script.Parent.Services.EconomyService)
local RobuxService = require(script.Parent.Services.RobuxService)
local StudioTools = require(script.Parent.Services.StudioTools)

Net.init()
CourseService.init()
EconomyService.init(CourseService.teleport)
RobuxService.init()
DataService.init()
StudioTools.init(CourseService.teleport) -- (chat commands for trying things, in Studio only)
