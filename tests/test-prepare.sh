#!/bin/bash
# Test for prepare.py. It has no fake server: prepare.py only reads and writes files.
# prepare.py reads settings.cfg from its own folder, so the test runs a copy of it in a
# sandbox folder with its own settings.cfg.
# Run it from anywhere:  ./tests/test-prepare.sh
set -u
cd "$(dirname "$0")/.."

SANDBOX=tests/out/prepare
rm -rf "$SANDBOX"
mkdir -p "$SANDBOX/data/testworld/edit/my-slug" "$SANDBOX/data/testworld/json"
cp prepare.py wa_common.py "$SANDBOX/"
cat > "$SANDBOX/settings.cfg" <<CFG
world_name = testworld
root_folder = data
CFG
# the downloaded article, and the edited text of it
cat > "$SANDBOX/data/testworld/json/my-slug_2026-01-01_000000.json" <<JSON
{"id": "11111111-2222-3333-4444-555555555555", "slug": "my-slug", "content": "old text", "title": "Same"}
JSON
printf 'my-slug_2026-01-01_000000.json' > "$SANDBOX/data/testworld/edit/my-slug/.jsonfile"
printf 'new text, a bit longer' > "$SANDBOX/data/testworld/edit/my-slug/content.txt"
printf 'Same' > "$SANDBOX/data/testworld/edit/my-slug/title.txt"

fail=0
check() {   # check <what> <expected> <actual>
    if [ "$2" = "$3" ]; then
        echo "  PASS  $1 = $3"
    else
        echo "  FAIL  $1: expected $2, got $3"
        fail=1
    fi
}

echo "--- root_folder is set: prepare must use it --------------------"
out=$(cd "$SANDBOX" && python3 prepare.py my-slug 2>&1)
echo "$out" | tail -4
PAYLOAD="$SANDBOX/data/testworld/deploy/my-slug.json"
check "payload written below root_folder" 1 "$(ls "$PAYLOAD" 2>/dev/null | wc -l)"
check "payload has the article id" 1 "$(grep -c '11111111-2222-3333-4444-555555555555' "$PAYLOAD" 2>/dev/null)"
check "payload has the changed field" 1 "$(grep -c 'new text, a bit longer' "$PAYLOAD" 2>/dev/null)"
check "payload has no unchanged field" 0 "$(grep -c '"title"' "$PAYLOAD" 2>/dev/null)"
check "no stray world folder next to the script" 0 "$(ls -d "$SANDBOX/testworld" 2>/dev/null | wc -l)"

echo "---------------------------------------------------------------"
if [ "$fail" = 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit $fail
