#!/bin/bash
# Smoke test for backup-world.py against the mock API.
# Run it from anywhere:  ./tests/test-world.sh
set -u
cd "$(dirname "$0")/.."

OUT=tests/out
PORT=8099
BASE="$OUT/testworld/world"

rm -rf "$OUT" cookies-settings-test.json
python3 tests/mock_wa_api.py --port "$PORT" --quiet --data tests/fixtures-world.json &
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
run1=$(python3 backup-world.py --settings tests/settings-test.cfg)
echo "$run1"

echo "--- checks ----------------------------------------------------"
check "world JSON saved, dated by updateDate" 1 "$(count "$BASE" 'world_2026-11-23_132104.json')"
check "world JSON has the long texts too" 1 "$(grep -c 'color: #123456' "$BASE"/world_*.json | head -1)"
check "displayCss file" "$(printf 'body { color: #123456; }\n.panel { margin: 0; }\n')" "$(cat "$BASE/latest/displayCss.css")"
# this CSS has Windows line endings (\r\n); they must stay, and must not make the file look changed on every run
printf '.side { width: 10px; }\r\n.x { top: 0; }\r\n' > "$OUT/expected-panel.css"
check "displayPanelCss file keeps its line endings" 0 "$(cmp "$BASE/latest/displayPanelCss.css" "$OUT/expected-panel.css" >/dev/null 2>&1; echo $?)"
check "descriptionParsed file" "<p>A <b>test</b> world.</p>" "$(cat "$BASE/latest/descriptionParsed.html")"
check "jsonMetadata file is pretty-printed JSON" 1 "$(grep -c '^  "isGalleriesMigrated": true' "$BASE/latest/jsonMetadata.json")"
check "empty field (displayJs) gets no file" 0 "$(count "$BASE/latest" 'displayJs*')"

echo "--- run 2 (nothing changed, so nothing may be written) --------"
run2=$(python3 backup-world.py --settings tests/settings-test.cfg)
check "files written on run 2" "Wrote 0 files" "$(echo "$run2" | grep -o 'Wrote 0 files')"

echo "--- run 3 (a latest/ file was changed by hand: it is restored) --"
echo "x" > "$BASE/latest/displayPanelCss.css"
run3=$(python3 backup-world.py --settings tests/settings-test.cfg)
check "file restored" 0 "$(cmp "$BASE/latest/displayPanelCss.css" "$OUT/expected-panel.css" >/dev/null 2>&1; echo $?)"
check "only that file was written" "Wrote 1 files" "$(echo "$run3" | grep -o 'Wrote 1 files')"

echo "---------------------------------------------------------------"
if [ "$fail" = 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit $fail
