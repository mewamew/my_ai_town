#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
fixture_ids_text="${AI_TOWN_ISOLATED_FIXTURE_IDS:-}"
if [[ -n "$fixture_ids_text" ]]; then
  fixture_ids=("${(@s: :)fixture_ids_text}")
  for fixture_id in "${fixture_ids[@]}"; do
    if [[ "$fixture_id" != beta[1-6] ]]; then
		print -u2 "存档兼容故事只接受 beta1 至 beta6。"
      exit 2
    fi
  done
  shard_id="${AI_TOWN_HISTORICAL_SHARD_ID:-matrix}"
  export AI_TOWN_ISOLATED_QA_PREFIX="ai-town-historical-$shard_id"
  export AI_TOWN_ISOLATED_TEMP_PREFIX="ai-town-historical-$shard_id"
  export AI_TOWN_ISOLATED_FIXTURE_ROOT_BASE="$script_dir/fixtures/historical_saves"
else
  fixture_id="${AI_TOWN_HISTORICAL_FIXTURE_ID:-beta2}"
	if [[ "$fixture_id" != beta[1-6] ]]; then
		print -u2 "存档兼容故事只接受 beta1 至 beta6。"
    exit 2
  fi
  export AI_TOWN_HISTORICAL_FIXTURE_ID="$fixture_id"
  export AI_TOWN_ISOLATED_QA_PREFIX="ai-town-historical-$fixture_id"
  export AI_TOWN_ISOLATED_TEMP_PREFIX="ai-town-historical-$fixture_id"
  export AI_TOWN_ISOLATED_FIXTURE_ROOT="$script_dir/fixtures/historical_saves/$fixture_id"
fi
export AI_TOWN_PROVIDER_TEST_NO_NETWORK=1
export AI_TOWN_ISOLATED_TEST_SCRIPT="res://tests/historical_save_migration_story_test.gd"
export AI_TOWN_ISOLATED_PASS_MARKER="HISTORICAL_SAVE_MIGRATION_STORY_PASS"
export AI_TOWN_ISOLATED_TIMEOUT_SECONDS="${AI_TOWN_HISTORICAL_MIGRATION_TIMEOUT_SECONDS:-600}"
export AI_TOWN_ISOLATED_FAILURE_MARKER="HISTORICAL_SAVE_MIGRATION_STORY_FAIL"
export AI_TOWN_ISOLATED_SUCCESS_MARKER="HISTORICAL_SAVE_MIGRATION_STORY_VERIFIED"
export AI_TOWN_ISOLATED_ALLOWED_ERROR_PATTERN='a^'

exec "$script_dir/run_isolated_formal_entry_story.sh"
