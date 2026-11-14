# Planning: per-game settings ladder

**Status:** plan only. No code. Revisit on a Mac with a Swift toolchain, Xcode and an iPhone.
**Scope:** an opt-in way for pcios to try launch settings on a game, measure the result on the
player's own phone, and keep or revert each step.
**Source of ideas:** the Android launcher's `(source path omitted)` (GPL-3.0). We take
the concept and the judging shape. We don't take its server, its Android-specific levers, or its
file-editing levers.

## 1. Problem

Some games run well at the default settings, some need a lower frame rate to avoid thermal
throttling, and some need a different graphics backend. Today the player finds these settings
by hand on each game's page. Shipped per-title defaults
([0074](../decisions/0074-per-title-compatibility-defaults.md)) only cover games we have tested.
The ladder would cover the rest by trying options and keeping what helps.

## 2. Goals and non-goals

Goals:
- Find a better launch setting for a game without the player tuning it by hand.
- Keep a change only if it measurably helped, and undo it when it didn't.
- Never override a setting the player chose.
- Judge entirely on the phone, with no computer attached. No telemetry, no server, in the first version.

Non-goals (first version):
- No edits to game files, registry, or INI files. Only `LaunchSettings` values, which the app
  already knows how to apply and revert.
- No community or server-side rules, and no GPU-keyed best-config database.
- No engine-specific rungs. Engine detection stays deferred until a rung needs it.
- No host-side measurement at runtime. Host tools calibrate the thresholds; they don't judge
  trials in the field.

## 3. What already exists in pcios

| Piece | Where | Role in the ladder |
|---|---|---|
| Launch settings | `app/PlayportKit/Sources/PlayportKit/LaunchSettings.swift` | The only thing a rung changes |
| Precedence | Decision 0074, amended by 0091 | Person's own choice, then the title's default, then Settings, then built-in default. The ladder sits below the person's choice. |
| Compat table | `app/PlayportKit/Titles/compat-defaults.json` | Shipped, verified defaults. The ladder never edits this file. |
| Frame pacing | `app/HostIOKit/Sources/HostIOKit/FramePacer.swift` | Used by the frame-limit rung |
| Present rate | `app/HostIOKit/Sources/HostIOKit/PresentRate.swift` | Frames per second and frame time, from frame timestamps. The judge's main input. |
| Performance overlay | `app/Sources/S1Probe/UI/PerformanceOverlay.swift` | Live numbers for the player and for dev runs |
| Title memory need | `app/PlayportKit/Titles/titles.json` | The memory footprint the title reached on the reference phone |
| Host calibration | `tools/perf.py` (`pp perf`, `--compare`, `--cool`) | Measures a run from a computer over USB and compares runs. Used only to check the in-app judge. |

## 4. Design

### 4.1 Rungs

A rung is a named change from the current settings, for example "frame limit 30" or "graphics
backend DXMT". The ladder is an ordered list, cheapest and least risky first:

1. Frame limit (less heat and power, usually little visible cost)
2. Screen size (lower render size)
3. Graphics backend, where Settings allows a choice
4. Memory settings, only where the title's memory need is known and the phone has headroom (4.9)
5. Runtime keys (x87 precision, instance limits), last, because they are the most likely to break a game

Each rung has a version number. A changed rung is judged again.

### 4.2 Trials and the app restart

Pcios restarts itself after each game so the next one gets a fresh JIT (0.3.3 release notes). A
trial therefore ends when the game session ends, and the restart is part of that boundary. The
trial's state is written before the restart, and the next launch continues from it.

- Start from the game's current settings.
- Apply one rung. Play. The trial ends when the game session ends.
- Judge the trial against the baseline (4.4).
- Keep the rung if it helped or the result is not comparable. Revert it if it was worse, or if
  the session crashed.
- Move to the next rung at the next launch of that game. Stop when the list ends, the player
  changes a setting, or a fixed number of rungs has been tried.

### 4.3 Metrics per trial, from the phone

Each metric is available to a third-party app on the device:

- Frames per second, the median of one-second windows (from `PresentRate`)
- Frame time 99th percentile, from frame timestamps
- Thermal state at the start and the end (`ProcessInfo.thermalState`, with change notifications)
- Memory headroom (`os_proc_available_memory()`) at the start, used by the memory-rung gate
- How the session ended: normal exit, crash, or freeze
- Gameplay seconds: the time from the first frame to the last

A freeze means no frame was presented for 30 seconds while the game's layer was on screen and
the app was not suspended. This uses only the app's own present timestamps.

Trials use the first 60 seconds as warm-up and skip them. Frame counts before that aren't
compared.

### 4.4 Judging

Starting values, tuned against host calibration runs (section 5):

- Helped: median frames per second up at least 8%, or frame time p99 down, with no new crash
  or freeze.
- Worse: median frames per second down more than 5%, or a new crash or freeze.
- Not comparable: under the minimum gameplay time, or thermal state reached "serious" or
  "critical" in one trial and not the other. Keep the rung, mark it not judged, and don't use
  it as evidence.
- A crash marks the rung bad for that game. The ladder never tries that rung again on that game
  until the rung's version changes.

Limit: the judge can't tell whether two trials showed the same scene. Menus, a different level, or
a different camera would all change the frame rate. Trials are therefore advisory. A verdict
should be shown to the player as "seemed faster", not as a measured fact. Section 8 asks whether
that's acceptable.

### 4.5 Keep and revert

- Before applying a rung, store the previous value of each key it changes.
- A reverted rung restores exactly those values, not the defaults.
- A kept rung stays until the player resets the game, or the rung's version changes.
- If the app is killed during a trial, the next launch restores the stored values before anything
  else. A trial must never leave a game in an unknown state.

### 4.6 Precedence

The ladder fills only keys the player has not set. If the player sets the frame limit, the
ladder never touches it for that game. This follows 0074 and 0091, with the ladder as its own
level.

### 4.7 State and privacy

- Per-game state is a small versioned JSON file in the app container. It stores tried rungs,
  their verdicts, and kept changes.
- Nothing leaves the device in the first version.

### 4.8 Player experience

- Opt-in per game, on the game's page: "Try better settings for this game".
- Shows what changed and why, in plain words, with one-tap revert.
- Player-facing text follows 0074: no issue IDs, no internal references, no build names.

### 4.9 Memory gate

Before a memory rung runs, the app checks `os_proc_available_memory()` and the title's memory
need from `titles.json`. If there isn't enough headroom, the rung is skipped and marked as not
tried.

## 5. Verification

Split by what each environment can prove:

| Check | Where | What it proves |
|---|---|---|
| Judge logic, ladder state machine, revert-on-kill, precedence | Swift unit tests, on a Mac or CI | Pure logic is right, including edge cases |
| Store and restore of launch settings | Swift tests, on a Mac | Stored values come back exactly |
| UI and state file across app restarts | iPhone Simulator | The page, the messages and the persisted state behave |
| In-app metrics match host measurements | Physical iPhone, `pp perf` on the same run | The in-app frame and frame-time numbers agree with the host's |
| Judge thresholds | Physical iPhone, host calibration runs, `--compare` | The thresholds match what a person would call better |
| Optional: a kept rung's cause | Mac, Instruments (Game Performance, Metal System Trace) | Why a rung helped, for the write-up |

The iPhone Simulator runs on the Mac's own hardware. It doesn't run the device JIT path, the
device memory limit, or thermal throttling the way a phone does. It can prove the logic and the
UI, not that a rung helps. Every "helped" verdict in the first version has to come from a phone.

## 6. Phases

0. **Decide** the open questions in section 8 and fix the starting thresholds.
1. **Pure logic:** judge, ladder state machine, state file, revert-on-kill, with Swift tests. No UI.
2. **In-app measurement:** wire the metrics in 4.3 to the trial. Check them against `pp perf` on
   the same runs.
3. **Calibration:** run the ladder on the two cohort titles (Hollow Knight, The Witcher 3) and
   tune the thresholds on those runs. Record the result in an evidence file.
4. **UI:** the opt-in on the game's page, with copy reviewed against 0074.
5. **Decision record:** write it up as a numbered decision once phase 3 has real results.

## 7. Risks

- **Thermal confounds.** A trial right after a long one runs hot and looks worse. Mitigation:
  compare only trials with similar thermal state, and mark the rest not comparable.
- **Scene differences.** The judge can't see whether two trials showed the same scene. Mitigation:
  verdicts are advisory and worded that way (4.4).
- **Noisy frame rates.** Short trials give wrong verdicts. Mitigation: minimum gameplay time and
  "not comparable" as a verdict.
- **Crash loops.** A bad rung restarts a game again and again. Mitigation: a crash marks the rung
  bad, and the ladder never retries it on that game.
- **Restarts mid-trial.** The app restarts after each game, and the OS can kill it at any time.
  Mitigation: state is written before each boundary, and the next launch recovers it (4.5).
- **Silent changes.** A player doesn't know why a game looks different. Mitigation: the opt-in
  shows every change and offers a revert.
- **Memory limit.** A lower-quality rung may still exceed the iOS memory limit. Mitigation: the
  memory gate (4.9).

## 8. Open questions for the owner

1. Is the ladder opt-in per game only, or is there a global switch too?
2. Which rungs go in the first version? The plan proposes frame limit, screen size and backend.
3. Are advisory verdicts ("seemed faster") acceptable to show players, given the scene limit in 4.4?
4. What minimum gameplay time makes a trial comparable? The plan starts from the Android launcher's
   setting and tunes on phone runs.
5. Does a kept rung survive a game update, or does a new build reset the state?
6. Should a crash-marked rung stay bad forever, or expire with a new app version?

## 9. Dependencies

- A Mac with a Swift toolchain and Xcode, for the logic and UI work
- A physical iPhone for judging (section 5)
- Decisions 0074 and 0091 still in force

## 10. What we cut, and why

These were in an earlier draft and are not available to a third-party app on a player's phone,
so they're out of the plan:

- **CPMS thermal power budgets and device syslog.** They come from the kernel's syslog, which
  apps can't read. Host calibration can use them, but the in-app judge can't.
- **Other processes' CPU, per-core residency, and energy.** iOS doesn't expose them to apps.
  Host calibration can use them.
- **GPU time from Metal command buffers.** We would need our Metal layer to expose it, and it
  isn't confirmed. Revisit only if the frame-time judge proves too weak.
- **Menu and loading detection.** The app can't tell what the game is showing. We use a fixed
  warm-up skip instead (4.3), and accept the scene limit (4.4).
- **Battery level.** Not needed for the judge; thermal state covers the heat question.
- **MetricKit.** Its daily aggregate reports are too coarse to judge one trial. It's a possible
  field-regression check later, not part of the ladder.
