#!/bin/zsh

set -uo pipefail

script_dir="${0:A:h}"
runner="$script_dir/run_verified_godot_test.sh"
runs="${AI_TOWN_INTERIOR_STABILITY_RUNS:-5}"
failures=0

for run_index in $(seq 1 "$runs"); do
	print "ISSUE141_STABILITY_RUN_BEGIN index=$run_index"
	"$runner" \
		res://tests/town_interior_build_stability_test.gd \
		TOWN_INTERIOR_BUILD_STABILITY_PASS \
		12
	run_exit=$?
	print "ISSUE141_STABILITY_RUN_END index=$run_index exit=$run_exit"
	if (( run_exit != 0 )); then
		failures=$((failures + 1))
	fi
done

print "ISSUE141_STABILITY_SUMMARY runs=$runs failures=$failures"
exit "$failures"
