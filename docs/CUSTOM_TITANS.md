# Custom Titan models

Until you add a model, every Titan is a recoloured, scaled R15 placeholder (colour/material come from
`TitanConfigs/<Name>.luau`). The moment a model with the matching name exists in `assets/titans`, it is
used instead - no code changes. Remove the model and the placeholder comes back.

## 1. Build the model (R15!)

Titans are R15; only normal players are R6. Your model needs:

| Needed | Why |
|---|---|
| A `Humanoid` with `RigType = R15` | movement, health, animations |
| `HumanoidRootPart` (set as `PrimaryPart`) | movement, camera, spawning |
| Standard R15 part names: `Head`, `UpperTorso`, `LowerTorso`, `Left/RightUpperArm`, `...LowerArm`, `...Hand`, `...UpperLeg`, `...LowerLeg`, `...Foot` | the shared R15 animations drive these |
| The standard `Motor6D` joints, especially **`Waist`** (in UpperTorso) and **`Neck`** (in Head) | the torso / head tilt when the camera looks up and down |
| A part called `Nape` (optional) | the weak point. If missing, an invisible one is added behind the neck (`Config.Shifting.CustomModels.AutoNape`) |

Easiest ways to get there in Roblox Studio:

1. **Avatar tab -> Rig Builder -> R15** to get a correct blank rig, then swap in your meshes (keep every part and joint name), or
2. **Avatar tab -> Import 3D / Avatar Auto Setup** on your mesh, which produces a full R15 rig for you.

Keep the model in a neutral standing pose (arms by the sides or in a T-pose), facing **-Z** (the front of the model looks along the root's LookVector), with its feet at the bottom.

Do not anchor it and do not put scripts in it (anchoring is cleared and scripts are deleted automatically, but it's tidier).

## 2. Name it exactly like the config

The model's name must equal the file name in `src/shared/Configs/TitanConfigs/`: `ArmoredTitan`, `AttackTitan`, `FemaleTitan` (or your own new Titan - see below).

## 3. Get it into the game with Rojo

1. In Studio, put the model anywhere, right-click it -> **Save to File...** -> `ArmoredTitan.rbxm`.
2. Drop that file into `assets/titans/` in the repository (the filename is the model name).
3. `rojo serve` / sync. It appears at `ServerStorage/Titans/ArmoredTitan`.

(You can also paste the model straight into `ServerStorage/Titans` in Studio while testing, but Rojo will overwrite it on the next sync unless the file is in `assets/titans`.)

When the server starts it prints one line per custom model to the Output window:

```
[TitanFactory] custom model 'ArmoredTitan' OK
[TitanFactory] custom model 'ArmoredTitan': missing R15 part LeftHand; Head has no Neck Motor6D ...
```

Fix whatever it lists.

## 4. Size and standing on the floor

* `Config.Shifting.CustomModels.FitHeight = true` scales your model so its total height is `HeightMeters * StudsPerMeter` from the Titan's config (15 m x 3 = 45 studs). Set it to `false` to keep exactly the size you built.
* Either way the factory then **sets `Humanoid.HipHeight` to the real gap between the bottom of the HumanoidRootPart (the hips) and the soles of the feet** and writes the Humanoid's `BodyDepthScale / BodyHeightScale / BodyWidthScale / HeadScale` values, with `AutomaticScalingEnabled` off. This is what stops a large R15 from sinking into the ground during its walk animation. If a Titan still floats or sinks, something is hanging below the feet - an invisible part, a long accessory or a wide `HumanoidRootPart`. The lowest part of the model is treated as the floor.
* Do not make the model asymmetrical in height from the root: the root should sit roughly at the hips, as in a normal R15.

## 5. Animations

Titan animations are R15 animation assets listed in `AnimationConfigs.R15_Animations` and overridden per Titan with `TitanConfigs.<Name>.Animations` (`idle`, `walk`, `run`, `jump`, `fall`, `M1 = { ... }`, optional `Dash`). They must be made on the R15 rig with standard joint names and **published under the same owner as the game** (your account or group), otherwise they won't play. If you add extra joints or bones for the custom mesh, keep animating through the standard joints for now.

## 6. Adding a brand-new Titan

1. Copy `TitanConfigs/AttackTitan.luau` to `TitanConfigs/YourTitan.luau` and edit it (health, speeds, combat, regen).
2. Optional: `Stamina = { RunSeconds = 90 }` or `Dash = { Distance = 0.6 }` in that file to override `Config.Titan` for this Titan only.
3. Optional: `server/Shifter/Titans/YourTitan.luau` for unique abilities (see `ArmoredTitan`).
4. Add the model `assets/titans/YourTitan.rbxm`.
5. Give it to someone: `/shifter <player> YourTitan`.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Still the grey placeholder | model name does not match the config name exactly (case matters), or it is not under `ServerStorage/Titans` |
| Error "must be an R15 model" | `Humanoid.RigType` is R6 |
| Torso / head don't tilt | no `Waist` / `Neck` Motor6D with those names |
| Sinks or hovers | see section 4 |
| Nape hits don't register | the `Nape` part is missing, or too small / too far from the neck |
| Doesn't move | a part is anchored inside a script-created weld chain; unanchor the model in Studio before saving |
