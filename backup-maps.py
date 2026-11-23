#!/usr/bin/python3
version = 'Tillerz Full Map Backup'

# --- requirements ----------------------------------------------------
# see https://github.com/Tillerz/wa-tools

import argparse
import requests
import time
from wa_common import (
    build_api_url,
    build_request_headers,
    chdir_to_script_dir,
    ensure_dir,
    entity_basename,
    entity_timestamp,
    fetch_all_pages,
    fetch_entity,
    load_cfg_or_exit,
    rate_limiter_from_cfg,
    safe_fetch,
    save_versioned,
    select_one_or_exit,
    sort_by_id,
    warnings,
    world_paths_from_cfg,
)

GRANULARITY = 2


parser = argparse.ArgumentParser(description="Backup all maps of a world, with layers, marker groups and markers.")
parser.add_argument("--map", metavar="MAP",
                    help="back up one map only, given as its uuid or (part of) its title")
parser.add_argument("--no-marker-details", action="store_true",
                    help="skip the GET /marker call for every single marker (much faster)")
parser.add_argument("--force", action="store_true",
                    help="fetch marker details even if the saved version is already up-to-date")
parser.add_argument("--settings", default="settings.cfg", metavar="FILE",
                    help="settings file to use (default: settings.cfg)")
args = parser.parse_args()

# main
chdir_to_script_dir(__file__)

cfg = load_cfg_or_exit(args.settings)
world_name = cfg['world_name']
world_id = cfg['world_id']
request_headers = build_request_headers(cfg, version)
api_url = build_api_url(cfg)
paths = world_paths_from_cfg(cfg)
maps_folder = paths["maps"]

try:
    ensure_dir(maps_folder)
except OSError as error:
    print(f"Cannot create folder {maps_folder}: {error}")
    raise SystemExit(1)

# --- action starts here ---------------------------------------------------

with requests.Session() as session:
    loop_start = time.monotonic()
    run_stamp = time.strftime("%Y-%m-%d_%H%M%S")
    limiter = rate_limiter_from_cfg(cfg)
    written = 0
    marker_calls = 0

    # 1) list all maps of the world
    try:
        all_maps = fetch_all_pages(limiter, session, api_url, "world/maps", world_id, request_headers, GRANULARITY)
    except requests.RequestException as e:
        print(f"Error fetching map list: {e}")
        raise SystemExit(1)

    if not all_maps:
        print("Error: No maps returned from API.")
        raise SystemExit(1)

    print(f"Found {len(all_maps)} maps.")
    if save_versioned(maps_folder, "all_maps", all_maps, run_stamp):
        written += 1

    if args.map:
        all_maps = select_one_or_exit(all_maps, args.map, "map")

    map_names = {}
    remaining = len(all_maps)
    for map_entry in sort_by_id(all_maps):
        map_id = map_entry.get("id")
        if not map_id:
            continue
        map_base = entity_basename(map_entry, map_names)
        map_folder = maps_folder / map_base
        print(f"--- MAP: {map_base} ({map_id})")

        # 2) map details
        limiter.wait()
        map_data = safe_fetch(
            f"{map_base}: map details", None,
            lambda: fetch_entity(session, api_url, "map", map_id, request_headers, GRANULARITY))
        if map_data is not None:
            if save_versioned(map_folder, "map", map_data, entity_timestamp(map_data, run_stamp)):
                written += 1

        # 3) layers
        layers = safe_fetch(
            f"{map_base}: layer list", [],
            lambda: fetch_all_pages(limiter, session, api_url, "map/layers", map_id, request_headers, GRANULARITY))
        if save_versioned(map_folder, "layers", layers, run_stamp):
            written += 1
        layer_names = {}
        for layer in sort_by_id(layers):
            base = entity_basename(layer, layer_names)
            if save_versioned(map_folder / "layers", base, layer, entity_timestamp(layer, run_stamp)):
                written += 1
        print(f"    layers: {len(layers)}")

        # 4) marker groups
        groups = safe_fetch(
            f"{map_base}: marker group list", [],
            lambda: fetch_all_pages(limiter, session, api_url, "map/markergroups", map_id, request_headers, GRANULARITY))
        if save_versioned(map_folder, "markergroups", groups, run_stamp):
            written += 1

        # 5) marker group details + 6) markers of each group
        marker_ids = {}
        group_names = {}
        for group in sort_by_id(groups):
            group_id = group.get("id")
            if not group_id:
                continue
            base = entity_basename(group, group_names)
            limiter.wait()
            group_data = safe_fetch(
                f"{map_base}: marker group {base}", None,
                lambda gid=group_id: fetch_entity(session, api_url, "markergroup", gid,
                                                  request_headers, GRANULARITY))
            if group_data is not None:
                if save_versioned(map_folder / "markergroups", base, group_data,
                                  entity_timestamp(group_data, run_stamp)):
                    written += 1
            group_markers = safe_fetch(
                f"{map_base}: markers of group {base}", [],
                lambda gid=group_id: fetch_all_pages(limiter, session, api_url,
                                                     "markergroup/markers", gid, request_headers, GRANULARITY))
            if save_versioned(map_folder / "markergroups", base + "_markers", group_markers, run_stamp):
                written += 1
            for marker in group_markers:
                if marker.get("id"):
                    marker_ids.setdefault(marker["id"], marker)
        print(f"    marker groups: {len(groups)}")

        # 7) markers of the map
        markers = safe_fetch(
            f"{map_base}: marker list", [],
            lambda: fetch_all_pages(limiter, session, api_url, "map/markers", map_id, request_headers, GRANULARITY))
        if save_versioned(map_folder, "markers", markers, run_stamp):
            written += 1
        for marker in markers:
            if marker.get("id"):
                marker_ids[marker["id"]] = marker
        print(f"    markers: {len(markers)} in list, {len(marker_ids)} unique")

        # 8) marker details, each marker only once
        if not args.no_marker_details:
            marker_names = {}
            todo = len(marker_ids)
            for marker_id, marker in sorted(marker_ids.items()):
                base = entity_basename(marker, marker_names)
                stamp = entity_timestamp(marker, "")
                target = map_folder / "markers" / f"{base}_{stamp}.json"
                if not args.force and stamp != "" and target.is_file():
                    todo -= 1
                    continue
                limiter.wait()
                marker_data = safe_fetch(
                    f"{map_base}: marker {marker_id}", None,
                    lambda mid=marker_id: fetch_entity(session, api_url, "marker", mid,
                                                       request_headers, GRANULARITY))
                if marker_data is not None:
                    marker_calls += 1
                    if save_versioned(map_folder / "markers", base,
                                      marker_data, entity_timestamp(marker_data, run_stamp)):
                        written += 1
                todo -= 1
                if todo % 25 == 0 and todo > 0:
                    print(f"    marker details left: {todo}")

        remaining -= 1
        print(f'------------------------ {remaining} maps left')

    print(f"Wrote {written} files, {marker_calls} marker detail requests.")
    if warnings:
        print(f"{len(warnings)} API calls failed, these maps are incomplete:")
        for label in warnings:
            print(f"  {label}")
    elapsed = int(time.monotonic() - loop_start)
    minutes, seconds = divmod(elapsed, 60)
    print(f"Elapsed time: {minutes}m {seconds:02d}s")
