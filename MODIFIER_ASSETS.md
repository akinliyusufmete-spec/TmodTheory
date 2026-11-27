# Modifier assets — what to build in Studio

The Modifiers code never builds or tunes an asset. It only **finds yours by name**, then clones, enables, plays or tweens it. Everything it looks up is listed here, with the exact name, class and children.

Missing an asset is safe. That one piece is skipped, and the Output shows **one** warning naming the path it expected:

```
[Tmod] Modifier asset missing: <path> (see MODIFIER_ASSETS.md) — skipping that piece.
```

Gameplay numbers (speeds, timers, radii, bonus %) are **not** assets. They live in `ReplicatedStorage.BaldiShared.ModifierConfig`.

Every ScreenGui below must have **`ResetOnSpawn = false`**, like your other screens.

---

## 1. The Modifier panel — `StarterGui.ModifiersGui`

Opens when a player who has unlocked modifiers presses Play for a Classic run. Until it exists, Play just starts a normal run, and a warning is logged.

| Path | Class | Notes |
|---|---|---|
| `ModifiersGui` | ScreenGui | `ResetOnSpawn = false`, `Enabled = false` (the code turns it on). Give it a `DisplayOrder` above the main menu, and make `Panel` (or a backdrop) cover the menu buttons so they can't be clicked through it |
| `ModifiersGui.Panel` | Frame / ImageLabel | the window that animates in and out |
| `Panel.List` | ScrollingFrame | holds the cards; give it a `UIListLayout` or `UIGridLayout` |
| `Panel.List.CardTemplate` | Frame / ImageLabel | `Visible = false`. Cloned once per modifier that has no hand-made card |
| `Panel.TotalBonus` | TextLabel | the code writes "Total bonus +X%" |
| `Panel.StartButton` | GuiButton | starts the run with the selection |
| `Panel.ClearButton` | GuiButton | deselects everything |
| `Panel.BackButton` | GuiButton | closes the panel without starting |

`Panel` and `Panel.StartButton` are required. Without either, the panel counts as missing and Play starts a normal run.

### Cards

For each modifier the code uses `Panel.List.<id>` if you made one, otherwise a clone of `CardTemplate` named `<id>`. Either way, the card needs these children:

| Child | Class | Notes |
|---|---|---|
| `Title` | TextLabel | the code writes the modifier's name |
| `Description` | TextLabel | the code writes the description |
| `Bonus` | TextLabel | the code writes "+X%" |
| `Toggle` | GuiButton | clicking selects or deselects |
| `Selected` | GuiObject | shown when selected, hidden when not. Style it however you like |

The **Randomizer** card (`Panel.List.Randomizer`, or the template clone) also needs:

| Child | Class | Notes |
|---|---|---|
| `Minus` | GuiButton | −1 roll |
| `Plus` | GuiButton | +1 roll |
| `Count` | TextLabel | the code writes 1 to 66 |

Card ids, in panel order: `Frenzy`, `Toji`, `PresidentialTortoise`, `ColorInversion`, `SeeMoon`, `StillYou`, `EvilTheory`, `GrandBully`, `Randomizer`, `FireDrill`, `SummerClasses`, `CramSchool`.

---

## 2. In-run HUD — `StarterGui.ModifierHudGui`

| Path | Class | Notes |
|---|---|---|
| `ModifierHudGui` | ScreenGui | `ResetOnSpawn = false` |
| `ModifierHudGui.PunchButton` | GuiButton | the touch punch button. The code shows it only while Grand Bully is active, and only on touch devices |
| `ModifierHudGui.FireDrillTimer` | TextLabel | optional, anywhere inside `ModifierHudGui`. Fire Drill writes the countdown ("2:59") here and turns it red under 30 s. Without it, Fire Drill shows banners at 2:00, 1:00, 0:30 and 0:10 instead |

---

## 3. Per-modifier folders — `ReplicatedStorage.BaldiShared.BaldiAssets.Modifiers.<id>`

Make a Folder named `Modifiers` inside `BaldiAssets`, then one Folder per modifier below.

### `Modifiers.ColorInversion`
Every **PostEffect** inside, such as ColorCorrectionEffect, is cloned into Lighting for the run and removed afterwards.
- Starting point to try: a `ColorCorrectionEffect` with `Contrast = -2`, `Saturation = 0`. Roblox may not give a true inversion; tune it until it looks right to you.

### `Modifiers.CramSchool`
- **Attributes on the folder itself.** The code applies whichever ones you set, and puts the originals back afterwards:
  - `Brightness` (number)
  - `Ambient` (Color3)
  - `OutdoorAmbient` (Color3)
  - `FogColor` (Color3)
  - `FogEnd` (number)
  - `ClockTime` (number)
- Any **Atmosphere**, **Sky** or **PostEffect** inside is cloned into Lighting. While it's active, the place's own Atmosphere is disabled.
- Starting point: `Brightness = 0`, `Ambient = 10,10,15`, `OutdoorAmbient = 10,10,15`, `FogColor = 0,0,0`, `FogEnd = 60`, `ClockTime = 0`.

### `Modifiers.FireDrill`
| Name | Class | Notes |
|---|---|---|
| `Siren` | Sound | looped for the whole drill. Set `Looped = true` and the volume you want |
| *(any)* | PostEffect | the red tint. Each one pulses between neutral and the values **you** set |

- Starting point: a `ColorCorrectionEffect` with `TintColor = 255,120,120`, `Saturation = 0.2`.

### `Modifiers.GrandBully`
| Name | Class | Notes |
|---|---|---|
| `PunchAnim` | Animation | played on your character for each punch |
| `PunchSound` | Sound | played for each punch |

### `Modifiers.PresidentialTortoise`
| Name | Class | Notes |
|---|---|---|
| `CatchSound` | Sound | plays when the turtle catches you |

### Folders that need nothing
`Frenzy`, `Toji`, `SeeMoon`, `StillYou`, `EvilTheory`, `Randomizer` and `SummerClasses` use no assets, so these folders can be skipped. `StillYou` and `EvilTheory` clone existing characters, and the others are code only.

---

## 4. The turtle rig — `ReplicatedStorage.BaldiShared.BaldiAssets.Npcs.Tortoise`

A Model rig like your other NPCs, with a `Humanoid`, a `HumanoidRootPart` and an `Animator`. Its walk animation and voicelines come from `CharacterConfig.Tortoise`, the same way as every other character. Until the rig exists, the usual placeholder NPC stands in.
