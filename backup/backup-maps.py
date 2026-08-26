#!/usr/bin/python3
version = 'Tillerz Full Map Backup'

# --- requirements ----------------------------------------------------
# see https://github.com/Tillerz/worldanvil-templates/blob/master/tools/backup/

import argparse
from collections import deque
from glob import escape as glob_escape
import json
from pathlib import Path
import requests
from requests.utils import dict_from_cookiejar
from requests.utils import cookiejar_from_dict
import time
from wa_common import (
    build_api_url,
    build_request_headers,
    chdir_to_script_dir,
    ensure_dir,
    fetch_entity,
    fetch_entity_list_page,
    load_cfg_or_exit,
    read_text,
    sanitize_filename_component,
    world_paths,
    write_json,
)

PAGESIZE = 50
GRANULARITY = 2
# matches the "_YYYY-MM-DD_HHMMSS.json" suffix of a saved version, and nothing else
STAMP_GLOB = "_[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9].json"

# labels of API calls that failed, printed as a summary at the end
warnings = []


class RateLimiter:
    """Allow at most <calls> requests per <seconds> seconds."""

    def __init__(self, calls=5, seconds=5):
        self.seconds = seconds
        self.times = deque(maxlen=calls)

    def wait(self):
        if len(self.times) == self.times.maxlen:
            elapsed = time.monotonic() - self.times[0]
            if elapsed < self.seconds:
                time.sleep(self.seconds - elapsed)
        self.times.append(time.monotonic())


def entity_timestamp(data, fallback):
    raw = data.get("updateDate")
    if isinstance(raw, dict):
        raw = raw.get("date")
    if not isinstance(raw, str) or raw == "":
        return fallback
    return raw.replace(".000000", "").replace(" ", "_").replace(":", "")


def entity_basename(data, used):
    base = ""
    for key in ("slug", "title", "name"):
        value = data.get(key)
        if isinstance(value, str) and value.strip() != "":
            base = sanitize_filename_component(value.strip())
            if base != "":
                break
    entity_id = data.get("id") or ""
    if base == "":
        base = sanitize_filename_component(entity_id) or "unnamed"
    if used.get(base, entity_id) != entity_id:
        base = base + "_" + entity_id[:8]
    used[base] = entity_id
    return base


def newest_version(folder, base):
    files = sorted(Path(folder).glob(glob_escape(base) + STAMP_GLOB))
    return files[-1] if files else None


def save_versioned(folder, base, data, timestamp):
    """Write <base>_<timestamp>.json, unless the newest saved version is identical."""
    ensure_dir(folder)
    previous = newest_version(folder, base)
    if previous is not None:
        try:
            if json.loads(read_text(previous)) == data:
                return False
        except (OSError, ValueError):
            pass
    write_json(Path(folder) / f"{base}_{timestamp}.json", data)
    return True


def entities_of(jdata):
    if isinstance(jdata, list):
        return jdata
    if isinstance(jdata, dict):
        if jdata.get("success") is False:
            return []
        entities = jdata.get("entities")
        if isinstance(entities, list):
            return entities
    return []


def fetch_all_pages(limiter, session, api_url, path, entity_id, request_headers):
    """Read a list endpoint page by page.

    The API can answer with fewer entries than the requested limit and still have
    more pages behind it, so a short page is not the end of the list. Only an empty
    page, or a page without a single new id, stops the loop.
    """
    items = []
    seen = set()
    offset = 0
    while True:
        limiter.wait()
        jdata = fetch_entity_list_page(
            session,
            api_url,
            path,
            entity_id,
            request_headers,
            granularity=GRANULARITY,
            limit=PAGESIZE,
            offset=offset,
        )
        page = entities_of(jdata)
        if not page:
            break
        added = 0
        for entry in page:
            entry_id = entry.get("id")
            if entry_id is not None:
                if entry_id in seen:
                    continue
                seen.add(entry_id)
            items.append(entry)
            added += 1
        if added == 0:
            break
        offset += PAGESIZE
    return items


def safe_fetch(label, default, action):
    """Run one API call. On an API error, warn and carry on with the rest of the map."""
    try:
        return action()
    except requests.RequestException as error:
        print(f"    WARNING: {label} failed: {error}")
        warnings.append(label)
        return default


def sort_by_id(entities):
    return sorted(entities, key=lambda e: e.get("id") or "")


parser = argparse.ArgumentParser(description="Backup all maps of a world, with layers, marker groups and markers.")
parser.add_argument("--no-marker-details", action="store_true",
                    help="skip the GET /marker call for every single marker (much faster)")
parser.add_argument("--force", action="store_true",
                    help="fetch marker details even if the saved version is already up-to-date")
args = parser.parse_args()

# main
chdir_to_script_dir(__file__)

file_cookies = "cookies.json"
cfg = load_cfg_or_exit("settings.cfg")
world_name = cfg['world_name']
world_id = cfg['world_id']
request_headers = build_request_headers(cfg, version)
api_url = build_api_url(cfg)
paths = world_paths(world_name, cfg.get('root_folder'))
maps_folder = paths["maps"]

try:
    ensure_dir(maps_folder)
except OSError as error:
    print(f"Cannot create folder {maps_folder}: {error}")
    raise SystemExit(1)

# --- action starts here ---------------------------------------------------

with requests.Session() as session:
    if Path(file_cookies).is_file():
        session.cookies.update(cookiejar_from_dict(json.loads(read_text(file_cookies))))

    loop_start = time.monotonic()
    run_stamp = time.strftime("%Y-%m-%d_%H%M%S")
    limiter = RateLimiter()
    written = 0
    marker_calls = 0

    # 1) list all maps of the world
    try:
        all_maps = fetch_all_pages(limiter, session, api_url, "world/maps", world_id, request_headers)
    except requests.RequestException as e:
        print(f"Error fetching map list: {e}")
        raise SystemExit(1)

    if not all_maps:
        print("Error: No maps returned from API.")
        raise SystemExit(1)

    print(f"Found {len(all_maps)} maps.")
    if save_versioned(maps_folder, "all_maps", all_maps, run_stamp):
        written += 1

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
            lambda: fetch_all_pages(limiter, session, api_url, "map/layers", map_id, request_headers))
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
            lambda: fetch_all_pages(limiter, session, api_url, "map/markergroups", map_id, request_headers))
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
                                                     "markergroup/markers", gid, request_headers))
            if save_versioned(map_folder / "markergroups", base + "_markers", group_markers, run_stamp):
                written += 1
            for marker in group_markers:
                if marker.get("id"):
                    marker_ids.setdefault(marker["id"], marker)
        print(f"    marker groups: {len(groups)}")

        # 7) markers of the map
        markers = safe_fetch(
            f"{map_base}: marker list", [],
            lambda: fetch_all_pages(limiter, session, api_url, "map/markers", map_id, request_headers))
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

    cookies = dict_from_cookiejar(session.cookies) if session.cookies else {}
    write_json(file_cookies, cookies)
