#!/usr/bin/python3
version = 'Tillerz Image Metadata Backup'

# --- requirements ----------------------------------------------------
# see https://github.com/Tillerz/wa-tools

import argparse
import requests
from wa_common import (
    BackupRun,
    build_api_url,
    build_request_headers,
    chdir_to_script_dir,
    ensure_dir,
    load_cfg_or_exit,
    rate_limiter_from_cfg,
    world_paths_from_cfg,
)

GRANULARITY = 2

# This saves the metadata of the images (title, size, width, height, file name, url ...),
# not the image files. The API cannot upload or download image files, and the spec says
# so. Every JSON file has the "url" of the file on the WA server.
#
# A world can have thousands of images, and every image is one read call (the list entries
# are thin). That is an hour at 5 calls per 5 seconds. So the script does nothing unless you
# say how much you want: --max N for a try, or --all for everything.
# The list entries have the updateDate of the image, so an image whose date is already in a
# saved file is not read again: the second run only reads the list (about a minute). --full
# reads everything.


parser = argparse.ArgumentParser(description="Backup the metadata of the images of a world.")
amount = parser.add_mutually_exclusive_group(required=True)
amount.add_argument("--max", type=int, metavar="N",
                    help="back up the first N images only (try it out: --max 50)")
amount.add_argument("--all", action="store_true",
                    help="back up all images (one list call per 50 images, and one read call per image)")
parser.add_argument("--full", action="store_true",
                    help="read every image again, also when the list says it did not change since the last run")
parser.add_argument("--settings", default="settings.cfg", metavar="FILE",
                    help="settings file to use (default: settings.cfg)")
args = parser.parse_args()
if args.max is not None and args.max < 1:
    parser.error("--max must be at least 1")

# main
chdir_to_script_dir(__file__)

cfg = load_cfg_or_exit(args.settings)
world_name = cfg['world_name']
world_id = cfg['world_id']
request_headers = build_request_headers(cfg, version)
api_url = build_api_url(cfg)
paths = world_paths_from_cfg(cfg)
images_folder = paths["images"]

try:
    ensure_dir(images_folder)
except OSError as error:
    print(f"Cannot create folder {images_folder}: {error}")
    raise SystemExit(1)

# --- action starts here ---------------------------------------------------

with requests.Session() as session:
    run = BackupRun(session, api_url, request_headers, rate_limiter_from_cfg(cfg), GRANULARITY)

    # the list of a limited run has its own file name, it is not the list of all images
    list_name = "all_images" if args.all else f"images_first_{args.max}"
    run.backup_children("images", "world/images", "image", world_id, images_folder,
                        list_name, children_folder=images_folder, max_items=args.max, skip_unchanged=not args.full)

    run.print_summary("images")
