--[[
	SpawnOverride (server)
	One-shot "spawn the next body HERE" requests. Used when a shifter turns back to human:
	the player really respawns (Player:LoadCharacter), and PlayerService applies the
	override to the fresh body (position, facing and starting health) before the loadout.

		SpawnOverride.set(player, { CFrame = cf, HealthFraction = 0.5 })
		SpawnOverride.take(player)  -- returns the request once, then forgets it
]]

local SpawnOverride = {}

export type Request = { CFrame: CFrame, HealthFraction: number? }

local pending: { [Player]: Request } = {}

function SpawnOverride.set(player: Player, request: Request)
	pending[player] = request
end

function SpawnOverride.take(player: Player): Request?
	local request = pending[player]
	pending[player] = nil
	return request
end

function SpawnOverride.clear(player: Player)
	pending[player] = nil
end

return SpawnOverride
