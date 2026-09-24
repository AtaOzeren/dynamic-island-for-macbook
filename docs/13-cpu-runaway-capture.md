# CPU Runaway Capture Kit

KerNotch intermittently enters a runaway-CPU state that has never been
reproduced under a profiler. The last report recorded **201% CPU over 8h27m**
(`.omo/plans/2026-09-04-relaunch-cpu-menubar-fixes.md`, item 7). This page is
the recipe to run **the next time the runaway happens**, on whichever build is
installed, so the capture happens while the bug is live instead of afterwards.

The idle budget this bug violates lives in
[`02-performance-contract.md`](02-performance-contract.md) — idle CPU < 0.1%,
< 1 wakeup/s. A runaway event is a contract breach by definition; what this
kit establishes is *which threads* are burning the time.

## When to run it

The moment you notice the fan spinning, the Mac heating, or KerNotch showing
a stuck-high CPU figure in Activity Monitor. Do not quit the app first — every
command below works on the live process and none of it disturbs it.

## The capture

Run in Terminal, in order. `sample` and `spindump` each take ~10 s.

```bash
pid=$(pgrep -x KerNotch)
mkdir -p ~/Desktop/kernotch-runaway
ps -M -p "$pid"                                            # per-thread CPU, right now
sample "$pid" 10 -file ~/Desktop/kernotch-runaway/sample-$(date +%Y%m%d-%H%M%S).txt
sudo spindump "$pid" 10 -file ~/Desktop/kernotch-runaway/spindump-$(date +%Y%m%d-%H%M%S).txt
log show --last 10m --predicate 'subsystem == "com.kernotch.KerNotch"' > ~/Desktop/kernotch-runaway/log.txt
```

What each step buys:

- `ps -M` — the per-thread CPU table, instantly. Run it **first** and paste
  the output into the notes below before anything else; it is the only step
  that shows every thread's share at the exact moment of capture.
- `sample` — a 10 s call-graph sample of the process. Shows where the busy
  threads are spending time.
- `spindump` — system-wide, includes what the kernel thinks the process is
  blocked on or spinning in; catches main-thread hangs that `sample` alone
  underreports.
- `log show` — the last 10 minutes of the app's own os_log stream, for what
  changed right before the runaway (provider events, display changes, agent
  messages).

## Why `ps -M` matters

The historical figure was **201%**. macOS reports CPU per process as a
percentage of one core, so 201% means **at least two threads were busy**, not
one hot loop. `sample` and `spindump` both under-sample fast paths; the
per-thread table in `ps -M` is the only output that answers "which N threads?"
directly — and whether they are main, a provider queue, or something the
system drove. That answer decides which fix lane applies, so it comes first.

## Facts to record alongside the capture

Copy the results under `.omo/evidence/cpu-runaway/` and note these in the
evidence file's header — each one is a suspected variable from the 2026-09-06
plan review:

| Fact | Why |
|---|---|
| macOS version, and the music backend from Settings › About (`ScriptingBridge` or `MediaRemote`) | The backend is chosen by macOS release and observes players differently (`06-activity-providers.md`) |
| Display target (built-in only / all displays, external monitor attached?) | Multi-display multiplies per-panel work |
| Was an agent working at the time? | The agent dot and session state drive the expanded island |

## If `log show` comes back empty

On a Mac where unified-log persistence is off, `log show` returns nothing for
*any* process — check with `log show --last 2m | wc -l` before concluding
KerNotch logged nothing. The capture kit's `log show` step is then dead weight,
and the live stream is the only way to read the app's own messages:

```bash
log stream --predicate 'subsystem == "com.kernotch.KerNotch"' --style compact
```

This does not weaken the watchdog's record. Everything the next occurrence has
to be diagnosed from is written to files, not to the log: the report and the
`sample` capture under `~/Library/Logs/KerNotch/`, the restart ledger and the
launch marker under `~/Library/Application Support/KerNotch/`. The log line is
a convenience; the files are the evidence.

## Turning the watchdog off

The CPU watchdog has no UI. It is switched off with a hidden default, and the
key is the settings store's namespaced name — every `SettingsKey` prefixes its
path with `com.kernotch.settings.`, so the bare `cpuWatchdog.disabled` written
by hand does nothing:

```bash
defaults write com.kernotch.KerNotch "com.kernotch.settings.cpuWatchdog.disabled" -bool YES
```

Relaunch KerNotch afterwards; the setting is read once, at launch. KerNotch keeps its settings in `~/Library/Application Support/KerNotch/settings.json`, and at launch it moves any `com.kernotch.settings.*` value found in its preferences domain into that file, so the write is honoured and then removed from the domain. The log
line `CPU watchdog not started: cpuWatchdogDisabled is set` (subsystem
`com.kernotch.KerNotch`, category `cpu-watchdog`) confirms it was honoured.
Undo it the same way, with `-bool NO`: by the time KerNotch has launched, the key is no longer in the domain for `defaults delete` to remove.

**If a sandbox container for `com.kernotch.KerNotch` exists on the machine**
(`~/Library/Containers/com.kernotch.KerNotch/`), `defaults` sends the write into
it, while KerNotch, which is not sandboxed, reads
`~/Library/Preferences/com.kernotch.KerNotch.plist`. The write then lands
where the running app never looks. Address the file directly and flush the
preferences daemon's cache:

```bash
defaults write "$HOME/Library/Preferences/com.kernotch.KerNotch" "com.kernotch.settings.cpuWatchdog.disabled" -bool YES
killall -u "$USER" cfprefsd
```

After relaunching, check that the value arrived where the app reads it:
`grep cpuWatchdog ~/Library/Application\ Support/KerNotch/settings.json`.

## Where results go

Everything lands under `.omo/evidence/cpu-runaway/`, named to sort by date:

```bash
mkdir -p .omo/evidence/cpu-runaway
cp ~/Desktop/kernotch-runaway/* .omo/evidence/cpu-runaway/
```

The idle-cost baseline matrix being filled in parallel lives at
`.omo/evidence/cpu-runaway/idle-matrix-baseline.md` (see
`Scripts/cpu-idle-matrix.sh`). A capture taken during a runaway plus that
baseline is what lets a fix claim a CPU win with evidence rather than a vibe.
