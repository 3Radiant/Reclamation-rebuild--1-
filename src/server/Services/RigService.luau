--[[
	RigService (server)
	Guarantees normal players are R6, even if the experience's Avatar Type setting says
	R15 or "player choice". (Set Game Settings > Avatar > R6 as well; this is the safety net.)

	Shifters/Titans are R15 on purpose, and are never touched here.

	How: when a fresh R15 human spawns, build an R6 body from the same appearance
	(HumanoidDescription), swap it in as Player.Character, and delete the R15 one.
	Returns true if it swapped, in which case CharacterAdded fires again for the R6 body.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)

local RigService = {}

local APPEARANCE_TIMEOUT = 5

function RigService.ensureR6(player: Player, character: Model): boolean
	if not GameConfig.Rig.EnforceR6 or character:GetAttribute("IsTitan") then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or humanoid.RigType == Enum.HumanoidRigType.R6 then
		return false
	end
	if player.Character ~= character then
		return false
	end

	-- Let the player's avatar finish loading so the R6 copy keeps their look
	local started = os.clock()
	while not player:HasAppearanceLoaded() and os.clock() - started < APPEARANCE_TIMEOUT do
		task.wait(0.1)
	end
	if player.Character ~= character or player.Parent ~= Players then
		return false
	end

	local okDescription, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if not okDescription then
		description = Instance.new("HumanoidDescription")
	end

	local okBuild, body = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R6)
	end)
	if not okBuild or not body then
		warn("[RigService] Couldn't build an R6 body, leaving the R15 one:", body)
		return false
	end

	body.Name = player.Name
	body:PivotTo(character:GetPivot())
	player.Character = body
	body.Parent = Workspace
	character:Destroy()
	return true
end

return RigService
