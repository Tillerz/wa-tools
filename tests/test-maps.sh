#!/bin/bash
# Smoke test for backup-maps.py against the mock API.
# Run it from anywhere:  ./tests/test-maps.sh
set -u
cd "$(dirname "$0")/.."

OUT=tests/out
PORT=8099
FORBIDDEN=22222222-2222-2222-2222-222222222222      # marker list denied, but the map read has the markers
NO_FALLBACK=33333333-3333-3333-3333-333333333333    # marker list denied, and the map read failed too: a warning

rm -rf "$OUT"
python3 tests/mock_wa_api.py --port "$PORT" --quiet \
    --short-pages --bulk-markers 130 \
    --forbid "map/markers:$FORBIDDEN" --forbid "map/markers:$NO_FALLBACK" --forbid "map:$NO_FALLBACK" &
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

echo "--- run 1 -----------------------------------------------------"
run1=$(python3 backup-maps.py --settings tests/settings-test.cfg)
echo "$run1"

echo "--- checks ----------------------------------------------------"
# 130 bulk + 2 listed markers in the map list, plus 2 more that only a group knows
markers=$(ls "$OUT"/testworld/maps/Harbour\ Town/markers/ 2>/dev/null | wc -l)
check "markers saved for Harbour Town" 134 "$markers"
check "all 3 maps found" 1 "$(echo "$run1" | grep -c 'Found 3 maps')"
check "both layers found" 1 "$(echo "$run1" | grep -c 'layers: 2')"
check "403 on the marker list: the markers of the map read are used" 1 "$(echo "$run1" | grep -c 'marker list denied (403), using the 2 markers')"
check "403 with a fallback is not a failed call" 0 "$(echo "$run1" | grep -c 'Secret Vault: marker list failed')"
check "403 without a fallback is reported" 1 "$(echo "$run1" | grep -c 'Empty Island: marker list failed')"
check "only those two calls failed" 1 "$(echo "$run1" | grep -c '^2 API calls failed')"
check "run continued after the 403" 1 "$(echo "$run1" | grep -c -- '--- MAP: Empty Island')"
# the group marker of the forbidden map is still saved
check "markers of the map with the denied list: both saved" 2 "$(ls "$OUT"/testworld/maps/Secret\ Vault/markers/ 2>/dev/null | wc -l)"
check "a marker that only the map read knows is saved" 1 "$(ls "$OUT"/testworld/maps/Secret\ Vault/markers/ 2>/dev/null | grep -c 'The Hidden Door')"

echo "--- run 2 (nothing changed, so nothing may be written) --------"
run2=$(python3 backup-maps.py --settings tests/settings-test.cfg)
check "files written on run 2" "Wrote 0 files" "$(echo "$run2" | grep -o 'Wrote 0 files')"

echo "--- run 3 (single map by title) -------------------------------"
run3=$(python3 backup-maps.py --settings tests/settings-test.cfg --map "Empty Island" --no-marker-details)
check "single map picked" 1 "$(echo "$run3" | grep -c 'Backing up 1 map: Empty Island')"
check "other maps skipped" 0 "$(echo "$run3" | grep -c 'MAP: Harbour Town')"

echo "--- run 4 (single map by uuid) --------------------------------"
run4=$(python3 backup-maps.py --settings tests/settings-test.cfg \
       --map 33333333-3333-3333-3333-333333333333 --no-marker-details)
check "uuid picked the map" 1 "$(echo "$run4" | grep -c 'Backing up 1 map: Empty Island')"

echo "---------------------------------------------------------------"
if [ "$fail" = 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit $fail
