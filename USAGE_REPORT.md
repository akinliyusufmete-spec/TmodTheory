# Script usage report

Every one of the 184 exported scripts is sorted into one of three groups: **123 used**, **18 unused** and **43 duplicates**.

The unused and duplicate files have since been **deleted from this repository**. To get them back, check out commit `d005069`, where they are still in `_Unused/` and `_Duplicates/`. **Nothing was changed in the Studio place**: every script listed here still exists there.

## How it was decided

- **Entry points.** A script counts as running if Roblox runs it where it lives:
  - `Script`s in Workspace and ServerScriptService.
  - `LocalScript`s in StarterPlayerScripts and ReplicatedFirst.
  - Workspace scripts with `RunContext = Client` also count. No script in the place is Disabled.
- **Modules.** A `ModuleScript` is used only if a running script reaches it through `require` chains.
- **Unused.** A script is unused if none of the above applies to it:
  - It is empty.
  - It sits in ServerStorage as a backup.
  - It is a module nothing requires.
  - It is a script inside an asset template. `AssetResolver.preparePropClone` and `NpcFactory.create` strip scripts from every clone, so those never run.
- **Duplicates.** A script is a duplicate when its bytes are identical to an earlier script in the export.
  - The first copy is kept, unless that copy is itself unused.
  - Every later copy was deleted.

> **Do not delete the Workspace duplicates in Studio.** Each door, part and merry-go-round piece runs its own copy of the script. Deleting a copy in the place stops that object from working. In the repo they were removed only because their code is identical; one copy is enough to read and edit the logic.

## Unused (18) — deleted

| # | Former file | Reason |
|--:|------|------|
| 10 | `_Unused/Workspace/Assets/Machine_BSODA/Script.server.luau` | Empty script (0 bytes) |
| 52 | `_Unused/StarterPlayer/StarterPlayerScripts/BaldiClient/UiKit.luau` | ModuleScript never required by any script |
| 79 | `_Unused/ReplicatedStorage/BaldiShared/BaldiAssets/Items/BSODA/Script.server.luau` | Script inside an item template; AssetResolver.preparePropClone destroys scripts when cloning, so it never runs |
| 85 | `_Unused/ReplicatedStorage/BaldiShared/BaldiAssets/Npcs/Guidelines/Torso/Attachment1/face/Script.server.luau` | Script inside an NPC rig template; NpcFactory.create destroys scripts when cloning, so it never runs |
| 86 | `_Unused/ReplicatedStorage/Packages/README.luau` | Documentation-only ModuleScript, never required |
| 151 | `_Unused/ServerScriptService/BaldiGame/NpcAnimator.luau` | ModuleScript never required (NPCs are animated by client-side NpcAnimatorClient) |
| 170 | `_Unused/ServerScriptService/BaldiGame/WaypointGraph.luau` | ModuleScript never required |
| 172 | `_Unused/ServerStorage/SoundWiringBackup/AssetConfig.luau` | Backup copy in ServerStorage; never run or required |
| 173 | `_Unused/ServerStorage/SoundWiringBackup/HudController.luau` | Backup copy in ServerStorage; never run or required |
| 174 | `_Unused/ServerStorage/SoundWiringBackup/SoundController.luau` | Backup copy in ServerStorage; never run or required |
| 175 | `_Unused/ServerStorage/SoundWiringBackup/ChaseTension.luau` | Backup copy in ServerStorage; never run or required |
| 176 | `_Unused/ServerStorage/SoundWiringBackup/GuyAI.luau` | Backup copy in ServerStorage; never run or required |
| 178 | `_Unused/ServerStorage/backups/GameConfig_BackupGuy.luau` | Backup copy in ServerStorage; never run or required |
| 180 | `_Unused/ServerStorage/backups/GuyAI_Backup.luau` | Backup copy in ServerStorage; never run or required |
| 181 | `_Unused/ServerStorage/backups/GuyAI_PreFail.luau` | Backup copy in ServerStorage; never run or required |
| 182 | `_Unused/ServerStorage/backups/GuyRevealFlash_Backup.luau` | Backup copy in ServerStorage; never run or required |
| 183 | `_Unused/ServerStorage/backups/GuyRevealFlash_PreFail.luau` | Backup copy in ServerStorage; never run or required |
| 184 | `_Unused/ServerStorage/backups/NotebookSpawner_PreFail.luau` | Backup copy in ServerStorage; never run or required |

## Duplicates (43) — deleted

| # | Former file | Same as |
|--:|------|------|
| 3 | `_Duplicates/Workspace/Assets/Part_2/Script.server.luau` | identical to #2 Workspace/Assets/Part/Script.server.luau |
| 4 | `_Duplicates/Workspace/Assets/Door_2/BlueDoor/Main.server.luau` | identical to #1 Workspace/Assets/Door/BlueDoor/Main.server.luau |
| 5 | `_Duplicates/Workspace/Assets/Door_3/BlueDoor/Main.server.luau` | identical to #1 Workspace/Assets/Door/BlueDoor/Main.server.luau |
| 6 | `_Duplicates/Workspace/Assets/Door_4/BlueDoor/Main.server.luau` | identical to #1 Workspace/Assets/Door/BlueDoor/Main.server.luau |
| 7 | `_Duplicates/Workspace/Assets/Part_3/Script.server.luau` | identical to #2 Workspace/Assets/Part/Script.server.luau |
| 8 | `_Duplicates/Workspace/Assets/Door_5/BlueDoor/Main.server.luau` | identical to #1 Workspace/Assets/Door/BlueDoor/Main.server.luau |
| 9 | `_Duplicates/Workspace/Assets/Door_6/BlueDoor/Main.server.luau` | identical to #1 Workspace/Assets/Door/BlueDoor/Main.server.luau |
| 11 | `_Duplicates/Workspace/Assets/Part_4/Script.server.luau` | identical to #2 Workspace/Assets/Part/Script.server.luau |
| 13 | `_Duplicates/Workspace/Assets/Merry-Go-round/Union_2/Script.server.luau` | identical to #12 Workspace/Assets/Merry-Go-round/Union/Script.server.luau |
| 14 | `_Duplicates/Workspace/Assets/Merry-Go-round/Union_3/Script.server.luau` | identical to #12 Workspace/Assets/Merry-Go-round/Union/Script.server.luau |
| 15 | `_Duplicates/Workspace/Assets/Merry-Go-round/Union_4/Script.server.luau` | identical to #12 Workspace/Assets/Merry-Go-round/Union/Script.server.luau |
| 16 | `_Duplicates/Workspace/Assets/Merry-Go-round/EnhancedCone/Script.server.luau` | identical to #12 Workspace/Assets/Merry-Go-round/Union/Script.server.luau |
| 17 | `_Duplicates/Workspace/Assets/Part_5/Script.server.luau` | identical to #2 Workspace/Assets/Part/Script.server.luau |
| 18 | `_Duplicates/Workspace/Assets/Door_7/BlueDoor/Main.server.luau` | identical to #1 Workspace/Assets/Door/BlueDoor/Main.server.luau |
| 19 | `_Duplicates/Workspace/Assets/Door_8/BlueDoor/Main.server.luau` | identical to #1 Workspace/Assets/Door/BlueDoor/Main.server.luau |
| 20 | `_Duplicates/Workspace/Assets/Door_9/BlueDoor/Main.server.luau` | identical to #1 Workspace/Assets/Door/BlueDoor/Main.server.luau |
| 21 | `_Duplicates/Workspace/Assets/Part_6/Script.server.luau` | identical to #2 Workspace/Assets/Part/Script.server.luau |
| 22 | `_Duplicates/Workspace/Assets/Door_10/BlueDoor/Main.server.luau` | identical to #1 Workspace/Assets/Door/BlueDoor/Main.server.luau |
| 23 | `_Duplicates/Workspace/Assets/Part_7/Script.server.luau` | identical to #2 Workspace/Assets/Part/Script.server.luau |
| 24 | `_Duplicates/Workspace/Assets/Door_11/BlueDoor/Main.server.luau` | identical to #1 Workspace/Assets/Door/BlueDoor/Main.server.luau |
| 25 | `_Duplicates/Workspace/Assets/Part_8/Script.server.luau` | identical to #2 Workspace/Assets/Part/Script.server.luau |
| 26 | `_Duplicates/Workspace/Assets/Part_9/Script.server.luau` | identical to #2 Workspace/Assets/Part/Script.server.luau |
| 27 | `_Duplicates/Workspace/Assets/Door_12/BlueDoor/Main.server.luau` | identical to #1 Workspace/Assets/Door/BlueDoor/Main.server.luau |
| 28 | `_Duplicates/Workspace/Assets/Part_10/Script.server.luau` | identical to #2 Workspace/Assets/Part/Script.server.luau |
| 29 | `_Duplicates/Workspace/Assets/Part_11/Script.server.luau` | identical to #2 Workspace/Assets/Part/Script.server.luau |
| 30 | `_Duplicates/Workspace/Assets/Part_12/Script.server.luau` | identical to #2 Workspace/Assets/Part/Script.server.luau |
| 31 | `_Duplicates/Workspace/Assets/Part_13/Script.server.luau` | identical to #2 Workspace/Assets/Part/Script.server.luau |
| 32 | `_Duplicates/Workspace/Assets/Part_14/Script.server.luau` | identical to #2 Workspace/Assets/Part/Script.server.luau |
| 33 | `_Duplicates/Workspace/Assets/Door_13/BlueDoor/Main.server.luau` | identical to #1 Workspace/Assets/Door/BlueDoor/Main.server.luau |
| 34 | `_Duplicates/Workspace/Assets/Part_15/Script.server.luau` | identical to #2 Workspace/Assets/Part/Script.server.luau |
| 35 | `_Duplicates/Workspace/Assets/Door_14/BlueDoor/Main.server.luau` | identical to #1 Workspace/Assets/Door/BlueDoor/Main.server.luau |
| 36 | `_Duplicates/Workspace/Assets/Door_15/BlueDoor/Main.server.luau` | identical to #1 Workspace/Assets/Door/BlueDoor/Main.server.luau |
| 37 | `_Duplicates/Workspace/Assets/Part_16/Script.server.luau` | identical to #2 Workspace/Assets/Part/Script.server.luau |
| 38 | `_Duplicates/Workspace/Assets/Machine_ZestyBar/Script.server.luau` | identical to #10 Workspace/Assets/Machine_BSODA/Script.server.luau |
| 39 | `_Duplicates/Workspace/Assets/Part_17/Script.server.luau` | identical to #2 Workspace/Assets/Part/Script.server.luau |
| 80 | `_Duplicates/ReplicatedStorage/BaldiShared/BaldiAssets/Items/Notebook/Script.server.luau` | identical to #79 ReplicatedStorage/BaldiShared/BaldiAssets/Items/BSODA/Script.server.luau |
| 81 | `_Duplicates/ReplicatedStorage/BaldiShared/BaldiAssets/Items/ZESTY/Script.server.luau` | identical to #79 ReplicatedStorage/BaldiShared/BaldiAssets/Items/BSODA/Script.server.luau |
| 82 | `_Duplicates/ReplicatedStorage/BaldiShared/BaldiAssets/Items/ALARM/Script.server.luau` | identical to #79 ReplicatedStorage/BaldiShared/BaldiAssets/Items/BSODA/Script.server.luau |
| 83 | `_Duplicates/ReplicatedStorage/BaldiShared/BaldiAssets/Items/SCISSORS/Script.server.luau` | identical to #79 ReplicatedStorage/BaldiShared/BaldiAssets/Items/BSODA/Script.server.luau |
| 84 | `_Duplicates/ReplicatedStorage/BaldiShared/BaldiAssets/Items/Nickel/Script.server.luau` | identical to #79 ReplicatedStorage/BaldiShared/BaldiAssets/Items/BSODA/Script.server.luau |
| 171 | `_Duplicates/ServerStorage/SoundWiringBackup/Cosmetics.luau` | identical to #75 ReplicatedStorage/BaldiShared/Cosmetics.luau |
| 177 | `_Duplicates/ServerStorage/backups/AssetConfig_PreSounds.luau` | identical to #73 ReplicatedStorage/BaldiShared/AssetConfig.luau |
| 179 | `_Duplicates/ServerStorage/backups/GameConfig_PreFail.luau` | identical to #178 ServerStorage/backups/GameConfig_BackupGuy.luau |

## Used (123) — kept

| # | File |
|--:|------|
| 1 | `Workspace/Assets/Door/BlueDoor/Main.server.luau` |
| 2 | `Workspace/Assets/Part/Script.server.luau` |
| 12 | `Workspace/Assets/Merry-Go-round/Union/Script.server.luau` |
| 40 | `ReplicatedFirst/LoadingScreen.client.luau` |
| 41 | `StarterPlayer/StarterPlayerScripts/Main.client.luau` |
| 42 | `StarterPlayer/StarterPlayerScripts/BaldiClient/DetentionOverlay.luau` |
| 43 | `StarterPlayer/StarterPlayerScripts/BaldiClient/FrostyVignette.luau` |
| 44 | `StarterPlayer/StarterPlayerScripts/BaldiClient/HudController.luau` |
| 45 | `StarterPlayer/StarterPlayerScripts/BaldiClient/InputHandler.luau` |
| 46 | `StarterPlayer/StarterPlayerScripts/BaldiClient/ItemUseClient.luau` |
| 47 | `StarterPlayer/StarterPlayerScripts/BaldiClient/BeansGumClient.luau` |
| 48 | `StarterPlayer/StarterPlayerScripts/BaldiClient/MenuController.luau` |
| 49 | `StarterPlayer/StarterPlayerScripts/BaldiClient/SilverMinigame.luau` |
| 50 | `StarterPlayer/StarterPlayerScripts/BaldiClient/SoundController.luau` |
| 51 | `StarterPlayer/StarterPlayerScripts/BaldiClient/StaminaController.luau` |
| 53 | `StarterPlayer/StarterPlayerScripts/BaldiClient/VendingMachineUI.luau` |
| 54 | `StarterPlayer/StarterPlayerScripts/BaldiClient/NotebookMinigame.luau` |
| 55 | `StarterPlayer/StarterPlayerScripts/BaldiClient/ChaseTension.luau` |
| 56 | `StarterPlayer/StarterPlayerScripts/BaldiClient/SequenceMinigame.luau` |
| 57 | `StarterPlayer/StarterPlayerScripts/BaldiClient/NpcAnimatorClient.luau` |
| 58 | `StarterPlayer/StarterPlayerScripts/BaldiClient/MathMinigame.luau` |
| 59 | `StarterPlayer/StarterPlayerScripts/BaldiClient/MemoryMinigame.luau` |
| 60 | `StarterPlayer/StarterPlayerScripts/BaldiClient/HudLayoutEditor.luau` |
| 61 | `StarterPlayer/StarterPlayerScripts/BaldiClient/CosmeticState.luau` |
| 62 | `StarterPlayer/StarterPlayerScripts/BaldiClient/NotebookSkinner.luau` |
| 63 | `StarterPlayer/StarterPlayerScripts/BaldiClient/ChainMinigame.luau` |
| 64 | `StarterPlayer/StarterPlayerScripts/BaldiClient/GuyRevealFlash.luau` |
| 65 | `StarterPlayer/StarterPlayerScripts/BaldiClient/UiFx.luau` |
| 66 | `StarterPlayer/StarterPlayerScripts/BaldiClient/KeystrokesController.luau` |
| 67 | `StarterPlayer/StarterPlayerScripts/BaldiClient/VoicelineController.luau` |
| 68 | `StarterPlayer/StarterPlayerScripts/BaldiClient/DeviceUi.luau` |
| 69 | `ReplicatedStorage/EzUISprings/init.luau` |
| 70 | `ReplicatedStorage/EzUISprings/Spring.luau` |
| 71 | `ReplicatedStorage/EzUISprings/Settings.luau` |
| 72 | `ReplicatedStorage/EzUISprings/InstanceFunctions.luau` |
| 73 | `ReplicatedStorage/BaldiShared/AssetConfig.luau` |
| 74 | `ReplicatedStorage/BaldiShared/GameConfig.luau` |
| 75 | `ReplicatedStorage/BaldiShared/Cosmetics.luau` |
| 76 | `ReplicatedStorage/BaldiShared/CharacterConfig.luau` |
| 77 | `ReplicatedStorage/BaldiShared/SoundLoader.luau` |
| 78 | `ReplicatedStorage/BaldiShared/AnimationLoader.luau` |
| 87 | `ReplicatedStorage/Packages/HyperText/init.luau` |
| 88 | `ReplicatedStorage/Packages/HyperText/Scheduler.luau` |
| 89 | `ReplicatedStorage/Packages/HyperText/Config.luau` |
| 90 | `ReplicatedStorage/Packages/HyperText/Types.luau` |
| 91 | `ReplicatedStorage/Packages/HyperText/Util.luau` |
| 92 | `ReplicatedStorage/Packages/HyperText/Markups/Helpers/AnimAttrsConverters.luau` |
| 93 | `ReplicatedStorage/Packages/HyperText/Markups/Helpers/AppendFlipbookAttrsConverters.luau` |
| 94 | `ReplicatedStorage/Packages/HyperText/Markups/Helpers/ApplyAnimation.luau` |
| 95 | `ReplicatedStorage/Packages/HyperText/Markups/Helpers/ApplyTrans.luau` |
| 96 | `ReplicatedStorage/Packages/HyperText/Markups/Helpers/EmitImage.luau` |
| 97 | `ReplicatedStorage/Packages/HyperText/Markups/Helpers/EmitImgAttrsConverters.luau` |
| 98 | `ReplicatedStorage/Packages/HyperText/Markups/Helpers/FlipbookEffect.luau` |
| 99 | `ReplicatedStorage/Packages/HyperText/Markups/Helpers/GradientAttrsConverters.luau` |
| 100 | `ReplicatedStorage/Packages/HyperText/Markups/Helpers/ApplyGradient.luau` |
| 101 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/anim.luau` |
| 102 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/bgImg.luau` |
| 103 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/clearAnim.luau` |
| 104 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/clearInterval.luau` |
| 105 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/clearTransDur.luau` |
| 106 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/color.luau` |
| 107 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/decode.luau` |
| 108 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/emitImg.luau` |
| 109 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/fog.luau` |
| 110 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/font.luau` |
| 111 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/gradient.luau` |
| 112 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/interval.luau` |
| 113 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/italic.luau` |
| 114 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/mark.luau` |
| 115 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/rainbow.luau` |
| 116 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/shadow.luau` |
| 117 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/shake.luau` |
| 118 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/shiny.luau` |
| 119 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/size.luau` |
| 120 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/soundId.luau` |
| 121 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/strike.luau` |
| 122 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/stroke.luau` |
| 123 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/strokeGradient.luau` |
| 124 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/trans.luau` |
| 125 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/underline.luau` |
| 126 | `ReplicatedStorage/Packages/HyperText/Markups/Paired/weight.luau` |
| 127 | `ReplicatedStorage/Packages/HyperText/Markups/Programmatic/ZIndex.luau` |
| 128 | `ReplicatedStorage/Packages/HyperText/Markups/Programmatic/horizontalAlignment.luau` |
| 129 | `ReplicatedStorage/Packages/HyperText/Markups/Programmatic/scaleDimension.luau` |
| 130 | `ReplicatedStorage/Packages/HyperText/Markups/Programmatic/sizeConstraint.luau` |
| 131 | `ReplicatedStorage/Packages/HyperText/Markups/Programmatic/verticalAlignment.luau` |
| 132 | `ReplicatedStorage/Packages/HyperText/Markups/SelfClosing/br.luau` |
| 133 | `ReplicatedStorage/Packages/HyperText/Markups/SelfClosing/img.luau` |
| 134 | `ReplicatedStorage/Packages/HyperText/Markups/SelfClosing/renderEvent.luau` |
| 135 | `ReplicatedStorage/Packages/HyperText/Markups/SelfClosing/wait.luau` |
| 136 | `ReplicatedStorage/Packages/Memoizer.luau` |
| 137 | `ReplicatedStorage/Packages/Signal.luau` |
| 138 | `ServerScriptService/Main.server.luau` |
| 139 | `ServerScriptService/WorldSoundApplier.server.luau` |
| 140 | `ServerScriptService/BaldiGame/HubTravel.luau` |
| 141 | `ServerScriptService/BaldiGame/AssetResolver.luau` |
| 142 | `ServerScriptService/BaldiGame/ChatReviveAI.luau` |
| 143 | `ServerScriptService/BaldiGame/DetentionSystem.luau` |
| 144 | `ServerScriptService/BaldiGame/ExitDoorManager.luau` |
| 145 | `ServerScriptService/BaldiGame/FrostyAI.luau` |
| 146 | `ServerScriptService/BaldiGame/GameManager.luau` |
| 147 | `ServerScriptService/BaldiGame/ItemEconomy.luau` |
| 148 | `ServerScriptService/BaldiGame/LpAI.luau` |
| 149 | `ServerScriptService/BaldiGame/MapResolver.luau` |
| 150 | `ServerScriptService/BaldiGame/NotebookSpawner.luau` |
| 152 | `ServerScriptService/BaldiGame/NpcBase.luau` |
| 153 | `ServerScriptService/BaldiGame/NpcFactory.luau` |
| 154 | `ServerScriptService/BaldiGame/PlaceholderMap.luau` |
| 155 | `ServerScriptService/BaldiGame/RemoteSetup.luau` |
| 156 | `ServerScriptService/BaldiGame/SilverAI.luau` |
| 157 | `ServerScriptService/BaldiGame/SweeperAI.luau` |
| 158 | `ServerScriptService/BaldiGame/PlayerProfiles.luau` |
| 159 | `ServerScriptService/BaldiGame/MazeArena.luau` |
| 160 | `ServerScriptService/BaldiGame/SportageAI.luau` |
| 161 | `ServerScriptService/BaldiGame/GuyAI.luau` |
| 162 | `ServerScriptService/BaldiGame/MatchMap.luau` |
| 163 | `ServerScriptService/BaldiGame/MatchServer.luau` |
| 164 | `ServerScriptService/BaldiGame/ChainAI.luau` |
| 165 | `ServerScriptService/BaldiGame/BeansAI.luau` |
| 166 | `ServerScriptService/BaldiGame/DoorService.luau` |
| 167 | `ServerScriptService/BaldiGame/SimplePath.luau` |
| 168 | `ServerScriptService/BaldiGame/VoicelineService.luau` |
| 169 | `ServerScriptService/BaldiGame/Badges.luau` |
