# Performance Contract

NotchFlow lives on the notch permanently. If it is not free while idle, it fails at the one job that matters more than any feature: staying invisible in Activity Monitor. This document is the numeric contract every build must satisfy. It is not a goal; it is a gate. Todo 66 turns every row below into an automated script, and a regression on any row is a build failure, not a follow-up ticket.

## The budget

| Metric | Budget | Measured how |
|---|---|---|
| Idle CPU | < 0.1% averaged over 60s | `powermetrics` sampler, see below |
| Idle wakeups | < 1 per second | `powermetrics --samplers tasks` |
| Resident memory (idle) | < 60 MB | `ps -o rss` on the app process |
| Continuous idle GPU work | No continuously committed frames | Instruments GPU report, 60s idle capture |
| Energy impact (idle) | "Low" in Activity Monitor | Manual read of the Energy tab after 5 min idle |

"Idle" means: the island is resting in its static compact form, no activity is active, and there has been no user interaction for at least 10 seconds. These are the conditions under which every number above must hold, not an average across a busy session.

## Forbidden patterns

Each of these has caused real notch-app battery complaints in the wild. None of them are acceptable, even temporarily, even behind a flag.

| Pattern | Why it's forbidden |
|---|---|
| `while true` polling loops | Pins a core; defeats App Nap entirely |
| A repeating `Timer` left active while idle | Wakes the process on a fixed cadence even with nothing to show |
| Periodic system re-query (e.g. polling `NSWorkspace` or media state on an interval) | Trades a push-based OS API for a busy-poll; wastes wakeups for no new information |
| Screen scanning of any kind | Not just a performance problem — it is also the privacy invariant this app is built around |
| Animation while idle | Keeps the compositor active even though compact content is unchanged |
| Unnecessary network calls while idle | Network activity is one of the most expensive wakeup sources on battery |
| A retained render loop (e.g. a `CADisplayLink`-style ticker) that keeps running while idle | Keeps the compositor scheduled at display refresh rate for unchanged content |

## Required patterns

| Pattern | Why it's required |
|---|---|
| Subscribe to OS notifications (`NSWorkspace`, `NSNotificationCenter`, distributed notifications) instead of polling | Push-based; the OS wakes us only when something actually changed |
| `DispatchSourceTimer` with generous leeway, active only while a time-based activity (countdown/stopwatch) is visible | Leeway lets the OS coalesce our wakeup with others already scheduled, instead of forcing a precise one |
| Static compact content after the final activity ends | Preserves the persistent island without retaining animation or timer work |
| Passive `NSEvent` global monitors rather than polling for input state | Global monitors are event-driven; polling mouse/keyboard state on a timer is pure waste |
| `ProcessInfo.beginActivity` scoped as narrowly as possible and ended promptly | Prevents accidental App Nap suppression outliving the work it was meant to protect |
| Explicit cooperation with App Nap — no blanket `.userInitiated` activity held for the app's lifetime | App Nap is the OS's own idle-cost enforcement; fighting it undoes everything else in this document |

## Measurement protocol

Run every measurement after the app has been idle for at least 60 seconds (no activity active, island compact, no user interaction). Numbers taken during an active animation or a just-triggered activity are not valid samples.

### CPU and wakeups: `powermetrics`

```
sudo powermetrics --samplers tasks -i 1000 -n 60 --show-process-energy | grep -A 5 "NotchFlow"
```

Run for 60 samples at 1-second intervals (60 seconds total). Average the CPU% column across all 60 samples; it must be < 0.1%. The wakeups-per-second column must average < 1.

### Resident memory: `ps`

```
ps -o rss= -p $(pgrep -x NotchFlow)
```

`rss` is reported in KB; divide by 1024 for MB. Must read < 60 MB while idle. Sample three times, 20 seconds apart, and use the median to avoid catching a transient allocation spike.

### GPU: Instruments

Use the **Core Animation** Instruments template and record a 60-second idle window. The persistent compact surface may remain composited, but it must not create a continuous stream of committed frames; any sustained frame activity is a failure.

### Energy Impact: Activity Monitor

Open Activity Monitor's Energy tab, let the app sit idle for 5 minutes, and confirm the Energy Impact column reads "Low." This is the only manual (non-scripted) check in this contract, because Activity Monitor's energy scoring is not exposed as a stable CLI/API surface.

### CPU profiling for regressions: Instruments Time Profiler

For deeper investigation when a budget is violated, use the **Time Profiler** template over the same 60-second idle window and inspect the heaviest stack. A passing run shows the profiler capturing almost nothing — near-zero samples is the expected, correct result for an idle app.

## Pass/fail

A build passes this contract only if every numeric row in the budget table is met simultaneously, on real hardware (not the simulator — there is no notch simulator, and idle-power characteristics do not transfer from a MacBook Pro to a MacBook Air). Todo 66 wires the `powermetrics` and `ps` checks above into an automated script that runs in CI and on real hardware before release; any regression against these thresholds blocks the build.
