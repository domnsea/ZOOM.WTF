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
ROOMS_TXT_NAMES = ("ROOMS.txt", "rooms.txt")

WEBSITE_SCORE = 100
NAME_AS_WEBSITE_SCORE = 90
KNOWN_MEETING_SCORE = 70
PROMOTED_ID_SCORE = 120
ALIAS_DOMAIN_SCORE = 80
NAME_PHRASE_SCORE = 45
ALIAS_PHRASE_SCORE = 40
MIN_ASSIGN_SCORE = 45
ROOMS_TXT_SCORE = 110

# 2060220206 was Ballroom once. It is not Ballroom. The 973 number being
# promoted is Ballroom.
STALE_BALLROOM_IDS = frozenset({"2060220206"})
BALLROOM_PROMOTED_PREFIXES = ("973",)


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


def meeting_id_token(value: str) -> str:
    digits = re.sub(r"\D", "", value or "")
    if 9 <= len(digits) <= 12:
        return digits
    return ""


def looks_like_meeting_id(value: str) -> bool:
    token = (value or "").strip()
    if not token:
        return False
    if re.fullmatch(r"[\d][\d\s-]*[\d]", token) is None:
        return False
    return bool(meeting_id_token(token))


def is_stale_ballroom_id(meeting_id: str) -> bool:
    return meeting_id_token(meeting_id) in STALE_BALLROOM_IDS


def is_promoted_ballroom_id(meeting_id: str) -> bool:
    mid = meeting_id_token(meeting_id)
    return bool(mid) and any(mid.startswith(prefix) for prefix in BALLROOM_PROMOTED_PREFIXES)


def is_ballroom_name(name: str) -> bool:
    return compact_name(name) in {"ballroom", "ballroomwtf"}


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
    extra_id = meeting_id_token(str(raw.get("id") or ""))
    if extra_id:
        meeting_ids.append(extra_id)
    meeting_ids = [m for m in meeting_ids if 9 <= len(m) <= 12]
    never_ids = [
        re.sub(r"\D", "", item)
        for item in _listish(raw.get("never_ids") or raw.get("stale_ids"))
    ]
    never_ids = [m for m in never_ids if 9 <= len(m) <= 12]
    never_ids = sorted(set(never_ids) | set(STALE_BALLROOM_IDS))
    meeting_ids = [m for m in meeting_ids if m not in never_ids and not is_stale_ballroom_id(m)]
    name = str(name).strip()
    for mid in list(meeting_ids):
        if is_promoted_ballroom_id(mid):
            name = "Ballroom"
            if not website:
                website = "https://ballroom.wtf"
    meeting_ids = [m for m in dict.fromkeys(meeting_ids) if m not in never_ids]
    if not str(name).strip() and website:
        name = str(website)
    room = {
        "id": str(raw.get("id") if raw.get("id") and not looks_like_meeting_id(str(raw.get("id"))) else "") 
        or compact_name(str(name)) 
        or f"room-{index}",
        "name": str(name).strip(),
        "website": str(website).strip(),
        "aliases": aliases,
        "meeting_ids": meeting_ids,
        "never_ids": sorted(set(never_ids)),
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
            if looks_like_meeting_id(str(name)):
                mid = meeting_id_token(str(name))
                if isinstance(value, dict):
                    payload = {"meeting_ids": [mid], **value}
                    if not payload.get("name"):
                        payload["name"] = "Room"
                else:
                    payload = {"name": str(value), "meeting_ids": [mid]}
            elif isinstance(value, dict):
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
        return finalize_key_rooms([room for room in rooms if room.get("name")])
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
                if len(bits) >= 2 and looks_like_meeting_id(bits[0]):
                    parts = [bits[0], " ".join(bits[1:])]
                elif len(bits) >= 2 and "." in bits[-1] and not bits[-1].endswith("."):
                    parts = [" ".join(bits[:-1]), bits[-1]]
                else:
                    parts = [line]
        payload: dict[str, Any] = {}
        if parts and looks_like_meeting_id(parts[0]):
            payload = {
                "meeting_ids": [meeting_id_token(parts[0])],
                "name": " ".join(parts[1:]).strip() or parts[0],
            }
        elif len(parts) > 1 and looks_like_meeting_id(parts[1]) and "." not in parts[1]:
            payload = {
                "name": parts[0],
                "meeting_ids": [meeting_id_token(parts[1])],
                "website": parts[2] if len(parts) > 2 else "",
            }
        else:
            payload = {
                "name": parts[0] if parts else "",
                "website": parts[1] if len(parts) > 1 else "",
                "aliases": parts[2] if len(parts) > 2 else "",
            }
        room = _room_from_mapping(payload, index)
        if room["name"]:
            rooms.append(room)
    return finalize_key_rooms(rooms)


def finalize_key_rooms(rooms: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Drop 2060220206-as-Ballroom. The 973 number is Ballroom. Merge duplicates."""
    merged: dict[str, dict[str, Any]] = {}
    order: list[str] = []
    for room in rooms:
        mids = [m for m in (room.get("meeting_ids") or []) if not is_stale_ballroom_id(m)]
        name = room.get("name") or ""
        if is_ballroom_name(name) or any(is_promoted_ballroom_id(m) for m in mids):
            name = "Ballroom"
            if not room.get("website"):
                room = {**room, "website": "https://ballroom.wtf"}
        if is_stale_ballroom_id(name):
            continue
        if looks_like_meeting_id(name) and not mids:
            continue
        room = {
            **room,
            "name": name,
            "meeting_ids": mids,
            "never_ids": sorted(set(room.get("never_ids") or []) | set(STALE_BALLROOM_IDS)),
            "id": compact_name(name) or room.get("id") or "room",
        }
        key = compact_name(name) or room["id"]
        if key in merged:
            existing = merged[key]
            existing["meeting_ids"] = list(
                dict.fromkeys([*(existing.get("meeting_ids") or []), *mids])
            )
            existing["aliases"] = list(
                dict.fromkeys([*(existing.get("aliases") or []), *(room.get("aliases") or [])])
            )
            if not existing.get("website") and room.get("website"):
                existing["website"] = room["website"]
            existing["never_ids"] = sorted(
                set(existing.get("never_ids") or [])
                | set(room.get("never_ids") or [])
                | set(STALE_BALLROOM_IDS)
            )
            continue
        merged[key] = room
        order.append(key)
    return [merged[key] for key in order if merged[key].get("name")]


ROOMS_TXT_HEADER = """# ROOMS.txt — the directory remembers these names.
# One room per line: NUMBER    NAME
# If the matcher cannot find a name, the number shows up here alone.
# Type the name next to it, save, and the directory keeps that name.
#
"""


def parse_rooms_txt(source: Any) -> list[dict[str, str]]:
    """Parse ROOMS.txt (NUMBER then NAME). Name may be blank until you add it."""
    if source is None:
        return []
    if isinstance(source, Path):
        if not source.is_file():
            return []
        return parse_rooms_txt(source.read_text(encoding="utf-8", errors="replace"))
    if isinstance(source, (list, tuple)):
        out = []
        for item in source:
            if isinstance(item, dict):
                mid = meeting_id_token(str(item.get("meeting_id") or item.get("id") or item.get("number") or ""))
                name = str(item.get("name") or item.get("room") or "").strip()
                if mid:
                    out.append({"meeting_id": mid, "name": name})
            else:
                out.extend(parse_rooms_txt(str(item)))
        return out
    text = str(source)
    entries: list[dict[str, str]] = []
    seen: set[str] = set()
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "|" in line:
            parts = [p.strip() for p in line.split("|")]
        elif "\t" in line:
            parts = [p.strip() for p in line.split("\t") if p.strip()]
        else:
            parts = line.split(None, 1)
        if not parts:
            continue
        mid = meeting_id_token(parts[0]) if looks_like_meeting_id(parts[0]) else ""
        name = parts[1].strip() if len(parts) > 1 else ""
        if not mid and looks_like_meeting_id(name):
            mid = meeting_id_token(name)
            name = parts[0].strip()
        if not mid or mid in seen:
            continue
        if is_stale_ballroom_id(mid) and is_ballroom_name(name):
            name = ""
        seen.add(mid)
        entries.append({"meeting_id": mid, "name": name})
    return entries


def remembered_name(meeting_id: str, memory: list[dict[str, str]]) -> str:
    mid = meeting_id_token(meeting_id)
    for entry in memory:
        if entry["meeting_id"] == mid:
            return entry.get("name") or ""
    return ""


def merge_rooms_txt_into_key(rooms: list[dict[str, Any]], memory: list[dict[str, str]]) -> list[dict[str, Any]]:
    rooms = list(rooms)
    by_name = {compact_name(room.get("name") or ""): room for room in rooms if room.get("name")}
    for entry in memory:
        mid = entry["meeting_id"]
        name = entry.get("name") or ""
        if is_promoted_ballroom_id(mid) and not name:
            name = "Ballroom"
        if not name:
            continue
        if is_stale_ballroom_id(mid) and is_ballroom_name(name):
            continue
        if is_promoted_ballroom_id(mid):
            name = "Ballroom"
        key = compact_name(name)
        if key in by_name:
            ids = by_name[key].setdefault("meeting_ids", [])
            if mid not in ids and not is_stale_ballroom_id(mid):
                ids.append(mid)
            continue
        payload = {"name": name, "meeting_ids": [mid]}
        if is_ballroom_name(name):
            payload["website"] = "https://ballroom.wtf"
        room = _room_from_mapping(payload, len(rooms))
        rooms.append(room)
        by_name[compact_name(room["name"]) or room["id"]] = room
    return finalize_key_rooms(rooms)


def format_rooms_txt(memory: list[dict[str, str]], extra_ids: Iterable[str] | None = None) -> str:
    by_id: dict[str, str] = {}
    order: list[str] = []
    for entry in memory:
        mid = entry["meeting_id"]
        if mid in by_id:
            if entry.get("name") and not by_id[mid]:
                by_id[mid] = entry["name"]
            continue
        by_id[mid] = entry.get("name") or ""
        order.append(mid)
    for raw in extra_ids or []:
        mid = meeting_id_token(str(raw))
        if not mid or mid in by_id:
            continue
        by_id[mid] = "Ballroom" if is_promoted_ballroom_id(mid) else ""
        if is_stale_ballroom_id(mid) and by_id[mid] == "Ballroom":
            by_id[mid] = ""
        order.append(mid)
    lines = [ROOMS_TXT_HEADER.rstrip(), ""]
    named = [mid for mid in order if by_id[mid]]
    unnamed = [mid for mid in order if not by_id[mid]]
    for mid in named:
        lines.append(f"{mid}    {by_id[mid]}")
    if unnamed:
        if named:
            lines.append("")
        lines.append("# Numbers with no name yet — add the name after the number:")
        for mid in unnamed:
            lines.append(mid)
    lines.append("")
    return "\n".join(lines)


def write_rooms_txt(path: Path, memory: list[dict[str, str]], extra_ids: Iterable[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    existing = parse_rooms_txt(path) if path.is_file() else []
    by_id = {entry["meeting_id"]: entry.get("name") or "" for entry in existing}
    order = [entry["meeting_id"] for entry in existing]
    for entry in memory:
        mid = entry["meeting_id"]
        if mid not in by_id:
            by_id[mid] = entry.get("name") or ""
            order.append(mid)
        elif entry.get("name") and not by_id[mid]:
            by_id[mid] = entry["name"]
    merged = [{"meeting_id": mid, "name": by_id[mid]} for mid in order]
    path.write_text(format_rooms_txt(merged, extra_ids), encoding="utf-8")


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
    if meeting and is_stale_ballroom_id(meeting) and is_ballroom_name(name):
        pass
    elif meeting and is_promoted_ballroom_id(meeting) and is_ballroom_name(name):
        score = max(score, PROMOTED_ID_SCORE)
        clues.append("promoted_id")
    elif meeting and meeting in set(room.get("meeting_ids") or []) and meeting not in set(room.get("never_ids") or []):
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
    rooms_txt: Any = None,
    generated_at: str | None = None,
) -> dict[str, Any]:
    memory = parse_rooms_txt(rooms_txt)
    rooms = merge_rooms_txt_into_key(parse_key(key), memory)
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
        join_mid = extract_meeting_id(join_url) or extract_meeting_id(text)
        room, score, clues = best_room_for_post(text, rooms)
        if join_mid and is_promoted_ballroom_id(join_mid):
            ballroom = next((item for item in rooms if is_ballroom_name(item.get("name") or "")), None)
            if ballroom is None:
                ballroom = {
                    "id": "ballroom",
                    "name": "Ballroom",
                    "website": "https://ballroom.wtf",
                    "aliases": [],
                    "meeting_ids": [join_mid],
                    "never_ids": sorted(STALE_BALLROOM_IDS),
                }
                rooms.append(ballroom)
                by_id[ballroom["id"]] = {
                    "id": ballroom["id"],
                    "name": ballroom["name"],
                    "website": _canonical_website(ballroom),
                    "status": "closed",
                    "join_url": None,
                    "room_number": None,
                    "matched_by": [],
                    "score": 0,
                    "last_seen": None,
                    "source": None,
                    "excerpt": None,
                }
            room = ballroom
            score = max(score, PROMOTED_ID_SCORE)
            clues = sorted(set(list(clues) + ["promoted_id"]))
        if room and is_ballroom_name(room.get("name") or "") and is_stale_ballroom_id(join_mid):
            unmatched.append(
                {
                    "join_url": join_url,
                    "room_number": join_mid or None,
                    "excerpt": _excerpt(text, join_url),
                    "source": post.get("source") or None,
                    "ts": post.get("ts") or None,
                    "reason": "stale id 2060220206 is not Ballroom",
                }
            )
            continue
        excerpt = _excerpt(text, join_url)
        ts = post.get("ts") or ""
        if room is None:
            remembered = remembered_name(join_mid, memory)
            if remembered:
                room = next(
                    (
                        item
                        for item in rooms
                        if compact_name(item.get("name") or "") == compact_name(remembered)
                    ),
                    None,
                )
                score = ROOMS_TXT_SCORE
                clues = ["rooms_txt"]
        if room is None:
            unmatched.append(
                {
                    "join_url": join_url,
                    "room_number": join_mid or extract_meeting_id(join_url) or extract_meeting_id(text) or None,
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
            "needs_name": False,
        }
        directory_rooms.append(public)

    seen_ids = {r.get("room_number") for r in directory_rooms if r.get("room_number")}
    for item in unmatched:
        mid = item.get("room_number")
        if not mid or mid in seen_ids:
            continue
        remembered = remembered_name(mid, memory)
        if remembered:
            continue
        if is_stale_ballroom_id(mid):
            continue
        directory_rooms.append(
            {
                "id": f"unknown-{mid}",
                "name": "",
                "website": None,
                "status": "open" if item.get("join_url") else "closed",
                "join_url": item.get("join_url"),
                "room_number": mid,
                "matched_by": [],
                "last_seen": item.get("ts"),
                "source": item.get("source"),
                "needs_name": True,
            }
        )
        seen_ids.add(mid)
    for entry in memory:
        mid = entry["meeting_id"]
        if mid in seen_ids or entry.get("name"):
            continue
        directory_rooms.append(
            {
                "id": f"unknown-{mid}",
                "name": "",
                "website": None,
                "status": "closed",
                "join_url": None,
                "room_number": mid,
                "matched_by": [],
                "last_seen": None,
                "source": "ROOMS.txt",
                "needs_name": True,
            }
        )
        seen_ids.add(mid)

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
    found = {"key": None, "posts": None, "rooms_txt": None}
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
        if found["rooms_txt"] is None and name in ROOMS_TXT_NAMES:
            found["rooms_txt"] = path
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
