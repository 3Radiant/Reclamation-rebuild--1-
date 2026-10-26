--[[
	DamageService (server)
	The ONE place damage is applied. Knows the difference between humans and Titans:
	  * Titans resist guns, take extra on the Nape, honour DamageMultiplier (hardening)
	  * Titan health is managed here so a defeated Titan returns the shifter to human
	    form instead of killing (and respawning) the player.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local Remotes = require(Shared.Remotes)
local HelmetService = require(script.Parent.HelmetService)

local DamageService = {}

-- Tells the attacker's client they got a kill (drives the grey screen flash).
-- Killing yourself doesn't count.
local function creditKill(attacker: Player?, victimModel: Model, kind: string)
	if attacker and Players:GetPlayerFromCharacter(victimModel) ~= attacker then
		Remotes.KillConfirm:FireClient(attacker, kind)
		attacker:SetAttribute("Kills", (attacker:GetAttribute("Kills") or 0) + 1) -- leaderboard
	end
end

-- The player a model belongs to: a human's own character, or the wielder of a Titan
local function ownerOf(model: Model): Player?
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return player
	end
	local userId = model:GetAttribute("OwnerUserId")
	return if userId then Players:GetPlayerByUserId(userId) else nil
end

-- ShifterService sets this: function(ownerPlayer, attackerPlayer)
DamageService.onTitanDefeated = nil :: ((Player?, Player?) -> ())?

-- info = { Source = "Gun" | "TitanMelee" | "Artillery", HitPart = BasePart? }
-- Returns the damage actually dealt.
function DamageService.damage(attacker: Player?, targetModel: Model, amount: number, info: any?): number
	info = info or {}

	-- No friendly fire (Config.Teams.FriendlyFire). Hurting yourself is still allowed.
	if attacker and not GameConfig.Teams.FriendlyFire then
		local victim = ownerOf(targetModel)
		if victim and victim ~= attacker and attacker.Team ~= nil and attacker.Team == victim.Team then
			return 0
		end
	end

	local humanoid = targetModel:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return 0
	end

	-- Humans: plain damage
	if not targetModel:GetAttribute("IsTitan") then
		if info.Source == "Gun" and info.HitPart and info.HitPart.Name == "Head" and HelmetService.absorb(targetModel) then
			return 0.01 -- tiny non-zero value so the shooter still gets their hit flash
		end
		humanoid:TakeDamage(amount)
		if humanoid.Health <= 0 then
			creditKill(attacker, targetModel, "Human")
		end
		return amount
	end

	-- Titans
	local multiplier: number = targetModel:GetAttribute("DamageMultiplier") or 1
	if info.Source == "Gun" then
		multiplier *= GameConfig.Damage.TitanGunMultiplier
	end
	if info.HitPart and info.HitPart.Name == "Nape" then
		multiplier *= GameConfig.Damage.NapeMultiplier
	end

	local final = amount * multiplier
	targetModel:SetAttribute("LastDamaged", Workspace:GetServerTimeNow())

	if humanoid.Health - final <= 0 then
		humanoid.Health = 1 -- never let the Titan humanoid actually die
		local owner = Players:GetPlayerByUserId(targetModel:GetAttribute("OwnerUserId") or 0)
		creditKill(attacker, targetModel, "Titan")
		if DamageService.onTitanDefeated then
			DamageService.onTitanDefeated(owner, attacker)
		end
		return final
	end

	humanoid.Health -= final
	return final
end

return DamageService
