# Changing a gun's model (Kar98k, FlareGun, ...)

Guns are `Tool`s. The game builds a plain placeholder unless a Tool named exactly like the gun id
exists in `ServerStorage/Guns` - which Rojo fills from the `assets/guns/` folder. So to replace the
Kar98k model:

1. In Studio make a **Tool** named exactly `Kar98k` (the key in `GunConfigs`; case matters).
2. Inside it, a part named **`Handle`** (a MeshPart is fine) with your gun model. Weld any extra parts to the Handle (WeldConstraint), `CanCollide = false`, and `Massless = true` on all of them.
3. Inside the Handle, add an **Attachment named `Muzzle`** at the tip of the barrel, with its **-Z axis (the blue arrow of the attachment) pointing out of the barrel**. This is where bullets and the muzzle flash start. Without it, shots start in front of the player's chest.
4. Set the hold position with the Tool's `Grip` properties (`GripPos`, `GripForward`, `GripRight`, `GripUp`). Quick way: equip it in Play mode, then adjust the `RightGrip` weld in the character until it sits right, and copy the numbers to the Tool. The arms are posed by code (the R6 pose in `R6Pose`), so only the grip needs tuning.
5. Don't put scripts in it, and leave `RequiresHandle = true`.
6. Right-click the Tool -> Save to File -> `Kar98k.rbxm`, and put it in `assets/guns/` in the repo. The file name must be `Kar98k.rbxm`.

Sync with Rojo and every Kar98k that spawns uses your model. Ammo, stance and reload attributes are added by the game; nothing else needs touching. Delete the file to go back to the placeholder.

The same works for the flare gun: a Tool named `FlareGun` in `assets/guns/`.

If your gun should have real animations rather than the code pose, publish R6 animations and put the ids into `AnimationConfigs.Guns.<AnimationGroup>` (`Rifle` for the Kar98k, `Pistol` for the flare gun).

## Gun sounds

In the gun's config (`src/shared/Configs/GunConfigs/Kar98k.luau`) fill in the `Sounds` table with asset ids:

```lua
Sounds = {
	Fire = "rbxassetid://123456789",   -- the shot; everyone nearby hears it, from the muzzle
	FireVolume = 1.5,
	FireDistance = 900,                -- how far away it can be heard (studs)
	Bolt = "rbxassetid://123456789",   -- bolt-action cycling, plays shortly after the shot
	Reload = "rbxassetid://123456789", -- plays when you start reloading
},
```

Blank means silent. The audio must be public or owned by the game's owner/group, otherwise Roblox won't play it. Each shot varies its pitch by a few percent so repeated shots don't sound identical. The flare gun has the same table in `FlareGun.luau`.
