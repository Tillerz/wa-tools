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
      str(Path("wa_common.py").resolve().parent / "data" / "w" / "articles"), str(world_paths("w")["articles"]))
check("world_paths: with root_folder", "/some/where/w/maps", str(world_paths("w", "/some/where")["maps"]))

# backup folder and work folder
from wa_common import world_paths_from_cfg
split = world_paths("w", "/b", work_folder="/work/w.work")
check("work_folder: edit, deploy, text-export go to the work folder", ["/work/w.work/edit", "/work/w.work/deploy", "/work/w.work/text-export"],
      [str(split[k]) for k in ("edit", "deploy", "text-export")])
check("work_folder: the backups stay in the backup folder, also the articles", ["/b/w", "/b/w/articles", "/b/w/maps", "/b/w/world"],
      [str(split["root"]), str(split["articles"]), str(split["maps"]), str(split["world"])])
check("the articles are in the folder articles (not json)", "/b/w/articles", str(world_paths("w", "/b")["articles"]))
check("there is no json folder any more", False, "json" in world_paths("w", "/b"))
check("backup_folder is the exact folder, no world name added", ["/exact", "/exact/maps"],
      [str(world_paths("w", backup_folder="/exact")["root"]), str(world_paths("w", backup_folder="/exact")["maps"])])
check("backup_folder wins over root_folder", "/exact/maps", str(world_paths("w", "/b", backup_folder="/exact")["maps"]))
check("no work_folder: the work data is in the backup folder (as before)", "/b/w/edit", str(world_paths("w", "/b")["edit"]))
only_work = world_paths("w", work_folder="/work/w.work")
check("only work_folder: backups go below data/, work data to the work folder",
      [str(Path("wa_common.py").resolve().parent / "data" / "w" / "articles"), "/work/w.work/edit"], [str(only_work["articles"]), str(only_work["edit"])])
check("~ is expanded in both folders", [str(Path.home() / "x"), str(Path.home() / "y")],
      [str(world_paths("w", backup_folder="~/x")["root"]), str(world_paths("w", work_folder="~/y")["edit"].parent)])
cfg_paths = world_paths_from_cfg({"world_name": "w", "root_folder": "/b", "work_folder": "/work/w.work", "x_auth_token": "t"})
check("world_paths_from_cfg reads the settings", ["/b/w/maps", "/work/w.work/edit"], [str(cfg_paths["maps"]), str(cfg_paths["edit"])])
check("an empty setting counts as not set", "/b/w/edit", str(world_paths_from_cfg({"world_name": "w", "root_folder": "/b", "work_folder": "", "backup_folder": ""})["edit"]))

# the settings template must match what the code reads
from wa_common import load_cfg
template = load_cfg("settings-template.cfg")
check("template: has backup_folder and work_folder", [True, True], ["backup_folder" in template, "work_folder" in template])
check("template: has no root_folder (the older setting)", False, "root_folder" in template)
template_paths = world_paths_from_cfg(template)
check("template: its backup_folder is used, ~ expanded", str(Path.home() / "data" / "YOUR_WORLD_NAME_HERE" / "articles"), str(template_paths["articles"]))
check("template: an empty work_folder means the backup folder", str(Path.home() / "data" / "YOUR_WORLD_NAME_HERE" / "edit"), str(template_paths["edit"]))

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
