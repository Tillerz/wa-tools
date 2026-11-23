#!/bin/bash
# Smoke test for backup-articles.py against the mock API.
# Run it from anywhere:  ./tests/test-articles.sh
set -u
cd "$(dirname "$0")/.."

OUT=tests/out
PORT=8099
BULK=60          # more than one page, so the paging really runs
TOTAL=$((BULK + 3))

rm -rf "$OUT"
python3 tests/mock_wa_api.py --port "$PORT" --quiet \
    --data tests/fixtures-articles.json \
    --short-pages --bulk-articles "$BULK" &
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
run1=$(python3 "${ARTICLE_SCRIPT:-backup-articles.py}" --settings tests/settings-test.cfg)
echo "$run1" | tail -5

echo "--- checks ----------------------------------------------------"
# the mock hands back one entry less per page; none may be lost
check "articles saved" "$TOTAL" "$(ls "$OUT"/testworld/articles/ 2>/dev/null | wc -l)"
check "list file saved" 1 "$(ls "$OUT"/testworld/all_articles.json 2>/dev/null | wc -l)"
check "article from fixture saved" 1 "$(ls "$OUT"/testworld/articles/harbour-master_* 2>/dev/null | wc -l)"

echo "--- run 2 (nothing changed, so nothing may be written) --------"
run2=$(python3 "${ARTICLE_SCRIPT:-backup-articles.py}" --settings tests/settings-test.cfg)
check "nothing updated on run 2" 1 "$(echo "$run2" | grep -c "$TOTAL articles were already up-to-date")"
check "still $TOTAL files" "$TOTAL" "$(ls "$OUT"/testworld/articles/ 2>/dev/null | wc -l)"

echo "--- run 3 (with a work_folder: the articles stay in the backup folder) ---"
rm -rf "$OUT/testworld" "$OUT/testworld.work"
python3 backup-articles.py --settings tests/settings-test-work.cfg >/dev/null
check "articles are in the backup folder" "$TOTAL" "$(ls "$OUT"/testworld/articles/ 2>/dev/null | wc -l)"
check "list of articles in the backup folder" 1 "$(ls "$OUT"/testworld/all_articles.json 2>/dev/null | wc -l)"
check "nothing in the work folder" 0 "$(ls "$OUT"/testworld.work 2>/dev/null | wc -l)"
run4=$(python3 backup-articles.py --settings tests/settings-test-work.cfg)
check "second run: nothing to update" 1 "$(echo "$run4" | grep -c "$TOTAL articles were already up-to-date")"

echo "---------------------------------------------------------------"
if [ "$fail" = 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit $fail
