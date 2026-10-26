# Blimps

`/blimps on` makes Marleyan airships drop out of the sky over the battlefield every so often. Each one
drifts around, fires volleys of artillery at random spots below it at random intervals, and leaves after a
while. The shells ignore teams.

Commands (admins; changes last until the server closes - edit `Config.Blimps` for permanent defaults):

| Command | Does |
|---|---|
| `/blimps on` / `off` | switch arrivals on / off (off: blimps already up leave) |
| `/blimps spawn [n]` | bring some in now (never above the max) |
| `/blimps clear` | remove them all immediately |
| `/blimps max <n>` | most blimps alive at once |
| `/blimps every <min> [max]` | seconds between arrivals |
| `/blimps stay <min> [max]` | how long each stays |
| `/blimps fire <min> [max]` | seconds between volleys, per blimp |
| `/blimps shells <min> [max]` | shells per volley |
| `/blimps range <studs>` | how far from itself a blimp aims |
| `/blimps alt <min> [max]` | altitude above the ground |
| `/blimps radius <studs>` | size of the battlefield they patrol |
| `/blimps speed <n>` | drift speed |
| `/blimps here` | make where you stand the battlefield centre |
| `/blimps status` | show all current values |

The shell itself (damage, blast size, random size ranges, sounds) is `ArtilleryConfigs/BlimpBarrage.luau`.

## Swapping in your own model

1. Build the model in Studio. Needs a `PrimaryPart` (any part, e.g. the envelope). The **nose points along -Z**.
2. Add small parts named exactly **`Muzzle`** wherever shells should leave from (any number; one is picked at random per volley). Make them invisible if you like. With none, shells leave from beneath the hull.
3. Right-click the model -> Save to File -> `Blimp.rbxm`, and put it in `assets/blimps/`. The file name is the model name; `Config.Blimps.Model` is `"Blimp"` by default (or `/blimps model OtherName` to switch live).
4. Nothing else: everything is anchored, made non-colliding and scripts are removed automatically. Delete the file and the placeholder comes back.

Scale it however you want; patrol altitude is set separately (`/blimps alt`), so a larger blimp may want a higher altitude.
