# Tmod Theory [RECODE!!!] — Script Source

Luau scripts exported from the Roblox place
**Tmod Theory [RECODE!!!]** (placeId `127143595327317`).

This folder holds **scripts only**. Models, parts, UI, sounds, animations and
other instances stay in the place file. Keep the `.rbxl` or the published place
as the source of truth for everything that is not code.

## Layout (Rojo-style)

| Roblox class   | File extension  |
|----------------|-----------------|
| `Script`       | `.server.luau`  |
| `LocalScript`  | `.client.luau`  |
| `ModuleScript` | `.luau`         |

- Each top-level folder is a service (`ReplicatedStorage/`, `ServerScriptService/`, …).
- Below that, the folder path follows the instance hierarchy in the place.
- A script that has script children becomes a folder, and its own source goes in `init.<ext>` inside it.
- Siblings with the same name get `_2`, `_3`, … suffixes, in the order the place lists them.

Scripts per service in the original export (before the unused and duplicate files were removed):

| Service             | Scripts |
|---------------------|--------:|
| ReplicatedStorage   | 69 |
| Workspace           | 39 |
| ServerScriptService | 33 |
| StarterPlayer       | 28 |
| ServerStorage       | 14 |
| ReplicatedFirst     | 1 |

## Integrity check

`manifest.tsv` lists every exported script: its index, byte length, FNV-1a
32-bit hash and path. The length and hash were computed **inside Studio** from
`Script.Source` at export time.

```bash
python3 tools/verify.py          # check every file
python3 tools/verify.py 74 87    # check specific indices
```

The script ends with `OK 123  BAD 0` when every kept file matches the place exactly.
After you edit any script, its manifest row will no longer match. That is
expected: the manifest is a snapshot from the export.

## Unused and duplicate scripts removed

This repository keeps only the **123 scripts that are used**. The other 61 have been deleted from the repo:
- 18 scripts that never run and are never required.
- 43 byte-for-byte duplicates.

[USAGE_REPORT.md](USAGE_REPORT.md) lists each removed file and the reason it was removed. The removed files are still in git history at commit `d005069`, under `_Unused/` and `_Duplicates/`. They also still exist in the place itself. In particular, the Workspace duplicates are needed there, because each door and part runs its own copy.

`manifest.tsv` still has all 184 rows. Its columns are:
- `status`: used, unused or duplicate.
- `studio_path`: where the file came from.
- `note`: the reason for its status.

`tools/verify.py` checks only the used rows.

## Rojo (scripts only)

`default.project.json` syncs **only scripts**. It covers 120 of the 123 scripts, in these places:

- `ReplicatedFirst.LoadingScreen`
- `ReplicatedStorage.BaldiShared`, `EzUISprings` and `Packages`
- `ServerScriptService.Main`, `WorldSoundApplier` and `BaldiGame`
- `StarterPlayer.StarterPlayerScripts.Main` and `BaldiClient`

Every node in the project sets `$ignoreUnknownInstances: true`. Every synced folder also has an
`init.meta.json` with `{"ignoreUnknownInstances": true}`. Because of this, Rojo **never deletes
anything that is in Studio but not in this repo**. That includes:

- `ReplicatedStorage.BaldiShared.BaldiAssets`, with `Npcs`, `Items` and `Traps`
- `ReplicatedFirst.LoadingScreen.LoadingGui`, and all UI, models, sounds and other services
- the Studio-only modules `Packages.README`, `BaldiGame.NpcAnimator`, `BaldiGame.WaypointGraph` and `BaldiClient.UiKit`

`Workspace` is **not synced**. Its 3 scripts sit inside models and parts that have siblings with the
same name, so Rojo could not match them to the right instance. Edit those scripts in Studio.
The `Workspace/` files here are a reference copy only.

`emitLegacyScripts` is on, so scripts keep the classic `Script`, `LocalScript` and `ModuleScript`
classes, as they are in the place.

### Connecting

1. Save or back up the place first. Use File → Save to File, or publish it.
2. From this folder, run `rojo serve`.
3. In Studio, open the Rojo plugin and click **Connect** (`localhost:34872`).
4. Edit the `.luau` files here. Rojo pushes the changes to Studio live.

Rojo sync goes one way, from files to Studio. If you edit a synced script in Studio while you are
connected, the next save of that file overwrites your Studio edit.

To regenerate the sourcemap for luau-lsp, run:

```bash
rojo sourcemap default.project.json -o sourcemap.json
```
