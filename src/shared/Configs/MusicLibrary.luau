--[[
	MusicLibrary (shared) - the tracks that show up in the admin music panel (press M, or
	`/music ui`). Add your own audio asset IDs here; the panel lists them in this order.

	    { Id = 1234567890, Title = "Sasageyo (instrumental)", Category = "Combat" },

	  Id        the audio asset id (just the number)
	  Title     shown in the panel and the "now playing" notice
	  Category  optional; shown as a small grey tag and searchable

	IMPORTANT (Roblox rule): an audio asset only plays in your experience if it is public/free
	to use, or was uploaded by the same account/group that owns the experience. If a track
	never starts, the id is probably private - the player skips it and tells you.
]]

local library: { { Id: number, Title: string, Category: string? } } = {
	-- { Id = 0, Title = "Example track", Category = "Ambient" },
	{Id = 111662099664251, Title = "Call Of Silence", Category = "Emotional"},
	{Id = 97118823736747, Title = "XL-TT", Category = "Cinematic"},
	{Id = 128263162954072, Title = "Bauklotze", Category = "Emotional"},
	{Id = 122866117032906, Title = "DOA", Category = "Action"},
	{Id = 109075702910676, Title = "In The Forest", Category = "Action"},
	{Id = 108861922643499, Title = "Sea Of Fire", Category = "Action"},
	{Id = 129693273184169, Title = "Shougeki", Category = "Emotional"},
	{Id = 109533714301343, Title = "YouSeeBigGirl weird ver", Category = "Action"},
	{Id = 110493034369228, Title = "Steel Ball Run Theme", Category = "Uplifting"},
	{Id = 9457171306, Title = "Crinkle SCP:SL", Category = ""},
	{Id = 9760708057, Title = "Time Window - Payday 2", Category = "Action"},
	{Id = 85313758955726, Title = "Tar - Xenoblade X"},
	{Id = 89825419422832, Title = "Call Your Name"},
	{Id = 93977181026846, Title = "Counterattack Mankind"},
	{Id = 128224784825603, Title = "Reluctant Heroes"},
	{Id = 116160088230482, Title = "Eren's Berserk Theme"},
	{Id = 127678428099361, Title = "The Warriors"},
	{Id = 90294642551236, Title = "Rise - League of Legends"},
}

return library
