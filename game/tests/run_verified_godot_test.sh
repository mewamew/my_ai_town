#!/bin/zsh

set -u
set -o pipefail

if (( $# != 2 && $# != 3 )); then
	print -u2 "用法：$0 <res://测试脚本.gd> <唯一通过标记> [最低断言数]"
	exit 2
fi

test_script="$1"
pass_marker="$2"
min_checks="${3:-}"
project_root="${0:A:h:h}"
timeout_seconds="${AI_TOWN_TEST_TIMEOUT_SECONDS:-300}"
temp_base="${TMPDIR:-/tmp}"
log_file="$(mktemp "$temp_base/ai-town-godot-test.XXXXXX")"

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
	print -u2 "Godot executable is not runnable: $godot_bin"
	exit 2
fi

# 正式回归只验证本地契约，不应读取开发机上的 Provider 配置并发起真实
# 健康检查。调用者仍可显式设为 0，专门运行需要联网的验证。
: "${AI_TOWN_PROVIDER_TEST_NO_NETWORK:=1}"
export AI_TOWN_PROVIDER_TEST_NO_NETWORK

cleanup() {
	rm -f "$log_file"
}
trap cleanup EXIT

/usr/bin/perl -e \
	'$timeout = shift @ARGV; alarm $timeout; exec @ARGV;' \
	"$timeout_seconds" \
	"$godot_bin" \
	--headless \
	--path "$project_root" \
	--script "$test_script" \
	>"$log_file" 2>&1
godot_status=$?

cat "$log_file"

if (( godot_status != 0 )); then
	print -u2 \
		"TEST_PROCESS_FAILED: $test_script exit=$godot_status timeout=${timeout_seconds}s"
	exit "$godot_status"
fi

if rg -q \
	-e 'SCRIPT ERROR:' \
	-e 'Parse Error:' \
	-e 'Failed to load script' \
	"$log_file"; then
	print -u2 "TEST_SCRIPT_ERROR: $test_script"
	exit 1
fi

# 行首 ERROR: 捕捉 Godot 引擎错误（如脱树 get_tree、退出资源泄漏）。
# 行首匹配避免误捕 JSON/断言文本里的 ERROR: 字样。注意 Godot 4.7 中
# push_error 的输出同样是行首 ERROR:——正式套件的测试在通过路径上
# 不应触发 push_error；确需验证预期错误的测试，为该测试加精确允许
# 条目（参见 run_isolated_formal_entry_story.sh 的做法），不放宽全局规则。
if rg -q -e '^ERROR:' "$log_file"; then
	print -u2 "TEST_ENGINE_ERROR: $test_script"
	exit 1
fi

if rg -q \
	-e 'ObjectDB instances were leaked at exit' \
	-e '^Leaked instance:' \
	"$log_file"; then
	print -u2 "TEST_RESOURCE_LEAK: $test_script"
	exit 1
fi

if ! rg -q -F "$pass_marker" "$log_file"; then
	print -u2 "TEST_PASS_MARKER_MISSING: $test_script marker=$pass_marker"
	exit 1
fi

# 分测试最低断言数（铁律第 2 条 (b)）：对已输出 checks=N 的测试，
# 校验通过标记所在行的 N 不低于套件清单钉住的最低值。
if [[ -n "$min_checks" ]]; then
	actual_checks="$(rg -F "$pass_marker" "$log_file" | rg -o 'checks=[0-9]+' | head -n 1 | cut -d= -f2)"
	if [[ -z "$actual_checks" ]]; then
		print -u2 "TEST_CHECKS_MISSING: $test_script 期望输出 checks=N (最低 $min_checks)"
		exit 1
	fi
	if (( actual_checks < min_checks )); then
		print -u2 "TEST_CHECKS_SHRUNK: $test_script checks=$actual_checks < 最低 $min_checks"
		exit 1
	fi
fi

print "VERIFIED_GODOT_TEST_PASS: $test_script"
