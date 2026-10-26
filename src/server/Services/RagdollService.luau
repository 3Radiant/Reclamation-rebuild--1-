local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)

local RagdollService = {}

local LIMITS = {
	Neck = { Swing = 45, Twist = 30 },
	["Left Shoulder"] = { Swing = 90, Twist = 45 },
	["Right Shoulder"] = { Swing = 90, Twist = 45 },
	["Left Hip"] = { Swing = 75, Twist = 20 },
	["Right Hip"] = { Swing = 75, Twist = 20 },
}

function RagdollService.ragdoll(character: Model)
	if character:GetAttribute("Ragdolled") then
		return
	end
	character:SetAttribute("Ragdolled", true)
	local settings = GameConfig.Ragdoll

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
		humanoid.AutoRotate = false
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") and descendant.Part0 and descendant.Part1 and descendant.Name ~= "RootJoint" then
			local a0 = Instance.new("Attachment")
			a0.Name = "RagdollA0"
			a0.CFrame = descendant.C0
			a0.Parent = descendant.Part0
			local a1 = Instance.new("Attachment")
			a1.Name = "RagdollA1"
			a1.CFrame = descendant.C1
			a1.Parent = descendant.Part1

			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "RagdollSocket"
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			local limit = LIMITS[descendant.Name]
			socket.LimitsEnabled = true
			socket.UpperAngle = if limit then limit.Swing else 60
			socket.TwistLimitsEnabled = true
			socket.TwistLowerAngle = -(if limit then limit.Twist else 30)
			socket.TwistUpperAngle = if limit then limit.Twist else 30
			socket.Parent = descendant.Part0

			descendant.Enabled = false
		end
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.CanCollide = false
	end
	for _, part in character:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.CanCollide = true
			pcall(part.SetNetworkOwner, part, nil)
			if settings.Impulse > 0 and part.Name == "Torso" then
				part:ApplyImpulse(Vector3.new(0, settings.Impulse * part.AssemblyMass, 0))
			end
		end
	end

	if settings.RemoveAfter > 0 then
		Debris:AddItem(character, settings.RemoveAfter)
	end
end

function RagdollService.watch(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.BreakJointsOnDeath = false
	humanoid.Died:Connect(function()
		if character:GetAttribute("Eaten") then
			return -- eaten bodies are hidden, not ragdolled
		end
		RagdollService.ragdoll(character)
	end)
end

return RagdollService