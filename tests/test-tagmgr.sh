#!/bin/bash
# Test for tagmgr.py. It has no fake server: tagmgr only reads article JSON files and writes deploy payloads.
# tagmgr.py reads settings.cfg from its own folder, so the test runs a copy of it in a sandbox folder with its own
# settings.cfg. The backup folder (articles) and the work folder (deploy) are different folders.
# Run it from anywhere:  ./tests/test-tagmgr.sh
set -u
cd "$(dirname "$0")/.."

W=tests/out/tagmgr
rm -rf "$W"
mkdir -p "$W/backup/articles"
cp tagmgr.py wa_common.py "$W/"
cat > "$W/settings.cfg" <<CFG
world_name = testworld
world_id = 0
backup_folder = backup
work_folder = work
CFG
python3 - "$W" <<'PY'
import json, sys
def article(slug, entity_class, tags, number):
    json.dump({"id": f"0000000{number}-0000-0000-0000-000000000000", "slug": slug, "title": slug.upper(), "entityClass": entity_class,
               "tags": tags, "updateDate": {"date": "2026-01-01 00:00:00.000000"}},
              open(f"{sys.argv[1]}/backup/articles/{slug}_2026-01-01_000000.json", "w"))
article("slug-a", "Person", "x,y", 1)
article("slug-b", "Person", "", 2)
article("slug-c", "Document", "x", 3)
PY

fail=0
check() {   # check <what> <expected> <actual>
    if [ "$2" = "$3" ]; then
        echo "  PASS  $1 = $3"
    else
        echo "  FAIL  $1: expected $2, got $3"
        fail=1
    fi
}
tagmgr() { (cd "$W" && python3 tagmgr.py "$@" 2>&1); }
payload() { tr -d '\n ' < "$W/work/deploy/$1.json" 2>/dev/null; }   # the payload of an article, without spaces

echo "--- reading ---------------------------------------------------"
check "--stats: tagged articles" 1 "$(tagmgr --stats | grep -c 'articles with tags: 2')"
check "--stats: untagged articles" 1 "$(tagmgr --stats | grep -c 'articles with no tags: 1')"
check "--stats: usage of tag x" 1 "$(tagmgr --stats | grep -c '^x: 2')"
check "--stats --type Document" 1 "$(tagmgr --stats --type Document | grep -c '^x: 1')"
check "--tags: tags of one article" "x y" "$(tagmgr --tags slug-a | tr '\n' ' ' | sed 's/ *$//')"
check "--articles x: two articles" 1 "$(tagmgr --articles x | grep -c 'matches: 2')"

echo "--- writing: the payloads go to the work folder ----------------"
tagmgr --add z slug-b --dry-run >/dev/null
check "--dry-run writes nothing" 0 "$(ls "$W/work/deploy" 2>/dev/null | wc -l)"
tagmgr --add z slug-b >/dev/null
check "--add: payload of the article" '{"id":"00000002-0000-0000-0000-000000000000","tags":"z"}' "$(payload slug-b)"
tagmgr --replace x w --all >/dev/null
check "--replace --all: article with x and y" '{"id":"00000001-0000-0000-0000-000000000000","tags":"w,y"}' "$(payload slug-a)"
check "--replace --all: article with x only" '{"id":"00000003-0000-0000-0000-000000000000","tags":"w"}' "$(payload slug-c)"
check "--replace --all leaves an article without x as it was" '{"id":"00000002-0000-0000-0000-000000000000","tags":"z"}' "$(payload slug-b)"

echo "--- chained operations change the same payload ----------------"
tagmgr --add q slug-a >/dev/null
check "--add after --replace" '{"id":"00000001-0000-0000-0000-000000000000","tags":"w,y,q"}' "$(payload slug-a)"
tagmgr --remove y slug-a >/dev/null
check "--remove after --add" '{"id":"00000001-0000-0000-0000-000000000000","tags":"w,q"}' "$(payload slug-a)"
check "nothing written next to the script or into the backup folder" 0 "$(ls -d "$W/deploy" "$W/testworld" "$W/backup/deploy" 2>/dev/null | wc -l)"

echo "---------------------------------------------------------------"
if [ "$fail" = 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit $fail
