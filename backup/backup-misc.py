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
    safe_fetch,
    save_cookies,
    world_paths,
)

GRANULARITY = 2

# The types that follow one pattern: a list call, then one read call for every entry (the
# list entries are thin). name -> (list path, read path, what the list belongs to).
# The list belongs to the "world" (the world id is sent) or to the "user" (the user id is sent,
# read with GET /identity; the entries then are not tied to a world).
# To back up another type of that pattern, add a line here and a folder in world_paths().
SIMPLE_TYPES = {
    "canvases": ("world/canvases", "canvas", "world"),
    "secrets": ("world/secrets", "secret", "world"),
    "blocktemplates": ("user/blocktemplates", "blocktemplate", "user"),
    "categories": ("world/categories", "category", "world"),
    "subscribergroups": ("world/subscribergroups", "subscribergroup", "world"),
}
# The types with children: a list of parents for the world, one read per parent, then for
# every parent a list of its children and one read per child.
# name -> (parent list path, parent read path, child list path, child read path,
#          name of the parent list in the file names, name of the children in the file names)
# The spec writes the variable paths with an underscore (variable_collection). The real API has
# none: /variablecollection answers, /variable_collection answers 404 (checked 2026-11-23).
NESTED_TYPES = {
    "variables": ("world/variablecollections", "variablecollection",
                  "variablecollection/variables", "variable", "variablecollections", "variables"),
    "blocks": ("world/blockfolders", "blockfolder",
               "blockfolder/blocks", "block", "blockfolders", "blocks"),
}
ALL_TYPES = list(SIMPLE_TYPES) + list(NESTED_TYPES)


parser = argparse.ArgumentParser(description="Backup canvases, secrets, categories, subscriber groups, block templates, variable collections with their variables, and block folders with their blocks.")
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
            list_path, read_path, belongs_to = SIMPLE_TYPES[type_name]
            owner_id = world_id if belongs_to == "world" else safe_fetch("user id", None, run.user_id)
            if owner_id is None:
                continue
            # list in <type>/all_<type>_<date>.json, entries in <type>/<name>_<date>.json
            run.backup_children(type_name, list_path, read_path, owner_id, folder,
                                f"all_{type_name}", children_folder=folder)
            continue

        # the parents (variable collections, block folders), and the children of each parent
        parent_list, parent_read, child_list, child_read, parent_name, child_name = NESTED_TYPES[type_name]
        parents = run.backup_children(parent_name, parent_list, parent_read, world_id, folder,
                                      f"all_{parent_name}", children_folder=folder)
        for parent, base in parents:
            run.backup_children(parent_name, child_list, child_read, parent["id"], folder,
                                f"{base}_{child_name}")

    run.print_summary("types")

    save_cookies(session, file_cookies)
