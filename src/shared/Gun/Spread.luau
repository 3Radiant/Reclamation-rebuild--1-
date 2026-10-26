local Spread = {}

export type Pellet = { Direction: Vector3, SpeedScale: number }

function Spread.pellets(config: any, direction: Vector3, seed: number): { Pellet }
	local count: number = math.max(1, math.floor(config.Pellets or 1))
	local cone = math.rad(config.Spread or 0)
	local bias: number = config.SpreadCenterBias or 1
	local jitter: number = config.SpeedJitter or 0
	local rng = Random.new(seed)
	local base = CFrame.lookAt(Vector3.zero, direction.Unit)

	local pellets = {}
	for _ = 1, count do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = cone * rng:NextNumber() ^ (0.5 * bias)
		local rotated = base * CFrame.Angles(0, 0, angle) * CFrame.Angles(radius, 0, 0)
		table.insert(pellets, {
			Direction = rotated.LookVector,
			SpeedScale = 1 + (if jitter > 0 then rng:NextNumber(-jitter, jitter) else 0),
		})
	end
	return pellets
end

return Spread