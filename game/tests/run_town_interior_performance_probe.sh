#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
expect_lazy="${AI_TOWN_INTERIOR_PERF_EXPECT_LAZY:-1}"
godot_bin="${GODOT_BIN:-}"
if [[ -z "$godot_bin" ]]; then
	for candidate in godot godot4 /opt/homebrew/bin/godot /Applications/Godot.app/Contents/MacOS/Godot; do
		if command -v "$candidate" >/dev/null 2>&1; then
			godot_bin="$(command -v "$candidate")"
			break
		fi
	done
fi
if [[ -z "$godot_bin" || ! -x "$godot_bin" ]]; then
	print -u2 "Godot executable not found"
	exit 2
fi

for mode in startup room_build entry_memory; do
	probe_output="$(AI_TOWN_PROVIDER_TEST_NO_NETWORK=1 \
	AI_TOWN_INTERIOR_PERF_MODE="$mode" \
		"$godot_bin" \
		--headless \
		--path "$project_root" \
		--script res://tests/town_interior_performance_probe.gd)"
	print -r -- "$probe_output"
	if [[ "$mode" == "room_build" && "$probe_output" != *"rooms=10"* ]]; then
		print -u2 "Room-build probe did not complete all ten rooms"
		exit 1
	fi
	if [[ "$mode" == "entry_memory" && (
		"$probe_output" != *"coldFirstEntryUsec="*
		|| "$probe_output" != *"prewarmedEntryUsec="*
		|| "$probe_output" != *"reentryUsec="*
	) ]]; then
		print -u2 "Entry probe did not report cold, prewarmed, and re-entry timings"
		exit 1
	fi
	if [[ "$mode" == "entry_memory" && "$expect_lazy" == "1" && (
		"$probe_output" != *"coldBuiltBefore=0"*
		|| "$probe_output" != *"prewarmedBuiltBefore=1"*
	) ]]; then
		print -u2 "Entry probe did not preserve the expected cold/prewarmed setup"
		exit 1
	fi
	if [[ "$mode" == "entry_memory" && "$probe_output" != *"rooms=10"* ]]; then
		print -u2 "Entry probe did not construct and enter all ten rooms"
		exit 1
	fi
done
