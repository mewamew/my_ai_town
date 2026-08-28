#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
repo_root="${script_dir:h:h}"
fixture_output="${1:-$repo_root/.tmp/historical-save-fixtures}"
capture_patch="$script_dir/historical_fixture_capture.patch"
activity_capture_patch="$script_dir/historical_activity_lifecycle_capture.patch"
verifier="$script_dir/verify_historical_save_fixtures.py"
expected_test_sha256="6a7ca497bc1c12567aee9414a424d53a7da504bb469a0725f77654c3979def03"

if [[ -n "${GODOT_BIN:-}" ]]; then
  godot_bin="$GODOT_BIN"
elif command -v godot >/dev/null 2>&1; then
  godot_bin="$(command -v godot)"
elif command -v godot4 >/dev/null 2>&1; then
  godot_bin="$(command -v godot4)"
else
  print -u2 "Godot executable not found; set GODOT_BIN."
  exit 1
fi

if [[ -e "$fixture_output" ]]; then
  print -u2 "输出目录已存在，不会覆盖：$fixture_output"
  exit 1
fi

case "$(uname -s)" in
  Darwin)
    capture_user_root="$HOME/Library/Application Support/my_ai_town_issue146_fixture"
    activity_user_root="$HOME/Library/Application Support/my_ai_town_issue146_custom_resident"
    ;;
  Linux)
    capture_user_root="${XDG_DATA_HOME:-$HOME/.local/share}/my_ai_town_issue146_fixture"
    activity_user_root="${XDG_DATA_HOME:-$HOME/.local/share}/my_ai_town_issue146_custom_resident"
    ;;
  *)
    print -u2 "当前脚本只支持 macOS 和 Linux。"
    exit 1
    ;;
esac

if [[ -e "$capture_user_root" ]]; then
  print -u2 "隔离用户目录已存在，请先确认并移走：$capture_user_root"
  exit 1
fi
if [[ -e "$activity_user_root" ]]; then
  print -u2 "隔离用户目录已存在，请先确认并移走：$activity_user_root"
  exit 1
fi

scratch_root="$(mktemp -d /tmp/my-ai-town-historical-fixtures.XXXXXX)"
capture_worktree="$scratch_root/worktree"
worktree_active=false

cleanup() {
  if [[ "$worktree_active" == true ]]; then
    git -C "$repo_root" worktree remove --force "$capture_worktree" >/dev/null 2>&1 || true
  fi
  if [[ -d "$capture_user_root" ]]; then
    mv "$capture_user_root" "$scratch_root/unclean-user-root" >/dev/null 2>&1 || true
  fi
  if [[ -d "$activity_user_root" ]]; then
    mv "$activity_user_root" "$scratch_root/unclean-activity-user-root" >/dev/null 2>&1 || true
  fi
  rm -rf "$scratch_root"
}
trap cleanup EXIT INT TERM

versions=(beta1 beta2 beta3 beta4 beta5 beta6)
source_refs=(
  v0.1.0-beta.1
  v0.1.0-beta.2
  v0.1.0-beta.3
  v0.1.0-beta.4
  v0.1.0-beta.5
  6675f770eb0062613360467ef5278bb721155846
)

mkdir -p "$fixture_output"
for index in {1..6}; do
  version_name="${versions[$index]}"
  source_ref="${source_refs[$index]}"
  import_log="$scratch_root/${version_name}-import.log"
  run_log="$scratch_root/${version_name}-run.log"

  git -C "$repo_root" worktree add --detach "$capture_worktree" "$source_ref" >/dev/null
  worktree_active=true
  test_sha256="$(shasum -a 256 "$capture_worktree/game/tests/session_save_continue_roundtrip_test.gd" | awk '{print $1}')"
  if [[ "$test_sha256" != "$expected_test_sha256" ]]; then
    print -u2 "$version_name 的生成测试与已审计版本不一致。"
    exit 1
  fi
  git -C "$capture_worktree" apply "$capture_patch"

  "$godot_bin" --headless --path "$capture_worktree/game" --import >"$import_log" 2>&1
  MY_AI_TOWN_FIXTURE_ID="$version_name" \
    "$godot_bin" --headless --path "$capture_worktree/game" \
    --script res://tests/session_save_continue_roundtrip_test.gd >"$run_log" 2>&1
  if ! rg -q '^SESSION_SAVE_CONTINUE_ROUNDTRIP_PASS checks=26$' "$run_log"; then
    tail -80 "$run_log" >&2
    exit 1
  fi
  if ! rg -q "^HISTORICAL_FIXTURE_CAPTURE\\|${version_name}\\|" "$run_log"; then
    tail -80 "$run_log" >&2
    exit 1
  fi
  if [[ ! -d "$capture_user_root" ]]; then
    print -u2 "$version_name 没有生成隔离用户目录。"
    exit 1
  fi

  mkdir -p "$fixture_output/$version_name"
  rsync -a \
    --exclude logs \
    --exclude objectdb_snapshots \
    "$capture_user_root/" "$fixture_output/$version_name/"
  mv "$capture_user_root" "$scratch_root/${version_name}-user-root"
  git -C "$repo_root" worktree remove --force "$capture_worktree" >/dev/null
  worktree_active=false
  print "HISTORICAL_FIXTURE_GENERATED $version_name"
done

long_path_id='long-path-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx'
git -C "$repo_root" worktree add --detach "$capture_worktree" v0.1.0-beta.5 >/dev/null
worktree_active=true
git -C "$capture_worktree" apply "$capture_patch"
"$godot_bin" --headless --path "$capture_worktree/game" --import \
  >"$scratch_root/beta5-scenarios-import.log" 2>&1
MY_AI_TOWN_FIXTURE_ID="$long_path_id" \
  "$godot_bin" --headless --path "$capture_worktree/game" \
  --script res://tests/session_save_continue_roundtrip_test.gd \
  >"$scratch_root/beta5-long-path-run.log" 2>&1
if ! rg -q '^SESSION_SAVE_CONTINUE_ROUNDTRIP_PASS checks=26$' \
  "$scratch_root/beta5-long-path-run.log"; then
  tail -80 "$scratch_root/beta5-long-path-run.log" >&2
  exit 1
fi
mkdir -p "$fixture_output/beta5-long-path"
rsync -a --exclude logs --exclude objectdb_snapshots \
  "$capture_user_root/" "$fixture_output/beta5-long-path/"
mv "$capture_user_root" "$scratch_root/beta5-long-path-user-root"

git -C "$capture_worktree" apply --reverse "$capture_patch"
git -C "$capture_worktree" apply "$activity_capture_patch"
MY_AI_TOWN_CAPTURE_CUSTOM_RESIDENT=1 \
MY_AI_TOWN_CAPTURE_ACTIVITY_LIFECYCLE=1 \
  "$godot_bin" --headless --path "$capture_worktree/game" \
  --script res://tests/game_flow_host_formal_entry_test.gd \
  >"$scratch_root/beta5-activity-lifecycle-run.log" 2>&1
if ! rg -q '^GAME_FLOW_HOST_FORMAL_ENTRY_PASS$' \
  "$scratch_root/beta5-activity-lifecycle-run.log"; then
  tail -80 "$scratch_root/beta5-activity-lifecycle-run.log" >&2
  exit 1
fi
if ! rg -q '^HISTORICAL_SCENARIO_CAPTURE\|beta5-custom-resident\|' \
  "$scratch_root/beta5-activity-lifecycle-run.log"; then
  tail -80 "$scratch_root/beta5-activity-lifecycle-run.log" >&2
  exit 1
fi
mkdir -p "$fixture_output/beta5-activity-lifecycle"
rsync -a --exclude logs --exclude objectdb_snapshots \
  "$activity_user_root/" "$fixture_output/beta5-activity-lifecycle/"
mv "$activity_user_root" "$scratch_root/beta5-activity-lifecycle-user-root"
git -C "$repo_root" worktree remove --force "$capture_worktree" >/dev/null
worktree_active=false
print "HISTORICAL_FIXTURE_GENERATED beta5-long-path"
print "HISTORICAL_FIXTURE_GENERATED beta5-activity-lifecycle"

cp "$repo_root/game/tests/fixtures/historical_saves/catalog.json" "$fixture_output/catalog.json"
python3 "$verifier" --root "$fixture_output" --refresh
