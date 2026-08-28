#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
test_script="${AI_TOWN_ISOLATED_TEST_SCRIPT:-res://tests/game_flow_host_formal_entry_test.gd}"
pass_marker="${AI_TOWN_ISOLATED_PASS_MARKER:-GAME_FLOW_HOST_FORMAL_ENTRY_PASS}"
timeout_seconds="${AI_TOWN_ISOLATED_TIMEOUT_SECONDS:-${AI_TOWN_FORMAL_ENTRY_TIMEOUT_SECONDS:-600}}"
qa_prefix="${AI_TOWN_ISOLATED_QA_PREFIX:-ai-town-automated-formal-story}"
temp_prefix="${AI_TOWN_ISOLATED_TEMP_PREFIX:-ai-town-formal-story}"
failure_marker="${AI_TOWN_ISOLATED_FAILURE_MARKER:-ISOLATED_FORMAL_ENTRY_STORY_FAIL}"
success_marker="${AI_TOWN_ISOLATED_SUCCESS_MARKER:-ISOLATED_FORMAL_ENTRY_STORY_PASS}"
fixture_root="${AI_TOWN_ISOLATED_FIXTURE_ROOT:-}"
fixture_ids_text="${AI_TOWN_ISOLATED_FIXTURE_IDS:-}"
fixture_root_base="${AI_TOWN_ISOLATED_FIXTURE_ROOT_BASE:-}"
qa_name="$qa_prefix-$$"
temp_base="${TMPDIR:-/tmp}"
if [[
	"$qa_prefix" == *[^a-z0-9-]*
	|| "$temp_prefix" == *[^a-z0-9-]*
]]; then
	print -u2 "隔离测试目录前缀无效。"
	exit 2
fi
if [[ -n "$fixture_root" && "$fixture_root" != "$project_root/tests/fixtures/"* ]]; then
	print -u2 "隔离测试样本必须位于 tests/fixtures 下。"
	exit 2
fi
if [[ -n "$fixture_ids_text" ]]; then
	if [[
		-n "$fixture_root"
		|| "$fixture_root_base" != "$project_root/tests/fixtures/"*
	]]; then
		print -u2 "批量隔离测试需要唯一的 tests/fixtures 样本根目录。"
		exit 2
	fi
	fixture_ids=("${(@s: :)fixture_ids_text}")
	for fixture_id in "${fixture_ids[@]}"; do
		if [[
			"$fixture_id" == *[^a-z0-9-]*
			|| ! -d "$fixture_root_base/$fixture_id"
		]]; then
			print -u2 "批量隔离测试样本无效：$fixture_id"
			exit 2
		fi
	done
else
	fixture_ids=()
fi
if [[ "$(uname -s)" == "Darwin" ]]; then
	default_userdata_root="${HOME}/Library/Application Support/Godot/app_userdata"
else
	default_userdata_root="${HOME}/.local/share/godot/app_userdata"
fi
godot_userdata_root="${GODOT_USERDATA_ROOT:-$default_userdata_root}"
qa_user_root="$godot_userdata_root/$qa_name"
temp_root="$(mktemp -d "$temp_base/$temp_prefix.XXXXXX")"
temp_game="$temp_root/game"
log_path="$temp_root/formal-entry.log"

cleanup() {
	if [[ "$temp_root" == "$temp_base/$temp_prefix."* ]]; then
		rm -rf "$temp_root"
	fi
	if [[ "$qa_user_root" == "$godot_userdata_root/$qa_prefix-"* ]]; then
		rm -rf "$qa_user_root"
	fi
}
trap cleanup EXIT

resolve_godot_bin() {
	if [[ -n "${GODOT_BIN:-}" ]]; then
		print -r -- "$GODOT_BIN"
		return 0
	fi
	local command_name
	for command_name in godot godot4; do
		if command -v "$command_name" >/dev/null 2>&1; then
			command -v "$command_name"
			return 0
		fi
	done
	local app_bin
	for app_bin in \
		"/Applications/Godot.app/Contents/MacOS/Godot" \
		"$HOME/Applications/Godot.app/Contents/MacOS/Godot"; do
		if [[ -x "$app_bin" ]]; then
			print -r -- "$app_bin"
			return 0
		fi
	done
	return 1
}

if ! godot_bin="$(resolve_godot_bin)"; then
	print -u2 "Godot executable not found; set GODOT_BIN or add godot/godot4 to PATH."
	exit 2
fi

if [[ ! -x "$godot_bin" ]]; then
	print -u2 "Godot 4.7.1 executable not found: $godot_bin"
	exit 2
fi

mkdir -p "$temp_game"
# Keep the full imported project state while isolating project name and user://.
if [[ "$(uname -s)" == "Darwin" ]]; then
	# APFS clone-on-write avoids duplicating the multi-gigabyte asset tree.
	cp -cR "$project_root/." "$temp_game/"
else
	# GNU cp：支持 reflink 的文件系统走克隆，其余自动回退为普通复制。
	cp -a --reflink=auto "$project_root/." "$temp_game/"
fi

# 用 perl 做原位替换：BSD 与 GNU sed 的 -i 语法不兼容，perl 两边一致
# （本脚本已依赖 /usr/bin/perl 做超时控制）。
/usr/bin/perl -pi -e \
	"s/^config\\/name=.*/config\\/name=\"$qa_name\"/" \
	"$temp_game/project.godot"
if [[ -n "$fixture_root" && ${#fixture_ids[@]} -eq 0 ]]; then
	mkdir -p "$qa_user_root"
	cp -R "$fixture_root/." "$qa_user_root/"
fi

import_log_path="$temp_root/editor-import.log"
set +e
/usr/bin/perl -e \
	'$timeout = shift @ARGV; alarm $timeout; exec @ARGV;' \
	"$timeout_seconds" \
	"$godot_bin" \
	--headless \
	--editor \
	--path "$temp_game" \
	--quit \
	>"$import_log_path" 2>&1
import_exit_code=$?
set -e

if (( import_exit_code != 0 )); then
	print -u2 \
		"$failure_marker import_exit=$import_exit_code timeout=${timeout_seconds}s"
	tail -n 120 "$import_log_path" >&2
	exit "$import_exit_code"
fi
if rg -q 'SCRIPT ERROR:|Parse Error:|Failed to load script' "$import_log_path"; then
	print -u2 "$failure_marker import_script_error=true"
	rg -n 'SCRIPT ERROR:|Parse Error:|Failed to load script' "$import_log_path" >&2
	exit 3
fi
if rg -q '^ERROR:' "$import_log_path"; then
	print -u2 "$failure_marker import_engine_error=true"
	rg -n '^ERROR:' "$import_log_path" >&2
	exit 3
fi

run_story() {
	local fixture_id="$1"
	local story_log="$log_path"
	local command_prefix=()
	if [[ -n "$fixture_id" ]]; then
		story_log="$temp_root/formal-entry-$fixture_id.log"
		command_prefix=(env "AI_TOWN_HISTORICAL_FIXTURE_ID=$fixture_id")
		rm -rf "$qa_user_root"
		mkdir -p "$qa_user_root"
		cp -R "$fixture_root_base/$fixture_id/." "$qa_user_root/"
		print "\n== 历史存档升级：$fixture_id → beta6 =="
	fi
	set +e
	"${command_prefix[@]}" /usr/bin/perl -e \
		'$timeout = shift @ARGV; alarm $timeout; exec @ARGV;' \
		"$timeout_seconds" \
		"$godot_bin" \
		--headless \
		--path "$temp_game" \
		--script "$test_script" \
		>"$story_log" 2>&1
	local exit_code=$?
	set -e

	if (( exit_code != 0 )); then
		print -u2 \
			"$failure_marker exit=$exit_code timeout=${timeout_seconds}s"
		tail -n 120 "$story_log" >&2
		return "$exit_code"
	fi
	if rg -q 'SCRIPT ERROR:|Parse Error:|Failed to load script' "$story_log"; then
		print -u2 "$failure_marker script_error=true"
		rg -n 'SCRIPT ERROR:|Parse Error:|Failed to load script' "$story_log" >&2
		return 3
	fi
	# 除精确允许的故事错误外，任何引擎错误都判失败。
	local allowed_error_pattern="${AI_TOWN_ISOLATED_ALLOWED_ERROR_PATTERN:-^ERROR: Agent Gateway 初始化失败：当前 session 要求正式 Agent Gateway。$}"
	local unexpected_engine_errors="$(rg '^ERROR:' "$story_log" | rg -v "$allowed_error_pattern" || true)"
	if [[ -n "$unexpected_engine_errors" ]]; then
		print -u2 "$failure_marker engine_error=true"
		print -r -- "$unexpected_engine_errors" >&2
		return 3
	fi
	if ! rg -Fq "$pass_marker" "$story_log"; then
		print -u2 "$failure_marker missing_pass_marker=true"
		tail -n 120 "$story_log" >&2
		return 4
	fi
	rg -F "$pass_marker" "$story_log" | tail -n 1
	print "$success_marker"
}

if (( ${#fixture_ids[@]} == 0 )); then
	run_story ""
else
	for fixture_id in "${fixture_ids[@]}"; do
		run_story "$fixture_id"
	done
fi
