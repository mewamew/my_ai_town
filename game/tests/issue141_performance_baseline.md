# Issue #141 performance baseline

The original comparison below was measured on 2026-08-25 with Godot
`4.7.stable.official.5b4e0cb0f`, headless `gl_compatibility`, on the same
machine. No other repository tests were running. The PR150-merged recheck was
run on 2026-08-26 with Godot `4.7.1.stable.official.a13da4feb`.

The probe fixes `workshop` as the cold-entry target and `home_a` as the delayed
prewarm target. Each mode runs in a separate Godot process. Entry time includes
the complete fade/transition used by the game.

## Reproduce

Baseline commit:

```text
ab6c1818b5c1ef1b0b6396f99b0f000f376e009b (origin/main)
```

After creating a detached worktree at that commit, copy the probe and runner
from this branch, import its assets once, then run:

```sh
/Applications/Godot.app/Contents/MacOS/Godot \
  --headless --editor --import --path /path/to/baseline/game
AI_TOWN_INTERIOR_PERF_EXPECT_LAZY=0 \
  /path/to/baseline/game/tests/run_town_interior_performance_probe.sh
```

Run the implementation from this worktree with:

```sh
game/tests/run_town_interior_performance_probe.sh
```

## Raw baseline output

```text
ISSUE141_PERF_STARTUP syncColdUsec=1359960 initialRooms=10 delayedRooms=10 delayedLongestFrameUsec=13128 queueMaxFrameUsec=0 queueMaxStageUsec=0 staticMiB=440.9 peakStaticMiB=440.9
ISSUE141_PERF_ROOM_BUILD rooms=10 totalUsec=937628 maxRoomUsec=110269 staticMiB=240.2 peakStaticMiB=348.3
ISSUE141_PERF_ENTRY coldInterior=workshop coldBuiltBefore=1 coldFirstEntryUsec=384169 prewarmedInterior=home_a prewarmedBuiltBefore=1 prewarmWaitFrames=0 prewarmedEntryUsec=582817 reentryInterior=workshop reentryUsec=587717 rooms=10 queueMaxRoomCpuUsec=0 queueMaxRoomWallUsec=0 staticMiB=441.7 peakStaticMiB=442.0
```

`origin/main` reports `coldBuiltBefore=1`: all ten rooms already exist before
the first entry, so it cannot provide a truly cold on-demand entry. The field is
kept to make that difference explicit instead of relabeling the eager result.

## Raw implementation output before PR150 merge

```text
ISSUE141_PERF_STARTUP syncColdUsec=381790 initialRooms=0 delayedRooms=1 delayedLongestFrameUsec=8483 queueMaxFrameUsec=7505 queueMaxStageUsec=1062 staticMiB=306.0 peakStaticMiB=351.2
ISSUE141_PERF_ROOM_BUILD rooms=10 totalUsec=1361457 maxRoomUsec=214782 staticMiB=243.3 peakStaticMiB=351.2
ISSUE141_PERF_ENTRY coldInterior=workshop coldBuiltBefore=0 coldFirstEntryUsec=833982 prewarmedInterior=home_a prewarmedBuiltBefore=1 prewarmWaitFrames=27 prewarmedEntryUsec=577058 reentryInterior=workshop reentryUsec=583419 rooms=10 queueMaxRoomCpuUsec=35962 queueMaxRoomWallUsec=346218 staticMiB=381.6 peakStaticMiB=382.1
```

The queue's `8000` microsecond value is a scheduling target, not a hard frame
guarantee. The dedicated stability test therefore records actual longest stage
and frame work separately. Direct synchronous room construction is slower in
the implementation; normal gameplay uses the resumable preparation path.

## PR150-merged recheck (2026-08-26)

This recheck uses `origin/main` at `7b1f3dbcfebfe35f0db7016adbdfdbd547424701`
plus the PR155 changes. It also includes the approach prewarm path: when the
player is within 720 px of the nearest unbuilt door, that room is queued with
priority so normal walking can finish preparation before the door threshold.
The probe intentionally keeps `workshop` cold at the entry point to preserve a
worst-case fallback measurement; the lazy-loading test separately verifies
that an approaching room is ready before entry.
If a transition starts without any approach time, the entry path now requests
the room before the fade begins so the fade overlaps preparation.

```text
ISSUE141_PERF_STARTUP syncColdUsec=318589 initialRooms=0 delayedRooms=1 delayedLongestFrameUsec=10257 queueMaxFrameUsec=7504 queueMaxStageUsec=1401 staticMiB=390.5 peakStaticMiB=395.9
ISSUE141_PERF_ROOM_BUILD rooms=10 totalUsec=1148604 maxRoomUsec=181628 staticMiB=327.7 peakStaticMiB=367.0
ISSUE141_PERF_ENTRY coldInterior=workshop coldBuiltBefore=0 coldFirstEntryUsec=599815 prewarmedInterior=home_a prewarmedBuiltBefore=1 prewarmWaitFrames=27 prewarmedEntryUsec=585352 reentryInterior=workshop reentryUsec=578740 rooms=10 queueMaxRoomCpuUsec=31694 queueMaxRoomWallUsec=326639
```

The absolute memory values include the local Godot import/runtime cache; use
the recorded trend and the bounded-frame checks for comparisons across runs.
