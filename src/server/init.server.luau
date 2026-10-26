-- Server entry point. Each service owns one part of the game.
local Services = script:WaitForChild("Services")

local ArtilleryService = require(Services:WaitForChild("ArtilleryService"))
local BossBarService = require(Services:WaitForChild("BossBarService"))
local BlimpService = require(Services:WaitForChild("BlimpService"))
local ChatService = require(Services:WaitForChild("ChatService"))
local GunService = require(Services:WaitForChild("GunService"))
local MusicService = require(Services:WaitForChild("MusicService"))
local PlayerService = require(Services:WaitForChild("PlayerService"))
local ShifterService = require(Services:WaitForChild("ShifterService"))

GunService.start()
ShifterService.start()
ArtilleryService.start()
BossBarService.start()
BlimpService.start()
MusicService.start()
ChatService.start()
PlayerService.start() -- (also starts Teams + Rounds) last: starts handing out loadouts
