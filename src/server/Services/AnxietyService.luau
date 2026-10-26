--[[
	AnxietyService (server)
	Sends the anxiety effect (greyscale + vignette + heartbeat, see AnxietyController) to
	players. Use it from anywhere on the server:

		AnxietyService.apply(player, 0.7, 20)        -- level 0..1 for 20 seconds
		AnxietyService.applyRadius(pos, 60, 1, 14)   -- everyone near a point, stronger the closer
		AnxietyService.clear(player)

	Strong anxiety also pops an inner thought (Config.Anxiety.Thoughts), rate limited.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local Remotes = require(Shared.Remotes)

local ThoughtService = require(script.Parent.ThoughtService)

local AnxietyService = {}

local rng = Random.new()
local lastThoughtAt: { [Player]: number } = {}

function AnxietyService.apply(player: Player, level: number, duration: number)
	level = math.clamp(level, 0, 1)
	Remotes.Anxiety:FireClient(player, level, math.max(0, duration))

	local settings = GameConfig.Anxiety
	if level >= settings.ThoughtMinLevel and #settings.Thoughts > 0 then
		local now = os.clock()
		if now - (lastThoughtAt[player] or -math.huge) >= settings.ThoughtCooldown then
			lastThoughtAt[player] = now
			ThoughtService.system(player, settings.Thoughts[rng:NextInteger(1, #settings.Thoughts)])
		end
	end
end

function AnxietyService.clear(player: Player)
	Remotes.Anxiety:FireClient(player, 0, 0)
end

-- Everyone within `radius` studs of `position`. Level falls off with distance but never
-- drops below minFraction * level inside the radius (default 0.25).
function AnxietyService.applyRadius(position: Vector3, radius: number, level: number, duration: number, minFraction: number?)
	local floor = minFraction or 0.25
	for _, player in Players:GetPlayers() do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local distance = (root.Position - position).Magnitude
			if distance <= radius then
				local closeness = 1 - distance / radius
				AnxietyService.apply(player, level * math.max(floor, closeness ^ 0.7), duration)
			end
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	lastThoughtAt[player] = nil
end)

return AnxietyService
