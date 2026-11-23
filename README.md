# Tillerz' World Anvil Backup/Edit/Deploy/Tag/Find Scripts

## Overview

Backup scripts. Each one downloads data of the world via the WA API and saves it as JSON files.
Run them one by one, or all at once with `backup-all.py` (see [Run all backups](#run-all-backups)).

| Script | Backs up | Saved in | Details |
|---|---|---|---|
| `backup-articles.py` | articles | `<world>/articles/` | [section 1](#1-article-backup) |
| `backup-maps.py` | maps, layers, marker groups, markers | `<world>/maps/` | [section 2](#2-full-map-backup) |
| `backup-manuscripts.py` | manuscripts, versions, parts, beats, stats, plots, labels, tags | `<world>/manuscripts/` | [section 3](#3-full-manuscript-backup) |
| `backup-notebooks.py` | notebooks, sections, notes | `<world>/notebooks/` | [section 4](#4-full-notebook-backup) |
| `backup-timelines.py` | timelines, histories (events) | `<world>/timelines/`, `<world>/histories/` | [section 5](#5-full-timeline-backup) |
| `backup-world.py` | the world itself: settings, descriptions, CSS, `jsonMetadata` | `<world>/world/` | [section 8](#8-world-backup) |
| `backup-images.py` | image metadata (not the image files). Needs `--max N` or `--all` | `<world>/images/` | [section 7](#7-image-metadata-backup) |
| `backup-misc.py` | canvases, secrets, categories, subscriber groups, variable collections, variables, block folders, blocks, block templates | `<world>/canvases/`, `secrets/`, `categories/`, `subscribergroups/`, `variables/`, `blocks/`, `blocktemplates/` | [section 6](#6-misc-backup-canvases-secrets-variables) |

Not backed up on purpose: RPG systems and marker types. They are WA-wide catalogs, not your data. `POST /rpgsystems` returns 835 systems: in a scan
of all of them, none has an author and none is editable by you. `POST /markertypes` returns 616 marker types (a sample of 30 had no
owner either). The RPG system list ignores `limit` and `offset` (the spec has no paging for it).
Not backed up: the image files themselves (the API cannot give them, `backup-images.py` saves the metadata and the `url`).
Not backed up because WA does not allow it: manuscript bookmarks (WA answers with an error).
Not backed up on purpose: chronicles (metadata only).

The article scripts support a full article flow:

1. download article JSON backups (`backup-articles.py`)
2. find and filter articles
3. extract editable text fields into plain text files
4. prepare minimal update payloads from edited text files
5. manage the article tags
6. deploy payloads to WA REST API

All backup scripts have `--settings <file>`, and most have an option to back up only one thing
(`--map`, `--manuscript`, `--notebook`, `--type`). All of them save a new file only when the data changed.


## Run all backups

`backup-all.py` (Windows: `backup-all.cmd`) runs the backup scripts one after the other, shows their output while they run, and prints a summary
table at the end. A step that fails does not stop the others.

```bash
usage: backup-all.py [-h] [--only STEPS] [--skip STEPS] [--images N|all] [--settings FILE]
```

- The steps, in this order: `world`, `articles`, `maps`, `manuscripts`, `notebooks`, `timelines`, `misc` (all of `backup-misc.py`), and
  `images`.
- `--only world,articles` runs only these steps, `--skip maps` leaves a step out.
- **`images` is not part of a normal run.** Add `--images 50` (the first 50 images) or `--images all`. Every image is one call, and the
  scripts read every image again on every run, so `all` takes about an hour for 3,657 images.
- `--settings <file>` is passed to every script.
- `backup-misc.py --parts` (every part of the block templates) is not run by it, it takes hours.
- Exit code: `0` all fine, `1` at least one step failed, `3` all steps ran, but some API calls failed, so a backup is incomplete. Useful for cron.

How long a full run takes (measured on the world with 878 articles, 44 maps with 1,432 markers, 183 block templates; 5 calls per 5 seconds):

| Step | Time | Why |
|---|---|---|
| `world` | 1 s | 1 call |
| `articles` | 17 s | 18 list calls, only changed articles are read |
| `maps` | **28 min** | about 1,560 calls: 1,214 markers have no last-changed date, so each is read again on every run |
| `manuscripts` | 1.5 min | |
| `notebooks` | 10 s | |
| `timelines` | 7 s | |
| `misc` | 7.5 min | 183 block templates, 108 variables, 96 categories, ... |
| **Total** | **about 38 min** | |
| `images` (only with `--images all`) | about 62 min | 3,657 images, one call each |

# Requirements

- Python 3
- Python packages:
  - `requests`
  - `beautifulsoup4`
  - `lxml`

Install example:

```bash
pip install requests beautifulsoup4 lxml
```


# Configuration

Copy `settings-template.cfg` to `settings.cfg` and fill values:

- `world_name`
- `world_id`
- `x_auth_token`
- `x_application_key`
- `proxy` (optional; leave empty to use `https://www.worldanvil.com`)
- `backup_folder` (optional; the folder of the backups, see below)
- `work_folder` (optional; the folder of the working data of the article flow, see below)

The scripts read `settings.cfg` from the folder of the scripts.

The data goes to two places:

- the **backup folder**: everything the backup scripts download: the articles (`articles/`), maps, manuscripts, ..., the world, and
  the list of articles (`all_articles.json`). Set it with `backup_folder`, the exact folder, for example `~/data/alana`. If it is empty,
  the data goes to `data/<world_name>/` next to the scripts (git ignores `data/`).
- the **work folder**: the working data of the article flow: `edit` (extracted fields), `deploy` (payloads) and `text-export`. Set it
  with `work_folder` (the exact folder, for example `~/data/alana.work`). If it is empty, the work data is in the backup folder,
  as before. The backups, the article backups too, always stay in the backup folder.

Why two places: you can keep what you edit apart from what you back up, for example to back up or sync only the backup folder.

Which folder goes where, with `backup_folder=~/data/alana` and `work_folder=~/data/alana.work`:

| Folder | Path |
|---|---|
| Article backups (JSON) | `~/data/alana/articles/` |
| List of articles | `~/data/alana/all_articles.json` |
| Extracted fields (work) | `~/data/alana.work/edit/` |
| Deploy payloads (work) | `~/data/alana.work/deploy/` |
| Text exports (work) | `~/data/alana.work/text-export/` |
| Map backups | `~/data/alana/maps/` |
| Manuscript backups | `~/data/alana/manuscripts/` |
| Notebook backups | `~/data/alana/notebooks/` |
| Timeline backups | `~/data/alana/timelines/` |
| History (event) backups | `~/data/alana/histories/` |
| Canvas backups | `~/data/alana/canvases/` |
| Secret backups | `~/data/alana/secrets/` |
| Variable backups | `~/data/alana/variables/` |
| Block backups | `~/data/alana/blocks/` |
| Block template backups | `~/data/alana/blocktemplates/` |
| Category backups | `~/data/alana/categories/` |
| Subscriber group backups | `~/data/alana/subscribergroups/` |
| Image metadata backups | `~/data/alana/images/` |
| World backup | `~/data/alana/world/` |


# Scripts

## 1) Article Backup

Script:

- Linux/macOS: `python3 backup-articles.py [options]`
- Windows: `backup-articles.cmd [options]`

Purpose:

- fetches all articles via WA API
- stores full article JSON in `<world_name>/articles/`
- downloads only new or changed articles
- requests are limited like in the map backup (`rate_limit_calls`, `rate_limit_seconds` in `settings.cfg`)

Usage:

```bash
usage: backup-articles.py [-h] [--settings FILE]
```

Parameters:

- `--settings <file>` use another settings file, for a second world or for the
  test setup.


## 2) Full Map Backup

Script:

- Linux/macOS: `python3 backup-maps.py [options]`
- Windows: `backup-maps.cmd [options]`

Purpose:

- fetches all maps of the world via WA API, with granularity 2
- stores maps, layers, marker groups and markers in `<world_name>/maps/`

Usage:

```bash
usage: backup-maps.py [-h] [--map MAP] [--no-marker-details] [--force]
                      [--settings FILE]
```

Parameters:

- `--map <uuid or title>` back up one map only. Maps have no slug in the API, so
  give the map uuid (the last part of the map URL) or its title. A part of the
  title is enough, as long as it matches only one map; if it matches several, the
  script lists them and stops.
- `--no-marker-details` skip the `GET /marker` call for every single marker; the
  marker lists are still saved. Use this for a fast run, the marker detail calls
  are by far the slowest part.
- `--force` fetch marker details again even when the saved version already
  matches the marker's last update date
- `--settings <file>` use another settings file, for a second world or for the
  test setup.

Examples:

```bash
# every map, everything in it
python3 backup-maps.py

# every map, but no per-marker detail calls
python3 backup-maps.py --no-marker-details

# one map, by title
python3 backup-maps.py --map "Bridgeport County"

# one map, by uuid
python3 backup-maps.py --map f0f47ee0-fed0-4030-973a-3b80dd1a95b7
```

Folder layout per map:

| File | Content |
|---|---|
| `maps/all_maps_<date>.json` | list of all maps of the world |
| `maps/<map-slug>/map_<date>.json` | map details |
| `maps/<map-slug>/layers_<date>.json` | list of layers of the map |
| `maps/<map-slug>/markergroups_<date>.json` | list of marker groups of the map |
| `maps/<map-slug>/markers_<date>.json` | list of markers of the map |
| `maps/<map-slug>/layers/<layer>_<date>.json` | one file per layer |
| `maps/<map-slug>/markergroups/<group>_<date>.json` | marker group details |
| `maps/<map-slug>/markergroups/<group>_markers_<date>.json` | markers of that group |
| `maps/<map-slug>/markers/<marker>_<date>.json` | marker details |

Notes:

- `<date>` is the entity's last update date if the API returns one, otherwise the
  start time of the run
- a new version file is only written when the content really changed, so repeated
  runs do not fill the folders
- markers that are in a marker group and in the map marker list are fetched only once
- there is no API call for single layer details, so the files in `layers/` hold the
  entries of the layer list
- all list calls are paged with 50 entries per page; a short page does not end the
  list, the script keeps asking until a page is empty or brings nothing new
- one failed API call (for example a 403 on a map you cannot read) only skips that
  one call; the rest of the map is still saved, and all failures are listed at the end
- requests are limited to 5 per 5 seconds, same as the article backup. Change it
  with `rate_limit_calls` and `rate_limit_seconds` in `settings.cfg`.
- a run always refreshes `maps/all_maps_<date>.json`, also with `--map`


## 3) Full Manuscript Backup

Script:

- Linux/macOS: `python3 backup-manuscripts.py [options]`
- Windows: `backup-manuscripts.cmd [options]`

Purpose:

- fetches all manuscripts of the world via WA API, with granularity 2
- stores manuscripts, versions, parts, beats, stats, plots, labels and tags in `<world_name>/manuscripts/`

Usage:

```bash
usage: backup-manuscripts.py [-h] [--manuscript MANUSCRIPT] [--settings FILE]
```

Parameters:

- `--manuscript <uuid, slug or title>` back up one manuscript only. A part of the
  title is enough, as long as it matches only one manuscript; if it matches several,
  the script lists them and stops.
- `--settings <file>` use another settings file, for a second world or for the
  test setup.

Examples:

```bash
# every manuscript, everything in it
python3 backup-manuscripts.py

# one manuscript, by a part of its title
python3 backup-manuscripts.py --manuscript "wrong half"
```

Folder layout per manuscript (`<ms>` is the manuscript slug):

| File | Content |
|---|---|
| `manuscripts/all_manuscripts_<date>.json` | list of all manuscripts of the world |
| `manuscripts/<ms>/manuscript_<date>.json` | manuscript details |
| `manuscripts/<ms>/labels_<date>.json`, `labels/<label>_<date>.json` | label list, one file per label |
| `manuscripts/<ms>/tags_<date>.json`, `tags/<tag>_<date>.json` | tag list, one file per tag |
| `manuscripts/<ms>/versions_<date>.json` | list of versions |
| `manuscripts/<ms>/versions/<version>_<date>.json` | version details |
| `manuscripts/<ms>/versions/<version>/parts_<date>.json` | list of parts of the version |
| `manuscripts/<ms>/versions/<version>/parts/<part>_<date>.json` | one part, with its text |
| `manuscripts/<ms>/versions/<version>/parts/<part>_beats_<date>.json` | beat list of the part, only if the part has beats |
| `manuscripts/<ms>/versions/<version>/parts/<part>_beats/<beat>_<date>.json` | one beat |
| `manuscripts/<ms>/versions/<version>/stats_<date>.json`, `stats/` | stat list, one file per stat |
| `manuscripts/<ms>/versions/<version>/plots_<date>.json`, `plots/` | plot list, one file per plot |

Notes:

- versions, parts, stats and plots are named `<title>_<first 8 characters of the id>`.
  Titles are not unique (a manuscript can have several parts with the same title), the
  id part keeps the file name the same between runs.
- parts have no update date in the API, so `<date>` is the start time of the run, and
  the script reads every part on every run. A new version file is only written when the
  content really changed.
- the list calls only return short entries, so every label, tag, version, part, stat,
  plot and beat is read again with its own call. A run takes about 1 second per call.
- **manuscript bookmarks are not backed up.** World Anvil answers with error 422 for
  `POST /manuscript/manuscript_bookmarks` (checked 2026-11-23): their database query is
  broken. Parts of a manuscript cannot be listed by manuscript either, only by version.
- one failed API call only skips that one call; the rest is still saved, and all
  failures are listed at the end. A failed list is never saved as an empty list.
- requests are limited like in the other backups (`rate_limit_calls`, `rate_limit_seconds`).


## 4) Full Notebook Backup

Script:

- Linux/macOS: `python3 backup-notebooks.py [options]`
- Windows: `backup-notebooks.cmd [options]`

Purpose:

- fetches the notebooks of your world via WA API, with granularity 2
- stores notebooks, sections and notes in `<world_name>/notebooks/`

Usage:

```bash
usage: backup-notebooks.py [-h] [--notebook NOTEBOOK] [--settings FILE]
```

Parameters:

- `--notebook <uuid or title>` back up one notebook only. A part of the title is
  enough, as long as it matches only one notebook. A notebook picked this way is
  saved even if it belongs to another world.
- `--settings <file>` use another settings file, for a second world or for the
  test setup.

Folder layout per notebook:

| File | Content |
|---|---|
| `notebooks/all_notebooks_<date>.json` | list of all notebooks of your user, from all worlds |
| `notebooks/<notebook>/notebook_<date>.json` | notebook details |
| `notebooks/<notebook>/notesections_<date>.json` | list of sections |
| `notebooks/<notebook>/notesections/<section>_<date>.json` | one section |
| `notebooks/<notebook>/notesections/<section>_notes_<date>.json` | list of notes of the section |
| `notebooks/<notebook>/notesections/<section>_notes/<note>_<date>.json` | one note, with its text |

Notes:

- **notebooks belong to your user, not to a world.** The script reads all your
  notebooks, then reads each one and keeps only those whose `world` is the world in
  `settings.cfg`. It prints the others as skipped.
- the documented call `POST /world/notebooks` does not work (the WA spec says so). The
  script uses `POST /user/notebooks`, the call WA announced as its replacement. It is
  not in the spec yet, but it works (checked 2026-11-23). It needs your user id, which
  the script reads with `GET /identity`.
- files are named `<title>_<first 8 characters of the id>`, because titles are not
  unique. Notebooks, sections and many notes have no update date, so `<date>` is the
  start time of the run for those; notes with an update date use that date. A new
  version file is only written when the content really changed.
- the list calls only return short entries, so every section and note is read again
  with its own call.
- one failed API call only skips that one call; the rest is still saved, and all
  failures are listed at the end. A failed list is never saved as an empty list.
- requests are limited like in the other backups (`rate_limit_calls`, `rate_limit_seconds`).


## 5) Full Timeline Backup

Script:

- Linux/macOS: `python3 backup-timelines.py [options]`
- Windows: `backup-timelines.cmd [options]`

Purpose:

- fetches all timelines and all histories (the events on the timelines) of the world via WA API, with granularity 2
- stores timelines in `<world_name>/timelines/` and histories in `<world_name>/histories/`

Usage:

```bash
usage: backup-timelines.py [-h] [--settings FILE]
```

Parameters:

- `--settings <file>` use another settings file, for a second world or for the
  test setup.

Folder layout:

| File | Content |
|---|---|
| `timelines/all_timelines_<date>.json` | list of all timelines of the world |
| `timelines/<timeline-slug>/timeline_<date>.json` | timeline details, including its calendar, eras and the list of its histories |
| `histories/all_histories_<date>.json` | list of all histories of the world |
| `histories/<history>_<date>.json` | one history |

Notes:

- a history is named `<title>_<first 8 characters of the id>`, because titles are not unique.
- histories belong to the world, not to a timeline. Each history lists its timelines in
  the field `timelines`.
- the timeline list only has short entries, so every timeline is read with its own call. The
  history list already holds the full data of every history (checked: identical to
  `GET /history`), so histories need no extra calls. A run takes a few seconds.
- `<date>` is the entity's last update date if the API returns one, otherwise the start
  time of the run. A new version file is only written when the content really changed.
- chronicles are not backed up. WA left them out of its API spec, and `GET /chronicle`
  only returns metadata.
- one failed API call only skips that one call; the rest is still saved, and all
  failures are listed at the end. A failed list is never saved as an empty list.
- requests are limited like in the other backups (`rate_limit_calls`, `rate_limit_seconds`).


## 6) Misc Backup: Canvases, Secrets, Variables, Blocks

Script:

- Linux/macOS: `python3 backup-misc.py [options]`
- Windows: `backup-misc.cmd [options]`

Purpose:

- one script for the smaller data types that follow one pattern: a list call for the world, then one read call for every entry
  (and for some types: a list of children below every entry, then one read call for every child)
- fetches them via WA API, with granularity 2

What is bundled in this script:

| `--type` | What | WA calls | Saved in | Calls per run |
|---|---|---|---|---|
| `canvases` | canvases (whiteboards) | `POST /world/canvases`, then `GET /canvas` for each | `<world_name>/canvases/` | 1 + number of canvases |
| `secrets` | secrets | `POST /world/secrets`, then `GET /secret` for each | `<world_name>/secrets/` | 1 + number of secrets |
| `variables` | variable collections, and the variables in each collection | `POST /world/variablecollections`, `GET /variablecollection` for each, then `POST /variablecollection/variables` and `GET /variable` for each variable | `<world_name>/variables/` | 1 + collections x 2 + variables |
| `categories` | categories (the article categories of the world) | `POST /world/categories`, then `GET /category` for each | `<world_name>/categories/` | 1 + number of categories |
| `subscribergroups` | subscriber groups, with their subscribers | `POST /world/subscribergroups`, then `GET /subscribergroup` for each | `<world_name>/subscribergroups/` | 1 + number of groups |
| `blocktemplates` | block templates (your own, the whole user, not tied to a world) | `POST /user/blocktemplates` (with the user id from `GET /identity`), then `GET /blocktemplate` for each | `<world_name>/blocktemplates/` | 2 + templates |
| `blocks` | block folders, and the blocks in each folder | `POST /world/blockfolders`, `GET /blockfolder` for each, then `POST /blockfolder/blocks` and `GET /block` for each block | `<world_name>/blocks/` | 1 + folders x 2 + blocks |

- `canvases`, `secrets`, `categories`, `subscribergroups` and `blocktemplates` are driven by a small table (`SIMPLE_TYPES` in the script). `variables` and `blocks` are driven by a
  second table (`NESTED_TYPES`), because their entries are one level below a parent (collection, block folder).
- another type of one of these patterns needs one line in the table and a folder in `world_paths()` in `wa_common.py`.
- the calls are sent one after the other, so the number of calls is the run time: with the default limit of 5 calls
  per 5 seconds, about 1 second per call.

Usage:

```bash
usage: backup-misc.py [-h] [--type TYPE] [--parts] [--template TEMPLATE] [--settings FILE]
```

Parameters:

- `--type <canvases|secrets|categories|subscribergroups|blocktemplates|variables|blocks>` back up this type only. Can be given several times.
  Default: all seven (see the table above). The block templates are the slowest part of a full run (about 3 minutes for 183 templates).
- `--parts` block templates only: also read **every part** of every template with `GET /blocktemplatepart`. This is **slow** (one call per
  part, about 28,000 parts for 183 templates, about 8 hours), so use it together with `--template`.
- `--template <id or title>` block templates only: read only this one template. A part of the title is enough, as long as it matches
  only one template; if it matches several, the script lists them and stops. It implies `--type blocktemplates`. The list of all
  templates is still saved. An id is a number, for example `2652`.
- `--settings <file>` use another settings file, for a second world or for the
  test setup.

Examples:

```bash
# everything
python3 backup-misc.py

# only secrets
python3 backup-misc.py --type secrets
```

Folder layout:

| File | Content |
|---|---|
| `canvases/all_canvases_<date>.json` | list of all canvases |
| `canvases/<canvas>_<date>.json` | one canvas |
| `secrets/all_secrets_<date>.json` | list of all secrets |
| `secrets/<secret>_<date>.json` | one secret, with its content |
| `variables/all_variablecollections_<date>.json` | list of all variable collections |
| `variables/<collection>_<date>.json` | one variable collection |
| `variables/<collection>_variables_<date>.json` | list of the variables of the collection |
| `variables/<collection>_variables/<variable>_<date>.json` | one variable, with its key `k` and value `v` |
| `categories/all_categories_<date>.json` | list of all categories |
| `categories/<category>_<date>.json` | one category, with its `parent`, `children`, and the `articles` in it (short references) |
| `subscribergroups/all_subscribergroups_<date>.json` | list of all subscriber groups |
| `subscribergroups/<group>_<date>.json` | one subscriber group, with its `paidsubscribers` |
| `blocktemplates/all_blocktemplates_<date>.json` | list of all block templates of the user |
| `blocktemplates/<template>_<date>.json` | one block template, with its `parts` (short references), `formSchema` and `displayStructure` |
| `blocktemplates/<template>_parts/<part>_<date>.json` | one part of a template, only with `--parts` |
| `blocks/all_blockfolders_<date>.json` | list of all block folders |
| `blocks/<folder>_<date>.json` | one block folder |
| `blocks/<folder>_blocks_<date>.json` | list of the blocks of the folder |
| `blocks/<folder>_blocks/<block>_<date>.json` | one block, with its data (`jsondata`) |

Notes:

- files are named `<title>_<first 8 characters of the id>`, because titles are not unique. Many variables have
  no title; those are named by the first 8 characters of the id. The key and the value are inside the file.
- **subscriber group files contain your subscribers:** `paidsubscribers` lists them by name (`title`) and profile link, no email address.
  Keep that in mind when you share or publish a backup folder.
- **block templates belong to your user, not to a world** (like notebooks, but a template has no `world` field, so there is no
  filter). They are saved in the folder of the configured world. With several worlds, each world folder gets all templates.
- a block template is saved from `GET /blocktemplate`, which holds the structure (`formSchema`, `displayStructure`) and the
  parts as short references. By default the parts are not read one by one: `POST /blocktemplate/blocktemplateparts` always fails (WA bug),
  and `GET /blocktemplatepart` for every part would be about 28,000 calls (about 8 hours) for 183 templates. Most fields of a part
  (type, label, placeholder, description, rows, options) are also in the template's `formSchema`, but **not** the order of the parts
  (`position`, set in every part), `trackable`, and the part ids. If you need them, use `--parts --template <id>`: the parts go to
  `blocktemplates/<template>_parts/<part>_<date>.json`. Tried on the template with 98 parts: 98 files in 1m41s.
- block and block folder ids are integers, not uuids (as the spec says). The file names use them as they are,
  for example `Characters_22629`.
- the API has no call that lists all blocks of a world. Blocks are listed per block folder, so a block that is in no
  block folder would be missed (there is none in the test world).
- all list calls return only short entries, so every entry is read with its own call. Your world has 95 variables, so
  a full run takes about 2 minutes.
- `<date>` is the entity's last update date if the API returns one, otherwise the start
  time of the run. A new version file is only written when the content really changed.
  Every entity carries a copy of its world, and the world's update date changes whenever anything in the world is
  edited. That one field is ignored when the script decides if something changed (all backup scripts do this,
  except the article backup).
- the WA spec writes the variable collection paths with an underscore (`/variable_collection`). The real API has none:
  `/variablecollection` and `/variablecollection/variables`. The script uses the real ones.
- one failed API call only skips that one call; the rest is still saved, and all
  failures are listed at the end. A failed list is never saved as an empty list.
- requests are limited like in the other backups (`rate_limit_calls`, `rate_limit_seconds`).


## 7) Image Metadata Backup

Script:

- Linux/macOS: `python3 backup-images.py (--max N | --all) [options]`
- Windows: `backup-images.cmd (--max N | --all) [options]`

Purpose:

- fetches the **metadata** of the images of the world via WA API, with granularity 2: title, size, width, height, file name,
  extension, `url`, the articles that use the image, galleries, credits
- **it does not save the image files.** The API cannot upload or download them (the spec says so). Every JSON file has the
  `url` of the file on the WA server.
- stores them in `<world_name>/images/`
- it is a separate script, and it **does nothing without `--max` or `--all`.** A world can have thousands of images, and every
  image is one read call (the list entries are thin). At 5 calls per 5 seconds, 1,000 images take about 17 minutes.

Usage:

```bash
usage: backup-images.py [-h] (--max N | --all) [--settings FILE]
```

Parameters:

- `--max <N>` back up the first N images only. Use this to try it: `--max 50` makes 1 list call and 50 read calls.
- `--all` back up all images: 1 list call per 50 images, and 1 read call per image.
- `--settings <file>` use another settings file, for a second world or for the
  test setup.

Examples:

```bash
# try it with the first 50 images
python3 backup-images.py --max 50

# everything (only when you know how many images you have)
python3 backup-images.py --all
```

Folder layout:

| File | Content |
|---|---|
| `images/images_first_<N>_<date>.json` | list of the first N images, from a `--max N` run |
| `images/all_images_<date>.json` | list of all images, from an `--all` run |
| `images/<image>_<date>.json` | one image: its metadata |

Notes:

- an image is named `<title>_<id>` (the id is an integer). Images without a title are named by their id.
- `--max` and `--all` write into the same folder. An `--all` run after a `--max` run only adds what is new or changed.
- `<date>` is the image's last update date. A new version file is only written when the content really changed.
- one failed API call only skips that one call; the rest is still saved, and all failures are listed at the end.
- requests are limited like in the other backups (`rate_limit_calls`, `rate_limit_seconds`).


## 8) World Backup

Script:

- Linux/macOS: `python3 backup-world.py [options]`
- Windows: `backup-world.cmd [options]`

Purpose:

- fetches the world itself via `GET /world` (granularity 2) and saves it as JSON: its settings, the descriptions, the
  homepage texts, the display settings, `displayCss`, `displayPanelCss`, `descriptionParsed`, `jsonMetadata`, `metaTitle`,
  `metaDescription` and the rest (138 fields)
- the long texts are also saved as files of their own, so you can read and diff them
- it is one call, and it takes a second

Usage:

```bash
usage: backup-world.py [-h] [--settings FILE]
```

Parameters:

- `--settings <file>` use another settings file, for a second world or for the
  test setup.

Folder layout:

| File | Content |
|---|---|
| `world/world_<date>.json` | the whole world, all fields, versioned |
| `world/latest/descriptionParsed.html` | the field `descriptionParsed` |
| `world/latest/displayCss.css` | the field `displayCss` (the custom CSS of the world, about 100 KB) |
| `world/latest/displayPanelCss.css` | the field `displayPanelCss` |
| `world/latest/jsonMetadata.json` | the field `jsonMetadata`: a JSON text inside the JSON, here pretty-printed |

Notes:

- the files in `latest/` are always the current state, they are rewritten when the text changed. The history is in the
  versioned `world_<date>.json` files, which hold the same texts. A field that is empty gets no file.
- a new `world_<date>.json` is only written when something changed. These do not count as a change: the world's `updateDate`
  (it changes whenever anything in the world is edited) and the statistics (`countFollowers`, `countComments`,
  `countArticles`, `countArticleLikes`, `countMaps`, `countTimelines`) and the page view counter `views`. The file keeps them, it just does not get a new
  version because of them alone.
- the files are compared as bytes. The CSS of a world can have Windows line endings (`\r\n`), and they are kept as they are.
- the API has no separate "meta" files of the world. What the world has of that kind is in the one JSON: `jsonMetadata`
  (internal settings of the world, as JSON text), `metaTitle` and `metaDescription` (the texts for search engines).


## 9) Find Articles

Script:

- Linux/macOS: `python3 find.py <filters> [options]`

Purpose:

- searches article JSON files in `<world_name>/articles/`
- prints matching file paths (one per line, full path) sorted by last updated date, newest first
- all filters combine: only articles matching every given filter are returned

Usage:

```bash
usage: find.py [-h] [--title TITLE] [--slug SLUG] [--text TEXT]
               [--tags TAGS] [--type ENTITY_TYPE] [--state STATE]
               [--all] [--case]
```

Filters (at least one required):

- `--title <string>` find articles with `<string>` in the title
- `--slug <string>` find articles with `<string>` in the slug
- `--text <string>` find articles with `<string>` in any major article text field
- `--tags <tag list>` find articles that have **all** of the given comma-separated tags
- `--type <entityClass>` filter by entity class (Article, Condition, Document, Ethnicity, Formation, Item, Landmark, Language, Law, Location, Material, MilitaryConflict, Myth, Organization, Person, Plot, Profession, Prose, Rank, Ritual, Settlement, Species, Vehicle)
- `--state <state>` filter by article state (`public`, `draft`, `wip`)

Options:

- `--all` search all stored versions of each article (default: latest version only)
- `--case` case-sensitive search (default: case-insensitive); applies to all string filters; tag matching is always exact

Examples:

```bash
# all published articles mentioning "dragon" in text
python3 find.py --text dragon --state public

# all Person articles tagged "undead" or "vampire"
python3 find.py --type Person --tags "undead,vampire"

# drafts with "council" in the title, case-sensitive
python3 find.py --title council --state draft --case

# pipe into extract to bulk-export main article text fields
python3 find.py --state public --type Prose | xargs -I{} python3 extract.py {} --export
```


## 10) Extract Editable Fields

Script:

- Linux/macOS: `python3 extract.py <filename> [options]`
- Windows: `extract.cmd <filename> [options]`

Input:

- `<filename>` is a JSON file name from `<world_name>/articles/`

Output:

- creates/updates `<world_name>/edit/<article-slug>/`
- writes one `<field>.txt` per extracted field
- writes `.jsonfile` with original JSON file name
- writes `.uuid` with article id (if present)
- with `--export`, it also writes combined main article text field exports to `<world_name>/text-export/<entityClass>/<slug>.txt`

Usage:

```bash
usage: extract.py [-h] [-f FIELDS] [-l] [-a] [-t] [-e] [-w] filename
```

Parameters:

- `filename` article json file name, looked up in `<world_name>/articles/`
- `-f, --fields` comma-separated field list to extract
- `-l, --list` list fields in JSON (default list mode: string fields)
- `-a, --all` with `-l`, include all fields (not only strings)
- `-t, --types` with `-l`, show field types
- `-e, --empty` create files for empty fields too
- `-x, --export` write combined main article text field exports to `<world_name>/text-export/<entityClass>/<slug>.txt`
- `-b, --bbcode` with `--export`, keep BBcode/WA tags in output instead of stripping and converting them
- `--copy <dest>` copy the latest JSON file of every matching article to `<dest>`
- `--extract-blocks <output_file>` extract all text blocks between `--start` and `--end` from every article's writing fields into one output file
- `--start <string>` start delimiter for `--extract-blocks`
- `--end <string>` end delimiter for `--extract-blocks`

Filters for `--copy` and `--extract-blocks` (`--copy` requires at least one):

- `--title <string>` articles with this string in the title
- `--slug <string>` articles with this string in the slug
- `--text <string>` articles with this string in any writing field
- `--tags <tag list>` articles that have all of these comma-separated tags
- `--type <entityClass>` filter by entity class (e.g. `Person`, `Location`)
- `--state <state>` filter by state (`public`, `draft`, `wip`)
- `--case` case-sensitive matching (default: case-insensitive)

Examples:

- `python3 extract.py <article-json-file> --export`
- `python3 extract.py <article-json-file> --export --bbcode`
- `python3 extract.py --export --all`
  creates text files of all published articles found in `<world_name>/articles/`
- `python3 extract.py --copy ~/export --type Person --state public`
  copies all public Person articles to `~/export/`
- `python3 extract.py --copy ~/export --tags "undead,vampire"`
  copies all articles tagged with both "undead" and "vampire" to `~/export/`
- `python3 extract.py --extract-blocks plothooks.txt --start "[var:plothook-tillerz]" --end "[var:plothook-end-tillerz]"`
  extracts all plothook blocks from every article into `plothooks.txt`
- `python3 extract.py --extract-blocks plothooks.txt --start "[var:plothook-tillerz]" --end "[var:plothook-end-tillerz]" --state public --type Plot`
  same, but limited to public Plot articles


## 11) Prepare Deploy Payload for One Article

Script:

- Linux/macOS: `python3 prepare.py <article-slug>`
- Windows: `prepare.cmd <article-slug>`

Purpose:

- reads edited files from `<world_name>/edit/<article-slug>/`
- loads original JSON (`.jsonfile` marker, with fallback by slug)
- compares each edited field with original value
- creates minimal payload containing:
  - `id`
  - only changed fields
- writes payload to `<world_name>/deploy/<article-slug>.json`

Notes:

- `None` vs empty string for text fields is treated as unchanged
- prints byte/word diffs for changed fields listed in `word_count_fields`

Usage:

```bash
usage: prepare.py [-h] article_slug
```

Parameters:

- `article_slug` slug folder name under `<world_name>/edit/`


## 12) Tag Manager

Script:

- Linux/macOS: `python3 tagmgr.py <command>`

Purpose:

Tool to manage the article tags.

- reads article json files from `<world_name>/articles/`
- inspects and updates article tags
- writes tag updates to `<world_name>/deploy/<article-slug>.json`
- if deploy payloads already exist, updates those files in place so multiple tag operations can be chained safely
- update files can then deployed to WA using `python3 deploy.py`

Format:

- a `<tag list>` can be a single tag or several tags separated by comma
- a single tag may not contain a comma
- `<article-slug>` is the slug of the article as seen in its WA URL (`../a/<article-slug>`)

Usage examples:

List all tags of all articles with usage count and some stats:
- `python3 tagmgr.py --stats`
List all tags of type Document with usage count and some stats:
- `python3 tagmgr.py --stats --type Document`

```
[..]
we2021: 1
we2022: 6
we2023: 1
we2024: 1
we2025: 1
zaxor: 1
---
articles with tags: 36
articles with no tags: 25
average tags per tagged article: 3.06
```

List all tags of the given article:

- `python3 tagmgr.py --tags <article-slug>`

List all articles using the given tags:

- `python3 tagmgr.py --articles "<tag list>"`

List all articles of type Document using the given tags:

- `python3 tagmgr.py --articles "<tag list>" --type Document`

Replace a tag in all articles or the given article:

- `python3 tagmgr.py --replace <old tag> <new tag> [--all | <article-slug>]`

Replace a tag in all articles of type Document:

- `python3 tagmgr.py --replace <old tag> <new tag> --all --type Document`

Dry-run replace:

- `python3 tagmgr.py --replace <old tag> <new tag> [--all | <article-slug>] --dry-run`

Add a list of tags to all articles or a given article:

- `python3 tagmgr.py --add "<tag list>" [--all | <article-slug>]`

Add a list of tags to all articles of type Document:

- `python3 tagmgr.py --add "<tag list>" --all --type Document`

Dry-run add:

- `python3 tagmgr.py --add "<tag list>" [--all | <article-slug>] --dry-run`

Remove a list of tags from all articles or a given article:

- `python3 tagmgr.py --remove "<tag list>" [--all | <article-slug>]`

Remove a list of tags from all articles of type Document:

- `python3 tagmgr.py --remove "<tag list>" --all --type Document`

Dry-run remove:

- `python3 tagmgr.py --remove "<tag list>" [--all | <article-slug>] --dry-run`

A dry-run lets you run the command to see the output without writing any update files to deploy/.

Optional filter `--type <entityClass>`:

- all commands that do not target a single article support `--type <type>`
- `<type>` matches the article root-level `entityClass` value in json files
- `--dry-run` is supported by `--add`, `--replace`, and `--remove`
- available values (alphabetical):
- `Article`
- `Condition`
- `Document`
- `Ethnicity`
- `Formation`
- `Item`
- `Landmark`
- `Language`
- `Law`
- `Location`
- `Material`
- `MilitaryConflict`
- `Myth`
- `Organization`
- `Person`
- `Plot`
- `Profession`
- `Prose`
- `Rank`
- `Ritual`
- `Settlement`
- `Species`
- `Vehicle`


## 13) Deploy Payloads

Script:

- Linux/macOS: `python3 deploy.py [--dry-run] [--validate]`
- Windows: `deploy.cmd [--dry-run] [--validate]`

Purpose:

- scans `<world_name>/deploy/*.json`
- validates payload format (`id` + at least one changed field)
- sends updates to WA API:
  - method: `PATCH`
  - URL: `.../api/external/boromir/article?id=<article_id>`
  - body: payload without `id`

Usage:

```bash
usage: deploy.py [-h] [--dry-run] [--validate]
```

Parameters:

- `--dry-run` validate and print planned PATCH calls without sending requests
- `--validate` after successful PATCH, fetch article again and verify uploaded fields


# Tests

`tests/` holds a fake World Anvil API, so the scripts can be tested offline
without an auth token. Each test is named after what it tests:

```bash
./tests/test-articles.sh
./tests/test-manuscripts.sh
./tests/test-notebooks.sh
./tests/test-timelines.sh
./tests/test-misc.sh
./tests/test-images.sh
./tests/test-world.sh
./tests/test-prepare.sh
./tests/test-tagmgr.sh
./tests/test-names.sh
./tests/test-all.sh
./tests/test-common.sh
./tests/test-maps.sh
```

See [tests/README.md](tests/README.md).


# Changes

What changed in these scripts, most recent first. Useful when you update your own scripts or cron jobs.

- **Fixed: `tagmgr.py` crashed on every start** (`NameError: datetime`): it used `datetime` without importing it. `tests/test-tagmgr.sh` runs all its
  commands (stats, tags, articles, add, replace, remove, dry-run, chained changes). `tests/test-names.sh` looks for names that a script uses but
  never defines or imports, in all scripts.
- **Removed: the cookie files** (`cookies.json` and `cookies-<settings name>.json`). WA and Cloudflare never set a cookie for API calls (checked
  directly and through the proxy: no `Set-Cookie` header), so the files always held `{}`. The scripts no longer load or save cookies. You can
  delete old `cookies*.json` files.
- **Renamed: the folder of the article backups is `articles/` now, it was `json/`.** The name `json` looked like work data, but it is
  the backup of the articles. Rename an existing folder: `mv <backup folder>/json <backup folder>/articles`. If you do not, `backup-articles.py`
  finds no articles and downloads all of them again. `find.py`, `extract.py`, `prepare.py` and `tagmgr.py` read `articles/` too.
- **New: `backup_folder` and `work_folder` settings.** The working data of the article flow (`edit`, `deploy`, `text-export`) can live in a
  folder of its own, apart from the backups. Both are exact folders. The older setting `root_folder` (the folder that holds the folder of
  the world, so `root_folder = ~/data` means `backup_folder = ~/data/<world_name>`) still works, but it is not in the template any more;
  `backup_folder` wins if both are set. Without `work_folder` nothing changes. `extract.py`
  built the text-export path from the backup folder, it uses the text-export folder now. `backup-articles.py` creates the backup folder as well.
- **Moved: all files of the former `backup/` folder are now in the repo root.** `backup/` held 50 of the 53 files, and it also held the article
  tools, so the name was wrong. Old paths like `.../wa-tools/backup/find.py` must be changed to `.../wa-tools/find.py`.
  The lint settings `.pylintrc` and `.ruff.toml` are in git now (so the same rules apply on every machine).
- **Fixed: `prepare.py` ignored `root_folder`.** It looked for the edited files and the downloaded JSON in `<script folder>/<world_name>/`
  and wrote the deploy payload there, while `extract.py` and `deploy.py` use `<root_folder>/<world_name>/`. It now uses `root_folder`
  like all other scripts. `tests/test-prepare.sh` covers it.
- **Changed: without a backup folder the data goes to `data/<world_name>/`** next to the scripts (git ignores it), no longer into a
  `<world_name>/` folder between the scripts.
- **New: `backup-world.py`** for the world itself (`GET /world`): settings, descriptions, `displayCss`, `displayPanelCss`,
  `descriptionParsed`, `jsonMetadata`.
- **Fixed: a changed entity could overwrite an older backup file.** The file name has the entity's `updateDate`. If the content
  changed but the date did not, the new version got the same name as the old one and replaced it. It is now named by the time of
  the run instead, and the old file stays.
- **New: `backup-images.py`** for the metadata of the images. It does nothing without `--max N` or `--all`, because a world can have
  thousands of images. `fetch_all_pages` and `backup_children` got a `max_items` option for it.
- **New: categories and subscriber groups** in `backup-misc.py` (`--type categories`, `--type subscribergroups`).
- **New: `backup-all.py`** runs all the backup scripts one after the other and prints a summary. See [Run all backups](#run-all-backups).
- **New: `--parts` and `--template` for the block templates** (`backup-misc.py`). `--parts` reads every part of the templates, `--template` picks one
  template. `BackupRun.backup_children` got the options `pick` and `on_read` for it.
- **New: block templates** in `backup-misc.py` (`--type blocktemplates`). `BackupRun.user_id()` reads the user id for the lists that
  belong to the user (the notebook backup uses it too).
- **New: block folders and blocks** in `backup-misc.py` (`--type blocks`). The shared code now accepts integer ids.
- **New: `backup-misc.py`** for canvases, secrets, variable collections and variables.
- **New: `backup-timelines.py`** for timelines and histories (events).
- **New: `backup-notebooks.py`** for notebooks, sections and notes. It uses `POST /user/notebooks`, because
  `POST /world/notebooks` does not work.
- **New: `backup-manuscripts.py`** for manuscripts with versions, parts, beats, stats, plots, labels and tags.
- **Renamed: `backup-full.py` is now `backup-articles.py`** (and `backup-full.cmd` is `backup-articles.cmd`).
  Change any script or cron job that calls the old name.
- **Fixed: the article backup lost articles.** It stepped through the article list by the page size, and skipped entries when
  the API answered with a short page. It now uses the same list reading as the other backups. It also creates the
  `articles/` folder if it is missing, and it follows `rate_limit_calls` and `rate_limit_seconds` from `settings.cfg`.
- **Fixed: no new version for a change elsewhere in the world** (all backups except the article backup). Every entity carries a
  copy of its world, and `world.updateDate` in it changes whenever anything in the world is edited. That field is ignored
  when the script decides if an entity changed. The saved file still has the full data.
- **Shared code:** `wa_common.py` has the code that the backups share (rate limit, paging, versioned saving, file names,
  the `BackupRun` class for list-then-read-each).
- **Tests:** a fake World Anvil API in `tests/`, and one smoke test per backup. See [Tests](#tests).
- **New option `--settings <file>`** for all backups, to use another settings file (second world, or the test setup).

# Known problems of the WA API

The backups work around these. They are listed for the WA team in `api-docs/wa-api-issues.md` (the `api-docs/` folder is kept local,
it is not in git).

| Endpoint | Problem | What the backup does |
|---|---|---|
| `POST /manuscript/manuscript_bookmarks` | always 422 (broken query on the WA side) | bookmarks are not backed up |
| `POST /blocktemplate/blocktemplateparts` | always 422 (broken query on the WA side) | uses `GET /blocktemplate`, which has the parts as short references |
| `POST /world/notebooks` | 404 (the spec says it does not work) | uses `POST /user/notebooks`, which is not in the spec |
| `/variable_collection...` | the spec has an underscore, the real paths have none | uses `/variablecollection...` |
| all list calls | `limit` can be up to 100, not 50 as the spec says | uses 50 |
| many entities | `updateDate` is `null` (manuscript parts, variables, ...) | reads every entity on every run and saves only real changes |
| many lists | list entries are short, only the single read has the content | reads every entity with its own call |
| `POST /rpgsystems` | ignores `limit` and `offset`, always returns all 835 systems (the spec has no paging for it); the systems have no author | not backed up: it is a WA-wide catalog, not your data |

# Typical Workflow

1. `python3 backup-articles.py`
2. `python3 extract.py <article-json-file>`
3. update/add files in `<world_name>/edit/<article-slug>/`
4. `python3 tagmgr --add <tag list> <article-slug>`
5. `python3 prepare.py <article-slug>`
6. review `<world_name>/deploy/<article-slug>.json`
7. `python3 deploy.py --dry-run`
8. `python3 deploy.py --validate`
