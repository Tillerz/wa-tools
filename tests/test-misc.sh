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
LOCKED_GROUP=grp00000-0000-0000-0000-000000000002
BASE="$OUT/testworld"

rm -rf "$OUT"
python3 tests/mock_wa_api.py --port "$PORT" --quiet \
    --data tests/fixtures-misc.json \
    --short-pages \
    --forbid "variablecollection/variables:$VC2" \
    --forbid "blockfolder/blocks:$LOCKED_FOLDER" \
    --forbid "blocktemplate:$LOCKED_TEMPLATE" \
    --forbid "subscribergroup:$LOCKED_GROUP" &
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

check "no --parts: no part folders" 0 "$(find "$BASE/blocktemplates" -maxdepth 1 -name '*_parts' | wc -l)"

# categories and subscriber groups
check "category list saved" 1 "$(count "$BASE/categories" 'all_categories_*.json')"
check "3 categories saved" 3 "$(find "$BASE/categories" -maxdepth 1 -type f ! -name 'all_*' | wc -l)"
check "same-title categories kept apart" 2 "$(count "$BASE/categories" 'Characters_*.json')"
check "category date comes from updateDate" 1 "$(count "$BASE/categories" 'Places_cat00000_2026-04-03_100000.json')"
check "subscriber group list saved" 1 "$(count "$BASE/subscribergroups" 'all_subscribergroups_*.json')"
check "1 subscriber group saved" 1 "$(find "$BASE/subscribergroups" -maxdepth 1 -type f ! -name 'all_*' | wc -l)"
check "subscriber group keeps its subscribers" 1 "$(grep -l 'player one' "$BASE"/subscribergroups/GM_* | wc -l)"
check "403 for a subscriber group was reported" 1 "$(echo "$run1" | grep -c 'subscribergroups: all_subscribergroups Locked_grp00000 failed')"

echo "--- run 2 (nothing changed, so nothing may be written) --------"
run2=$(python3 backup-misc.py --settings tests/settings-test.cfg)
check "files written on run 2" "Wrote 0 files" "$(echo "$run2" | grep -o 'Wrote 0 files')"

echo "--- run 3 (one type only) -------------------------------------"
rm -rf "$OUT"
run3=$(python3 backup-misc.py --settings tests/settings-test.cfg --type secrets)
check "secrets saved" 1 "$(count "$BASE/secrets" 'all_secrets_*.json')"
check "other types skipped" 0 "$(ls -d "$BASE"/canvases "$BASE"/variables "$BASE"/blocks "$BASE"/blocktemplates "$BASE"/categories "$BASE"/subscribergroups 2>/dev/null | wc -l)"

echo "--- run 4 (one block template, with its parts) ---------------"
rm -rf "$OUT"
run4=$(python3 backup-misc.py --settings tests/settings-test.cfg --template 2652 --parts)
echo "$run4" | grep -E "BLOCKTEMPLATES|_parts"
check "--template implies the block templates only" 0 "$(ls -d "$BASE"/secrets "$BASE"/canvases "$BASE"/variables 2>/dev/null | wc -l)"
check "the template list has all templates" 4 "$(python3 -c "import json,glob;print(len(json.load(open(glob.glob('$BASE/blocktemplates/all_blocktemplates_*.json')[0]))))")"
check "only the picked template was read" 1 "$(find "$BASE/blocktemplates" -maxdepth 1 -type f ! -name 'all_*' | wc -l)"
check "both parts saved" 2 "$(find "$BASE/blocktemplates/2652_parts" -type f 2>/dev/null | wc -l)"
check "a part keeps its own data" 1 "$(grep -l 'Fighter or Fighter / Cleric' "$BASE"/blocktemplates/2652_parts/Class_63609_* 2>/dev/null | wc -l)"

echo "--- run 5 (the same again: nothing changed, nothing written) ---"
run5=$(python3 backup-misc.py --settings tests/settings-test.cfg --template 2652 --parts)
check "files written on run 5" "Wrote 0 files" "$(echo "$run5" | grep -o 'Wrote 0 files')"

echo "--- run 6 (--template with two matches: it must stop) ---------"
rm -rf "$OUT"
run6=$(python3 backup-misc.py --settings tests/settings-test.cfg --template Adversary 2>&1); code=$?
check "exit code is an error" 1 "$code"
check "both matches are listed" 1 "$(echo "$run6" | grep -c "matches 2 block templates")"
check "no template was read" 0 "$(find "$BASE/blocktemplates" -maxdepth 1 -type f ! -name 'all_*' 2>/dev/null | wc -l)"

echo "--- run 7 (--template together with another --type is an error) --"
python3 backup-misc.py --settings tests/settings-test.cfg --template 2652 --type secrets >/dev/null 2>&1
check "exit code of the wrong combination" 2 "$?"

echo "--- run 8 (categories and secrets: not read again when the date in the list is the same) --"
rm -rf "$OUT"
python3 backup-misc.py --settings tests/settings-test.cfg --type categories --type secrets >/dev/null
run8=$(python3 backup-misc.py --settings tests/settings-test.cfg --type categories --type secrets)
echo "$run8" | grep -E "unchanged|Wrote"
check "categories (all 3 have a date) and the secret with a date are not read again; 2 secrets without a date are" "Wrote 0 files, 2 detail requests." "$(echo "$run8" | grep -o 'Wrote 0 files, [0-9]* detail requests.')"
run9=$(python3 backup-misc.py --settings tests/settings-test.cfg --type categories --type secrets --full)
check "--full: all 3 categories and all 3 secrets are read" "Wrote 0 files, 6 detail requests." "$(echo "$run9" | grep -o 'Wrote 0 files, [0-9]* detail requests.')"
run10a=$(python3 backup-misc.py --settings tests/settings-test.cfg --type subscribergroups | grep -o '[0-9]* detail requests')
run10b=$(python3 backup-misc.py --settings tests/settings-test.cfg --type subscribergroups | grep -o '[0-9]* detail requests')
check "a type without dates in the list is read on every run" "$run10a" "$run10b"
check "... and it did read something" 1 "$([ "${run10a%% *}" -gt 0 ] && echo 1 || echo 0)"

echo "---------------------------------------------------------------"
if [ "$fail" = 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit $fail
