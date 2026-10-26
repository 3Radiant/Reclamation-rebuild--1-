# Reclamation (rebuild)

A clean Rojo rebuild of the Warley / Attack on Titan game: movement, custom camera, projectile guns with
the Idle → Ready → Aiming stance system, and shifters (Armored, Attack, Female) with melee combat,
transformation and de-shifting.

## Setup

```
aftman install          # installs Rojo 7.7.0
rojo build -o Reclamation.rbxlx
rojo serve              # then connect from Studio's Rojo plugin
```

Open `Reclamation.rbxlx`, press Play. Everything the game needs (spawn, baseplate, `Hitboxes` folder,
`ServerStorage/Titans` and `ServerStorage/Guns`) is created by `default.project.json`, so a fresh
`rojo build` works from scratch. RemoteEvents are created in code (`Shared/Remotes`).

## Rigs: R6 humans, R15 Shifters/Titans

- **Normal players are R6.** `default.project.json` sets the place's Avatar Type to R6, but a published
  game's Avatar Type comes from the website, so also set **Game Settings > Avatar > R6** for your experience.
  As a safety net, `RigService` converts any R15 player that spawns into an R6 copy of their avatar
  (turn off with `Config.Rig.EnforceR6`).
- **Shifters and Titans are R15.** `TitanFactory` builds R15 placeholders and refuses a custom model in
  `assets/titans` unless its Humanoid is R15 (it also needs a part called `Nape`).
- **Animations are per rig.** Humans use `R6_Animations` and the gun animations; Titans use `R15_Animations`,
  overridden per Titan in `TitanConfigs.<Name>.Animations`. Author each set on the matching rig.
  Note `bitehand` has the same id in both tables (copied from your original), so replace the R6 one with
  an R6 version if it looks wrong.
- **Holding a gun in R6:** with no gun animations yet, `Gun/R6Pose` raises the arms in code for every player
  holding a gun (idle / ready / aiming), and stops by itself once a gun has an `aim` animation.

## Controls

| Key | Action |
| --- | --- |
| WASD / Space | move / jump |
| Left Shift | sprint |
| Left Ctrl | crouch (hold) |
| Hold Right Mouse | look around (normal Roblox third-person camera; cursor stays free for aiming) |
| Scroll | zoom |
| 1 | equip / unequip the rifle |
| Click | ready the gun (Idle → Ready). While Aiming: fire. Empty gun: reload |
| F | Ready ⇄ Aiming (you must ready the gun first) |
| R | reload |
| 2 | equip the Artillery Signal (aim the circle, click to call a barrage) |
| ; | open the admin command bar (admins only). Enter runs, Esc closes, Up/Down = history |
| Tab | open / close the roster (leaderboard) |
| V (flare gun) | cycle the flare colour (or `/flare red`, `blue`, `purple`, `yellow`, `green`, `black`, `white`, `orange`) |
| M | open the music panel (admins). Same as `/music ui` |
| Q (Titan) | short dash toward the W/A/S/D key you hold (forward if none) |
| Shift (Titan) | run: drains the stamina bar (~60 s from full, ~2.5 min to refill) |
| P | shift into your Titan / turn back (turning back respawns you as a human where the Titan stood) |
| J | check your health (an inner thought: "I currently feel perfect." ... "At this rate, I will perish.") |
| Left Click (Titan) | melee combo |
| E (Armored Titan) | Harden |

### Chat, languages and thoughts

| Command | Who | What it does |
| --- | --- | --- |
| `/t <text>` | everyone | an inner thought: pops up on YOUR screen and is also shown to admins (marked with your name). Nobody else sees it |
| `/eldian`, `/marleyan` | everyone | choose the language your chat messages are in |
| `/thought <me\|all\|name> <text>` | admins | pop a thought up on someone's screen |
| `/lang <me\|all\|name> <Eldian\|Marleyan\|Both>` | admins | set which languages someone understands |
| `/shifter <me\|all\|name> <Titan\|none>` | admins | give / take away a Titan. Nobody is a shifter until an admin sets them (`/titan <name>` is the self-assign shortcut) |
| `/anxiety <me\|all\|name> [1-10] [seconds\|off]` | admins | give someone the anxiety effect (greyscale, closing vignette, heartbeat pulse, tremor) |
| `/strike [me\|name]` | admins | call an artillery barrage on someone's position |
| `/bossbar <player\|npc name> [title]`, `/bossbar off [name\|all]` | admins | show a boss bar (live health) at the top centre of everyone's screen |
| `/music play <id\|name>`, `add <ids...>`, `skip`, `pause`, `resume`, `stop`, `clear`, `remove <n>`, `volume <0-100>`, `speed <0.5-2>`, `loop <off\|track\|queue>`, `shuffle`, `seek <secs>`, `queue`, `ui` | admins | the global music player. A bare id works too: `/music 1234567890` queues it |
| `/mymusic <0-100>` | everyone | your own music volume (nobody else is affected) |
| `/team` | everyone | open the "Choose your side" menu (switch between battles, or while dead) |
| `/announce line one \| line two` | admins | a cinematic server message (letterbox + large lines) for everyone |
| `/shirt` `/pants` `<me\|all\|name> <id\|none\|reset> [true\|false]` | admins | custom clothing; the last argument makes it persist across lives (in memory, ends with the server) |
| `/blimps on\|off\|spawn\|clear\|status\|...` | admins | Marleyan blimps that shell the battlefield at random, ignoring teams. Full list and custom model guide: `docs/CUSTOM_BLIMPS.md` |
| `/cursor <image id\|preset\|default\|list>` | everyone | change your own mouse cursor (presets: `Config.Cursor.Presets`) |
| `/flare <colour>` | everyone | pick the flare gun's colour |
| `/armoredtitanintro` (or `:armoredtitanintro`) | admins | typewriter speech near the bottom middle; at "Bulwark marches" the camera turns to the Armored Titan's holder and slowly zooms in, everyone else gets an inner thought + anxiety, then the camera returns. Text and timing: `Config.Intros.ArmoredTitan` |
| `/rank <me\|name> <rank>` | admins | set a leaderboard rank (lists in `Config.Ranks`) |
| `/round status\|start\|end [team\|draw]\|lives <team> <n>` | admins | control the round |
| `/yell <text>` | everyone | a yell card at the bottom of the screen for players within `Config.Yell.Range` studs |
| `/yellto <me\|all\|name> <text>` | admins | a yell card on specific players' screens |
| `/cmds` | admins | list admin commands |

In chat and thoughts, `*text*` is *italic*, `**text**` is **bold**, `***text***` is ***both***.
Messages get a `[ELD]` (Eldian) or `[MAR]` (Marleyan) tag, in the chat window and on overhead speech bubbles; anyone who doesn't understand that language sees scrambled
same-length words instead. Admins = the game owner, `Config.Admins`, and everyone in Studio.
**Teams & rounds** (`Config.Teams`, `Config.Round`): joining shows a menu to pick Eldian or Marleyan (teams are created by `TeamService`; any `SpawnLocation` with `Neutral = false` and the team's colour is that side's spawn, otherwise a pad is made at `SpawnPosition`). Each round gives both teams 300 lives; every human death costs one and the player respawns after 5 s. At 0 lives a team can't respawn, and when its last living member falls the other team wins (also: time limit -> more lives wins). Dying as a Titan costs nothing. Rounds start with a slow-motion intro (everyone moves at 30% speed) and cinematic server messages (`Config.Round.Intros`, picked at random). No friendly fire by default. Automatic spawning is OFF (`CharacterAutoLoads = false`): `RoundService` spawns players.

**Round + leaderboard (minimal, text only):** the round (`Round 2 - 14:32`, both sides' lives under it) sits at the top middle. Top right is your face, name and a thin health bar (no background), then a plain roster grouped by side with ranks in italics. Tab hides it. `Config.Leaderboard`: `ShowStats` (kills/deaths, off by default), `HideEnemyNames`. Boss bars sit below the round text (`Config.BossBar.TopOffset`).

**Titan body** (`Config.Titan`): the camera orbits the Titan's head and sits slightly above it, so the head shows in the lower third of the screen (`Camera.TitanHeadScreenY`, 0.35 = 35% up from the bottom). The torso and head tilt up / down with the camera (`Titan.Look`), visible to everyone. Running drains stamina (`Titan.Stamina`), and `Q` dashes (free) (`Titan.Dash`). Any value can be overridden inside a Titan's own config. Titans are now scaled with explicit hip height + body scale values so big R15 rigs stay on the floor.

**Custom Titan models:** drop `assets/titans/<TitanName>.rbxm` and it replaces the placeholder. Full guide: `docs/CUSTOM_TITANS.md`.

**Transformation effects:** a lightning bolt strikes the shifter, the screen flashes yellow -> white/black impact frames -> yellow -> fades. Put your Attack on Titan shift sound's asset id in `Config.Shifting.Sounds.Shift` (not bundled: it's copyrighted audio).

**Music:** one server-owned Sound plays in SoundService for everyone, with a shared queue. Track list for the panel: `src/shared/Configs/MusicLibrary.luau` (add `{ Id = ..., Title = ..., Category = ... }`). Defaults in `Config.Music`. The server skips tracks that fail to load. Roblox only plays audio that is public or uploaded by the experience's owner, so a private id will be skipped. Clients re-sync their playback position, so late joiners start at the right second.

**Boss bars** (`Config.BossBar`): from code, `BossBarService.add(playerOrModel, "Title")` / `.remove(...)`. A bar on a player follows their current body, so it survives respawns and shifting; NPC/Titan models need a Humanoid. New players see existing bars automatically.
**Yells** (`Config.Yell`) show the text, a headshot of the speaker on the right, and their username bottom-left (with an `[ELD]`/`[MAR]` tag). Thought cards move up above them, and yells are scrambled for listeners who don't know the language.

**Anxiety** also triggers from artillery: a rising dread when a barrage is called on your area, and a hard hit if you are near an impact. From your own code: `AnxietyService.apply(player, level 0..1, seconds)` or `AnxietyService.applyRadius(pos, radius, level, seconds)`. Tune it in `Config.Anxiety` (optional heartbeat sound id, strength, pulse rate, thoughts).
The command bar and chat both run the same server commands, which always re-check admin rights.

Kills (players, NPCs, or defeating a Titan) flash your screen grey for about a second.

**Local chat:** with `Config.Chat.GlobalChat = false` (default) you only receive messages from players within
`Config.Chat.ProximityRange` studs (enforced on the server). Speech bubbles appear over speakers' heads; the
scrolling chat window is hidden by default (`Config.Chat.ShowChatWindow`), the input bar stays.

Aiming is a slow walk (no jump, sprint or crouch) that turns you toward the mouse. Reloading drops you back
to Idle so you can run while it finishes.

## Layout

```
src/
├─ shared/                       -> ReplicatedStorage.Shared
│  ├─ Configs/                   Config, AnimationConfigs, GunConfigs/*, TitanConfigs/*
│  ├─ Gun/                       GunStates (stance rules), Ballistics (projectile sim)
│  ├─ Hitbox, PlayerState (global state), Remotes
│  └─ TextFormat (*markdown* + safe escaping), Languages (scramble)
├─ server/                       -> ServerScriptService.Server (init.server.luau)
│  ├─ Services/                  Damage, Gun, Player, Rig, Shifter, SpawnOverride, Anxiety, BossBar, Yell, Music, Team, Round, Message, Admin, Thought, Chat, Artillery
│  └─ Shifter/                   ShifterBase, TitanFactory, Effects, Titans/ArmoredTitan
├─ client/                       -> StarterPlayerScripts.Client (init.client.luau)
│  ├─ Controllers/               Camera, Character, Gun, Shifter, Hud,
│  │                             Thought, Chat, Effects (kill flash), Anxiety, AdminBar, Music, MusicUi, BossBar, Yell, Artillery, ArtilleryEffects
│  └─ Gun/                       Aim, BulletVisuals, R6Pose
└─ character/Animate.client.luau (empty; suppresses Roblox's default Animate)
assets/titans, assets/guns, assets/tools   drop real models here (see below)
```

## How to customise

- **Aim camera per gun:** in each `GunConfigs/<Name>.luau`: `AimFov`, `AimZoom`, `AimShoulder` (nil = no change).
- **New gun:** add `src/shared/Configs/GunConfigs/<Name>.luau` (copy `Kar98k`). Put a Tool named `<Name>` in
  `assets/guns` for a real model (needs a `Handle` with a `Muzzle` Attachment).
- **New Titan:** add `TitanConfigs/<Name>.luau`. Optional subclass in `server/Shifter/Titans/<Name>.luau`
  for unique abilities (see `ArmoredTitan`). Real model → `assets/titans/<Name>` (needs Humanoid,
  HumanoidRootPart as PrimaryPart, and a part named `Nape`).
- **Artillery:** tune `Configs/ArtilleryConfigs/FieldArtillery.luau` (range, cooldown, shell count, spread,
  damage, `Visual` size/shake/flash, `Anxiety`, and `Sounds`: the whistle and explosion default to Roblox's
  built-in sounds, so replace them with your own `rbxassetid://` ids for the full effect). Put a Tool named `FieldArtillery` in `assets/tools` for a real model.
- **Health thoughts (J):** edit the lines/tiers in `Configs/HealthThoughts.luau`.
- **Thought look/timing:** `Config.Thoughts` (width, how many stack, lifetime, offset above the hotbar).
- **Kill effect:** `Config.KillEffect` (on/off, Titan intensity, optional sound id).
- **Languages:** add one to `Languages.List` / `Languages.Info` (colour + scramble syllables).
- **Animations:** every ID lives in `AnimationConfigs` / the Titan configs. Blank IDs are skipped. Gun
  animations (idle, ready, aim, fire, reload) should be arm/torso-only so legs keep walking.
- **Movement restrictions:** `CharacterController.setLock(name, {...})` / `clearLock(name)`. The gun uses it
  for aiming and the shifter for the transformation, so systems never fight over WalkSpeed.
- **Global state:** `PlayerState` (attributes on the Player: Shifted, Transforming, ShifterName, ...).

## Testing tips

- `Config.Shifting.MaxShifts` (default 3) and `Cooldown` (20 s) are low on purpose; raise MaxShifts while testing.
- `Config.DebugHitboxes = true` draws Titan melee hitboxes in red.
- Studio chat: `/titan AttackTitan` or `/titan FemaleTitan` switches which Titan you wield (human form only).

## Known limitations

- Chat needs the new TextChatService (the project file selects it). `/t` is Roblox's team-chat alias, so the
  built-in team command is disabled on the client; if both ever fire, remove `/t` from `COMMANDS`
  in `ChatController` and use `/thought me` instead.
- Language scrambling happens on each reader's client, so it hides text from normal players but can't stop
  someone modifying their own client. Roblox's native speech bubbles are off; the game draws its own so tags and scrambling work.
- Player-typed thoughts go through Roblox's text filter before anyone else sees them.

- Written without access to Roblox Studio: it builds with Rojo and passes syntax and path checks, but has not
  been play-tested. Expect some tuning (hit boxes, camera feel, Titan spawn height).
- Titan models are placeholders (recoloured R15 rig scaled to 15 m × 3 studs/m). Anime heights are used for
  the Titans (Armored 15 m, Attack 15 m, Female 14 m); all combat stats are gameplay placeholders.
- Rifles do 5% damage to Titans (nape ×2). Tune `Config.Damage`.
- No lag compensation, mobile/controller input, or datastore persistence yet.


**Artillery:** the size of each strike and of each blast is now random (`RadiusScale` / `BlastScale` in the artillery config), and there is no circle on the ground any more - only the flare. The caller sees a small aiming ring.

**Flare gun:** Eldians spawn with it (`Config.TeamGuns`). It uses the same ballistics as bullets - fairly straight, then a gentle arc, shorter range - and the flare keeps burning where it lands. Config: `GunConfigs/FlareGun.luau`. **Changing a gun's model:** `docs/CUSTOM_GUNS.md`.
