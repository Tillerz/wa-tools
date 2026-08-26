# Tillerz' World Anvil Backup/Edit/Deploy/Tag/Find Scripts

## Articles
Scripts in this folder support a full article flow:

1. download article JSON backups
2. find and filter articles
3. extract editable text fields into plain text files
4. prepare minimal update payloads from edited text files
5. manage the article tags
6. deploy payloads to WA REST API

## Maps

1. download map JSON backups, with layers, marker groups and markers


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
- `root_folder` (optional; base folder for all data files, e.g. `~/data`)

The scripts read `settings.cfg` from this folder (`tools/backup`).

When `root_folder` is set, all article data is read from and written to
`<root_folder>/<world_name>/`. Without it, the scripts use `<world_name>/`
relative to the script folder.

Examples with `root_folder=~/data` and `world_name=alana`:

| Folder | Path |
|---|---|
| JSON backups | `~/data/alana/json/` |
| Extracted fields | `~/data/alana/edit/` |
| Deploy payloads | `~/data/alana/deploy/` |
| Text exports | `~/data/alana/text-export/` |
| Map backups | `~/data/alana/maps/` |


# Scripts

## 1) Full Backup

Script:

- Linux/macOS: `python3 backup-full.py`
- Windows: `backup-full.cmd`

Purpose:

- fetches all articles via WA API
- stores full article JSON in `<world_name>/json/`

Parameters:

- none


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
  test setup. Each settings file gets its own cookie file.

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


## 3) Find Articles

Script:

- Linux/macOS: `python3 find.py <filters> [options]`

Purpose:

- searches article JSON files in `<world_name>/json/`
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


## 4) Extract Editable Fields

Script:

- Linux/macOS: `python3 extract.py <filename> [options]`
- Windows: `extract.cmd <filename> [options]`

Input:

- `<filename>` is a JSON file name from `<world_name>/json/`

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

- `filename` article json file name, looked up in `<world_name>/json/`
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
  creates text files of all published articles found in `<world_name>/json/`
- `python3 extract.py --copy ~/export --type Person --state public`
  copies all public Person articles to `~/export/`
- `python3 extract.py --copy ~/export --tags "undead,vampire"`
  copies all articles tagged with both "undead" and "vampire" to `~/export/`
- `python3 extract.py --extract-blocks plothooks.txt --start "[var:plothook-tillerz]" --end "[var:plothook-end-tillerz]"`
  extracts all plothook blocks from every article into `plothooks.txt`
- `python3 extract.py --extract-blocks plothooks.txt --start "[var:plothook-tillerz]" --end "[var:plothook-end-tillerz]" --state public --type Plot`
  same, but limited to public Plot articles


## 5) Prepare Deploy Payload for One Article

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


## 6) Tag Manager

Script:

- Linux/macOS: `python3 tagmgr.py <command>`

Purpose:

Tool to manage the article tags.

- reads article json files from `<world_name>/json/`
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


## 7) Deploy Payloads

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
./tests/test-maps.sh
```

See [tests/README.md](tests/README.md).


# Typical Workflow

1. `python3 backup-full.py`
2. `python3 extract.py <article-json-file>`
3. update/add files in `<world_name>/edit/<article-slug>/`
4. `python3 tagmgr --add <tag list> <article-slug>`
5. `python3 prepare.py <article-slug>`
6. review `<world_name>/deploy/<article-slug>.json`
7. `python3 deploy.py --dry-run`
8. `python3 deploy.py --validate`
