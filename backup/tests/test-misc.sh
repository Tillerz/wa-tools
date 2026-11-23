#!/bin/bash
# Smoke test for backup-misc.py against the mock API.
# Run it from anywhere:  ./tests/test-misc.sh
set -u
cd "$(dirname "$0")/.."

OUT=tests/out
PORT=8099
VC2=cccccccc-0000-0000-0000-000000000002
LOCKED_FOLDER=22631
LOCKED_TEMPLATE=2655
BASE="$OUT/testworld"

rm -rf "$OUT" cookies-settings-test.json
python3 tests/mock_wa_api.py --port "$PORT" --quiet \
    --data tests/fixtures-misc.json \
    --short-pages \
    --forbid "variablecollection/variables:$VC2" \
    --forbid "blockfolder/blocks:$LOCKED_FOLDER" \
    --forbid "blocktemplate:$LOCKED_TEMPLATE" &
MOCK_PID=$!
trap 'kill $MOCK_PID 2>/dev/null' EXIT
sleep 1

fail=0
check() {   # check <what> <expected> <actual>
    if [ "$2" = "$3" ]; then
        echo "  PASS  $1 = $3"
    else
        echo "  FAIL  $1: expected $2, got $3"
        fail=1
    fi
}
count() {   # count <folder> <name pattern>: files in that folder only
    find "$1" -maxdepth 1 -type f -name "$2" 2>/dev/null | wc -l
}

echo "--- run 1 -----------------------------------------------------"
run1=$(python3 backup-misc.py --settings tests/settings-test.cfg)
echo "$run1"

echo "--- checks ----------------------------------------------------"
check "canvas list saved" 1 "$(count "$BASE/canvases" 'all_canvases_*.json')"
check "canvas saved" 1 "$(count "$BASE/canvases" 'Family tree_*.json')"
check "secret list saved" 1 "$(count "$BASE/secrets" 'all_secrets_*.json')"
check "3 secrets saved" 3 "$(find "$BASE/secrets" -maxdepth 1 -type f ! -name 'all_secrets_*' | wc -l)"
# two secrets share a title and the first 8 characters of the id, they must not share a file
check "same-title secrets kept apart" 2 "$(count "$BASE/secrets" 'Great Library_*.json')"
check "secret keeps its text (from the single read)" 1 "$(grep -l vault "$BASE"/secrets/Great* | wc -l)"
check "collection list saved" 1 "$(count "$BASE/variables" 'all_variablecollections_*.json')"
check "3 collections saved" 3 "$(find "$BASE/variables" -maxdepth 1 -type f ! -name 'all_*' ! -name '*_variables_*' | wc -l)"
check "variable list of collection 1 saved" 1 "$(count "$BASE/variables" 'Alana_cccccccc_variables_*.json')"
check "2 variables saved" 2 "$(find "$BASE/variables/Alana_cccccccc_variables" -type f | wc -l)"
check "variable without title is named by its id" 1 "$(count "$BASE/variables/Alana_cccccccc_variables" 'vvvvvvvv_*.json')"
check "variable keeps its value" 1 "$(grep -l Tillerz "$BASE"/variables/Alana_cccccccc_variables/* | wc -l)"
check "empty collection: empty list saved" 1 "$(count "$BASE/variables" 'Subscriber_cccccccc_variables_*.json')"
# the 403 for the variables of one collection
check "403 was reported" 1 "$(echo "$run1" | grep -c 'containers_cccccccc_variables list failed')"
check "failed list not saved as empty" 0 "$(count "$BASE/variables" 'containers_cccccccc_variables_*.json')"

# block folders and blocks: the ids are integers
check "block folder list saved" 1 "$(count "$BASE/blocks" 'all_blockfolders_*.json')"
check "3 block folders saved" 3 "$(find "$BASE/blocks" -maxdepth 1 -type f ! -name 'all_*' ! -name '*_blocks_*' | wc -l)"
check "block list of folder saved" 1 "$(count "$BASE/blocks" 'Characters_22629_blocks_*.json')"
check "2 blocks saved" 2 "$(find "$BASE/blocks/Characters_22629_blocks" -type f | wc -l)"
check "same-title blocks kept apart" 2 "$(count "$BASE/blocks/Characters_22629_blocks" 'Druid_*.json')"
check "block keeps its data (from the single read)" 1 "$(grep -l 'hp.*40' "$BASE"/blocks/Characters_22629_blocks/* | wc -l)"
check "empty folder: empty list saved" 1 "$(count "$BASE/blocks" 'Items_22632_blocks_*.json')"
check "403 for the blocks was reported" 1 "$(echo "$run1" | grep -c 'Locked_22631_blocks list failed')"
check "failed block list not saved as empty" 0 "$(count "$BASE/blocks" 'Locked_22631_blocks_*.json')"

# block templates belong to the user (the user id comes from GET /identity), the ids are integers
check "template list saved" 1 "$(count "$BASE/blocktemplates" 'all_blocktemplates_*.json')"
check "3 templates saved" 3 "$(find "$BASE/blocktemplates" -maxdepth 1 -type f ! -name 'all_*' | wc -l)"
check "same-title templates kept apart" 2 "$(count "$BASE/blocktemplates" 'Adversary_*.json')"
check "template without title is named by its id" 1 "$(count "$BASE/blocktemplates" '2652_*.json')"
check "template keeps its parts" 1 "$(grep -l 'Level' "$BASE"/blocktemplates/2652_* | wc -l)"
check "403 for a template was reported" 1 "$(echo "$run1" | grep -c 'blocktemplates Locked_2655 failed')"
check "failed template not saved" 0 "$(count "$BASE/blocktemplates" 'Locked_*.json')"

echo "--- run 2 (nothing changed, so nothing may be written) --------"
run2=$(python3 backup-misc.py --settings tests/settings-test.cfg)
check "files written on run 2" "Wrote 0 files" "$(echo "$run2" | grep -o 'Wrote 0 files')"

echo "--- run 3 (one type only) -------------------------------------"
rm -rf "$OUT"
run3=$(python3 backup-misc.py --settings tests/settings-test.cfg --type secrets)
check "secrets saved" 1 "$(count "$BASE/secrets" 'all_secrets_*.json')"
check "other types skipped" 0 "$(ls -d "$BASE"/canvases "$BASE"/variables "$BASE"/blocks "$BASE"/blocktemplates 2>/dev/null | wc -l)"

echo "---------------------------------------------------------------"
if [ "$fail" = 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit $fail
