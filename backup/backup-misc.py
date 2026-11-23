#!/usr/bin/python3
version = 'Tillerz Misc Backup'

# --- requirements ----------------------------------------------------
# see https://github.com/Tillerz/worldanvil-templates/blob/master/tools/backup/

import argparse
import requests
from wa_common import (
    BackupRun,
    build_api_url,
    build_request_headers,
    chdir_to_script_dir,
    cookie_file_for,
    ensure_dir,
    load_cfg_or_exit,
    load_cookies,
    rate_limiter_from_cfg,
    save_cookies,
    world_paths,
)

GRANULARITY = 2

# The types that follow one pattern: a list call for the world, then one read call for
# every entry (the list entries are thin). name -> (list path, read path).
# To back up another type of that pattern, add a line here and a folder in world_paths().
SIMPLE_TYPES = {
    "canvases": ("world/canvases", "canvas"),
    "secrets": ("world/secrets", "secret"),
}
# Variable collections have variables below them, so they have their own code.
# The spec writes the paths with an underscore (variable_collection). The real API has
# none: /variablecollection answers, /variable_collection answers 404 (checked 2026-11-23).
ALL_TYPES = list(SIMPLE_TYPES) + ["variables"]


parser = argparse.ArgumentParser(description="Backup canvases, secrets, and variable collections with their variables.")
parser.add_argument("--type", choices=ALL_TYPES, action="append", metavar="TYPE",
                    help=f"back up this type only; can be given several times (default: all of {', '.join(ALL_TYPES)})")
parser.add_argument("--settings", default="settings.cfg", metavar="FILE",
                    help="settings file to use (default: settings.cfg)")
args = parser.parse_args()
selected_types = args.type or ALL_TYPES

# main
chdir_to_script_dir(__file__)

file_cookies = cookie_file_for(args.settings)
cfg = load_cfg_or_exit(args.settings)
world_name = cfg['world_name']
world_id = cfg['world_id']
request_headers = build_request_headers(cfg, version)
api_url = build_api_url(cfg)
paths = world_paths(world_name, cfg.get('root_folder'))

try:
    for type_name in selected_types:
        ensure_dir(paths[type_name])
except OSError as error:
    print(f"Cannot create folders below {paths['root']}: {error}")
    raise SystemExit(1)

# --- action starts here ---------------------------------------------------

with requests.Session() as session:
    load_cookies(session, file_cookies)

    run = BackupRun(session, api_url, request_headers, rate_limiter_from_cfg(cfg), GRANULARITY)

    for type_name in selected_types:
        folder = paths[type_name]
        print(f"--- {type_name.upper()}")

        if type_name in SIMPLE_TYPES:
            list_path, read_path = SIMPLE_TYPES[type_name]
            # list in <type>/all_<type>_<date>.json, entries in <type>/<name>_<date>.json
            run.backup_children(type_name, list_path, read_path, world_id, folder,
                                f"all_{type_name}", children_folder=folder)
            continue

        # variable collections, and the variables of each collection
        collections = run.backup_children("variable collections", "world/variablecollections",
                                          "variablecollection", world_id, folder,
                                          "all_variablecollections", children_folder=folder)
        for collection, base in collections:
            run.backup_children("variable collections", "variablecollection/variables", "variable",
                                collection["id"], folder, base + "_variables")

    run.print_summary("types")

    save_cookies(session, file_cookies)
