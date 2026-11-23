#!/usr/bin/python3
version = 'Tillerz Full Notebook Backup'

# --- requirements ----------------------------------------------------
# see https://github.com/Tillerz/wa-tools

import argparse
import requests
from wa_common import (
    BackupRun,
    build_api_url,
    build_request_headers,
    chdir_to_script_dir,
    cookie_file_for,
    ensure_dir,
    entity_timestamp,
    fetch_all_pages,
    load_cfg_or_exit,
    load_cookies,
    rate_limiter_from_cfg,
    save_cookies,
    select_one_or_exit,
    sort_by_id,
    stable_basename,
    world_paths_from_cfg,
)

GRANULARITY = 2

# Notebooks belong to the user, not to the world. The documented list call,
# POST /world/notebooks, does not work (the WA spec says so, and the API answers 404).
# POST /user/notebooks is the call WA announced as its replacement. It is not in the
# spec yet, but it works (checked 2026-11-23). If WA changes it, this is the place.
LIST_PATH = "user/notebooks"


parser = argparse.ArgumentParser(description="Backup the notebooks of a world, with their sections and notes.")
parser.add_argument("--notebook", metavar="NOTEBOOK",
                    help="back up one notebook only, given as its uuid or (part of) its title. "
                         "It is saved even if it belongs to another world.")
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
paths = world_paths_from_cfg(cfg)
notebooks_folder = paths["notebooks"]

try:
    ensure_dir(notebooks_folder)
except OSError as error:
    print(f"Cannot create folder {notebooks_folder}: {error}")
    raise SystemExit(1)

# --- action starts here ---------------------------------------------------

with requests.Session() as session:
    load_cookies(session, file_cookies)

    run = BackupRun(session, api_url, request_headers, rate_limiter_from_cfg(cfg), GRANULARITY)

    # 1) list all notebooks of the user. The list call needs the user id.
    try:
        all_notebooks = fetch_all_pages(run.limiter, session, api_url, LIST_PATH,
                                        run.user_id(), request_headers, GRANULARITY)
    except requests.RequestException as e:
        print(f"Error fetching notebook list: {e}")
        raise SystemExit(1)

    if not all_notebooks:
        print("Error: No notebooks returned from API.")
        raise SystemExit(1)

    print(f"Found {len(all_notebooks)} notebooks of the user.")
    run.save(notebooks_folder, "all_notebooks", all_notebooks, run.run_stamp)

    # Name the notebooks before one is picked: a name depends on the other notebooks
    # (two can share a title), and it must not change when --notebook is used.
    used = {}
    names = {entry["id"]: stable_basename(entry, used)
             for entry in sort_by_id(all_notebooks) if entry.get("id")}

    if args.notebook:
        all_notebooks = select_one_or_exit(all_notebooks, args.notebook, "notebook")

    remaining = len(all_notebooks)
    for entry in sort_by_id(all_notebooks):
        notebook_id = entry.get("id")
        if not notebook_id:
            continue
        name = names[notebook_id]
        folder = notebooks_folder / name
        print(f"--- NOTEBOOK: {name} ({notebook_id})")

        # 2) notebook details. The list entry does not say which world the notebook is in.
        data = run.read(f"{name}: notebook details", "notebook", notebook_id)
        remaining -= 1
        if data is None:
            continue
        notebook_world = (data.get("world") or {}).get("id")
        if not args.notebook and notebook_world != world_id:
            print(f"    skipped: belongs to {'another world' if notebook_world else 'no world'}")
            continue
        run.save(folder, "notebook", data, entity_timestamp(data, run.run_stamp))

        # 3) sections, and the notes of each section
        sections = run.backup_children(name, "notebook/notesections", "notesection",
                                       notebook_id, folder, "notesections")
        for section_entry, section_base in sections:
            run.backup_children(name, "notesection/notes", "note",
                                section_entry["id"], folder / "notesections",
                                section_base + "_notes")
        print(f'------------------------ {remaining} notebooks left')

    run.print_summary("notebooks")

    save_cookies(session, file_cookies)
