#!/usr/bin/python3

from collections import deque
from datetime import datetime
from glob import escape as glob_escape
import json
import os
from pathlib import Path
import requests
from requests.utils import cookiejar_from_dict, dict_from_cookiejar
import time

TEXT_ENCODING = "utf-8"
PAGESIZE = 50
# matches the "_YYYY-MM-DD_HHMMSS.json" suffix of a saved version, and nothing else
STAMP_GLOB = "_[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9].json"

# labels of API calls that failed, printed as a summary at the end
warnings = []


def read_text(path):
    return Path(path).read_text(encoding=TEXT_ENCODING)


def write_text(path, content):
    Path(path).write_text(content, encoding=TEXT_ENCODING)


def read_json(path):
    return json.loads(read_text(path))


def write_json(path, data, compact=False, indent=None):
    kwargs: dict = {"ensure_ascii": False}
    if compact:
        kwargs["separators"] = (",", ":")
    elif indent is not None:
        kwargs["indent"] = indent
    Path(path).write_text(json.dumps(data, **kwargs), encoding=TEXT_ENCODING)


def load_cfg(path):
    cfg = {}
    with open(path, "r", encoding=TEXT_ENCODING) as myfile:
        for line in myfile:
            line = line.strip()
            if not line.startswith("#"):
                name, var = line.partition("=")[::2]
                cfg[name.strip()] = str(var.strip())
    return cfg


def load_cfg_or_exit(path="settings.cfg"):
    try:
        return load_cfg(path)
    except FileNotFoundError:
        print(f"Error: The file {path} was not found.")
        raise SystemExit(1)
    except IOError:
        print(f"Error: The file {path} could not be read.")
        raise SystemExit(1)


def sanitize_filename_component(value):
    invalid_filename_chars = '/\\<>:"|?*'
    invalid_filename_chars += "".join(chr(i) for i in range(32))
    table = str.maketrans("", "", invalid_filename_chars)
    sanitized = os.path.basename(value.replace("\\", "/")).translate(table).strip()
    return sanitized


def ensure_dir(path):
    os.makedirs(path, exist_ok=True)


def chdir_to_script_dir(file_path):
    os.chdir(Path(file_path).resolve().parent)


def world_paths(world_name, root_folder=None):
    if root_folder:
        root = Path(root_folder).expanduser() / world_name
    else:
        root = Path(world_name)
    return {
        "root": root,
        "json": root / "json",
        "edit": root / "edit",
        "deploy": root / "deploy",
        "text-export": root / "text-export",
        "maps": root / "maps",
        "manuscripts": root / "manuscripts",
    }


def parse_wa_datetime(raw):
    if not isinstance(raw, str) or raw == "":
        return None
    cleaned = raw.replace(".000000", "")
    try:
        return datetime.strptime(cleaned, "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None


def parse_tags(value):
    if value is None:
        return []
    if isinstance(value, str):
        if value == "":
            return []
        return [part for part in value.split(",") if part != ""]
    return []


def format_tags(tags):
    return ",".join(tags)


def unique_preserve_order(values):
    seen = set()
    result = []
    for value in values:
        if value not in seen:
            seen.add(value)
            result.append(value)
    return result


def validate_single_comma_free_tag(value, label):
    if "," in value:
        raise ValueError(f"{label} may not contain commas.")


def build_request_headers(cfg, version):
    world_name = cfg["world_name"]
    return {
        "Content-Type": "application/json",
        "x-auth-token": cfg["x_auth_token"],
        "x-application-key": cfg["x_application_key"],
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " + version,
        "Referer": "https://www.worldanvil.com/w/" + world_name,
    }


def build_api_url(cfg):
    proxy_url = cfg.get("proxy", "")
    base_url = proxy_url if proxy_url != "" else "https://www.worldanvil.com"
    return base_url + "/api/external/boromir/"


def fetch_article(session, api_url, article_id, request_headers, granularity=3):
    endpoint = api_url + "article?id=" + article_id + "&granularity=" + str(granularity)
    response = session.get(endpoint, headers=request_headers)
    response.raise_for_status()
    return response.json()


def patch_article(session, api_url, article_id, payload, request_headers, timeout=60):
    endpoint = api_url + "article?id=" + article_id
    response = session.patch(
        endpoint, json=payload, headers=request_headers, timeout=timeout
    )
    response.raise_for_status()
    return response


def fetch_entity(session, api_url, path, entity_id, request_headers, granularity=2):
    endpoint = api_url + path + "?id=" + entity_id + "&granularity=" + str(granularity)
    response = session.get(endpoint, headers=request_headers)
    response.raise_for_status()
    return response.json()


def fetch_entity_list_page(
    session,
    api_url,
    path,
    entity_id,
    request_headers,
    granularity=2,
    limit=50,
    offset=0,
):
    endpoint = api_url + path + "?id=" + entity_id + "&granularity=" + str(granularity)
    payload = {"limit": limit, "offset": offset}
    response = session.post(endpoint, json=payload, headers=request_headers)
    response.raise_for_status()
    return response.json()


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


def rate_limiter_from_cfg(cfg):
    return RateLimiter(int(cfg.get("rate_limit_calls") or 5),
                       int(cfg.get("rate_limit_seconds") or 5))


def cookie_file_for(settings_path):
    """A second settings file gets its own cookie jar, so a test run cannot
    overwrite the cookies that belong to the real world."""
    stem = Path(settings_path).stem
    return "cookies.json" if stem == "settings" else f"cookies-{stem}.json"


def load_cookies(session, cookie_file):
    if Path(cookie_file).is_file():
        session.cookies.update(cookiejar_from_dict(read_json(cookie_file)))


def save_cookies(session, cookie_file):
    write_json(cookie_file, dict_from_cookiejar(session.cookies) if session.cookies else {})


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
            if read_json(previous) == data:
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


def fetch_all_pages(limiter, session, api_url, path, entity_id, request_headers, granularity=2):
    """Read a list endpoint page by page.

    The API can answer with fewer entries than the requested limit and still have
    more pages behind it, so a short page is not the end of the list. Only an empty
    page, or a page without a single new id, stops the loop.

    The next offset counts the entries that really came back, not the page size.
    Stepping by the page size would jump over everything the short page left out.
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
            granularity=granularity,
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
        offset += len(page)
    return items


def safe_fetch(label, default, action):
    """Run one API call. On an API error, warn and carry on with the rest of the work."""
    try:
        return action()
    except requests.RequestException as error:
        print(f"    WARNING: {label} failed: {error}")
        warnings.append(label)
        return default


def sort_by_id(entities):
    return sorted(entities, key=lambda e: e.get("id") or "")


def stable_basename(data, used):
    """File name that stays the same between runs: <slug or title>_<first 8 of id>.

    Titles are not unique (a manuscript can have three parts with the same title), and
    some entities have no update date. A name that depends on the id does not change
    between runs. If two entities of one list still end up with the same name (the
    same title and the same first 8 characters of the id), the second one gets its
    full id, so two entities can never share a file."""
    entity_id = data.get("id") or ""
    base = ""
    for key in ("slug", "title", "name"):
        value = data.get(key)
        if isinstance(value, str) and value.strip() != "":
            base = sanitize_filename_component(value.strip())
            if base != "":
                break
    if entity_id == "":
        return base or "unnamed"
    name = (base + "_" if base else "") + entity_id[:8]
    if used.get(name, entity_id) != entity_id:
        name = (base + "_" if base else "") + entity_id
    used[name] = entity_id
    return name


class BackupRun:
    """One run of a backup script: the API connection, the rate limit, and the
    helpers that read entities and save them as versioned files."""

    def __init__(self, session, api_url, request_headers, limiter, granularity=2):
        self.session = session
        self.api_url = api_url
        self.request_headers = request_headers
        self.limiter = limiter
        self.granularity = granularity
        self.run_stamp = time.strftime("%Y-%m-%d_%H%M%S")
        self.start = time.monotonic()
        self.written = 0
        self.detail_calls = 0

    def save(self, folder, base, data, stamp):
        if save_versioned(folder, base, data, stamp):
            self.written += 1

    def read(self, label, path, entity_id):
        """GET one entity. On an API error: warn, return None."""
        self.limiter.wait()
        data = safe_fetch(label, None, lambda: fetch_entity(
            self.session, self.api_url, path, entity_id, self.request_headers, self.granularity))
        if data is not None:
            self.detail_calls += 1
        return data

    def listing(self, label, path, parent_id):
        """POST one list endpoint, all pages. On an API error: warn, return None.
        None is not the same as an empty list: a failed call must not be saved as
        "this entity has no children"."""
        return safe_fetch(label, None, lambda: fetch_all_pages(
            self.limiter, self.session, self.api_url, path, parent_id,
            self.request_headers, self.granularity))

    def backup_children(self, label, list_path, read_path, parent_id, folder, list_name,
                        skip_if_empty=False):
        """Save the list of the children of one entity, and every child itself.

        The list entries are thin: a part or a note in a list has little or no content,
        so every child is read once with its own GET. The list goes to
        <folder>/<list_name>_<date>.json, the children to
        <folder>/<list_name>/<name>_<date>.json.
        With skip_if_empty, an empty list that was never saved before is not written
        and not printed (used for the beats: most parts have none).
        Returns [(list entry, file base name)], for the caller to go on with."""
        entries = self.listing(f"{label}: {list_name} list", list_path, parent_id)
        if entries is None:
            return []
        if entries or not skip_if_empty or newest_version(folder, list_name):
            self.save(folder, list_name, entries, self.run_stamp)
            print(f"    {list_name}: {len(entries)}")
        result = []
        used = {}
        for entry in sort_by_id(entries):
            if not entry.get("id"):
                continue
            base = stable_basename(entry, used)
            data = self.read(f"{label}: {list_name} {base}", read_path, entry["id"])
            if data is not None:
                self.save(folder / list_name, base, data, entity_timestamp(data, self.run_stamp))
            result.append((entry, base))
        return result

    def print_summary(self, incomplete):
        """Print the end of a run. <incomplete> names what a failed call leaves
        incomplete, for example "manuscripts"."""
        print(f"Wrote {self.written} files, {self.detail_calls} detail requests.")
        if warnings:
            print(f"{len(warnings)} API calls failed, these {incomplete} are incomplete:")
            for label in warnings:
                print(f"  {label}")
        minutes, seconds = divmod(int(time.monotonic() - self.start), 60)
        print(f"Elapsed time: {minutes}m {seconds:02d}s")


def select_entities(entities, query):
    """Find the entities that the user asked for, by uuid, slug or title.
    An exact match wins over a partial one."""
    wanted = query.strip().lower()

    def field(entity, key):
        return (entity.get(key) or "").strip().lower()

    by_id = [e for e in entities if field(e, "id") == wanted]
    if by_id:
        return by_id
    exact = [e for e in entities if wanted in (field(e, "slug"), field(e, "title"))]
    if exact:
        return exact
    return [e for e in entities if wanted in field(e, "title") or wanted in field(e, "slug")]


def select_one_or_exit(entities, query, kind):
    """Return a one-entry list for the entity the user asked for. Stop the script
    if nothing matches or if the query is not precise enough."""
    selected = select_entities(entities, query)
    if not selected:
        print(f"No {kind} matches '{query}'. Use the {kind} uuid or a part of its title.")
        raise SystemExit(1)
    if len(selected) > 1:
        print(f"'{query}' matches {len(selected)} {kind}s, please be more precise:")
        for entry in selected:
            print(f"  {entry.get('title')}  ({entry.get('id')})")
        raise SystemExit(1)
    print(f"Backing up 1 {kind}: {selected[0].get('title')}")
    return selected


writing_fields = (
    "title",
    "subheading",
    "snippet",
    "excerpt",
    "pronunciation",
    "content",
    "fullfooter",
    "sidepanelcontenttop",
    "sidepanelcontent",
    "sidebarcontentbottom",
    "sidebarcontent",
)


def load_all_json_articles(json_folder):
    results = []
    for path in sorted(Path(json_folder).glob("*.json")):
        try:
            data = read_json(path)
        except Exception as error:
            print(f"Warning: skipped invalid json {path.as_posix()}: {error}")
            continue
        slug = data.get("slug")
        if not isinstance(slug, str) or slug == "":
            continue
        update_obj = data.get("updateDate")
        update_raw = update_obj.get("date") if isinstance(update_obj, dict) else None
        update_date = parse_wa_datetime(update_raw)
        source_mtime = path.stat().st_mtime
        results.append((data, path, update_date, source_mtime))
    return results


def matches_title(jdata, query, case_sensitive):
    title = jdata.get("title") or ""
    if not case_sensitive:
        return query.lower() in title.lower()
    return query in title


def matches_slug(jdata, query, case_sensitive):
    slug = jdata.get("slug") or ""
    if not case_sensitive:
        return query.lower() in slug.lower()
    return query in slug


def matches_text(jdata, query, case_sensitive):
    for field in writing_fields:
        value = jdata.get(field)
        if not isinstance(value, str) or value == "":
            continue
        if not case_sensitive:
            if query.lower() in value.lower():
                return True
        else:
            if query in value:
                return True
    return False


def matches_tags(jdata, required_tags):
    article_tags = set(parse_tags(jdata.get("tags")))
    return set(required_tags).issubset(article_tags)


def matches_type(jdata, entity_type, case_sensitive):
    entity_class = jdata.get("entityClass") or ""
    if not case_sensitive:
        return entity_type.lower() == entity_class.lower()
    return entity_type == entity_class


def matches_state(jdata, state, case_sensitive):
    article_state = jdata.get("state") or ""
    if not case_sensitive:
        return state.lower() == article_state.lower()
    return state == article_state


def load_latest_json_by_slug(json_folder, require_article_id=False):
    latest_by_slug = {}
    for path in sorted(Path(json_folder).glob("*.json")):
        try:
            data = read_json(path)
        except Exception as error:
            print(f"Warning: skipped invalid json {path.as_posix()}: {error}")
            continue

        slug = data.get("slug")
        if not isinstance(slug, str) or slug == "":
            continue

        if require_article_id:
            article_id = data.get("id")
            if not isinstance(article_id, str) or article_id == "":
                continue

        update_obj = data.get("updateDate")
        update_raw = update_obj.get("date") if isinstance(update_obj, dict) else None
        update_date = parse_wa_datetime(update_raw)
        source_mtime = path.stat().st_mtime

        current = latest_by_slug.get(slug)
        if current is None:
            latest_by_slug[slug] = (data, path, update_date, source_mtime)
            continue

        current_key = (
            current[2] if current[2] is not None else datetime.min,
            current[3],
        )
        new_key = (
            update_date if update_date is not None else datetime.min,
            source_mtime,
        )
        if new_key >= current_key:
            latest_by_slug[slug] = (data, path, update_date, source_mtime)

    return latest_by_slug
