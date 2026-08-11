#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
runner="$script_dir/run_verified_godot_test.sh"
export AI_TOWN_FORMAL_UI_FULL_CLOSURE=1
start_at="${AI_TOWN_FORMAL_RELEASE_START_AT:-1}"
end_at="${AI_TOWN_FORMAL_RELEASE_END_AT:-0}"
skip_indices=",${AI_TOWN_FORMAL_RELEASE_SKIP_INDICES:-},"
# 慢速档(aya 2026-08-06 批准):FAST=1 时本地快速链跳过下列最慢五项,
# 批次收官链与 CI 全量跑。required_tests 清单不受影响(测试仍注册)。
fast_mode="${AI_TOWN_FORMAL_RELEASE_FAST:-0}"
slow_lane=(
	"res://tests/town_world_foundation_test.gd"
	"res://tests/town_activity_test.gd"
	"res://tests/town_world_agent_test.gd"
	"res://tests/town_occupation_test.gd"
)

# 行数棘轮已迁 tools/guards/line_ratchet.py（基线 line_ratchet.json，只降不升；
# CI 的 guards 任务同样运行，此处保留本地验收入口）。
python3 "$script_dir/../../tools/guards/line_ratchet.py" --check

checks=(
	"res://tests/town_world_agent_test.gd|TOWN_WORLD_AGENT_PASS"
	"res://tests/town_world_foundation_test.gd|TOWN_WORLD_FOUNDATION_PASS|164"
	"res://tests/town_conversation_test.gd|TOWN_CONVERSATION_PASS"
	"res://tests/town_occupation_test.gd|TOWN_OCCUPATION_PASS"
	"res://tests/resident_presentation_test.gd|RESIDENT_PRESENTATION_PASS"
	"res://tests/town_world_action_type_registry_test.gd|TOWN_WORLD_ACTION_TYPE_REGISTRY_PASS|66"
	"res://tests/resident_character_speed_stability_test.gd|RESIDENT_CHARACTER_SPEED_STABILITY_PASS"
	"res://tests/town_ui_runtime_test.gd|TOWN_UI_RUNTIME_PASS"
	"res://tests/town_activity_test.gd|TOWN_ACTIVITY_PASS"
	"res://tests/town_resident_content_test.gd|TOWN_RESIDENT_CONTENT_PASS|392"
	"res://tests/town_world_save_test.gd|TOWN_WORLD_SAVE_PASS|177"
	"res://tests/session_save_continue_roundtrip_test.gd|SESSION_SAVE_CONTINUE_ROUNDTRIP_PASS|28"
	"res://tests/windows_directory_cleanup_test.gd|WINDOWS_DIRECTORY_CLEANUP_PASS|22"
	"res://tests/startup_social_feedback_test.gd|STARTUP_SOCIAL_FEEDBACK_PASS|56"
)

index=0
passed=0
skipped=0
for check in "${checks[@]}"; do
	index=$((index + 1))
	if (( index < start_at )) || [[ "$skip_indices" == *",$index,"* ]]; then
		skipped=$((skipped + 1))
		continue
	fi
	if (( end_at > 0 && index > end_at )); then
		skipped=$((skipped + 1))
		continue
	fi
	fields=("${(@s:|:)check}")
	test_script="${fields[1]}"
	pass_marker="${fields[2]}"
	min_checks="${fields[3]:-}"
	if [[ "$fast_mode" == "1" ]] && (( ${slow_lane[(Ie)$test_script]} )); then
		print "\n== 快速链跳过慢速档 $index/${#checks[@]}: $test_script (收官链与 CI 全跑) =="
		skipped=$((skipped + 1))
		continue
	fi
	print "\n== 正式故事检查 $index/${#checks[@]}: $test_script =="
	"$runner" "$test_script" "$pass_marker" ${min_checks:+"$min_checks"}
	passed=$((passed + 1))
done

print "\nFORMAL_RELEASE_STORY_SUITE_PASS checks=$passed skipped=$skipped"
