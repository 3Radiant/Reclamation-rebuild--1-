--[[
	HudController (client)
	Clean HUD, built entirely in code (no assets):

	  bottom-left   status card: name, health bar (green -> amber -> red), and the language chip
	  bottom-right  weapon: plain stencil text - name, big ammo count, cartridge ticks, stance, reload line
	                artillery card: ready / cooldown bar
	  bottom-right  shifter card: Titan name, shifts left, cooldown bar, key hint
	  Titan form    large Titan health bar + ability keys instead of the weapon cards

	Everything updates on RenderStepped from live state; cards hide when not relevant.
	Colours/sizes are at the top of the file.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Configs.Config)
local Languages = require(Shared.Languages)
local PlayerState = require(Shared.PlayerState)
local TitanConfigs = require(Shared.Configs.TitanConfigs)

local ArtilleryController = require(script.Parent.ArtilleryController)
local CharacterController = require(script.Parent.CharacterController)
local GunController = require(script.Parent.GunController)

local player = Players.LocalPlayer

local HudController = {}

local C = {
	Card = Color3.fromRGB(18, 20, 24),
	Track = Color3.fromRGB(44, 48, 56),
	Text = Color3.fromRGB(220, 216, 202), -- warm off-white
	Dim = Color3.fromRGB(138, 134, 120),
	Good = Color3.fromRGB(96, 200, 120),
	Warn = Color3.fromRGB(196, 160, 84),
	Bad = Color3.fromRGB(184, 66, 56),
	Accent = Color3.fromRGB(110, 160, 235),
	Titan = Color3.fromRGB(196, 74, 60),
}
local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold
local MARGIN = 20

----------------------------------------------------------------------
-- Tiny UI helpers
----------------------------------------------------------------------

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function label(parent: Instance, text: string, size: number, color: Color3, bold: boolean?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.Font = if bold then FONT_BOLD else FONT
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function card(parent: Instance, name: string, width: number, height: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = UDim2.fromOffset(width, height)
	f.BackgroundColor3 = C.Card
	f.BackgroundTransparency = 0.25
	f.BorderSizePixel = 0
	corner(f, 10)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.9
	stroke.Parent = f
	f.Parent = parent
	return f
end

-- A progress bar: returns (track, setFraction, setColor)
local function bar(parent: Instance, position: UDim2, size: UDim2, color: Color3)
	local track = Instance.new("Frame")
	track.Position = position
	track.Size = size
	track.BackgroundColor3 = C.Track
	track.BorderSizePixel = 0
	corner(track, 4)
	track.Parent = parent

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	corner(fill, 4)
	fill.Parent = track

	return track,
		function(fraction: number)
			fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
		end,
		function(newColor: Color3)
			fill.BackgroundColor3 = newColor
		end
end

local function chip(parent: Instance, text: string, color: Color3): (Frame, TextLabel)
	local f = Instance.new("Frame")
	f.AutomaticSize = Enum.AutomaticSize.X
	f.Size = UDim2.fromOffset(0, 20)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 0.75
	f.BorderSizePixel = 0
	corner(f, 10)
	f.Parent = parent

	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 9)
	pad.PaddingRight = UDim.new(0, 9)
	pad.Parent = f

	local l = label(f, text, 12, color, true)
	l.AutomaticSize = Enum.AutomaticSize.X
	l.Size = UDim2.fromOffset(0, 20)
	return f, l
end

local function healthColor(fraction: number): Color3
	if fraction > 0.6 then
		return C.Good
	elseif fraction > 0.3 then
		return C.Warn
	end
	return C.Bad
end

----------------------------------------------------------------------

function HudController.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "ReclamationHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Bottom-right stack of cards ------------------------------------------
	local stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.AnchorPoint = Vector2.new(1, 1)
	stack.Position = UDim2.new(1, -MARGIN, 1, -MARGIN)
	stack.Size = UDim2.fromOffset(260, 0)
	stack.AutomaticSize = Enum.AutomaticSize.Y
	stack.BackgroundTransparency = 1
	stack.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 8)
	layout.Parent = stack

	-- Weapon: no card, no colour blocks. Plain stencil-style text, right-aligned, with thin
	-- cartridge ticks for the ammo - the look of a field manual, not a mobile game.
	local weapon = Instance.new("Frame")
	weapon.Name = "Weapon"
	weapon.Size = UDim2.fromOffset(260, 74)
	weapon.BackgroundTransparency = 1
	weapon.LayoutOrder = 1
	weapon.Parent = stack

	local function rugged(text: string, size: number, color: Color3, xAlign: Enum.TextXAlignment, y: number, height: number): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.Code
		l.RichText = true
		l.Text = text
		l.TextSize = size
		l.TextColor3 = color
		l.TextXAlignment = xAlign
		l.Position = UDim2.fromOffset(0, y)
		l.Size = UDim2.new(1, 0, 0, height)
		local outline = Instance.new("UIStroke")
		outline.Thickness = 1
		outline.Transparency = 0.5
		outline.Color = Color3.new(0, 0, 0)
		outline.Parent = l
		l.Parent = weapon
		return l
	end

	local weaponName = rugged("", 13, C.Dim, Enum.TextXAlignment.Right, 0, 16)
	local ammoText = rugged("", 34, C.Text, Enum.TextXAlignment.Right, 14, 36)
	local stanceLabel = rugged("", 12, C.Dim, Enum.TextXAlignment.Left, 56, 16)
	local pips = Instance.new("Frame")
	pips.Position = UDim2.fromOffset(0, 54)
	pips.Size = UDim2.new(1, 0, 0, 12)
	pips.BackgroundTransparency = 1
	pips.Parent = weapon
	local pipLayout = Instance.new("UIListLayout")
	pipLayout.FillDirection = Enum.FillDirection.Horizontal
	pipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	pipLayout.Padding = UDim.new(0, 3)
	pipLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	pipLayout.Parent = pips
	local reloadLine = Instance.new("Frame") -- a 1px line that fills while reloading
	reloadLine.AnchorPoint = Vector2.new(1, 0)
	reloadLine.Position = UDim2.new(1, 0, 0, 72)
	reloadLine.Size = UDim2.fromOffset(0, 1)
	reloadLine.BackgroundColor3 = C.Text
	reloadLine.BorderSizePixel = 0
	reloadLine.Parent = weapon
	local function setReload(fraction: number)
		reloadLine.Size = UDim2.fromOffset(math.floor(260 * math.clamp(fraction, 0, 1)), 1)
	end
	local pipFrames: { Frame } = {}
	local pipGunId: string? = nil

	-- Artillery card
	local artillery = card(stack, "Artillery", 260, 52)
	artillery.LayoutOrder = 2
	local artilleryName = label(artillery, "", 14, C.Text, true)
	artilleryName.Position = UDim2.fromOffset(14, 8)
	artilleryName.Size = UDim2.new(0.6, 0, 0, 18)
	local artilleryStatus = label(artillery, "", 12, C.Dim, true)
	artilleryStatus.TextXAlignment = Enum.TextXAlignment.Right
	artilleryStatus.Position = UDim2.new(0.4, 0, 0, 8)
	artilleryStatus.Size = UDim2.new(0.6, -14, 0, 18)
	local _, setArtillery, setArtilleryColor = bar(artillery, UDim2.fromOffset(14, 34), UDim2.new(1, -28, 0, 6), C.Good)

	-- Shifter card
	local shifter = card(stack, "Shifter", 260, 62)
	shifter.LayoutOrder = 3
	local shifterName = label(shifter, "", 14, C.Text, true)
	shifterName.Position = UDim2.fromOffset(14, 8)
	shifterName.Size = UDim2.new(0.6, 0, 0, 18)
	local shifterStatus = label(shifter, "", 12, C.Dim, true)
	shifterStatus.TextXAlignment = Enum.TextXAlignment.Right
	shifterStatus.Position = UDim2.new(0.4, 0, 0, 8)
	shifterStatus.Size = UDim2.new(0.6, -14, 0, 18)
	local shiftsText = label(shifter, "", 12, C.Dim)
	shiftsText.Position = UDim2.fromOffset(14, 28)
	shiftsText.Size = UDim2.new(1, -28, 0, 16)
	local _, setShiftBar, setShiftBarColor = bar(shifter, UDim2.fromOffset(14, 48), UDim2.new(1, -28, 0, 6), C.Accent)

	-- Titan form: big health bar + abilities ---------------------------------
	local titanCard = card(gui, "TitanCard", 460, 62)
	titanCard.AnchorPoint = Vector2.new(0.5, 1)
	titanCard.Position = UDim2.new(0.5, 0, 1, -MARGIN)
	local titanName = label(titanCard, "", 16, C.Text, true)
	titanName.Position = UDim2.fromOffset(16, 8)
	titanName.Size = UDim2.new(0.5, 0, 0, 20)
	local titanKeys = label(titanCard, "", 12, C.Dim, true)
	titanKeys.TextXAlignment = Enum.TextXAlignment.Right
	titanKeys.Position = UDim2.new(0.4, 0, 0, 10)
	titanKeys.Size = UDim2.new(0.6, -16, 0, 18)
	local _, setTitanHealth = bar(titanCard, UDim2.fromOffset(16, 36), UDim2.new(1, -32, 0, 14), C.Titan)

	local function buildPips(gunId: string, count: number)
		for _, f in pipFrames do
			f:Destroy()
		end
		table.clear(pipFrames)
		for i = 1, count do
			local pip = Instance.new("Frame")
			pip.Size = UDim2.fromOffset(3, 12) -- a thin cartridge tick
			pip.BackgroundColor3 = C.Text
			pip.BorderSizePixel = 0
			pip.LayoutOrder = i
			pip.Parent = pips
			table.insert(pipFrames, pip)
		end
		pipGunId = gunId
	end

	RunService.RenderStepped:Connect(function()
		local character = CharacterController.getCharacter()
		local humanoid = CharacterController.getHumanoid()
		local isTitan = character ~= nil and character:GetAttribute("IsTitan") == true

		stack.Visible = not isTitan
		titanCard.Visible = isTitan

		if not character or not humanoid then
			stack.Visible = false
			titanCard.Visible = false
			return
		end

		local fraction = if humanoid.MaxHealth > 0 then humanoid.Health / humanoid.MaxHealth else 0

		if isTitan then
			local config = TitanConfigs[character:GetAttribute("TitanName")]
			titanName.Text = config and config.DisplayName or "Titan"
			setTitanHealth(fraction)
			local keys = { "LMB attack", "P turn back" }
			if config and config.Abilities then
				for name, ability in config.Abilities do
					table.insert(keys, 1, ("%s %s"):format(ability.Key.Name, name))
				end
			end
			titanKeys.Text = table.concat(keys, "   ")
			return
		end

		-- Weapon
		local gun = GunController.getActive()
		weapon.Visible = gun ~= nil
		if gun then
			if pipGunId ~= gun.Config.DisplayName then
				buildPips(gun.Config.DisplayName, gun.Config.Ammo)
			end
			local ammo = gun.Tool:GetAttribute("Ammo") or 0
			local reloading = gun.Tool:GetAttribute("Reloading") == true
			weaponName.Text = string.upper(gun.Config.DisplayName)
			local flareName = gun.Tool:GetAttribute("FlareColor")
			local flareColor = flareName and gun.Config.Colors and gun.Config.Colors[flareName]
			if flareColor then -- flare gun: show the loaded colour (V to change)
				local shown = if flareColor.R + flareColor.G + flareColor.B < 0.45 then Color3.fromRGB(120, 120, 128) else flareColor
				weaponName.Text ..= ('  <font color="#%s">%s</font>  [V]'):format(shown:ToHex(), string.upper(flareName))
			end
			ammoText.Text = ('%d<font size="16" color="#8a8678"> / %d</font>'):format(ammo, gun.Config.Ammo)
			ammoText.TextColor3 = if ammo == 0 then C.Bad else C.Text
			for i, pip in pipFrames do
				pip.BackgroundColor3 = if i <= ammo then C.Text else C.Track
			end

			local stanceText, stanceColor = string.upper(tostring(gun.Stance)), C.Dim
			if reloading then
				stanceText, stanceColor = "RELOADING", C.Warn
			elseif gun.Stance == "Aiming" then
				stanceColor = C.Bad
			elseif gun.Stance == "Ready" then
				stanceColor = C.Warn
			end
			stanceLabel.Text = stanceText
			stanceLabel.TextColor3 = stanceColor

			if reloading then
				local endsAt = gun.Tool:GetAttribute("ReloadEndsAt") or 0
				local total = math.max(gun.Config.ReloadTime, 0.01)
				setReload(1 - math.clamp((endsAt - Workspace:GetServerTimeNow()) / total, 0, 1))
			else
				setReload(0)
			end
		end

		-- Artillery
		local art = ArtilleryController.getActive()
		artillery.Visible = art ~= nil
		if art then
			local wait = ArtilleryController.getCooldown()
			artilleryName.Text = art.Config.DisplayName
			if wait > 0 then
				artilleryStatus.Text = ("%ds"):format(math.ceil(wait))
				artilleryStatus.TextColor3 = C.Warn
				setArtilleryColor(C.Warn)
				setArtillery(1 - math.clamp(wait / math.max(art.Config.Cooldown, 0.01), 0, 1))
			else
				artilleryStatus.Text = "READY - click to call"
				artilleryStatus.TextColor3 = C.Good
				setArtilleryColor(C.Good)
				setArtillery(1)
			end
		end

		-- Shifter
		local titanConfig = TitanConfigs[PlayerState.get(player, "ShifterName")]
		shifter.Visible = titanConfig ~= nil
		if titanConfig then
			local wait = math.max(0, PlayerState.get(player, "ShiftReadyAt") - Workspace:GetServerTimeNow())
			local left = PlayerState.get(player, "ShiftsLeft")
			shifterName.Text = titanConfig.DisplayName
			shiftsText.Text = ("Shifts left: %d"):format(left)
			if PlayerState.get(player, "Transforming") then
				shifterStatus.Text, shifterStatus.TextColor3 = "TRANSFORMING", C.Bad
				setShiftBar(1)
				setShiftBarColor(C.Bad)
			elseif left <= 0 then
				shifterStatus.Text, shifterStatus.TextColor3 = "NO SHIFTS LEFT", C.Dim
				setShiftBar(0)
			elseif wait > 0 then
				shifterStatus.Text, shifterStatus.TextColor3 = ("%ds"):format(math.ceil(wait)), C.Warn
				setShiftBarColor(C.Warn)
				setShiftBar(1 - math.clamp(wait / GameConfig.Shifting.Cooldown, 0, 1))
			else
				shifterStatus.Text, shifterStatus.TextColor3 = "P - SHIFT", C.Good
				setShiftBarColor(C.Good)
				setShiftBar(1)
			end
		end
	end)
end

return HudController
