#!/usr/bin/python3
version = "Tillerz Article Find"

from argparse import ArgumentParser
from datetime import datetime
from pathlib import Path
from wa_common import (
    chdir_to_script_dir,
    load_cfg_or_exit,
    load_latest_json_by_slug,
    parse_tags,
    parse_wa_datetime,
    read_json,
    unique_preserve_order,
    world_paths,
)

writing_fields = (
    "title",
    "subheading",
    "snippet",
    "excerpt",
    "pronunciation",
    "content",
    "fullfooter",
    "sidepanelcontenttop",
    "sidepanelcontent",
    "sidebarcontentbottom",
    "sidebarcontent",
)


def matches_title(jdata, query, case_sensitive):
    title = jdata.get("title") or ""
    if not case_sensitive:
        return query.lower() in title.lower()
    return query in title


def matches_text(jdata, query, case_sensitive):
    for field in writing_fields:
        value = jdata.get(field)
        if not isinstance(value, str) or value == "":
            continue
        if not case_sensitive:
            if query.lower() in value.lower():
                return True
        else:
            if query in value:
                return True
    return False


def matches_slug(jdata, query, case_sensitive):
    slug = jdata.get("slug") or ""
    if not case_sensitive:
        return query.lower() in slug.lower()
    return query in slug


def matches_tags(jdata, required_tags):
    article_tags = set(parse_tags(jdata.get("tags")))
    return set(required_tags).issubset(article_tags)


def matches_type(jdata, entity_type, case_sensitive):
    entity_class = jdata.get("entityClass") or ""
    if not case_sensitive:
        return entity_type.lower() == entity_class.lower()
    return entity_type == entity_class


def matches_state(jdata, state, case_sensitive):
    article_state = jdata.get("state") or ""
    if not case_sensitive:
        return state.lower() == article_state.lower()
    return state == article_state


def load_all_articles(json_folder):
    results = []
    for path in sorted(Path(json_folder).glob("*.json")):
        try:
            data = read_json(path)
        except Exception as error:
            print(f"Warning: skipped invalid json {path.as_posix()}: {error}")
            continue
        slug = data.get("slug")
        if not isinstance(slug, str) or slug == "":
            continue
        update_obj = data.get("updateDate")
        update_raw = update_obj.get("date") if isinstance(update_obj, dict) else None
        update_date = parse_wa_datetime(update_raw)
        source_mtime = path.stat().st_mtime
        results.append((data, path, update_date, source_mtime))
    return results


# main
chdir_to_script_dir(__file__)

parser = ArgumentParser(description="Search World Anvil article JSON files.")
parser.add_argument("--title", help="find articles with this string in the title")
parser.add_argument("--slug", help="find articles with this string in the slug")
parser.add_argument("--text", help="find articles with this string in any writing field")
parser.add_argument("--tags", help="find articles that have all of these comma-separated tags")
parser.add_argument("--type", dest="entity_type", help="filter by entity class (e.g. person, location, myth)")
parser.add_argument("--state", help="filter by state (e.g. public, draft, wip)")
parser.add_argument("--all", action="store_true", help="search all versions of each article (default: latest version only)")
parser.add_argument("--case", action="store_true", help="case-sensitive search (default: case-insensitive)")
args = parser.parse_args()

if args.title is None and args.slug is None and args.text is None and args.tags is None and args.entity_type is None and args.state is None:
    parser.error("at least one of --title, --slug, --text, --tags, --type, or --state is required")

cfg = load_cfg_or_exit("settings.cfg")
world_name = cfg["world_name"]
paths = world_paths(world_name, cfg.get("root_folder"))
json_folder = paths["json"]

if not json_folder.is_dir():
    print(f"JSON folder not found: {json_folder.as_posix()}")
    raise SystemExit(1)

required_tags = []
if args.tags is not None:
    required_tags = unique_preserve_order(parse_tags(args.tags))
    if not required_tags:
        parser.error("--tags: tag list is empty")

if args.all:
    articles = load_all_articles(json_folder)
else:
    articles = list(load_latest_json_by_slug(json_folder).values())

results = []
for data, path, update_date, source_mtime in articles:
    if args.title is not None and not matches_title(data, args.title, args.case):
        continue
    if args.slug is not None and not matches_slug(data, args.slug, args.case):
        continue
    if args.text is not None and not matches_text(data, args.text, args.case):
        continue
    if required_tags and not matches_tags(data, required_tags):
        continue
    if args.entity_type is not None and not matches_type(data, args.entity_type, args.case):
        continue
    if args.state is not None and not matches_state(data, args.state, args.case):
        continue
    results.append((data, path, update_date, source_mtime))

results.sort(
    key=lambda item: (
        item[2] if item[2] is not None else datetime.min,
        item[3],
    ),
    reverse=True,
)

for _data, path, _update_date, _source_mtime in results:
    print(path.resolve().as_posix())
