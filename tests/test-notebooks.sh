#!/bin/bash
# Smoke test for backup-notebooks.py against the mock API.
# Run it from anywhere:  ./tests/test-notebooks.sh
set -u
cd "$(dirname "$0")/.."

OUT=tests/out
PORT=8099
N2_ID=nnnnnnnn-0000-0000-0000-000000000002
LOCKED=sssssss2-0000-0000-0000-000000000002
BASE="$OUT/testworld/notebooks"
NB1="$BASE/Notes_nnnnnnnn"      # the notebook of the test world

rm -rf "$OUT"
python3 tests/mock_wa_api.py --port "$PORT" --quiet \
    --data tests/fixtures-notebooks.json \
    --short-pages \
    --forbid "notesection/notes:$LOCKED" &
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
run1=$(python3 backup-notebooks.py --settings tests/settings-test.cfg)
echo "$run1"

echo "--- checks ----------------------------------------------------"
check "all 3 notebooks of the user found" 1 "$(echo "$run1" | grep -c 'Found 3 notebooks')"
check "user notebook list saved" 1 "$(count "$BASE" 'all_notebooks_*.json')"
check "notebook of the world saved" 1 "$(count "$NB1" 'notebook_*.json')"
check "notebook of another world skipped" 1 "$(echo "$run1" | grep -c 'skipped: belongs to another world')"
check "notebook without world skipped" 1 "$(echo "$run1" | grep -c 'skipped: belongs to no world')"
check "only one notebook folder" 1 "$(find "$BASE" -mindepth 1 -maxdepth 1 -type d | wc -l)"
check "section list saved" 1 "$(count "$NB1" 'notesections_*.json')"
check "2 sections saved" 2 "$(find "$NB1/notesections" -maxdepth 1 -type f ! -name '*_notes_*' | wc -l)"
# two notes share a title and the first 8 characters of the id, they must not share a file
check "same-title notes kept apart" 2 "$(count "$NB1/notesections/Lists_sssssss1_notes" 'Guild Names_*.json')"
check "note keeps its text" 1 "$(grep -l Silvertongue "$NB1"/notesections/Lists_sssssss1_notes/* | wc -l)"
# the 403 for the notes of one section
check "403 was reported" 1 "$(echo "$run1" | grep -c 'Locked_sssssss2_notes list failed')"
check "failed list not saved as empty" 0 "$(count "$NB1/notesections" 'Locked_sssssss2_notes_*.json')"
check "other section was saved" 1 "$(count "$NB1/notesections" 'Lists_sssssss1_notes_*.json')"

echo "--- run 2 (nothing changed, so nothing may be written) --------"
run2=$(python3 backup-notebooks.py --settings tests/settings-test.cfg)
check "files written on run 2" "Wrote 0 files" "$(echo "$run2" | grep -o 'Wrote 0 files')"

echo "--- run 3 (one notebook by uuid, even from another world) -----"
run3=$(python3 backup-notebooks.py --settings tests/settings-test.cfg --notebook "$N2_ID")
check "notebook picked" 1 "$(echo "$run3" | grep -c 'Backing up 1 notebook: Notes')"
check "not skipped" 0 "$(echo "$run3" | grep -c 'skipped')"
# the two notebooks share a title and the first 8 characters of the id: separate folders, always
check "other world notebook in its own folder" 1 "$(count "$BASE/Notes_$N2_ID" 'notebook_*.json')"
check "first notebook folder untouched" 1 "$(count "$NB1" 'notebook_*.json')"

echo "---------------------------------------------------------------"
if [ "$fail" = 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit $fail
