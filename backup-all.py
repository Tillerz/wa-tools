#!/usr/bin/python3
version = 'Tillerz Backup All'

# --- requirements ----------------------------------------------------
# see https://github.com/Tillerz/wa-tools

import argparse
from pathlib import Path
import re
import subprocess
import sys
import time

# The backup scripts, in the order they run. A step that fails does not stop the others.
STEPS = [
    ("world", "backup-world.py"),
    ("articles", "backup-articles.py"),
    ("maps", "backup-maps.py"),
    ("manuscripts", "backup-manuscripts.py"),
    ("notebooks", "backup-notebooks.py"),
    ("timelines", "backup-timelines.py"),
    ("misc", "backup-misc.py"),
    ("images", "backup-images.py"),
]
STEP_NAMES = [name for name, _script in STEPS]

# Lines of the scripts that say what the run did. The last one that matches is shown in the summary.
RESULT_LINES = (
    re.compile(r"^Wrote \d+ files"),
    re.compile(r"^Updated \d+ articles"),
    re.compile(r"^\d+ articles were already up-to-date"),
)
FAILED_CALLS = re.compile(r"^(\d+) API calls failed")

EXIT_OK, EXIT_FAILED, EXIT_INCOMPLETE = 0, 1, 3


def names_list(value):
    names = [part.strip() for part in value.split(",") if part.strip()]
    unknown = [name for name in names if name not in STEP_NAMES]
    if unknown:
        raise argparse.ArgumentTypeError(f"unknown step: {', '.join(unknown)} (the steps are: {', '.join(STEP_NAMES)})")
    return names


def images_option(value):
    if value == "all":
        return value
    if value.isdigit() and int(value) > 0:
        return int(value)
    raise argparse.ArgumentTypeError("give a number of images, or 'all'")


def minutes_seconds(seconds):
    minutes, seconds = divmod(int(seconds), 60)
    return f"{minutes}m {seconds:02d}s"


def run_step(name, script, extra_args):
    """Run one backup script, show its output while it runs, and return what happened."""
    command = [sys.executable, "-u", str(Path(__file__).resolve().parent / script), *extra_args]
    start = time.monotonic()
    result_line = ""
    failed_calls = 0
    last_lines = []
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1,
                               encoding="utf-8", errors="replace")
    try:
        for line in process.stdout:
            line = line.rstrip("\n")
            print(line, flush=True)
            last_lines = (last_lines + [line])[-6:]
            if any(pattern.match(line) for pattern in RESULT_LINES):
                result_line = line
            match = FAILED_CALLS.match(line)
            if match:
                failed_calls = int(match.group(1))
        process.wait()
    except KeyboardInterrupt:
        process.terminate()
        process.wait()
        raise
    return {
        "name": name,
        "code": process.returncode,
        "seconds": time.monotonic() - start,
        "result": result_line,
        "failed_calls": failed_calls,
        "last_lines": last_lines,
    }


def status_of(step):
    if step["code"] != 0:
        return "FAILED"
    if step["failed_calls"]:
        return "INCOMPLETE"
    return "OK"


def print_summary(done, total_seconds, not_run):
    print("\n=== Summary " + "=" * 60)
    for step in done:
        status = status_of(step)
        if status == "FAILED":
            detail = f"exit code {step['code']}: " + (step["last_lines"][-1] if step["last_lines"] else "")
        elif status == "INCOMPLETE":
            detail = f"{step['failed_calls']} API calls failed. {step['result']}"
        else:
            detail = step["result"]
        print(f"  {step['name']:12} {status:11} {minutes_seconds(step['seconds']):>8}   {detail}")
    for name in not_run:
        print(f"  {name:12} {'not run':11}")
    print(f"Total time: {minutes_seconds(total_seconds)}")
    if any(status_of(step) == "FAILED" for step in done):
        print("At least one step FAILED. Read its output above.")
    elif any(status_of(step) == "INCOMPLETE" for step in done):
        print("All steps ran, but some API calls failed. The backups of those steps are incomplete, see the list at the end of their output.")


parser = argparse.ArgumentParser(
    description="Run the backup scripts one after the other: " + ", ".join(STEP_NAMES[:-1]) + ". "
                "The images are only backed up with --images.",
    epilog="Exit code: 0 all fine, 1 at least one step failed, 3 all steps ran but some API calls failed (incomplete backup).")
parser.add_argument("--only", type=names_list, metavar="STEPS",
                    help=f"run only these steps, comma separated (steps: {', '.join(STEP_NAMES)})")
parser.add_argument("--skip", type=names_list, metavar="STEPS", help="do not run these steps, comma separated")
parser.add_argument("--images", type=images_option, metavar="N|all",
                    help="also back up the image metadata: the first N images, or all. A world can have thousands of images, "
                         "and an image is one call, so 'all' can take hours")
parser.add_argument("--full", action="store_true",
                    help="read everything again: entries that the list says did not change are not skipped (images, categories, secrets), "
                         "and the markers of the maps are read again (--force)")
parser.add_argument("--settings", default="settings.cfg", metavar="FILE",
                    help="settings file to use, passed to every script (default: settings.cfg)")
args = parser.parse_args()
if args.only and "images" in args.only and args.images is None:
    parser.error("the step images needs --images N or --images all")

selected = [name for name in STEP_NAMES if name != "images" or args.images is not None]
if args.only:
    selected = [name for name in selected if name in args.only]
if args.skip:
    selected = [name for name in selected if name not in args.skip]
if not selected:
    parser.error("no step is left to run")

scripts = dict(STEPS)
done = []
start = time.monotonic()
print(f"{version}: {len(selected)} steps: {', '.join(selected)}", flush=True)
try:
    for number, name in enumerate(selected, 1):
        print(f"\n=== [{number}/{len(selected)}] {name} " + "=" * 50, flush=True)
        extra = ["--settings", args.settings]
        if args.full and name in ("images", "misc"):
            extra.append("--full")
        if args.full and name == "maps":
            extra.append("--force")
        if name == "images":
            extra += ["--all"] if args.images == "all" else ["--max", str(args.images)]
        done.append(run_step(name, scripts[name], extra))
except KeyboardInterrupt:
    print("\nInterrupted.")
    print_summary(done, time.monotonic() - start, [name for name in selected if name not in [s["name"] for s in done]])
    raise SystemExit(130)

print_summary(done, time.monotonic() - start, [])
if any(status_of(step) == "FAILED" for step in done):
    raise SystemExit(EXIT_FAILED)
if any(status_of(step) == "INCOMPLETE" for step in done):
    raise SystemExit(EXIT_INCOMPLETE)
