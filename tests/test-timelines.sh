#!/bin/bash
# Smoke test for backup-timelines.py against the mock API.
# Run it from anywhere:  ./tests/test-timelines.sh
set -u
cd "$(dirname "$0")/.."

OUT=tests/out
PORT=8099
BULK=60          # more than one page, so the paging really runs
TOTAL=$((BULK + 3))
T2_ID=tttttttt-0000-0000-0000-000000000002
BASE="$OUT/testworld"

rm -rf "$OUT" cookies-settings-test.json
python3 tests/mock_wa_api.py --port "$PORT" --quiet \
    --data tests/fixtures-timelines.json \
    --short-pages --bulk-histories "$BULK" \
    --forbid "timeline:$T2_ID" &
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
run1=$(python3 backup-timelines.py --settings tests/settings-test.cfg)
echo "$run1"

echo "--- checks ----------------------------------------------------"
check "both timelines found" 1 "$(echo "$run1" | grep -c 'Found 2 timelines')"
check "timeline list saved" 1 "$(count "$BASE/timelines" 'all_timelines_*.json')"
check "timeline details saved" 1 "$(count "$BASE/timelines/boresia-timeline" 'timeline_*.json')"
# the 403 for one timeline
check "403 was reported" 1 "$(echo "$run1" | grep -c 'timeline dashan-timeline failed')"
check "run continued after the 403" 1 "$(echo "$run1" | grep -c 'Found 63 histories')"
check "failed timeline not saved" 0 "$(count "$BASE/timelines/dashan-timeline" '*.json')"
# the mock hands back one entry less per page; no history may be lost
check "history list saved" 1 "$(count "$BASE/histories" 'all_histories_*.json')"
check "all histories saved" "$TOTAL" "$(find "$BASE/histories" -maxdepth 1 -type f ! -name 'all_histories_*' | wc -l)"
# two events share a title and the first 8 characters of the id, they must not share a file
check "same-title histories kept apart" 2 "$(count "$BASE/histories" 'Founding_*.json')"
check "history keeps its data" 1 "$(grep -l '"endingYear": 2115' "$BASE"/histories/1st\ War_* | wc -l)"

echo "--- run 2 (nothing changed, so nothing may be written) --------"
run2=$(python3 backup-timelines.py --settings tests/settings-test.cfg)
check "files written on run 2" "Wrote 0 files" "$(echo "$run2" | grep -o 'Wrote 0 files')"

echo "---------------------------------------------------------------"
if [ "$fail" = 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit $fail
