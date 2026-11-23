# Tests for the backup scripts

This folder holds a fake World Anvil API. With it you can test the scripts
without touching the real API, without an auth token, and without waiting for
the rate limit.

## Files

| File | What it is |
|---|---|
| `mock_wa_api.py` | the fake API server, shared by all tests |
| `settings-test.cfg` | settings that point at the fake server, shared by all tests |
| `fixtures-maps.json` | the world the map test uses: 3 maps, layers, marker groups, markers |
| `test-maps.sh` | smoke test for `backup-maps.py` |
| `fixtures-articles.json` | the articles the article test uses: 3 articles |
| `fixtures-manuscripts.json` | the manuscripts the manuscript test uses: 2 manuscripts, versions, parts, beats, stats, labels |
| `test-manuscripts.sh` | smoke test for `backup-manuscripts.py`, including two parts with the same title and a 403 |
| `fixtures-notebooks.json` | the notebooks the notebook test uses: 3 notebooks (one per case: this world, another world, no world), sections, notes |
| `test-notebooks.sh` | smoke test for `backup-notebooks.py`, including the world filter, two notes with the same title and a 403 |
| `fixtures-timelines.json` | the timelines the timeline test uses: 2 timelines, 3 histories |
| `test-timelines.sh` | smoke test for `backup-timelines.py`, with 60 more generated histories to force paging, two events with the same title and a 403 |
| `fixtures-misc.json` | the data the misc test uses: 1 canvas, 3 secrets, 3 variable collections with variables, 3 block folders with blocks (integer ids) |
| `test-misc.sh` | smoke test for `backup-misc.py`, including same-title secrets, an empty collection, a 403 and `--type` |
| `test-common.sh` | tests of shared code in `wa_common.py` that need no fake server (for example: the version comparison) |
| `test-articles.sh` | smoke test for `backup-articles.py`, with 60 more generated articles to force paging |

A test is named after what it tests: `test-<subject>.sh`, with its data in
`fixtures-<subject>.json`.

## Run the tests

```bash
./tests/test-maps.sh
./tests/test-articles.sh
./tests/test-manuscripts.sh
./tests/test-notebooks.sh
./tests/test-timelines.sh
./tests/test-misc.sh
./tests/test-common.sh
```

It prints `ALL TESTS PASSED` or lists what went wrong. Everything it downloads
lands in `tests/out/` and is deleted at the start of each run.

## Use the server by hand

Start it:

```bash
python3 tests/mock_wa_api.py
```

Then, from the `backup` folder, run any script against it:

```bash
python3 backup-maps.py --settings tests/settings-test.cfg
```

`settings-test.cfg` sets `proxy = http://127.0.0.1:8099`, so all calls go to the
fake server. It also uses its own cookie file, so your real `cookies.json` is
never overwritten.

## Make the server misbehave

The real API has two habits that broke earlier versions of `backup-maps.py`.
Both can be turned on:

| Option | What it does |
|---|---|
| `--short-pages` | hands back one entry less than asked for, while more pages still follow |
| `--forbid map/markers` | answers 403, like a map you are not allowed to read |
| `--forbid map/markers:<uuid>` | the same, but only for one map |
| `--bulk-markers 130` | adds 130 generated markers to the first map, so paging really runs |
| `--bulk-articles 60` | adds 60 generated articles, so paging really runs |
| `--bulk-histories 60` | adds 60 generated histories, so paging really runs |

Example, the exact case that lost markers before:

```bash
python3 tests/mock_wa_api.py --short-pages --bulk-markers 130 \
    --forbid map/markers:22222222-2222-2222-2222-222222222222
```

Other options: `--port` (default 8099), `--data <file>` for a different fixture
file, `--quiet` to stop the request log.

## Add your own test data

Copy `fixtures-maps.json`, edit it, and start the server with `--data yourfile.json`.
The format is:

```json
{
  "maps":         [ { "id": "<map uuid>", "title": "..." } ],
  "layers":       { "<map uuid>":   [ { "id": "...", "title": "..." } ] },
  "markergroups": { "<map uuid>":   [ { "id": "...", "title": "..." } ] },
  "groupmarkers": { "<group uuid>": [ { "id": "...", "title": "..." } ] },
  "markers":      { "<map uuid>":   [ { "id": "...", "title": "..." } ] }
}
```

A `GET` for a single map, marker group, or marker is answered from the same
lists, with `"granularity": 2` added.
