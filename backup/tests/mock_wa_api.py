#!/usr/bin/python3
"""Fake World Anvil Boromir API, for testing the backup scripts offline.

It answers the map, article, manuscript, notebook, timeline, canvas, secret and
variable endpoints that the backup scripts use, reading its data from a JSON fixture file. It can also misbehave on purpose, so the tricky cases stay
testable:

  --short-pages   hand back one entry less than the requested limit, while more
                  pages still follow. The real API does this, and it made the
                  first version of backup-maps.py stop reading too early.
  --forbid        answer 403 for an endpoint, like the real API does for some maps
  --bulk-markers  add N generated markers to the first map, to force paging
  --bulk-articles add N generated articles, to force paging
  --bulk-histories add N generated histories, to force paging
  --bulk-images   add N generated images, to force paging

See README.md in this folder.
"""

import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

DEFAULT_LIMIT = 50

# List endpoints below a parent entity: path -> fixture key. The fixture holds a dict
# { "<parent uuid>": [entries] } under that key.
CHILD_LISTS = {
    "manuscript/manuscript_versions": "manuscript_versions",
    "manuscript/manuscript_labels": "manuscript_labels",
    "manuscript/manuscript_tags": "manuscript_tags",
    "manuscript_version/manuscript_parts": "version_parts",
    "manuscript_version/manuscript_stats": "version_stats",
    "manuscript_version/manuscript_plots": "version_plots",
    "manuscript_part/manuscript_beats": "part_beats",
    "notebook/notesections": "notebook_sections",
    "notesection/notes": "section_notes",
    "variablecollection/variables": "collection_variables",
    "blockfolder/blocks": "folder_blocks",
}
# List endpoints of the world, and the single reads of the same entities:
# path -> fixture key. The fixture holds a plain list under that key.
WORLD_LISTS = {
    "world/canvases": "canvases",
    "world/secrets": "secrets",
    "world/variablecollections": "variablecollections",
    "world/blockfolders": "blockfolders",
    "user/blocktemplates": "blocktemplates",
    "world/categories": "categories",
    "world/subscribergroups": "subscribergroups",
    "world/images": "images",
}
WORLD_READS = {
    "canvas": "canvases",
    "secret": "secrets",
    "variablecollection": "variablecollections",
    "blockfolder": "blockfolders",
    "blocktemplate": "blocktemplates",
    "category": "categories",
    "subscribergroup": "subscribergroups",
    "image": "images",
}
LIST_KEYS = ("maps", "articles", "manuscripts", "notebooks", "timelines", "histories",
             *WORLD_LISTS.values())
# Single reads: path -> fixture key to look the entity up in.
CHILD_READS = {
    "manuscript_version": "manuscript_versions",
    "manuscript_part": "version_parts",
    "manuscript_stat": "version_stats",
    "manuscript_label": "manuscript_labels",
    "manuscript_tag": "manuscript_tags",
    "manuscript_plot": "version_plots",
    "manuscript_beat": "part_beats",
    "notesection": "notebook_sections",
    "note": "section_notes",
    "variable": "collection_variables",
    "block": "folder_blocks",
}
USER_ID = "uuuuuuuu-0000-0000-0000-000000000001"


def load_fixture(path):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    for key in (*LIST_KEYS, "layers", "markergroups", "groupmarkers", "markers", *CHILD_LISTS.values()):
        data.setdefault(key, [] if key in LIST_KEYS else {})
    return data


def add_bulk_markers(data, count):
    if count <= 0 or not data["maps"]:
        return
    map_id = data["maps"][0]["id"]
    generated = [{"id": f"bulk-{n:04d}", "title": f"Bulk marker {n:04d}",
                  "updateDate": {"date": "2026-01-01 12:00:00.000000"}}
                 for n in range(count)]
    data["markers"].setdefault(map_id, []).extend(generated)


def add_bulk_articles(data, count):
    generated = [{"id": f"bulk-article-{n:04d}", "title": f"Bulk article {n:04d}",
                  "slug": f"bulk-article-{n:04d}", "wordcount": 100 + n,
                  "updateDate": {"date": "2026-01-01 12:00:00.000000"}}
                 for n in range(count)]
    data["articles"].extend(generated)


def add_bulk_histories(data, count):
    generated = [{"id": f"bulk-history-{n:04d}", "title": f"Bulk event {n:04d}", "slug": None,
                  "year": 1000 + n, "updateDate": {"date": "2026-01-01 12:00:00.000000"}}
                 for n in range(count)]
    data["histories"].extend(generated)


def add_bulk_images(data, count):
    generated = [{"id": 5000 + n, "title": f"Bulk image {n:04d}", "slug": None, "entityClass": "Image",
                  "updateDate": {"date": "2026-01-01 12:00:00.000000"}} for n in range(count)]
    data["images"].extend(generated)


def find_entity(groups_of_lists, entity_id):
    for entries in groups_of_lists:
        for entry in entries:
            if str(entry.get("id")) == entity_id:  # block and block folder ids are integers
                return entry
    return None


def make_handler(data, options):

    class Handler(BaseHTTPRequestHandler):

        def log_message(self, fmt, *fargs):
            if not options.quiet:
                print("  mock: " + fmt % fargs)

        def reply(self, payload, code=200):
            body = json.dumps(payload).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def parse(self):
            path, _, query = self.path.partition("?")
            path = path.split("boromir/", 1)[-1].strip("/")
            params = dict(part.split("=", 1) for part in query.split("&") if "=" in part)
            return path, params

        def forbidden(self, path, entity_id):
            for rule in options.forbid:
                rule_path, _, rule_id = rule.partition(":")
                if rule_path == path and (rule_id == "" or rule_id == entity_id):
                    return True
            return False

        def all_markers(self):
            return list(data["markers"].values()) + list(data["groupmarkers"].values())

        def do_GET(self):
            path, params = self.parse()
            entity_id = params.get("id", "")
            if self.forbidden(path, entity_id):
                return self.reply({"success": False, "error": "forbidden"}, 403)
            if path == "article":
                entity = find_entity([data["articles"]], entity_id)
            elif path == "identity":
                return self.reply({"id": USER_ID, "username": "tester", "success": True})
            elif path == "manuscript":
                entity = find_entity([data["manuscripts"]], entity_id)
            elif path == "notebook":
                entity = find_entity([data["notebooks"]], entity_id)
            elif path == "timeline":
                entity = find_entity([data["timelines"]], entity_id)
            elif path in WORLD_READS:
                entity = find_entity([data[WORLD_READS[path]]], entity_id)
            elif path in CHILD_READS:
                entity = find_entity(data[CHILD_READS[path]].values(), entity_id)
            elif path == "map":
                entity = find_entity([data["maps"]], entity_id)
            elif path == "markergroup":
                entity = find_entity(data["markergroups"].values(), entity_id)
            elif path == "marker":
                entity = find_entity(self.all_markers(), entity_id)
            else:
                return self.reply({"success": False, "error": "unknown endpoint"}, 404)
            if entity is None:
                return self.reply({"success": False, "error": "not found"}, 404)
            # the answer to a single read carries more than the list entry does
            granularity = int(params.get("granularity") or 2)
            return self.reply(dict(entity, success=True, granularity=granularity))

        def do_POST(self):
            path, params = self.parse()
            entity_id = params.get("id", "")
            if self.forbidden(path, entity_id):
                return self.reply({"success": False, "error": "forbidden"}, 403)
            length = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(length) or "{}")
            offset = body.get("offset", 0)
            limit = body.get("limit", DEFAULT_LIMIT)

            if path == "world/maps":
                entries = data["maps"]
            elif path == "world/articles":
                entries = data["articles"]
            elif path == "world/manuscripts":
                entries = data["manuscripts"]
            elif path == "user/notebooks":
                entries = data["notebooks"]
            elif path == "world/timelines":
                entries = data["timelines"]
            elif path == "world/histories":
                entries = data["histories"]
            elif path in WORLD_LISTS:
                entries = data[WORLD_LISTS[path]]
            elif path in CHILD_LISTS:
                entries = data[CHILD_LISTS[path]].get(entity_id, [])
            elif path == "map/layers":
                entries = data["layers"].get(entity_id, [])
            elif path == "map/markergroups":
                entries = data["markergroups"].get(entity_id, [])
            elif path == "markergroup/markers":
                entries = data["groupmarkers"].get(entity_id, [])
            elif path == "map/markers":
                entries = data["markers"].get(entity_id, [])
            else:
                return self.reply({"success": False, "error": "unknown endpoint"}, 404)

            page = entries[offset:offset + limit]
            if options.short_pages and len(page) > 1:
                page = page[:-1]
            return self.reply({"success": True, "entities": page})

    return Handler


parser = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("--port", type=int, default=8099, help="port to listen on (default: 8099)")
parser.add_argument("--data", default=str(Path(__file__).with_name("fixtures-maps.json")),
                    help="JSON fixture file (default: fixtures-maps.json next to this script)")
parser.add_argument("--short-pages", action="store_true",
                    help="hand back one entry less per page, while more pages still follow")
parser.add_argument("--forbid", action="append", default=[], metavar="ENDPOINT[:ID]",
                    help="answer 403 for this endpoint, e.g. 'map/markers' or 'map/markers:<uuid>'")
parser.add_argument("--bulk-markers", type=int, default=0, metavar="N",
                    help="add N generated markers to the first map, to force paging")
parser.add_argument("--bulk-articles", type=int, default=0, metavar="N",
                    help="add N generated articles, to force paging")
parser.add_argument("--bulk-histories", type=int, default=0, metavar="N",
                    help="add N generated histories, to force paging")
parser.add_argument("--bulk-images", type=int, default=0, metavar="N",
                    help="add N generated images, to force paging")
parser.add_argument("--quiet", action="store_true", help="do not log requests")
options = parser.parse_args()

fixture = load_fixture(options.data)
add_bulk_markers(fixture, options.bulk_markers)
add_bulk_articles(fixture, options.bulk_articles)
add_bulk_histories(fixture, options.bulk_histories)
add_bulk_images(fixture, options.bulk_images)
server = HTTPServer(("127.0.0.1", options.port), make_handler(fixture, options))
print(f"Mock WA API on http://127.0.0.1:{options.port} using {options.data}")
print(f"  maps: {len(fixture['maps'])}, articles: {len(fixture['articles'])}, "
      f"manuscripts: {len(fixture['manuscripts'])}, notebooks: {len(fixture['notebooks'])}, timelines: {len(fixture['timelines'])}, short-pages: {options.short_pages}, forbid: {options.forbid or 'none'}")
try:
    server.serve_forever()
except KeyboardInterrupt:
    print("\nMock WA API stopped.")
