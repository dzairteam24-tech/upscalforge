-- Loads the game's ModuleScripts outside Roblox so pure logic can be tested with Lune.
-- It fakes the `script` object (Name / Parent / child lookup) from the folder layout used by Rojo.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Loader = {}

-- Extra globals for modules that need engine stand-ins (set by a test before requiring).
Loader.extraEnv = {} :: { [string]: any }

local cache: { [string]: any } = {}
local nodes: { [string]: any } = {}

local function stripExt(name: string): string
	return (name:gsub("%.luau$", ""):gsub("%.lua$", ""))
end

-- Lune's fs calls can yield, and metamethods can't, so the whole tree is read up front.
local entries: { [string]: { children: { [string]: string }, source: string? } } = {}

local function scan(path: string)
	if fs.isDir(path) then
		local children = {}
		for _, entry in fs.readDir(path) do
			local childPath = path .. "/" .. entry
			children[stripExt(entry)] = childPath
			scan(childPath)
		end
		local init = path .. "/init.luau"
		entries[path] = { children = children, source = if fs.isFile(init) then fs.readFile(init) else nil }
	else
		entries[path] = { children = {}, source = fs.readFile(path) }
	end
end

local function makeNode(path: string, name: string, parent: any): any
	if nodes[path] then
		return nodes[path]
	end
	local node = { Name = name, Parent = parent, __path = path }
	setmetatable(node, {
		__index = function(self, key)
			local childPath = entries[path].children[key]
			if not childPath then
				error(("%s has no child %s"):format(path, tostring(key)), 2)
			end
			return makeNode(childPath, key, self)
		end,
	})
	nodes[path] = node
	return node
end

local requireNode

local function load(path: string, node: any): any
	if cache[path] ~= nil then
		return cache[path]
	end
	local source = entries[path].source
	assert(source, path .. " is not a module")
	local environment = {
			script = node,
			require = requireNode,
			Color3 = roblox.Color3,
			Vector2 = roblox.Vector2,
			Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame,
			Instance = roblox.Instance,
			Enum = roblox.Enum,
			UDim = roblox.UDim,
			UDim2 = roblox.UDim2,
			ColorSequence = roblox.ColorSequence,
			ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
			NumberSequence = roblox.NumberSequence,
			NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
			NumberRange = roblox.NumberRange,
	}
	for key, value in Loader.extraEnv do
		environment[key] = value
	end
	local chunk = luau.load(source, {
		debugName = path,
		environment = environment,
	})
	local result = chunk()
	cache[path] = result
	return result
end

function requireNode(target: any): any
	if type(target) == "table" and rawget(target, "__path") then
		return load(rawget(target, "__path"), target)
	end
	return require(target)
end

-- Returns the node for a folder that Rojo maps to an Instance, e.g. Loader.root("roblox/shared", "Shared").
function Loader.root(path: string, name: string): any
	scan(path)
	local parent = { Name = "ReplicatedStorage" }
	return makeNode(path, name, parent)
end

Loader.require = requireNode
Loader.stripExt = stripExt

return Loader
