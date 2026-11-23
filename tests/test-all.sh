#!/bin/bash
# Test for backup-all.py against the mock API. The fixtures of all the other tests are merged into one world,
# so the whole chain can run: world, articles, maps, manuscripts, notebooks, timelines, misc, images.
# Run it from anywhere:  ./tests/test-all.sh
set -u
cd "$(dirname "$0")/.."

OUT=tests/out
PORT=8099
BASE="$OUT/testworld"
FORBIDDEN=11111111-1111-1111-1111-111111111111   # a map whose layer list answers 403 (no fallback): one step must report it

rm -rf "$OUT"
mkdir -p "$OUT"
python3 - "$OUT/fixtures-all.json" <<'PY'
import json, sys
merged = {}
for name in ("articles", "maps", "manuscripts", "notebooks", "timelines", "misc", "images", "world"):
    part = json.load(open(f"tests/fixtures-{name}.json"))
    clash = set(merged) & set(part)
    assert not clash, f"fixtures-{name}.json uses keys of another fixture: {clash}"
    merged.update(part)
json.dump(merged, open(sys.argv[1], "w"))
PY
python3 tests/mock_wa_api.py --port "$PORT" --quiet --data "$OUT/fixtures-all.json" \
    --forbid "map/layers:$FORBIDDEN" &
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
summary_line() {   # summary_line <output> <step>: the line of one step in the summary
    echo "$1" | sed -n '/=== Summary/,$p' | grep -E "^  $2 " | head -1
}
ALL="python3 backup-all.py --settings tests/settings-test.cfg"

echo "--- run 1: all steps (the 403 makes the maps step incomplete) -"
run1=$($ALL 2>&1); code=$?
echo "$run1" | sed -n '/=== Summary/,$p'
check "exit code: all steps ran, one is incomplete" 3 "$code"
for step in world articles manuscripts notebooks timelines misc; do
    check "$step: OK" 1 "$(summary_line "$run1" $step | grep -c ' OK ')"
done
check "maps: INCOMPLETE" 1 "$(summary_line "$run1" maps | grep -c 'INCOMPLETE')"
check "maps: the number of failed calls is shown" 1 "$(summary_line "$run1" maps | grep -c '1 API calls failed')"
check "images: not part of a normal run" 0 "$(echo "$run1" | sed -n '/=== Summary/,$p' | grep -c '^  images')"
for folder in world articles maps manuscripts notebooks timelines histories canvases secrets variables blocks blocktemplates categories subscribergroups; do
    [ -d "$BASE/$folder" ] || { echo "  FAIL  folder $folder is missing"; fail=1; }
done
check "no images folder" 0 "$(ls -d "$BASE/images" 2>/dev/null | wc -l)"

echo "--- run 2: nothing changed, nothing may be written -----------"
run2=$($ALL 2>&1)
check "no step wrote a file" 0 "$(echo "$run2" | sed -n '/=== Summary/,$p' | grep -cE "Wrote [1-9][0-9]* files|Updated [1-9]")"
check "the steps with a result line say 0 files or up-to-date" 7 "$(echo "$run2" | sed -n '/=== Summary/,$p' | grep -cE "Wrote 0 files|already up-to-date")"

echo "--- --only and --skip -----------------------------------------"
run3=$($ALL --only world,articles 2>&1); code3=$?
check "--only: two steps" 2 "$(echo "$run3" | sed -n '/=== Summary/,$p' | grep -cE '^  (world|articles) ')"
check "--only: the others are not in the summary" 0 "$(echo "$run3" | sed -n '/=== Summary/,$p' | grep -cE '^  (maps|misc) ')"
check "--only: exit code 0" 0 "$code3"
run4=$($ALL --skip maps,misc,manuscripts,notebooks,timelines 2>&1)
check "--skip: world and articles are left" 2 "$(echo "$run4" | sed -n '/=== Summary/,$p' | grep -cE '^  (world|articles) ')"

echo "--- images need --images ---------------------------------------"
$ALL --only images >/dev/null 2>&1
check "--only images without --images is an error" 2 "$?"
$ALL --only nonsense >/dev/null 2>&1
check "an unknown step is an error" 2 "$?"
run5=$($ALL --only images --images 2 2>&1)
check "--images 2: two image files" 2 "$(find "$BASE/images" -maxdepth 1 -type f ! -name '*images_first_*' ! -name 'all_images_*' | wc -l)"
check "--images 2: the step is in the summary" 1 "$(summary_line "$run5" images | grep -c ' OK ')"
run6=$($ALL --only images --images all 2>&1)
check "--images all: all three images" 3 "$(find "$BASE/images" -maxdepth 1 -type f ! -name 'images_first_*' ! -name 'all_images_*' | wc -l)"

echo "--- a step that fails ------------------------------------------"
run7=$(python3 backup-all.py --settings tests/does-not-exist.cfg --only world,maps 2>&1); code=$?
check "exit code: failed" 1 "$code"
check "both steps FAILED" 2 "$(echo "$run7" | sed -n '/=== Summary/,$p' | grep -cE '^  (world|maps) +FAILED')"
check "the second step still ran after the first failed" 1 "$(echo "$run7" | grep -c '\[2/2\] maps')"

echo "---------------------------------------------------------------"
if [ "$fail" = 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit $fail
