#!/bin/bash
# Test for prepare.py. It has no fake server: prepare.py only reads and writes files.
# prepare.py reads settings.cfg from its own folder, so the test runs a copy of it in a
# sandbox folder with its own settings.cfg.
# Run it from anywhere:  ./tests/test-prepare.sh
set -u
cd "$(dirname "$0")/.."

SANDBOX=tests/out/prepare
rm -rf "$SANDBOX"
mkdir -p "$SANDBOX/data/testworld/edit/my-slug" "$SANDBOX/data/testworld/articles"
cp prepare.py wa_common.py "$SANDBOX/"
cat > "$SANDBOX/settings.cfg" <<CFG
world_name = testworld
root_folder = data
CFG
# the downloaded article, and the edited text of it
cat > "$SANDBOX/data/testworld/articles/my-slug_2026-01-01_000000.json" <<JSON
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

echo "--- backup_folder and work_folder: the articles are read from the backup folder, the work data goes to the work folder ---"
W=tests/out/work-flow
rm -rf "$W"
mkdir -p "$W/backup/articles"
cp extract.py prepare.py wa_common.py "$W/"
cat > "$W/settings.cfg" <<CFG
world_name = testworld
world_id = 0
x_auth_token = t
x_application_key = k
backup_folder = backup
work_folder = work
CFG
python3 - "$W" <<'PY'
import json, sys
json.dump({"id": "11111111-2222-3333-4444-555555555555", "slug": "my-slug", "entityClass": "Person", "state": "public",
           "title": "Same", "wordcount": 80, "content": "old text " * 40, "updateDate": {"date": "2026-01-01 00:00:00.000000"}},
          open(sys.argv[1] + "/backup/articles/my-slug_2026-01-01_000000.json", "w"))
PY
(cd "$W" && python3 extract.py my-slug_2026-01-01_000000.json >/dev/null 2>&1)
(cd "$W" && python3 extract.py my-slug_2026-01-01_000000.json --export >/dev/null 2>&1)
check "extract: edit files in the work folder" 1 "$(ls "$W/work/edit/my-slug/content.txt" 2>/dev/null | wc -l)"
check "extract: text export in the work folder" 1 "$(ls "$W/work/text-export/Person/my-slug.txt" 2>/dev/null | wc -l)"
printf 'new text' > "$W/work/edit/my-slug/content.txt"
(cd "$W" && python3 prepare.py my-slug >/dev/null 2>&1)
check "prepare: payload in the work folder" 1 "$(ls "$W/work/deploy/my-slug.json" 2>/dev/null | wc -l)"
check "the backup folder has only the articles, no work data" "articles" "$(ls "$W/backup" 2>/dev/null | tr '\n' ' ' | sed 's/ *$//')"
check "no stray folder next to the scripts" 0 "$(ls -d "$W/testworld" "$W/data" 2>/dev/null | wc -l)"

echo "---------------------------------------------------------------"
if [ "$fail" = 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit $fail
