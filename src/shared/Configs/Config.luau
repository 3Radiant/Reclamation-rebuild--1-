--[[
	Config (shared) - global tuning values. Units: studs and seconds.
]]

local Config = {
	-- Rigs: normal players are R6. Shifters and Titans are R15 (their models must be R15).
	Rig = {
		EnforceR6 = true, -- if the experience's Avatar Type isn't R6, convert spawned players to R6
	},

	Gun = {
		-- R6 has no built-in "hold a rifle" pose. When a gun has no aim animation yet, the arms
		-- are posed in code (visible to every player). Turns itself off per gun once you add
		-- an `aim` animation in AnimationConfigs.Guns.
		ProceduralR6Pose = true,
	},

	StudsPerMeter = 3, -- used to turn canon Titan heights (metres) into studs
	DebugHitboxes = false, -- draw melee hitboxes in red

	-- Admins: the game owner (or group owner) is always an admin. Add extra UserIds here.
	-- In Studio everyone is an admin when AdminsInStudio is true.
	Admins = {} :: { number },
	AdminsInStudio = true,

	-- Inner thought pop-ups (bottom centre, above the hotbar)
	Thoughts = {
		Width = 480,
		MaxVisible = 5,
		Gap = 8, -- px between stacked thoughts
		BottomOffset = 118, -- px above the bottom of the screen (clears the hotbar)
		BaseLifetime = 4.5, -- seconds on screen...
		PerCharLifetime = 0.045, -- ...plus this per character
		MaxLifetime = 12,
		FadeTime = 0.6,
		TextSize = 20,
		MaxLength = 200, -- longest thought a player may type with /t
		HealthCheckKey = Enum.KeyCode.J,
		HealthCheckCooldown = 0.8,
	},

	-- Screen effect when you kill someone
	KillEffect = {
		Enabled = true,
		TitanIntensity = 1.25, -- defeating a Titan hits a little harder
		SoundId = "", -- e.g. "rbxassetid://123"; blank = silent
	},

	-- Chat languages (see Shared/Languages for the lists)
	-- The anxiety effect: greyscale + closing vignette + heartbeat pulse + slight tremor.
	-- Triggered by admins (/anxiety), artillery (warning + near-miss) or your own scripts
	-- via AnxietyService.apply(player, level 0..1, seconds).
	Anxiety = {
		MaxSaturationLoss = 0.9, -- at full level the screen is nearly greyscale
		VignetteStrength = 0.92, -- 0..1, how dark the edges get
		VignetteReach = 0.42, -- how far (fraction of the screen) the edges reach in at full level
		PulseRateMin = 1.0, -- heartbeats per second at low level
		PulseRateMax = 2.6, -- ...and at full level
		Tremor = 0.5, -- constant camera shake at full level (0 = off)
		FovNarrow = 7, -- degrees the FOV pinches on each heartbeat at full level
		FadeOutTime = 4, -- seconds spent easing out at the end of the duration
		HeartbeatSoundId = "", -- optional looping heartbeat, "rbxassetid://..." (blank = silent)
		ThoughtMinLevel = 0.4, -- levels at or above this also pop an inner thought
		ThoughtCooldown = 25,
		Thoughts = {
			"My hands won't stop shaking.",
			"*Breathe.* Just breathe.",
			"My heart is pounding... I can hear it in my ears.",
			"I can't think straight. I can't *think*.",
			"Everything feels so far away.",
			"Don't panic. **Don't panic.**",
		},
	},

	-- Global music player (MusicService). Admin only: /music ..., or the panel (UIKey / /music ui).
	-- Track list for the panel: Configs/MusicLibrary.luau
	Music = {
		DefaultVolume = 0.5, -- 0..1
		MaxQueue = 100,
		MaxIdsPerCommand = 10,
		LoadTimeout = 12, -- seconds to wait for a track to load before skipping it
		AnnounceTrack = true, -- everyone gets a small "now playing" card
		UIKey = Enum.KeyCode.M, -- opens the panel (admins)
	},

	Ragdoll = {
		Impulse = 6,
		RemoveAfter = 12,
	},

	-- Teams: created by TeamService. Players pick one in the join menu (or /team).
	Teams = {
		OnlyKnowOwnLanguage = true,
		FriendlyFire = false, -- false = you can't hurt teammates
		MaxImbalance = 3, -- you can't join a team that already has this many more players than the other
		SetSpeakLanguage = true, -- joining a team sets your chat language to theirs
		Order = { "Eldian", "Marleyan" },
		Eldian = {
			Display = "Eldian",
			Color = Color3.fromRGB(96, 190, 124),
			BrickColor = "Earth green", -- the Roblox Team colour (also matches team SpawnLocations)
			Language = "Eldian",
			Tagline = "Protect the Inheritors",
			Emblem = "", -- optional "rbxassetid://..." image for menu / leaderboard header
			SpawnPosition = Vector3.new(-60, 0.5, 0), -- only used if the map has no spawn of this team's colour
		},
		Marleyan = {
			Display = "Marleyan",
			Color = Color3.fromRGB(214, 84, 72),
			BrickColor = "Crimson",
			Language = "Marleyan",
			Tagline = "Reclaim the lost powers",
			Emblem = "",
			SpawnPosition = Vector3.new(60, 0.5, 0),
		},
	},

	-- Rank names shown on the leaderboard, highest first. The LAST one is the default.
	-- Admins set them with /rank <player> <rank>.
	Ranks = {
		Eldian = { "Commander", "Captain", "Lieutenant", "Lance Corporal", "Corporal", "Private First Class", "Recruit" },
		Marleyan = { "General", "Colonel", "Major", "War Chief", "Vice War Chief", "Warrior", "Captain", "Lieutenant", "Sergeant", "Corporal", "Private" },
	},

	-- Rounds: each team has Lives lives. Every human death costs one. At 0 lives a team can't
	-- respawn, and when its last living member falls the other team wins.
	Round = {
		Enabled = true,
		Lives = 300,
		MinPlayers = 1, -- players on teams needed to start a round (raise for a real server)
		IntermissionTime = 20, -- seconds between rounds (players can pick teams / spawn in)
		RespawnTime = 5,
		MaxTime = 1800, -- seconds; when time runs out the team with more lives wins
		EndScreenTime = 12, -- how long the result stays up before the next intermission
		SlowMoDuration = 9, -- everyone moves in slow motion while the intro plays
		SlowMoSpeed = 0.3, -- 1 = normal
		-- One of these is picked at random for each round's intro (shown one line at a time)
		Intros = {
			{
				"The Eldian & Marleyan War has begun.",
				"Marley moves to reclaim their lost powers.",
				"The Eldians fight to protect their Inheritors.",
				"The battle between the Inheritors has begun.",
			},
			{
				"The walls of silence have fallen.",
				"Marley marches to take back what was stolen.",
				"Eldia stands to defend what remains.",
				"Let the war for the Titans begin.",
			},
			{
				"Once again, blood will decide the fate of the world.",
				"Marley hungers for the power of the Titans.",
				"Eldia will not give up its Inheritors.",
				"The battle between the Inheritors has begun.",
			},
		},
		Victory = {
			Eldian = { "The Eldians have won.", "The Inheritors are safe... for now." },
			Marleyan = { "Marley has won.", "The powers of the Titans are theirs once more." },
			Draw = { "The war ends in a stalemate.", "Neither side could claim the Inheritors." },
		},
	},

	-- /cursor: anyone can change their own mouse cursor. Presets are name = image asset id.
	Cursor = {
		Presets = {
			Box = "rbxassetid://4127964114"
			-- Crosshair = "rbxassetid://0000000000",
		},
	},

	-- Cinematic intros: /armoredtitanintro (admins). Text types out near the bottom middle; when
	-- the Trigger phrase is reached the camera turns to the Titan's holder and slowly closes in,
	-- everyone else gets a random inner thought and a rush of anxiety, then the camera returns.
	Intros = {
		ArmoredTitan = {
			Text = "Citizens of the Republic, bear witness to the shield that has never failed you. Marley's Bulwark stands as the nation's eternal sentinel, a living fortress whose stride has carried our banners through fire and ruin. His armour is not merely a gift, it is a covenant, a promise that no foreign power shall breach our borders, no invader shall claim our soil. When the Bulwark marches, the earth itself seems to steady beneath him, as though acknowledging its rightful guardian. He is the wall that stands between our people and Oblivion, and he has never once allowed that wall to crack.",
			Sound = "rbxassetid://119786714207702", -- plays for everyone when the intro starts ("" = none)
			SoundVolume = 1,
			Titan = "ArmoredTitan", -- whoever holds this Titan is the subject (shifted or not)
			Trigger = "Bulwark marches", -- the camera moves when this phrase has been typed
			CharsPerSecond = 16,
			Focus = { PanTime = 1.8, ZoomSeconds = 7, Zoom = 0.5, HoldSeconds = 7 }, -- HoldSeconds: how long before the camera returns
			AnxietyLevel = 0.8,
			AnxietySeconds = 9,
			ThoughtCount = 2,
			Thoughts = {
				"What is this feeling..?!",
				"I need to get away from that man..!",
				"My legs... they won't stop shaking.",
				"That presence... it's *crushing* me.",
				"Is it just me, or is the ground trembling..?",
				"**Don't look at him.** Don't look...",
				"I can't breathe. What *is* he..?",
			},
			HolderThought = "They are all looking at me.", -- shown to the holder instead (nil = nothing)
			EndHold = 8, -- seconds the finished text stays before fading
		},
	},

	-- Extra guns handed out on spawn, by team (everyone also gets the rifle). Names are GunConfigs.
	TeamGuns = {
		Eldian = {
			"FlareGun",
		},

		Marleyan = {
			"FlareGun",
			"Trench Shotgun",
		},
	},
	
	TeamItems = {
		Eldian = { "MarleyanHelmet" },
		Marleyan = { "MarleyanHelmet" },
	},

	Leaderboard = {
		StartOpen = true, -- the roster is open at first; Tab toggles it
		ToggleKey = Enum.KeyCode.Tab,
		ShowStats = false, -- kills / deaths numbers
		HideEnemyNames = false, -- true = players on the other team show as "???"
		MaxRows = 30,
	},

	-- Boss bars: big health bars at the top centre (BossBarService, /bossbar).
	BossBar = {
		Width = 620,
		TopOffset = 64, -- px from the top of the screen (the round timer sits above)
		Spacing = 12, -- px between stacked bars
		ShowNumbers = false, -- show "420 / 600" on the bar
		DeadFadeDelay = 1.6, -- seconds a bar stays (empty) after its target dies
		FillColor = Color3.fromRGB(150, 14, 14),
		TrailColor = Color3.fromRGB(226, 96, 84), -- the "damage just taken" sliver
	},

	-- Yells: a card at the bottom of the screen with the text, a portrait of the speaker's face
	-- on the right and their username bottom-left. Thought cards move up to make room.
	Yell = {
		Range = 400, -- studs: how far a player's /yell carries
		Cooldown = 1, -- seconds between a player's yells (admins' /yellto ignores it)
		MaxLength = 160,
		Width = 560,
		MaxVisible = 3,
		BottomOffset = 92, -- px above the bottom of the screen (clears the hotbar)
		BaseLifetime = 5,
		PerCharLifetime = 0.05,
		MaxLifetime = 14,
		TextSize = 18,
	},

	Chat = {
		-- false = LOCAL chat only: you only receive messages from players within ProximityRange
		-- studs (decided on the server, so it can't be bypassed). true = everyone hears everyone.
		GlobalChat = false,
		ProximityRange = 60,
		AdminsHearAll = false, -- admins receive every message even with GlobalChat off
		ShowChatWindow = false, -- the scrolling chat box. The input bar (to type) stays on either way
		Bubbles = true, -- overhead speech bubbles
		BubbleDuration = 6, -- seconds a bubble stays up
		BubblesPerPlayer = 3, -- older bubbles are pushed up and dropped past this
		BubbleMaxChars = 160,
	},

	Languages = {
		Default = "Eldian", -- what new players speak
		DefaultKnown = { "Eldian", "Marleyan" }, -- what new players understand
		AdminsUnderstandAll = false, -- true = admins read every language (hides the scrambling while testing in Studio, where everyone is an admin)
	},

	Movement = {
		Human = { Walk = 12, Crouch = 9, Run = 26, JumpHeight = 7.2 },
		JumpCooldown = 1.2,
		TitanJumpCooldown = 2.5,
	},
	FovWalk = 70,
	FovRun = 80,
	AnimationFadeTime = 0.3,

	Camera = {
		Sensitivity = 0.0035, -- radians per pixel of mouse movement
		MaxPitch = math.rad(80),

		-- Human: the normal Roblox third-person camera (centred behind you, focused on your head,
		-- no shoulder offset). Hold RIGHT MOUSE to look; the cursor stays free for aiming.
		-- Aiming changes (FOV / zoom / shoulder) are PER WEAPON: see AimFov, AimZoom, AimShoulder
		-- in each GunConfigs file.
		MinZoom = 3,
		MaxZoom = 30,
		DefaultZoom = 12.5, -- Roblox's default camera distance
		HeadOffset = Vector3.new(0, 1.5, 0), -- head height above the root (R6)

		-- Titan (mouse locked). The camera orbits the Titan's HEAD and sits slightly above it:
		-- TitanHeadScreenY is where the head appears on screen, as a fraction up from the
		-- bottom (0.35 = 35% up, i.e. in the lower third; 0.4 = a little higher). Distance is
		-- scaled by the Titan's height so it works for any size.
		TitanHeadScreenY = 0.4,
		TitanZoomMinScale = 1.1,
		TitanZoomMaxScale = 1.1,
		TitanDefaultPitch = math.rad(-10),
	},

	-- Marleyan blimps (BlimpService). Toggle and tune live with /blimps (see /blimps help).
	-- Every value below is just the starting value; commands change it for this server only.
	Blimps = {
		Model = "Blimp", -- ServerStorage/Blimps/<Model> (assets/blimps/Blimp.rbxm). Missing = placeholder.
		Barrage = "BlimpBarrage", -- ArtilleryConfigs entry used for their shells

		MaxAlive = 20, -- never more than this many at once
		SpawnEvery = { Min = 25, Max = 60 }, -- seconds between arrivals while switched on
		StayFor = { Min = 90, Max = 180 }, -- seconds a blimp stays before leaving
		Altitude = { Min = 230, Max = 900 }, -- studs above the ground at the battlefield
		Speed = 18, -- studs/second drift

		-- The battlefield the blimps patrol over and shell. /blimps here moves the centre to you.
		Area = { Center = Vector3.new(0, 0, 0), Radius = 900 },

		-- Each blimp fires at a random time and a random spot below it, with no regard for teams
		FireEvery = { Min = 6, Max = 16 }, -- seconds between volleys (per blimp)
		Shells = { Min = 1, Max = 4 }, -- shells per volley
		FireRadius = 280, -- shells aim up to this far (horizontally) from the blimp

		Announce = true, -- server message when blimps arrive
		AnnounceLines = { "Marleyan airships have been sighted." },
		Sounds = { Engine = "", Fire = "rbxassetid://118249846141433", Warhorn = ""}, -- "rbxassetid://..." (blank = silent)
	},

	-- Titan body: look tilt, stamina and dash (client side). Any value can be overridden per Titan
	-- by adding the same table to its TitanConfigs file (e.g. Stamina = { RunSeconds = 90 }).
	Titan = {
		-- The torso and head tilt to follow where the camera looks (up / down)
		Look = {
			Enabled = true,
			Strength = 0.92, -- 1 = the body follows the camera pitch exactly
			WaistShare = 0.6, -- how much of the tilt the waist takes (the neck takes the rest)
			MaxDown = math.rad(67),
			MaxUp = math.rad(55),
			Smoothing = 10, -- higher = snappier
			SendRate = 0.1, -- seconds between updates sent to other players
		},

		-- Running drains stamina: about RunSeconds of continuous running from full, and a LONG
		-- time to refill. Below ResumeAt you can't run until it recovers (you are winded).
		Stamina = {
			RunSeconds = 60,
			RegenSeconds = 150, -- empty -> full
			RegenDelay = 4, -- seconds after you stop running before it starts refilling
			ResumeAt = 0.2, -- fraction needed to run again after running out
		},

		-- A short dash in the direction you are holding (W / A / S / D; none = forward).
		-- Distance is in TITAN HEIGHTS so it scales with the model.
		Dash = {
			Key = Enum.KeyCode.Q,
			Distance = 1.5,
			Duration = 0.22,
			Cooldown = 1.5,
			StaminaCost = 0, -- fraction of the stamina bar (0 = free)
		},

		Grab = {
			ModeKey = Enum.KeyCode.LeftAlt,
			GrabKeys = { Left = Enum.KeyCode.Q, Right = Enum.KeyCode.E },
			UseKeys = { Left = Enum.KeyCode.T, Right = Enum.KeyCode.Y },
			Cooldown = 1.2,
			ReachTime = 0.45, ReachHit = 0.7,
			EatTime = 1.8, EatBite = 0.65,
			CrushTime = 1.1, CrushHit = 0.55,
			HitSize = Vector3.new(3, 2, 3), -- in Titan heights --0.5, 0.45, 0.5
			HitY = -0.2,
			HitForward = 0.55,
			HitSide = 0.22,
			EatHeal = 0.12,
			GrabTitans = true,
			GrabTeammates = true,
			HoldOffset = Vector3.new(0, 0.35, 0), -- where the victim sits in the hand (hand-size multiples)
			HoldRotation = Vector3.new(0, 0, 0), -- degrees
			AnxietyLevel = 0.9,
		},
	},

	Shifting = {
		-- Nobody gets a Titan automatically: admins give one with /shifter <player> <Titan>.
		MaxShifts = 3, -- per player per session. Raise while testing!
		BiteTime = 1.6, -- seconds; set to the length of your "bitehand" animation
		Cooldown = 20, -- seconds after turning back before shifting again

		-- Transformation lightning + flash (client-side, see ShiftEffects)
		Lightning = true,
		FlashRange = 400, -- other players closer than this also see the flash (fades with distance)
		-- Sound slots ("rbxassetid://..."). Shift = your Attack-on-Titan transformation sound
		-- (put the asset id here - I can't bundle copyrighted audio). Thunder defaults to a
		-- built-in Roblox boom so the lightning isn't silent.
		-- Custom Titan models (ServerStorage/Titans/<TitanName>, from assets/titans). See
		-- docs/CUSTOM_TITANS.md. These only affect custom models; the placeholder is always sized.
		CustomModels = {
			FitHeight = true, -- scale a custom model to HeightMeters * StudsPerMeter
			AutoNape = true, -- add an invisible Nape part if the model has none
			StripScripts = true, -- delete Scripts/LocalScripts inside the model
		},
		Sounds = {
			Shift = "rbxassetid://81957295389905",
			Thunder = "rbxasset://sounds/impact_explosion_03.mp3",
		},
	},

	Damage = {
		-- Rifles barely scratch a Titan (as in the anime). Nape shots hurt more.
		TitanGunMultiplier = 0.05,
		NapeMultiplier = 2,
		TitanArtilleryMultiplier = 1,
		HumanHealthAfterDefeat = 0.5, -- fraction of max health when forced out of Titan form
	},
}

return Config
