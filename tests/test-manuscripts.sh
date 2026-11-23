#!/bin/bash
# Smoke test for backup-manuscripts.py against the mock API.
# Run it from anywhere:  ./tests/test-manuscripts.sh
set -u
cd "$(dirname "$0")/.."

OUT=tests/out
PORT=8099
M1=2661281675-test-the-end-of-the-loaf
M2=3000000000-test-the-wrong-half
M2_ID=mmmmmmmm-0000-0000-0000-000000000002
BASE="$OUT/testworld/manuscripts"
V1="$BASE/$M1/versions/Draft 1_vvvvvvvv"

rm -rf "$OUT" cookies-settings-test.json
python3 tests/mock_wa_api.py --port "$PORT" --quiet \
    --data tests/fixtures-manuscripts.json \
    --short-pages \
    --forbid "manuscript/manuscript_labels:$M2_ID" &
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
run1=$(python3 backup-manuscripts.py --settings tests/settings-test.cfg)
echo "$run1"

echo "--- checks ----------------------------------------------------"
check "both manuscripts found" 1 "$(echo "$run1" | grep -c 'Found 2 manuscripts')"
check "manuscript list saved" 1 "$(count "$BASE" 'all_manuscripts_*.json')"
check "manuscript details saved" 1 "$(count "$BASE/$M1" 'manuscript_*.json')"
check "version details saved" 1 "$(count "$BASE/$M1/versions" 'Draft 1_vvvvvvvv_*.json')"
# the mock hands back one entry less per page; no part may be lost
check "part list saved" 1 "$(count "$V1" 'parts_*.json')"
check "3 parts saved" 3 "$(find "$V1/parts" -maxdepth 1 -type f ! -name '*_beats_*' | wc -l)"
# two parts share a title and the first 8 characters of the id, they must not share a file
check "same-title parts kept apart" 2 "$(count "$V1/parts" 'The End of the Loaf_*.json')"
check "beat saved" 1 "$(find "$V1/parts" -type f -path '*_beats/*' | wc -l)"
check "empty beat lists not written" 1 "$(find "$V1/parts" -type f -name '*_beats_*.json' | wc -l)"
check "stat saved" 1 "$(count "$V1/stats" '*.json')"
check "label saved" 1 "$(count "$BASE/$M1/labels" 'Blue_*.json')"
# the 403 for the labels of the second manuscript
check "403 was reported" 1 "$(echo "$run1" | grep -c 'wrong-half: labels list failed')"
check "failed list not saved as empty" 0 "$(count "$BASE/$M2" 'labels_*.json')"
check "run continued after the 403" 1 "$(count "$BASE/$M2" 'versions_*.json')"

echo "--- run 2 (nothing changed, so nothing may be written) --------"
run2=$(python3 backup-manuscripts.py --settings tests/settings-test.cfg)
check "files written on run 2" "Wrote 0 files" "$(echo "$run2" | grep -o 'Wrote 0 files')"

echo "--- run 3 (single manuscript by part of the title) ------------"
run3=$(python3 backup-manuscripts.py --settings tests/settings-test.cfg --manuscript "wrong half")
check "single manuscript picked" 1 "$(echo "$run3" | grep -c 'Backing up 1 manuscript: The Wrong Half')"
check "other manuscript skipped" 0 "$(echo "$run3" | grep -c "MANUSCRIPT: $M1")"

echo "--- run 4 (single manuscript by slug) -------------------------"
run4=$(python3 backup-manuscripts.py --settings tests/settings-test.cfg --manuscript "$M1")
check "slug picked the manuscript" 1 "$(echo "$run4" | grep -c 'Backing up 1 manuscript: The End of the Loaf')"

echo "---------------------------------------------------------------"
if [ "$fail" = 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit $fail
