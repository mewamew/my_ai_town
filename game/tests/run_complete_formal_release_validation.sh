#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"

"$script_dir/run_formal_release_story_suite.sh"
"$script_dir/run_isolated_formal_entry_story.sh"
"$script_dir/run_historical_save_migration_matrix.sh"

print "COMPLETE_FORMAL_RELEASE_VALIDATION_PASS"
