# Compatibility candidates from an Android launcher

**Status:** queue, not shipped. Nothing here is in `app/PlayportKit/Titles/compat-defaults.json`.
Decision [0074](decisions/0074-per-title-compatibility-defaults.md) ships only settings
"known to make a game work". These fixes are proven on the Android launcher's Box64/Bionic stack
(GPL-3.0, an Android launcher, `(source path omitted)`),
not on pcios's FEX and Wine stack. Each entry moves into the shipped table only after a phone
run confirms it, with its evidence record.

Catalogue keys: Steam titles are `app-<appid>`. GOG and Epic fixes use the Android launcher's own IDs,
so each one needs its catalogue id confirmed before use. The Epic GUID-keyed fixes are not
mapped yet.

## 1. Expressible now with the current schema

These fit `LaunchSettings` as they stand: `arguments` for launch arguments, `runtime` for
`env.NAME=value`.

| Catalogue id | an Android launcher fix | Candidate `settings` | Verify on phone |
|---|---|---|---|
| `app-220` (Half-Life 2) | launch arg `-game hl2_complete` | `{"arguments": "-game hl2_complete"}` | Starts the full game, not the mod menu |
| `app-400` (Portal) | launch arg `-game portal` | `{"arguments": "-game portal"}` | Starts Portal |
| `app-3373660` (Look Outside) | launch arg `--no-sandbox` | `{"arguments": "--no-sandbox"}` | Reaches the menu |
| `app-1637320` (Dome Keeper) | launch arg `--rendering-driver vulkan` | `{"arguments": "--rendering-driver vulkan"}` | Renders on Vulkan |
| `app-413150` (Stardew Valley) | `WINEDLLOVERRIDES=icu=n` | `{"runtime": "env.WINEDLLOVERRIDES=icu=n"}` | Starts without the ICU error |
| `app-413420` (Danganronpa 2) | `WINEDLLOVERRIDES=d3dx9_43=native,builtin d3dcompiler_43=native,builtin` | `{"runtime": "env.WINEDLLOVERRIDES=d3dx9_43=native,builtin d3dcompiler_43=native,builtin"}` | Starts past the DirectX error. The value has spaces, so check how `runtime` splits it. |
| GOG Stardew Valley (`1453375253`) | same `icu=n` as Steam | as above, with the GOG id | Same as Steam |
| GOG Mars: War Logs (`1129934535`), Of Orcs and Men (`1177610018`), Bound by Flame (`1787707874`) | launch arg `-lang=eng` | `{"arguments": "-lang=eng"}` | Language is English |
| GOG Dome Keeper (`1635627436`) | launch arg `--rendering-driver vulkan` | `{"arguments": "--rendering-driver vulkan"}` | Renders on Vulkan |
| GOG Jazz Jackrabbit (`1808582759`) | launch arg with DOSBox `-conf` paths | `{"arguments": "-conf \"..\\dosbox_jazz.conf\" -conf \"..\\dosbox_jazz_single.conf\" -noconsole -c \"exit\""}` | Starts the game. The Windows-style paths need checking against our prefix. |
| Epic Kingdom Hearts III (`e345fdb9…`) | `WINEDLLOVERRIDES=mf=n;mfmediaengine=n` | `{"runtime": "env.WINEDLLOVERRIDES=mf=n;mfmediaengine=n"}` | Cutscenes play. Epic id needs mapping to `epic-<name>`. |

## 2. Needs new runtime support first

The schema can't express these. Each needs code in the Wine launch path, so they wait for a
Swift build and a phone session.

| an Android launcher fix | Titles | What it needs |
|---|---|---|
| Registry keys (`RegistryKeyFix`) | Fallout 3, Fallout: New Vegas, Oblivion, Silent Hill 4 (Steam, GOG, Epic) | Registry writes in the prefix, before launch |
| INI edits (`IniFileFix`) | Steam `752580` | Config file edits |
| Binary patch with length and byte check (`BinaryPatchFix`) | FFXII: The Zodiac Age (`595520`) | The patch-and-verify pattern is worth adopting. The shipped patch itself is a last resort. |
| Redist DLL extraction (`RedistDllExtractFix`) | FFXII (`595520`) | Cabinet extraction from the game's own redistributable. Check our ucrtbase evidence first (`docs/evidence/2026-10-09-fm2022-app-local-ucrtbase.md`). |
| Prefix file writes (`PrefixFileFix`) | Steam `1962700` | Files under `drive_c` |
| Folder deletion (`DeleteFolderFix`) | Hogwarts Legacy (Steam `990080`, Epic) | Folder removal before launch |
| Vulkan extension blacklist (`VulkanExtensionBlacklistFix`) | Half-Life 2: VR Mod (`658920`) | Vulkan extensions hidden from the game. Applies to any Vulkan driver, so worth doing. |
| Mouse-drag compatibility (`GameInputCompatibility`) | Crushed in Time (`3858650`) | XGE support and sub-pixel drag accumulation |

## 3. Not applicable to pcios

| an Android launcher fix | Why not |
|---|---|
| `BionicSteamClientFix` (Whisk `3602270`, Whisk Demo `4320000`) | Switches between the Android launcher's Bionic Steam client and the real one. pcios's Steam client is native Swift. |
| WoW Forever DXVK pin (custom `wowb-arm64.exe`) | Pins a an Android launcher-built DXVK. pcios draws through Vulkan on KosmicKrisp and Direct3D through DXMT, so the pin doesn't carry over. |
| Pre-install scripts (GOG script interpreter, Ubisoft Connect) | Only needed if pcios supports those launchers. Ubisoft Connect is refused today. |

## Other ideas from the same survey

- **Driconf per-app Mesa options (`Driconf.kt`): not applicable.** `patches/mesa/0043` says
  KosmicKrisp "has no driconf option table", so there is nothing to write to.
- **Engine detection (`EngineHint.kt`): deferred.** It only helps if some setting changes by
  engine. Nothing in pcios reads an engine yet, so porting it now would be dead code.
- **Apply, measure, keep or revert ladder (`optimize/`): deferred.** It needs a Swift build and
  on-device sessions to judge results. Our starting point would be `FramePacer.swift` and
  `PresentRate.swift` in HostIOKit. See the note in the summary.
