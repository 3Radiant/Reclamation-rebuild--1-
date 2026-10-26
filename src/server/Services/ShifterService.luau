--[[
	ShifterService (server)
	One shifter object PER PLAYER (no shared singleton), plus the remotes that drive
	them: ShiftToggle, TitanM1, TitanAbility. Also runs Titan regeneration.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local PlayerState = require(Shared.PlayerState)
local Remotes = require(Shared.Remotes)
local TitanConfigs = require(Shared.Configs.TitanConfigs)

local ShifterFolder = script.Parent.Parent:WaitForChild("Shifter")
local ShifterBase = require(ShifterFolder.ShifterBase)
local DamageService = require(script.Parent.DamageService)
local ThoughtService = require(script.Parent.ThoughtService)
local TitanFactory = require(ShifterFolder.TitanFactory)

-- Titan-specific subclasses (Shifter/Titans/<TitanName>). Titans without one use ShifterBase.
local TitanClasses: { [string]: any } = {}
for _, module in ShifterFolder.Titans:GetChildren() do
	if module:IsA("ModuleScript") then
		TitanClasses[module.Name] = require(module)
	end
end

local ShifterService = {}

local shifters: { [Player]: any } = {}

function ShifterService.get(player: Player): any
	return shifters[player]
end

-- Choose which Titan a player wields. Not allowed mid-transformation / while shifted.
function ShifterService.assign(player: Player, titanName: string): boolean
	if not TitanConfigs[titanName] then
		warn("[ShifterService] Unknown Titan:", titanName)
		return false
	end
	local existing = shifters[player]
	if existing and (existing.Shifted or existing.Transforming) then
		return false
	end

	local class = TitanClasses[titanName] or ShifterBase
	shifters[player] = class.new(player, titanName)
	PlayerState.set(player, "ShifterName", titanName)
	PlayerState.set(player, "ShiftsLeft", shifters[player].MaxShifts)
	return true
end

-- New round: forget any Titan state and hand out a fresh shifter (resets shifts left)
function ShifterService.reset(player: Player)
	local existing = shifters[player]
	PlayerState.set(player, "Shifted", false)
	PlayerState.set(player, "Transforming", false)
	if not existing then
		return -- not a shifter: nothing to reset
	end
	local titanName = existing.TitanName
	existing:Destroy()
	shifters[player] = nil
	ShifterService.assign(player, titanName)
end

-- Take a player's Titan away (not while they are shifted / transforming)
function ShifterService.unassign(player: Player): boolean
	local existing = shifters[player]
	if not existing then
		return true
	end
	if existing.Shifted or existing.Transforming then
		return false
	end
	existing:Destroy()
	shifters[player] = nil
	PlayerState.set(player, "ShifterName", "")
	PlayerState.set(player, "ShiftsLeft", 0)
	return true
end

function ShifterService.remove(player: Player)
	local shifter = shifters[player]
	if shifter then
		shifter:Destroy()
		shifters[player] = nil
	end
end

function ShifterService.start()
	TitanFactory.checkTemplates() -- prints OK / problems for every custom model in assets/titans

	-- A defeated Titan sends its wielder back to human form
	DamageService.onTitanDefeated = function(owner: Player?)
		local shifter = owner and shifters[owner]
		if shifter then
			task.spawn(shifter.Deshift, shifter, "Defeated") -- never respawn from inside the damage call
		end
	end

	Remotes.ShiftToggle.OnServerEvent:Connect(function(player)
		local shifter = shifters[player]
		if not shifter then
			ThoughtService.system(player, "I don't carry the power of a Titan.")
			return
		end
		if shifter.Shifted then
			task.spawn(shifter.Deshift, shifter, "Manual") -- yields while the new body loads
		else
			task.spawn(shifter.Shift, shifter) -- yields (bite animation), so don't block
		end
	end)

	-- Where a Titan's wielder is looking (up / down), so every client can tilt its body
	Remotes.TitanLook.OnServerEvent:Connect(function(player, pitch)
		local character = player.Character
		if character and character:GetAttribute("IsTitan") and typeof(pitch) == "number" and pitch == pitch then
			character:SetAttribute("LookPitch", math.clamp(pitch, -math.rad(89), math.rad(89)))
		end
	end)

	Remotes.TitanM1.OnServerEvent:Connect(function(player)
		local shifter = shifters[player]
		if shifter then
			shifter:M1()
		end
	end)

	Remotes.TitanMode.OnServerEvent:Connect(function(player)
		local shifter = shifters[player]
		if shifter then
			shifter:SetMode()
		end
	end)

	Remotes.TitanHand.OnServerEvent:Connect(function(player, action, arm)
		local shifter = shifters[player]
		if not shifter or typeof(action) ~= "string" or typeof(arm) ~= "string" then
			return
		end
		if action == "Grab" then
			shifter:Grab(arm)
		elseif action == "Use" then
			shifter:UseHand(arm)
		end
	end)

	Remotes.TitanAbility.OnServerEvent:Connect(function(player, abilityName)
		local shifter = shifters[player]
		if shifter and typeof(abilityName) == "string" then
			shifter:UseAbility(abilityName)
		end
	end)

	RunService.Heartbeat:Connect(function(dt)
		for _, shifter in shifters do
			if shifter.Shifted then
				shifter:Tick(dt)
			end
		end
	end)
end

return ShifterService
