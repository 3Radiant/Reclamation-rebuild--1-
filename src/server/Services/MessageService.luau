--[[
	MessageService (server)
	Big "server messages" shown to everyone (see MessageController on the client).

		MessageService.broadcast({ "The war has begun.", "Marley moves to reclaim..." })
		MessageService.broadcast({ "Heads up." }, { Style = "Alert", Hold = 4 })

	Style "Round": cinematic - letterbox bars and large centred lines, one after another.
	Style "Alert": a compact banner near the top. Chat: /announce line one | line two
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local MessageService = {}

export type Options = { Style: string?, Hold: number? }

function MessageService.broadcast(lines: { string }, options: Options?)
	local opts = options or {}
	Remotes.ServerMessage:FireAllClients({
		Lines = lines,
		Style = opts.Style or "Round",
		Hold = opts.Hold or 2.6, -- seconds each line stays fully visible
	})
end

function MessageService.send(player: Player, lines: { string }, options: Options?)
	local opts = options or {}
	Remotes.ServerMessage:FireClient(player, {
		Lines = lines,
		Style = opts.Style or "Round",
		Hold = opts.Hold or 2.6,
	})
end

return MessageService
