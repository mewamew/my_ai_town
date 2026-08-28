#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
parallel="${AI_TOWN_HISTORICAL_MATRIX_PARALLEL:-2}"
if [[ "$parallel" != <1-2> ]]; then
  print -u2 "历史矩阵并行数必须为 1 或 2。"
  exit 2
fi

run_shard() {
  local shard_id="$1"
  local fixture_ids="$2"
  AI_TOWN_HISTORICAL_SHARD_ID="$shard_id" \
  AI_TOWN_ISOLATED_FIXTURE_IDS="$fixture_ids" \
    "$script_dir/run_historical_save_migration_story.sh"
}

if ((parallel == 1)); then
	run_shard "matrix" "beta1 beta2 beta3 beta4 beta5 beta6"
else
  log_root="$(mktemp -d "${TMPDIR:-/tmp}/ai-town-history-matrix.XXXXXX")"
  trap 'rm -rf "$log_root"' EXIT
  run_shard "matrix-a" "beta1 beta3 beta5" >"$log_root/a.log" 2>&1 &
  first_pid=$!
	run_shard "matrix-b" "beta2 beta4 beta6" >"$log_root/b.log" 2>&1 &
  second_pid=$!
  failed=0
  if ! wait "$first_pid"; then
    failed=1
  fi
  if ! wait "$second_pid"; then
    failed=1
  fi
  cat "$log_root/a.log"
  cat "$log_root/b.log"
  if ((failed != 0)); then
    exit 1
  fi
fi
print "HISTORICAL_SAVE_MIGRATION_MATRIX_PASS releases=6"
