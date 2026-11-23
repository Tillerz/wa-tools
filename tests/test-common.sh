#!/bin/bash
# Tests for the shared code in wa_common.py that needs no fake server.
# Run it from anywhere:  ./tests/test-common.sh
set -u
cd "$(dirname "$0")/.."

OUT=tests/out/common
rm -rf "$OUT"
mkdir -p "$OUT"

python3 - "$OUT" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, ".")
from wa_common import save_versioned, without_volatile

folder = Path(sys.argv[1])
failed = False


def check(what, expected, actual):
    global failed
    if expected == actual:
        print(f"  PASS  {what} = {actual}")
    else:
        print(f"  FAIL  {what}: expected {expected}, got {actual}")
        failed = True


entity = {"id": "a", "title": "x", "updateDate": {"date": "2026-01-01"},
          "world": {"id": "w", "updateDate": {"date": "2026-11-23 13:03:51"}}}
check("first save writes", True, save_versioned(folder, "x", entity, "2026-11-23_130351"))
# only the world's updateDate moved: not a change of the entity
moved = {**entity, "world": {"id": "w", "updateDate": {"date": "2026-11-23 13:09:35"}}}
check("world updateDate alone writes nothing", False, save_versioned(folder, "x", moved, "2026-11-23_130935"))
check("one file only", 1, len(list(folder.glob("x_*.json"))))
# the entity's own updateDate is not volatile
edited = {**entity, "updateDate": {"date": "2026-12-01"}}
check("own updateDate change writes", True, save_versioned(folder, "x", edited, "2026-12-01_000000"))
# a real change next to the world change
changed = {**moved, "title": "y"}
check("title change writes", True, save_versioned(folder, "x", changed, "2026-12-02_000000"))
# the file keeps the full data, also the volatile field
check("file keeps world updateDate", "2026-11-23 13:09:35",
      __import__("json").loads(sorted(folder.glob("x_*.json"))[-1].read_text())["world"]["updateDate"]["date"])
# updateDate of other objects stays
check("other nested updateDate stays", {"a": {"updateDate": 1}},
      without_volatile({"a": {"updateDate": 1}}))
check("lists are walked", [{"world": {"id": "w"}}],
      without_volatile([{"world": {"id": "w", "updateDate": 5}}]))

# the content changed, the date did not: the older version must not be overwritten
same_date = {"id": "s", "title": "one", "updateDate": {"date": "2026-05-01"}}
save_versioned(folder, "s", same_date, "2026-05-01_000000")
check("same date, new content writes", True, save_versioned(folder, "s", {**same_date, "title": "two"}, "2026-05-01_000000"))
check("same date: two files, the old one is kept", 2, len(list(folder.glob("s_*.json"))))
check("same date: the old file still has the old content", "one",
      __import__("json").loads((folder / "s_2026-05-01_000000.json").read_text())["title"])

# <ignore>: top-level fields that do not count as a change, but stay in the file
world = {"id": "w", "title": "x", "updateDate": "d1", "countFollowers": 1}
check("ignore: first save writes", True, save_versioned(folder, "w", world, "2026-01-01_000000", ignore=["updateDate", "countFollowers"]))
check("ignore: only ignored fields changed, no write", False,
      save_versioned(folder, "w", {**world, "updateDate": "d2", "countFollowers": 99}, "2026-01-02_000000", ignore=["updateDate", "countFollowers"]))
check("ignore: a real change writes", True,
      save_versioned(folder, "w", {**world, "updateDate": "d3", "title": "y"}, "2026-01-03_000000", ignore=["updateDate", "countFollowers"]))
check("ignore: without the option the same change writes", True,
      save_versioned(folder, "w", {**world, "updateDate": "d4", "title": "y"}, "2026-01-04_000000"))

# where the data of a world goes
from wa_common import world_paths
check("world_paths: without root_folder below data/ next to the scripts",
      str(Path("wa_common.py").resolve().parent / "data" / "w" / "json"), str(world_paths("w")["json"]))
check("world_paths: with root_folder", "/some/where/w/maps", str(world_paths("w", "/some/where")["maps"]))

# block and block folder ids are integers, not uuids
from wa_common import entity_basename, select_entities, sort_by_id, stable_basename
check("integer id: stable name", "Wildshape_1285074", stable_basename({"id": 1285074, "title": "Wildshape"}, {}))
check("integer id: entity_basename", "Wildshape", entity_basename({"id": 1285074, "title": "Wildshape"}, {}))
check("integer id: sort order does not depend on the input order", sort_by_id([{"id": 2}, {"id": 10}]),
      sort_by_id([{"id": 10}, {"id": 2}]))
check("integer id: select by id", [{"id": 22629, "title": "Characters"}],
      select_entities([{"id": 22629, "title": "Characters"}, {"id": 22630, "title": "Items"}], "22629"))
sys.exit(1 if failed else 0)
PY
status=$?
echo "---------------------------------------------------------------"
if [ "$status" = 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit $status
