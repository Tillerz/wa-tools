#!/usr/bin/python3
version = 'Tillerz Full Manuscript Backup'

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
    fetch_all_pages,
    load_cfg_or_exit,
    load_cookies,
    rate_limiter_from_cfg,
    save_cookies,
    select_one_or_exit,
    sort_by_id,
    world_paths_from_cfg,
)

GRANULARITY = 2

# Not backed up: manuscript bookmarks (POST /manuscript/manuscript_bookmarks).
# World Anvil answers 422 for them, because of a broken database query on their
# side. Checked 2026-11-23. Add them like the labels when WA has fixed it.


parser = argparse.ArgumentParser(description="Backup all manuscripts of a world, with versions, parts, beats, stats, plots, labels and tags.")
parser.add_argument("--manuscript", metavar="MANUSCRIPT",
                    help="back up one manuscript only, given as its uuid, its slug or (part of) its title")
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
manuscripts_folder = paths["manuscripts"]

try:
    ensure_dir(manuscripts_folder)
except OSError as error:
    print(f"Cannot create folder {manuscripts_folder}: {error}")
    raise SystemExit(1)

# --- action starts here ---------------------------------------------------

with requests.Session() as session:
    load_cookies(session, file_cookies)

    run = BackupRun(session, api_url, request_headers, rate_limiter_from_cfg(cfg), GRANULARITY)

    # 1) list all manuscripts of the world
    try:
        all_manuscripts = fetch_all_pages(run.limiter, session, api_url, "world/manuscripts",
                                          world_id, request_headers, GRANULARITY)
    except requests.RequestException as e:
        print(f"Error fetching manuscript list: {e}")
        raise SystemExit(1)

    if not all_manuscripts:
        print("Error: No manuscripts returned from API.")
        raise SystemExit(1)

    print(f"Found {len(all_manuscripts)} manuscripts.")
    run.save(manuscripts_folder, "all_manuscripts", all_manuscripts, run.run_stamp)

    if args.manuscript:
        all_manuscripts = select_one_or_exit(all_manuscripts, args.manuscript, "manuscript")

    remaining = len(all_manuscripts)
    manuscript_names = {}
    for manuscript in sort_by_id(all_manuscripts):
        manuscript_id = manuscript.get("id")
        if not manuscript_id:
            continue
        name = entity_basename(manuscript, manuscript_names)  # the slug, unique and stable
        folder = manuscripts_folder / name
        print(f"--- MANUSCRIPT: {name} ({manuscript_id})")

        # 2) manuscript details
        data = run.read(f"{name}: manuscript details", "manuscript", manuscript_id)
        if data is not None:
            run.save(folder, "manuscript", data, entity_timestamp(data, run.run_stamp))

        # 3) labels and tags of the manuscript
        run.backup_children(name, "manuscript/manuscript_labels", "manuscript_label",
                        manuscript_id, folder, "labels")
        run.backup_children(name, "manuscript/manuscript_tags", "manuscript_tag",
                        manuscript_id, folder, "tags")

        # 4) versions. The parts, stats and plots belong to a version, not to the manuscript.
        versions = run.backup_children(name, "manuscript/manuscript_versions", "manuscript_version",
                                   manuscript_id, folder, "versions")
        for version_entry, version_base in versions:
            version_id = version_entry["id"]
            version_label = f"{name}/{version_base}"
            version_folder = folder / "versions" / version_base
            print(f"  - version: {version_base}")

            # 5) stats and plots of the version
            run.backup_children(version_label, "manuscript_version/manuscript_stats", "manuscript_stat",
                            version_id, version_folder, "stats")
            run.backup_children(version_label, "manuscript_version/manuscript_plots", "manuscript_plot",
                            version_id, version_folder, "plots")

            # 6) parts of the version, and the beats of each part
            parts = run.backup_children(version_label, "manuscript_version/manuscript_parts", "manuscript_part",
                                    version_id, version_folder, "parts")
            for part_entry, part_base in parts:
                run.backup_children(version_label, "manuscript_part/manuscript_beats",
                                "manuscript_beat", part_entry["id"], version_folder / "parts",
                                part_base + "_beats", skip_if_empty=True)

        remaining -= 1
        print(f'------------------------ {remaining} manuscripts left')

    run.print_summary("manuscripts")

    save_cookies(session, file_cookies)
