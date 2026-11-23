#!/usr/bin/python3
version = 'Tillerz Full Timeline Backup'

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
    entity_basename,
    entity_timestamp,
    load_cfg_or_exit,
    load_cookies,
    rate_limiter_from_cfg,
    save_cookies,
    sort_by_id,
    stable_basename,
    world_paths,
)

GRANULARITY = 2

# Not backed up: chronicles (POST /world/chronicles). WA left them out of its API
# spec. The list works, but GET /chronicle only returns metadata, no content.


parser = argparse.ArgumentParser(description="Backup all timelines and histories (events) of a world.")
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
timelines_folder = paths["timelines"]
histories_folder = paths["histories"]

try:
    ensure_dir(timelines_folder)
    ensure_dir(histories_folder)
except OSError as error:
    print(f"Cannot create folders below {paths['root']}: {error}")
    raise SystemExit(1)

# --- action starts here ---------------------------------------------------

with requests.Session() as session:
    load_cookies(session, file_cookies)

    run = BackupRun(session, api_url, request_headers, rate_limiter_from_cfg(cfg), GRANULARITY)

    # 1) timelines. The list entries are thin, so every timeline is read on its own.
    timelines = run.listing("timeline list", "world/timelines", world_id)
    if timelines is not None:
        print(f"Found {len(timelines)} timelines.")
        run.save(timelines_folder, "all_timelines", timelines, run.run_stamp)
        names = {}
        for entry in sort_by_id(timelines):
            if not entry.get("id"):
                continue
            name = entity_basename(entry, names)  # the slug, unique and stable
            print(f"--- TIMELINE: {name} ({entry['id']})")
            data = run.read(f"timeline {name}", "timeline", entry["id"])
            if data is not None:
                run.save(timelines_folder / name, "timeline", data,
                         entity_timestamp(data, run.run_stamp))

    # 2) histories (the events). One list call is enough: at granularity 2 the list
    # entry holds everything that GET /history returns (checked 2026-11-23, 92 events,
    # only isEditable and success differ). That saves one call per event.
    histories = run.listing("history list", "world/histories", world_id)
    if histories is not None:
        print(f"Found {len(histories)} histories.")
        run.save(histories_folder, "all_histories", histories, run.run_stamp)
        used = {}
        for entry in sort_by_id(histories):
            if entry.get("id"):
                run.save(histories_folder, stable_basename(entry, used), entry,
                         entity_timestamp(entry, run.run_stamp))

    run.print_summary("timelines and histories")

    save_cookies(session, file_cookies)
