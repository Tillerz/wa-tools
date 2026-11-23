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
check("the updateDate of any nested object does not count", {"a": {}},
      without_volatile({"a": {"updateDate": 1}}))
check("the entity's own updateDate counts", {"updateDate": 1, "a": {}},
      without_volatile({"updateDate": 1, "a": {"updateDate": 2}}))
check("in a list file every entry is an entity: its own updateDate counts, a nested one does not", [{"updateDate": 1, "map": {}}],
      without_volatile([{"updateDate": 1, "map": {"updateDate": 2}}]))
check("nested lists: the entries are nested objects", {"parts": [{"id": "p"}]},
      without_volatile({"parts": [{"id": "p", "updateDate": 3}]}))
check("lists are walked", [{"world": {"id": "w"}}],
      without_volatile([{"world": {"id": "w", "updateDate": 5}}]))

# the copy of the map inside a marker: the map's updateDate changes when anything on the map is edited
marker = {"id": "m", "title": "Inn", "geoX": 10, "updateDate": None, "map": {"id": "map1", "title": "Town", "updateDate": {"date": "2026-01-01"}}}
check("marker: first save writes", True, save_versioned(folder, "marker", marker, "2026-06-01_000000"))
check("marker: only the map copy's updateDate changed, no write", False,
      save_versioned(folder, "marker", {**marker, "map": {**marker["map"], "updateDate": {"date": "2026-02-02"}}}, "2026-06-02_000000"))
check("marker: a real change (x) writes", True, save_versioned(folder, "marker", {**marker, "geoX": 11}, "2026-06-03_000000"))
check("marker: a real change in the nested group title writes", True,
      save_versioned(folder, "marker", {**marker, "geoX": 11, "group": {"id": "g", "title": "Streets"}}, "2026-06-04_000000"))

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

# file names made from the name of an entity
from wa_common import sanitize_filename_component as sanitize
check("a slash does not cut the name (it was: everything before the last / was lost)",
      'bow (-baʊ-) - front part of the ship', sanitize('bow ("/baʊ/") - front part of the ship'))
check("a slash with spaces", "Action - Feat", sanitize("Action / Feat"))
check("a slash without spaces", "NPC-Monster", sanitize("NPC/Monster"))
check("a backslash", "a-b-c", sanitize("a\\b\\c"))
check("a path to the parent folder stays harmless (no leading dots, no slash)", "etc-passwd", sanitize("../etc/passwd"))
check("a name with leading dots would be a hidden file: the dots are removed", "hidden", sanitize(".hidden"))
check("leading dots and a title that is a sentence", "and so on", sanitize("...and so on"))
check("a leading dash would look like an option to a command: it is removed", "rf", sanitize("-rf"))
check("dots, dashes and spaces inside a name stay", "Mr. Smith - v1.2", sanitize("Mr. Smith - v1.2"))
check("no path separator is left", False, any(c in sanitize("a/b\\c//d") for c in "/\\"))
check("characters that Windows does not allow are removed, as before", "What Now yes no", sanitize("What? *Now*: <yes> |no|"))
check("a colon is removed, as before", "Appendix Calendar", sanitize("Appendix: Calendar"))
check("control characters are removed", "abc", sanitize("a\x01b\tc"))
check("spaces at the start and the end are removed", "padded", sanitize("  padded  "))
check("a normal name stays as it is", "Great Library (2nd edition) - östlich", sanitize("Great Library (2nd edition) - östlich"))
check("empty stays empty", "", sanitize(""))
check("a long name is cut to at most 150 bytes, not in the middle of a character", "ä" * 75, sanitize("ä" * 100))
check("a long ASCII name", "x" * 150, sanitize("x" * 300))
check("the cut leaves no space at the end", "word", sanitize("word" + " " * 200 + "tail")[:4] + "")
check("a name of 124 bytes (the longest in the real data) is not cut", "y" * 124, sanitize("y" * 124))

# security: nothing from the API may decide where a file is written
from wa_common import entity_basename, entity_timestamp, stable_basename
check(".. as a name is not usable (it would be the parent folder)", "", sanitize(".."))
check(". as a name is not usable", "", sanitize("."))
check(".. with spaces is not usable", "", sanitize("  ..  "))
check("a name of only dots and dashes is no name", "", sanitize(" .-. - "))
# the characters that were asked about: " ' / \ ? %
check("the characters \" ' / \\ ? % together", "say hi it's 100% ok yes-no-maybe", sanitize('say "hi" it\'s 100% ok? yes/no\\maybe'))
check("an apostrophe stays (valid everywhere, 128 names have one)", "Land's End", sanitize("Land's End"))
check("a percent sign stays", "100% done", sanitize("100% done"))
check("percent-encoded dots and slashes are only text, they are never decoded", "%2e%2e%2fetc", sanitize("%2e%2e%2fetc"))
check("brackets and an ampersand stay", "Kingdoms & Warfare [small]", sanitize("Kingdoms & Warfare [small]"))
# invisible characters, and characters that break the encoder
check("a right-to-left override (it fakes a file ending) is removed", "evilgpj.exe", sanitize("evil\u202egpj.exe"))
check("a zero width space is removed", "ab", sanitize("a\u200bb"))
check("a lone surrogate is removed (it would break .encode)", "x", sanitize("\ud800x"))
check("the result can always be encoded", True, bool(sanitize("\ud800\udfffz\u0085y").encode("utf-8")))
check("the first 150 bytes are cut after the invisible characters are gone", "ä" * 75, sanitize("\u200b" + "ä" * 100))
# Windows: no trailing dots or spaces, no device names (a name can be the name of a folder)
check("a trailing dot is removed (Windows would drop it)", "Mr", sanitize("Mr. "))
check("trailing dots are removed", "name", sanitize("name..."))
check("a device name of Windows gets an underscore", "CON_", sanitize("CON"))
check("a device name in lower case", "nul_", sanitize("nul"))
check("a device name with a number", "LPT9_", sanitize("LPT9"))
check("a name that only starts like a device name", "Console", sanitize("Console"))
check("a name that is only .. falls back to the id", "00000000-aaaa", entity_basename({"id": "00000000-aaaa", "title": ".."}, {}))
check("stable name for a title ..: the name is the start of the id", "00000000", stable_basename({"id": "00000000-aaaa", "title": ".."}, {}))
hostile = stable_basename({"id": "../../x/1234567", "title": "../../etc/passwd"}, {})
check("hostile title and id: no separator in the stable name", False, "/" in hostile or "\\" in hostile or hostile in ("", ".", ".."))
hostile = entity_basename({"id": "../../x/1234567", "title": "x"}, {"x": "other-id"})
check("hostile id in the collision suffix: no separator", False, "/" in hostile or "\\" in hostile)
check("a good update date becomes a stamp", "2026-01-10_081500", entity_timestamp({"updateDate": {"date": "2026-01-10 08:15:00.000000"}}, "FALLBACK"))
check("an update date with a path is not used", "FALLBACK", entity_timestamp({"updateDate": {"date": "../../../etc/x"}}, "FALLBACK"))
check("an update date in another format is not used", "FALLBACK", entity_timestamp({"updateDate": {"date": "2026-01-10 08:15:00.123456"}}, "FALLBACK"))
check("no update date: the fallback", "FALLBACK", entity_timestamp({"updateDate": None}, "FALLBACK"))

# save_versioned must write directly into its folder, whatever the name says
import wa_common
import shutil
outside = folder.parent / "outside-target"      # next to the folder of the test: where a hostile name would write to
shutil.rmtree(outside, ignore_errors=True)
outside.mkdir()
before = len(wa_common.warnings)
for hostile_base, hostile_stamp in (("../outside-target/escaped", "2026-01-01_000000"), ("ok", "../outside-target/x"), ("a/../../outside-target/b", "2026-01-01_000000"), ("..\\outside-target\\c", "2026-01-01_000000")):
    saved = save_versioned(folder, hostile_base, {"id": 1}, hostile_stamp)
    check(f"hostile name {hostile_base!r} / {hostile_stamp!r} is not saved", False, saved)
check("nothing was written outside the folder", 0, len(list(outside.iterdir())))
check("each refusal is a warning", 4, len(wa_common.warnings) - before)
wa_common.warnings[before:] = []
check("a normal name is still saved", True, save_versioned(folder, "fine", {"id": 1}, "2026-01-01_000000"))

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
