# Planning: per-game settings ladder

**Status:** plan only. No code. Revisit on a Mac with a Swift toolchain, Xcode and an iPhone.
**Scope:** an opt-in way for pcios to try launch settings on a game, measure the result, and keep
or revert each step.
**Source of ideas:** GameNative's `app/src/main/java/app/gamenative/optimize/` (GPL-3.0). We take
the concept and the judging rules. We don't take its server, its Android-specific levers, or its
file-editing levers.

## 1. Problem

Some games run well at the default settings, some need a lower frame rate to avoid
thermal throttling, and some need a different graphics backend. Today the player finds these
settings by hand on each game's page. Shipped per-title defaults
([0074](../decisions/0074-per-title-compatibility-defaults.md)) only cover games we have tested.
The ladder would cover the rest by trying the options and keeping what helps.

## 2. Goals and non-goals

Goals:
- Find a better launch setting for a game without the player tuning it by hand.
- Only keep a change that measurably helped, and undo it when it didn't.
- Never override a setting the player chose.
- Keep everything on the device. No telemetry, no server, in the first version.

Non-goals (first version):
- No edits to game files, registry, or INI files. Only `LaunchSettings` values, which the
  app already knows how to apply and revert. This avoids most of GameNative's levers.
- No community or server-side rules, and no GPU-keyed best-config database.
- No engine-specific rungs. Engine detection stays deferred until a rung needs it.

## 3. What already exists in pcios

| Piece | Where | Role in the ladder |
|---|---|---|
| Launch settings | `app/PlayportKit/Sources/PlayportKit/LaunchSettings.swift` | The only thing a rung changes: screen, aspect, frame limit, graphics backend, runtime keys, graphics options, JIT pool, and others |
| Precedence | Decision 0074, amended by 0091 | Person's own choice, then the title's default, then Settings, then built-in default. The ladder slots in as a level below the person's choice. |
| Compat table | `app/PlayportKit/Titles/compat-defaults.json` | Shipped, verified defaults. The ladder never edits this file. |
| Frame pacing | `app/HostIOKit/Sources/HostIOKit/FramePacer.swift` | Used by the frame-limit rung |
| Present rate | `app/HostIOKit/Sources/HostIOKit/PresentRate.swift` | Frame rate and frame time, for judging |
| Performance overlay | `app/Sources/S1Probe/UI/PerformanceOverlay.swift` | Live numbers for the player and for dev runs |
| Offline measurement | `tools/perf.py` (`pp perf`, `--compare`, `--cool`) | Measures a title run second by second, compares two runs, and cools the phone between runs. It is the calibration tool for the judge. |
| Thermal notes | `docs/DEVICE.md` (around line 581) | Records that thermals set the frame rate on long runs |

## 4. Design

### 4.1 Rungs

A rung is a named change from the current settings, for example "frame limit 30" or "graphics
backend DXMT" or "x87 reduced precision on". The ladder is an ordered list of rungs, cheapest
and least risky first:

1. Frame limit (cuts heat and power, usually costs nothing the player notices)
2. Screen size (lower render size)
3. Graphics backend, where Settings allows a choice
4. Memory and JIT pool settings, only where the title's memory need is known
5. Runtime keys (x87 precision, instance limits), last, because they are the most likely to break a game

Each rung has a version number. A rung change means it is judged again.

### 4.2 Steps

- Start from the current settings for the game.
- Apply one rung. Play a fixed-length session. Record the metrics in 4.3.
- Judge the session against the baseline (4.4).
- Keep the rung if it helped or the result is not comparable. Revert it if it made things worse,
  or if the game crashed.
- Move to the next rung. Stop when the list ends, when the player changes a setting, or after a
  fixed number of tries.

### 4.3 Metrics per session

- Steady frame rate (median per-second frame rate over gameplay)
- Frame rate 10th percentile (low end, as a stutter proxy)
- Frame time 99th percentile
- Thermal state reached (`ProcessInfo.thermalState`, the iOS equivalent of Android's thermal status)
- Crash or freeze at exit
- Gameplay seconds, excluding menus and loading (a session is comparable only above a minimum)

GameNative's judge uses 5-minute windows, skips the first window, and marks a session as
frozen if no frame arrives for 30 seconds while the game is on screen. We take the same shape
and tune the numbers on our phone.

### 4.4 Judging

Starting values, to be tuned against `pp perf --compare` runs:

- Helped: steady frame rate up at least 8%, or frame time p99 down, with no new crash.
- Worse: steady frame rate down more than 5%, or a new crash or freeze.
- Not comparable: under the minimum gameplay time, or menu-heavy. Keep the rung, mark it
  not judged, and don't use it as evidence.
- Crash at any point marks the rung as bad for that game, so it is never tried again on
  that game until the rung's version changes.

### 4.5 Keep and revert

- Before applying a rung, store the previous value of each key it changes.
- A reverted rung restores exactly those values, not the defaults.
- A kept rung stays in the game's state until the player resets the game, or the rung's
  version changes.
- If the app is killed while a trial is running, the next launch restores the stored values
  before doing anything else. A trial must never leave a game in an unknown state.

### 4.6 Precedence

The ladder fills only keys the player has not set. If the player sets the frame limit, the
ladder never touches the frame limit for that game. This follows the existing precedence from
0074 and 0091, with the ladder as its own level.

### 4.7 State and privacy

- Per-game state is a small versioned JSON file in the app container. It stores the tried
  rungs, their verdicts, and any kept changes.
- Nothing leaves the device in the first version. There is no server and no shared rule table.

### 4.8 Player experience

- Opt-in per game, on the game's page: "Try better settings for this game".
- Shows what changed and why, in plain words, and offers one-tap revert.
- Player-facing text follows the rules in 0074: no issue IDs, no internal references, no
  build names.

## 5. Verification plan

Split by what each environment can prove:

| Check | Where | What it proves |
|---|---|---|
| Judge logic, ladder state machine, revert-on-kill, precedence | Swift unit tests, on a Mac or CI | Pure logic is right, including edge cases |
| Store and restore of launch settings | Swift tests, on a Mac | The stored values come back exactly |
| UI flow and persistence | iPhone Simulator | The page, the messages and the state file behave |
| Real frame rate, thermals, memory limits, JIT | Physical iPhone only | Whether a rung helps. A simulator can't show this. |
| Judge calibration | `pp perf` runs on the phone, `--compare` offline | The thresholds match what a person would call better |

Important limit: the iPhone Simulator runs on the Mac's own hardware and doesn't run the JIT
path, the device memory limit, or thermal throttling the way a phone does. It can prove the
logic and the UI. It can't prove that a rung helps on the game. Every "helped" verdict in the
first version has to come from a phone run.

## 6. Phases

0. **Decide** the open questions in section 8 and fix the starting thresholds.
1. **Pure logic:** judge, ladder state machine, state file, revert-on-kill, with Swift tests. No UI.
2. **Measurement:** connect the session metrics to the ladder, and check them against `pp perf`
   runs on the phone.
3. **Calibration:** run the ladder on the two cohort titles (Hollow Knight, The Witcher 3) and
   tune the thresholds on those runs. Record the result in an evidence file.
4. **UI:** the opt-in on the game's page, with copy reviewed against 0074.
5. **Decision record:** write it up as a numbered decision once phase 3 has real results.

## 7. Risks

- **Thermal confounds.** A session right after a long one runs hot and looks worse. Mitigation:
  cool down between trials (`pp perf --cool`), and compare only sessions with similar thermal state.
- **Noisy frame rates.** Short sessions give wrong verdicts. Mitigation: minimum gameplay time,
  and "not comparable" as a verdict.
- **Crash loops.** A bad rung restarts a game again and again. Mitigation: a crash marks the rung
  bad, and the ladder never retries it on that game.
- **Silent changes.** A player doesn't know why a game looks different. Mitigation: the opt-in
  shows every change and offers a revert.
- **Memory limit.** A rung that lowers quality may still exceed the iOS memory limit. Mitigation:
  the memory need from the title config is checked before any memory rung runs.

## 8. Open questions for the owner

1. Is the ladder opt-in per game only, or is there a global switch as well?
2. Which rungs go in the first version? The plan proposes frame limit, screen size and backend only.
3. What minimum gameplay time makes a session comparable? The plan starts from GameNative's
   setting and tunes on phone runs.
4. Does a kept rung survive a game update, or does a new build reset the state?
5. Should a crash-marked rung stay bad forever, or expire after a new app version?

## 9. Dependencies

- A Mac with a Swift toolchain and Xcode, for the logic and UI work
- A physical iPhone for judging (section 5)
- The `pp perf` path working for the cohort titles
- Decision 0074 and 0091 still in force
