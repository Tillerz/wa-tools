#!/usr/bin/python3
version = 'Tillerz World Backup'

# --- requirements ----------------------------------------------------
# see https://github.com/Tillerz/worldanvil-templates/blob/master/tools/backup/

import argparse
import json
import requests
from wa_common import (
    BackupRun,
    build_api_url,
    build_request_headers,
    chdir_to_script_dir,
    cookie_file_for,
    ensure_dir,
    entity_timestamp,
    load_cfg_or_exit,
    load_cookies,
    rate_limiter_from_cfg,
    save_cookies,
    save_versioned,
    world_paths,
)

GRANULARITY = 2   # 1, 2 and 3 give the same 138 fields (checked 2026-11-23); 0 has no jsonMetadata

# Long texts of the world, also saved as files of their own, so they are easy to read and to
# diff: field name -> file extension. The whole world is saved as JSON anyway.
EXTRACT_FIELDS = {
    "descriptionParsed": ".html",
    "displayCss": ".css",
    "displayPanelCss": ".css",
    "jsonMetadata": ".json",   # a JSON text inside the JSON, saved pretty-printed
}


def comparison_ignores(world):
    """The fields of the world that change without the world being edited: its updateDate
    (the world's own copy changes whenever anything in it is edited) and the statistics
    (countFollowers, countComments, ...). Alone, they do not make a new version."""
    return ["updateDate"] + [key for key in world if key.startswith("count")]


def field_text(name, value):
    if not isinstance(value, str):
        return ""
    if name == "jsonMetadata":
        try:
            return json.dumps(json.loads(value), indent=2, ensure_ascii=False) + "\n"
        except ValueError:
            return value
    return value


parser = argparse.ArgumentParser(description="Backup the world itself: its settings, texts and CSS.")
parser.add_argument("--settings", default="settings.cfg", metavar="FILE",
                    help="settings file to use (default: settings.cfg)")
args = parser.parse_args()

# main
chdir_to_script_dir(__file__)

file_cookies = cookie_file_for(args.settings)
cfg = load_cfg_or_exit(args.settings)
world_name = cfg['world_name']
world_id = cfg['world_id']
request_headers = build_request_headers(cfg, version)
api_url = build_api_url(cfg)
paths = world_paths(world_name, cfg.get('root_folder'))
world_folder = paths["world"]
latest_folder = world_folder / "latest"

try:
    ensure_dir(latest_folder)
except OSError as error:
    print(f"Cannot create folder {latest_folder}: {error}")
    raise SystemExit(1)

# --- action starts here ---------------------------------------------------

with requests.Session() as session:
    load_cookies(session, file_cookies)

    run = BackupRun(session, api_url, request_headers, rate_limiter_from_cfg(cfg), GRANULARITY)

    world = run.read("world", "world", world_id)
    if world is None:
        print("Error: the world could not be read.")
        raise SystemExit(1)
    print(f"World: {world.get('title')} ({len(world)} fields)")

    # the whole world, as versioned JSON
    if save_versioned(world_folder, "world", world, entity_timestamp(world, run.run_stamp),
                      ignore=comparison_ignores(world)):
        run.written += 1

    # the long texts, as files of their own: always the latest state. The history of them
    # is in the versioned JSON.
    for name, extension in EXTRACT_FIELDS.items():
        target = latest_folder / (name + extension)
        text = field_text(name, world.get(name))
        if target.is_file():
            # compare bytes: read_text() would turn the Windows line endings (\r\n) of a CSS
            # into \n, and the file would look changed on every run
            if target.read_bytes() == text.encode("utf-8"):
                continue
        elif text == "":
            continue
        with open(target, "w", encoding="utf-8", newline="") as handle:   # newline="": keep \r\n as it is
            handle.write(text)
        run.written += 1
        print(f"    latest/{target.name}: {len(text)} characters")

    run.print_summary("world files")

    save_cookies(session, file_cookies)
