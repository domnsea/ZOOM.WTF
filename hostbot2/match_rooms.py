#!/usr/bin/env python3
"""Match HOSTBOT2 posts to rooms using the key.

The key already lists room names (and usually a website). Posts usually name
the room as a website — `ballroom.wtf` means Ballroom. Website / domain clues
outrank a name mention so a post that says palace.party and also mentions
another room still lands on Palace.
"""
from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Iterable
from urllib.parse import urlparse

REFRESH_SECONDS = 300

ZOOM_LINK_RE = re.compile(
    r"https?://(?:[\w-]+\.)?(?:zoom\.us|app\.zoom\.us)/[^\s<>\"']+",
    re.I,
)
MEETING_ID_RE = re.compile(r"(?:/j/|/wc/join/|[?&]confno=)(\d{9,12})", re.I)
BARE_MEETING_RE = re.compile(r"\b(\d{3}[\s-]*\d{3}[\s-]*\d{3,4})\b")
URL_RE = re.compile(r"https?://[^\s<>\"']+", re.I)
BARE_DOMAIN_RE = re.compile(
    r"\b(?:www\.)?([a-z0-9][a-z0-9-]{1,61}(?:\.[a-z0-9][a-z0-9-]{1,61})*\.[a-z]{2,24})\b",
    re.I,
)
EMAIL_RE = re.compile(r"\b\S+@\S+\.\S+\b")

NOISE_HOSTS = {
    "zoom.us",
    "www.zoom.us",
    "app.zoom.us",
    "zoom.com",
    "t.me",
    "telegram.me",
    "telegram.org",
    "telegra.ph",
    "discord.gg",
    "discord.com",
    "youtube.com",
    "youtu.be",
    "twitter.com",
    "x.com",
    "instagram.com",
    "facebook.com",
    "fb.com",
    "bit.ly",
    "tinyurl.com",
    "goo.gl",
    "shopify.com",
    "myshopify.com",
    "google.com",
    "gmail.com",
    "whatsapp.com",
    "soundcloud.com",
    "github.com",
    "cdn.shopify.com",
}

KEY_NAMES = (
    "key.json",
    "key.txt",
    "KEY.txt",
    "KEY.json",
    "rooms-key.json",
    "rooms.json",
    "room-key.json",
    "room-key.txt",
)
POST_NAMES = (
    "posts.json",
    "posts.txt",
    "feed.json",
    "telegram.json",
    "messages.json",
    "directory-posts.json",
)

WEBSITE_SCORE = 100
NAME_AS_WEBSITE_SCORE = 90
KNOWN_MEETING_SCORE = 70
ALIAS_DOMAIN_SCORE = 80
NAME_PHRASE_SCORE = 45
ALIAS_PHRASE_SCORE = 40
MIN_ASSIGN_SCORE = 45


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _as_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, dict):
        parts = []
        for key in (
            "text",
            "message",
            "body",
            "content",
            "html",
            "caption",
            "post",
            "raw",
        ):
            if key in value:
                parts.append(_as_text(value[key]))
        if not parts:
            parts.append(json.dumps(value, ensure_ascii=False))
        return "\n".join(p for p in parts if p)
    if isinstance(value, (list, tuple)):
        return "\n".join(_as_text(item) for item in value)
    return str(value)


def strip_html(html: str) -> str:
    chunks: list[str] = []

    class _T(HTMLParser):
        def handle_data(self, data: str) -> None:
            chunks.append(data)

        def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
            if tag in {"br", "p", "div", "li", "tr"}:
                chunks.append("\n")
            for name, val in attrs:
                if name in {"href", "src"} and val:
                    chunks.append(" " + val + " ")

    parser = _T()
    try:
        parser.feed(html)
        parser.close()
    except Exception:
        return re.sub(r"<[^>]+>", " ", html)
    return " ".join("".join(chunks).split())


def normalize_host(host: str) -> str:
    host = (host or "").strip().lower()
    host = host.split(":")[0]
    if host.startswith("www."):
        host = host[4:]
    return host


def is_noise_host(host: str) -> bool:
    host = normalize_host(host)
    if not host or "." not in host:
        return True
    if host in NOISE_HOSTS:
        return True
    return any(host == n or host.endswith("." + n) for n in NOISE_HOSTS)


def compact_name(value: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "", (value or "").lower())
    if s.startswith("the") and len(s) - 3 >= 4:
        s = s[3:]
    return s


def phrase_present(phrase: str, text: str) -> bool:
    phrase = (phrase or "").strip()
    if len(phrase) < 3:
        return False
    pattern = r"(?<![a-z0-9])" + re.escape(phrase.strip()) + r"(?![a-z0-9])"
    return re.search(pattern, text, re.I) is not None


def extract_zoom_links(text: str) -> list[str]:
    found: list[str] = []
    seen: set[str] = set()
    for match in ZOOM_LINK_RE.finditer(text or ""):
        url = match.group(0).rstrip(").,;]>\"'")
        key = url.rstrip("/")
        if key.lower() not in seen:
            seen.add(key.lower())
            found.append(url)
    return found


def extract_meeting_id(url_or_text: str) -> str:
    text = url_or_text or ""
    match = MEETING_ID_RE.search(text)
    if match:
        return match.group(1)
    digits = re.sub(r"\D", "", text)
    if 9 <= len(digits) <= 12:
        return digits
    loose = BARE_MEETING_RE.search(text)
    if loose:
        only = re.sub(r"\D", "", loose.group(1))
        if 9 <= len(only) <= 12:
            return only
    return ""


def extract_hosts(text: str) -> list[str]:
    hosts: list[str] = []
    seen: set[str] = set()
    cleaned = EMAIL_RE.sub(" ", text or "")
    for match in URL_RE.finditer(cleaned):
        raw = match.group(0)
        try:
            host = urlparse(raw).hostname or ""
        except Exception:
            host = ""
        host = normalize_host(host)
        if host and not is_noise_host(host) and host not in seen:
            seen.add(host)
            hosts.append(host)
    for match in BARE_DOMAIN_RE.finditer(cleaned):
        host = normalize_host(match.group(1))
        if host and not is_noise_host(host) and host not in seen:
            seen.add(host)
            hosts.append(host)
    return hosts


def _listish(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        parts = re.split(r"[,;|/]+", value)
        return [p.strip() for p in parts if p.strip()]
    if isinstance(value, (list, tuple, set)):
        out: list[str] = []
        for item in value:
            out.extend(_listish(item))
        return out
    return [str(value)]


def _room_from_mapping(raw: dict[str, Any], index: int) -> dict[str, Any]:
    name = (
        raw.get("name")
        or raw.get("room")
        or raw.get("title")
        or raw.get("label")
        or ""
    )
    website = (
        raw.get("website")
        or raw.get("site")
        or raw.get("url")
        or raw.get("domain")
        or raw.get("web")
        or ""
    )
    aliases = _listish(raw.get("aliases") or raw.get("aka") or raw.get("names"))
    meeting_ids = [
        re.sub(r"\D", "", item)
        for item in _listish(raw.get("meeting_ids") or raw.get("meeting_id") or raw.get("ids"))
    ]
    meeting_ids = [m for m in meeting_ids if 9 <= len(m) <= 12]
    if not str(name).strip() and website:
        name = str(website)
    room = {
        "id": str(raw.get("id") or compact_name(str(name)) or f"room-{index}"),
        "name": str(name).strip(),
        "website": str(website).strip(),
        "aliases": aliases,
        "meeting_ids": meeting_ids,
    }
    return room


def _rooms_from_json(data: Any) -> list[dict[str, Any]]:
    if isinstance(data, dict):
        for key in ("rooms", "key", "entries", "directory"):
            if isinstance(data.get(key), list):
                return _rooms_from_json(data[key])
        if any(k in data for k in ("name", "website", "room", "title")):
            return [_room_from_mapping(data, 0)]
        rooms = []
        for index, (name, value) in enumerate(data.items()):
            if isinstance(value, dict):
                payload = {"name": name, **value}
            else:
                payload = {"name": name, "website": value}
            rooms.append(_room_from_mapping(payload, index))
        return rooms
    if isinstance(data, list):
        rooms = []
        for index, item in enumerate(data):
            if isinstance(item, dict):
                rooms.append(_room_from_mapping(item, index))
            elif isinstance(item, str):
                rooms.extend(parse_key(item))
            elif isinstance(item, (list, tuple)) and item:
                payload = {"name": item[0], "website": item[1] if len(item) > 1 else ""}
                if len(item) > 2:
                    payload["aliases"] = item[2]
                rooms.append(_room_from_mapping(payload, index))
        return rooms
    return []


def parse_key(source: Any) -> list[dict[str, Any]]:
    """Parse the HOSTBOT2 key. Names on the key are the room list."""
    if source is None:
        return []
    if isinstance(source, Path):
        text = source.read_text(encoding="utf-8", errors="replace")
        suffix = source.suffix.lower()
        if suffix == ".json":
            return parse_key(json.loads(text))
        return parse_key(text)
    if isinstance(source, (dict, list)):
        rooms = _rooms_from_json(source)
        return [room for room in rooms if room.get("name")]
    text = str(source).strip()
    if not text:
        return []
    if text[:1] in "{[":
        try:
            return parse_key(json.loads(text))
        except json.JSONDecodeError:
            pass
    if "<" in text and ">" in text:
        text = strip_html(text)
    rooms: list[dict[str, Any]] = []
    for index, raw_line in enumerate(text.splitlines()):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if re.match(r"^[-*|]+$", line):
            continue
        if "|" in line:
            parts = [p.strip() for p in line.split("|")]
        elif "\t" in line:
            parts = [p.strip() for p in line.split("\t") if p.strip()]
        else:
            parts = [p.strip() for p in re.split(r"\s{2,}", line) if p.strip()]
            if len(parts) == 1:
                bits = line.split()
                if len(bits) >= 2 and "." in bits[-1] and not bits[-1].endswith("."):
                    parts = [" ".join(bits[:-1]), bits[-1]]
                else:
                    parts = [line]
        payload = {
            "name": parts[0] if parts else "",
            "website": parts[1] if len(parts) > 1 else "",
            "aliases": parts[2] if len(parts) > 2 else "",
        }
        room = _room_from_mapping(payload, index)
        if room["name"]:
            rooms.append(room)
    return rooms


def parse_posts(source: Any) -> list[dict[str, Any]]:
    if source is None:
        return []
    if isinstance(source, Path):
        text = source.read_text(encoding="utf-8", errors="replace")
        if source.suffix.lower() == ".json":
            return parse_posts(json.loads(text))
        return parse_posts(text)
    if isinstance(source, dict):
        for key in ("posts", "messages", "items", "feed", "data"):
            if key in source:
                return parse_posts(source[key])
        return parse_posts([source])
    if isinstance(source, list):
        posts = []
        for item in source:
            if isinstance(item, dict):
                text = _as_text(item)
                if "<" in text and ">" in text:
                    text = strip_html(text)
                posts.append(
                    {
                        "text": text,
                        "source": item.get("source") or item.get("channel") or item.get("from") or "",
                        "ts": item.get("ts") or item.get("date") or item.get("time") or item.get("created_at") or "",
                    }
                )
            else:
                posts.extend(parse_posts(item))
        return [p for p in posts if p.get("text", "").strip()]
    text = str(source)
    if text.strip()[:1] in "{[":
        try:
            return parse_posts(json.loads(text))
        except json.JSONDecodeError:
            pass
    if "<" in text and ">" in text:
        text = strip_html(text)
    chunks = re.split(r"\n\s*\n", text)
    if len(chunks) == 1:
        chunks = text.splitlines()
    posts = []
    for chunk in chunks:
        chunk = chunk.strip()
        if chunk:
            posts.append({"text": chunk, "source": "", "ts": ""})
    return posts


def room_hosts(room: dict[str, Any]) -> list[str]:
    hosts: list[str] = []
    seen: set[str] = set()
    for raw in [room.get("website", ""), *room.get("aliases", [])]:
        blob = str(raw)
        for host in extract_hosts(blob if "://" in blob or "." in blob else ""):
            if host not in seen:
                seen.add(host)
                hosts.append(host)
        if "://" in blob:
            try:
                host = normalize_host(urlparse(blob).hostname or "")
            except Exception:
                host = ""
            if host and not is_noise_host(host) and host not in seen:
                seen.add(host)
                hosts.append(host)
    return hosts


def score_room(post_text: str, room: dict[str, Any]) -> tuple[int, list[str]]:
    text = post_text or ""
    hosts = extract_hosts(text)
    clues: list[str] = []
    score = 0
    room_host_set = set(room_hosts(room))
    name = room.get("name") or ""
    compact_room = compact_name(name)

    for host in hosts:
        if host in room_host_set:
            score = max(score, WEBSITE_SCORE)
            clues.append("website")
            break
        website_host = ""
        if room.get("website"):
            website_host = normalize_host(
                urlparse(
                    room["website"] if "://" in room["website"] else "https://" + room["website"]
                ).hostname
                or room["website"]
            )
        if website_host and (host == website_host or host.endswith("." + website_host)):
            score = max(score, WEBSITE_SCORE)
            clues.append("website")
            break

    for host in hosts:
        label = host.split(".")[0]
        compact_host = compact_name(label)
        if compact_room and compact_host == compact_room and len(compact_room) >= 4:
            score = max(score, NAME_AS_WEBSITE_SCORE)
            clues.append("name_as_website")
            break
        if compact_room and compact_name(host) == compact_room:
            score = max(score, NAME_AS_WEBSITE_SCORE)
            clues.append("name_as_website")
            break

    meeting = extract_meeting_id(text)
    if meeting and meeting in set(room.get("meeting_ids") or []):
        score = max(score, KNOWN_MEETING_SCORE)
        clues.append("meeting_id")

    for alias in room.get("aliases") or []:
        alias_hosts = extract_hosts(alias if "." in alias else "")
        if any(host in alias_hosts for host in hosts) or any(
            compact_name(host.split(".")[0]) == compact_name(alias)
            and len(compact_name(alias)) >= 4
            for host in hosts
        ):
            score = max(score, ALIAS_DOMAIN_SCORE)
            clues.append("alias_website")
            break

    if phrase_present(name, text):
        score = max(score, NAME_PHRASE_SCORE)
        clues.append("name")

    for alias in room.get("aliases") or []:
        if "." not in alias and phrase_present(alias, text):
            score = max(score, ALIAS_PHRASE_SCORE)
            clues.append("alias")
            break

    # Longer / more specific names win ties against short overlaps (Ball vs Ballroom).
    if clues and compact_room:
        score += min(len(compact_room), 20)

    return score, sorted(set(clues))


def best_room_for_post(
    post_text: str, rooms: list[dict[str, Any]]
) -> tuple[dict[str, Any] | None, int, list[str]]:
    ranked: list[tuple[int, int, dict[str, Any], list[str]]] = []
    for room in rooms:
        score, clues = score_room(post_text, room)
        ranked.append((score, len(compact_name(room.get("name") or "")), room, clues))
    ranked.sort(key=lambda row: (row[0], row[1]), reverse=True)
    if not ranked or ranked[0][0] < MIN_ASSIGN_SCORE:
        return None, 0, []
    winner = ranked[0]
    if len(ranked) > 1 and ranked[1][0] == winner[0] and "website" not in winner[3] and "name_as_website" not in winner[3]:
        return None, winner[0], ["ambiguous"]
    return winner[2], winner[0], winner[3]


def build_directory(
    key: Any,
    posts: Any,
    *,
    generated_at: str | None = None,
) -> dict[str, Any]:
    rooms = parse_key(key)
    parsed_posts = parse_posts(posts)
    by_id: dict[str, dict[str, Any]] = {}
    for room in rooms:
        by_id[room["id"]] = {
            "id": room["id"],
            "name": room["name"],
            "website": _canonical_website(room),
            "status": "closed",
            "join_url": None,
            "room_number": None,
            "matched_by": [],
            "score": 0,
            "last_seen": None,
            "source": None,
            "excerpt": None,
        }

    unmatched: list[dict[str, Any]] = []
    for index, post in enumerate(parsed_posts):
        text = post.get("text") or ""
        links = extract_zoom_links(text)
        if not links:
            continue
        join_url = links[-1]
        room, score, clues = best_room_for_post(text, rooms)
        excerpt = _excerpt(text, join_url)
        ts = post.get("ts") or ""
        if room is None:
            unmatched.append(
                {
                    "join_url": join_url,
                    "room_number": extract_meeting_id(join_url) or extract_meeting_id(text) or None,
                    "excerpt": excerpt,
                    "source": post.get("source") or None,
                    "ts": ts or None,
                    "reason": "no key match" if "ambiguous" not in clues else "ambiguous key match",
                }
            )
            continue
        entry = by_id[room["id"]]
        better = score > entry["score"] or (
            score == entry["score"] and index >= 0 and (not entry["last_seen"] or ts >= (entry["last_seen"] or ""))
        )
        if better or entry["status"] != "open":
            if score >= entry["score"]:
                entry.update(
                    {
                        "status": "open",
                        "join_url": join_url,
                        "room_number": extract_meeting_id(join_url) or extract_meeting_id(text) or None,
                        "matched_by": clues,
                        "score": score,
                        "last_seen": ts or generated_at or utc_now_iso(),
                        "source": post.get("source") or "HOSTBOT2",
                        "excerpt": excerpt,
                    }
                )

    directory_rooms = []
    for room in rooms:
        entry = by_id[room["id"]]
        public = {
            "id": entry["id"],
            "name": entry["name"],
            "website": entry["website"],
            "status": entry["status"],
            "join_url": entry["join_url"],
            "room_number": entry["room_number"],
            "matched_by": entry["matched_by"],
            "last_seen": entry["last_seen"],
            "source": entry["source"],
        }
        directory_rooms.append(public)

    return {
        "source": "HOSTBOT2",
        "generated_at": generated_at or utc_now_iso(),
        "refresh_seconds": REFRESH_SECONDS,
        "rooms": directory_rooms,
        "unmatched": unmatched,
    }


def _canonical_website(room: dict[str, Any]) -> str | None:
    website = (room.get("website") or "").strip()
    if website:
        if not re.match(r"^https?://", website, re.I):
            return "https://" + website.lstrip("/")
        return website
    hosts = room_hosts(room)
    if hosts:
        return "https://" + hosts[0]
    return None


def _excerpt(text: str, join_url: str, limit: int = 180) -> str:
    cleaned = re.sub(r"\s+", " ", text).strip()
    if join_url in cleaned:
        cleaned = cleaned.replace(join_url, " ").strip()
    if len(cleaned) > limit:
        cleaned = cleaned[: limit - 1].rstrip() + "…"
    return cleaned


def discover_hostbot2_files(root: Path) -> dict[str, Path | None]:
    root = root.expanduser().resolve()
    found = {"key": None, "posts": None}
    if not root.exists():
        return found
    files = list(root.rglob("*")) if root.is_dir() else [root]
    for path in files:
        if not path.is_file():
            continue
        name = path.name
        if found["key"] is None and name in KEY_NAMES:
            found["key"] = path
        if found["posts"] is None and name in POST_NAMES:
            found["posts"] = path
    if found["key"] is None:
        for path in files:
            if path.is_file() and "key" in path.name.lower() and path.suffix.lower() in {".json", ".txt", ".csv", ".html"}:
                found["key"] = path
                break
    if found["posts"] is None:
        for path in files:
            if path.is_file() and any(token in path.name.lower() for token in ("post", "feed", "telegram", "message")):
                found["posts"] = path
                break
    return found


def load_maybe(path: Path | None) -> Any:
    if path is None:
        return None
    if path.suffix.lower() == ".json":
        return json.loads(path.read_text(encoding="utf-8", errors="replace"))
    return path


def dump_directory(directory: dict[str, Any], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(directory, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
