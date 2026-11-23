#!/bin/bash
# Smoke test for backup-images.py against the mock API.
# Run it from anywhere:  ./tests/test-images.sh
set -u
cd "$(dirname "$0")/.."

OUT=tests/out
PORT=8099
BULK=60          # more than one page, so the paging really runs
TOTAL=$((BULK + 3))
BASE="$OUT/testworld/images"

rm -rf "$OUT" cookies-settings-test.json
python3 tests/mock_wa_api.py --port "$PORT" --quiet \
    --data tests/fixtures-images.json \
    --short-pages --bulk-images "$BULK" &
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
images() {  # number of image files (not the list files)
    find "$BASE" -maxdepth 1 -type f ! -name 'all_images_*' ! -name 'images_first_*' 2>/dev/null | wc -l
}

echo "--- no amount given: it must do nothing -----------------------"
python3 backup-images.py --settings tests/settings-test.cfg >/dev/null 2>&1
check "exit code is an error" 2 "$?"
check "nothing saved" 0 "$(ls -d "$BASE" 2>/dev/null | wc -l)"
python3 backup-images.py --settings tests/settings-test.cfg --max 0 >/dev/null 2>&1
check "--max 0 is an error" 2 "$?"

echo "--- --max 2 ---------------------------------------------------"
run1=$(python3 backup-images.py --settings tests/settings-test.cfg --max 2)
echo "$run1" | tail -4
check "2 images saved" 2 "$(images)"
check "list of the limited run has its own name" 1 "$(count "$BASE" 'images_first_2_*.json')"
check "no list of all images yet" 0 "$(count "$BASE" 'all_images_*.json')"
check "list holds 2 entries" 2 "$(python3 -c "import json,glob;print(len(json.load(open(glob.glob('$BASE/images_first_2_*.json')[0]))))")"

echo "--- --max 55 (more than one page, short pages) ----------------"
python3 backup-images.py --settings tests/settings-test.cfg --max 55 >/dev/null
check "55 images in total" 55 "$(images)"

echo "--- --all -----------------------------------------------------"
run3=$(python3 backup-images.py --settings tests/settings-test.cfg --all)
check "all $TOTAL images saved, none lost" "$TOTAL" "$(images)"
check "list of all images saved" 1 "$(count "$BASE" 'all_images_*.json')"
check "same-title images kept apart" 2 "$(count "$BASE" 'Harbour at dusk_*.json')"
check "image without title is named by its id" 1 "$(count "$BASE" '4674531_*.json')"
check "image keeps its data (from the single read)" 1 "$(grep -l '"width": 1456' "$BASE"/Harbour*4674529* | wc -l)"

echo "--- --all again (nothing changed, so nothing may be written) ---"
run4=$(python3 backup-images.py --settings tests/settings-test.cfg --all)
check "files written" "Wrote 0 files" "$(echo "$run4" | grep -o 'Wrote 0 files')"

echo "---------------------------------------------------------------"
if [ "$fail" = 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit $fail
