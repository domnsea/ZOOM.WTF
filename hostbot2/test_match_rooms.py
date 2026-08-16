#!/usr/bin/env python3
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "hostbot2"))

from match_rooms import (  # noqa: E402
    build_directory,
    extract_hosts,
    parse_key,
    parse_rooms_txt,
    write_rooms_txt,
)


KEY = {
    "rooms": [
        {
            "name": "Ballroom",
            "website": "https://ballroom.wtf",
            "aliases": ["BALLROOM", "Ballroom Zoom"],
        },
        {
            "name": "Palace",
            "website": "https://palace.party",
            "aliases": ["The Palace"],
        },
        {
            "name": "Circuit",
            "website": "",
            "aliases": ["circuit.room"],
        },
    ]
}


class ParseKeyTest(unittest.TestCase):
    def test_json_rooms(self):
        rooms = parse_key(KEY)
        self.assertEqual([r["name"] for r in rooms], ["Ballroom", "Palace", "Circuit"])
        self.assertEqual(rooms[0]["website"], "https://ballroom.wtf")

    def test_text_key_uses_names_already_on_the_key(self):
        rooms = parse_key(
            """
            Ballroom    ballroom.wtf
            Palace | palace.party | The Palace
            Circuit
            """
        )
        self.assertEqual([r["name"] for r in rooms], ["Ballroom", "Palace", "Circuit"])
        self.assertIn("palace.party", rooms[1]["website"])

    def test_name_then_website_on_one_line(self):
        rooms = parse_key("Ballroom ballroom.wtf\n")
        self.assertEqual(rooms[0]["name"], "Ballroom")
        self.assertEqual(rooms[0]["website"], "ballroom.wtf")


class WebsiteClueTest(unittest.TestCase):
    def test_website_in_post_is_the_room(self):
        directory = build_directory(
            KEY,
            [
                {
                    "text": "OPEN ballroom.wtf https://us02web.zoom.us/j/11122233344",
                    "ts": "2026-08-15T22:00:00Z",
                }
            ],
        )
        ballroom = next(r for r in directory["rooms"] if r["name"] == "Ballroom")
        palace = next(r for r in directory["rooms"] if r["name"] == "Palace")
        self.assertEqual(ballroom["status"], "open")
        self.assertEqual(ballroom["join_url"], "https://us02web.zoom.us/j/11122233344")
        self.assertIn("website", ballroom["matched_by"] + ["name_as_website"])
        self.assertEqual(palace["status"], "closed")
        self.assertIsNone(palace["join_url"])

    def test_room_name_as_website_without_key_url(self):
        directory = build_directory(
            KEY,
            [{"text": "circuit.room just opened https://zoom.us/j/99988877766"}],
        )
        circuit = next(r for r in directory["rooms"] if r["name"] == "Circuit")
        self.assertEqual(circuit["status"], "open")
        self.assertIn("name_as_website", circuit["matched_by"] + circuit.get("matched_by"))
        self.assertTrue(
            "name_as_website" in circuit["matched_by"] or "alias_website" in circuit["matched_by"]
        )

    def test_website_beats_a_name_mention_of_another_room(self):
        post = "Palace people heading to ballroom.wtf https://us02web.zoom.us/j/11122233344"
        directory = build_directory(KEY, [{"text": post}])
        ballroom = next(r for r in directory["rooms"] if r["name"] == "Ballroom")
        palace = next(r for r in directory["rooms"] if r["name"] == "Palace")
        self.assertEqual(ballroom["status"], "open")
        self.assertEqual(ballroom["room_number"], "11122233344")
        self.assertEqual(palace["status"], "closed")

    def test_https_www_and_path_still_count_as_the_room_site(self):
        post = "live https://www.ballroom.wtf/pages/zoom https://us02web.zoom.us/j/12345678901"
        directory = build_directory(KEY, [{"text": post}])
        ballroom = next(r for r in directory["rooms"] if r["name"] == "Ballroom")
        self.assertEqual(ballroom["status"], "open")
        self.assertEqual(ballroom["room_number"], "12345678901")

    def test_zoom_us_is_not_treated_as_a_room_website(self):
        hosts = extract_hosts("join https://us02web.zoom.us/j/12345678901 please")
        self.assertEqual(hosts, [])


class PhraseAndIdTest(unittest.TestCase):
    def test_room_name_phrase_when_no_website(self):
        directory = build_directory(
            KEY,
            [{"text": "Ballroom is open https://zoom.us/j/12312312312"}],
        )
        ballroom = next(r for r in directory["rooms"] if r["name"] == "Ballroom")
        self.assertEqual(ballroom["status"], "open")
        self.assertIn("name", ballroom["matched_by"])

    def test_known_meeting_id_from_key(self):
        key = {
            "rooms": [
                {"name": "Ballroom", "website": "ballroom.wtf", "meeting_ids": ["44455566677"]}
            ]
        }
        directory = build_directory(
            key,
            [{"text": "same room still up https://zoom.us/j/44455566677?pwd=x"}],
        )
        self.assertEqual(directory["rooms"][0]["status"], "open")
        self.assertIn("meeting_id", directory["rooms"][0]["matched_by"])

    def test_unmatched_zoom_link_does_not_invent_a_room(self):
        directory = build_directory(
            KEY,
            [{"text": "random lobby https://zoom.us/j/12121212121"}],
        )
        named = [r for r in directory["rooms"] if not r.get("needs_name")]
        unknown = [r for r in directory["rooms"] if r.get("needs_name")]
        self.assertTrue(all(r["status"] == "closed" for r in named))
        self.assertEqual([r["name"] for r in named], ["Ballroom", "Palace", "Circuit"])
        self.assertEqual(len(unknown), 1)
        self.assertEqual(unknown[0]["room_number"], "12121212121")
        self.assertEqual(len(directory["unmatched"]), 1)
        self.assertEqual(directory["unmatched"][0]["room_number"], "12121212121")

    def test_directory_always_lists_every_key_room(self):
        directory = build_directory(KEY, [])
        self.assertEqual([r["name"] for r in directory["rooms"]], ["Ballroom", "Palace", "Circuit"])
        self.assertEqual(directory["refresh_seconds"], 300)
        self.assertEqual(directory["source"], "HOSTBOT2")


class LaterPostWinsTest(unittest.TestCase):
    def test_newer_link_replaces_older_for_same_room(self):
        directory = build_directory(
            KEY,
            [
                {
                    "text": "ballroom.wtf https://zoom.us/j/11111111111",
                    "ts": "2026-08-15T20:00:00Z",
                },
                {
                    "text": "ballroom.wtf https://zoom.us/j/22222222222",
                    "ts": "2026-08-15T22:00:00Z",
                },
            ],
        )
        ballroom = next(r for r in directory["rooms"] if r["name"] == "Ballroom")
        self.assertEqual(ballroom["room_number"], "22222222222")


class PublishCliTest(unittest.TestCase):
    def test_publish_example_files(self):
        import subprocess

        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "zoom-directory.json"
            proc = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "hostbot2" / "publish_directory.py"),
                    "--key",
                    str(ROOT / "hostbot2" / "key.example.json"),
                    "--posts",
                    str(ROOT / "hostbot2" / "posts.example.json"),
                    "--out",
                    str(out),
                ],
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertIn("open=2", proc.stdout)
            data = json.loads(out.read_text())
            self.assertEqual(data["refresh_seconds"], 300)
            open_names = {r["name"] for r in data["rooms"] if r["status"] == "open"}
            self.assertEqual(open_names, {"Ballroom", "Example Palace"})


class BallroomIdentityTest(unittest.TestCase):
    def test_stale_2060220206_is_not_ballroom(self):
        rooms = parse_key("2060220206 BALLROOM\n")
        names = [r["name"] for r in rooms]
        self.assertIn("Ballroom", names)
        ballroom = next(r for r in rooms if r["name"] == "Ballroom")
        self.assertNotIn("2060220206", ballroom.get("meeting_ids") or [])
        self.assertNotEqual(ballroom["name"], "2060220206")
        directory = build_directory(
            "2060220206 BALLROOM\n",
            [{"text": "BALLROOM https://us02web.zoom.us/j/2060220206"}],
        )
        ballroom = next(r for r in directory["rooms"] if r["name"] == "Ballroom")
        self.assertNotEqual(ballroom.get("room_number"), "2060220206")
        self.assertIsNone(ballroom.get("join_url"))
        self.assertTrue(
            any(u.get("room_number") == "2060220206" for u in directory["unmatched"])
        )

    def test_973_number_is_ballroom(self):
        rooms = parse_key("97385123456 Palace\n")
        self.assertEqual([r["name"] for r in rooms], ["Ballroom"])
        self.assertIn("97385123456", rooms[0]["meeting_ids"])
        directory = build_directory(
            {"rooms": [{"name": "Palace", "website": "https://palace.party"}]},
            [{"text": "open https://us02web.zoom.us/j/97385123456"}],
        )
        ballroom = next(r for r in directory["rooms"] if r["name"] == "Ballroom")
        self.assertEqual(ballroom["status"], "open")
        self.assertEqual(ballroom["room_number"], "97385123456")
        self.assertIn("promoted_id", ballroom["matched_by"])

    def test_website_still_does_not_revive_stale_id(self):
        directory = build_directory(
            KEY,
            [{"text": "ballroom.wtf https://zoom.us/j/2060220206"}],
        )
        ballroom = next(r for r in directory["rooms"] if r["name"] == "Ballroom")
        self.assertNotEqual(ballroom.get("room_number"), "2060220206")
        self.assertIsNone(ballroom.get("join_url"))


class RoomsTxtTest(unittest.TestCase):
    def test_named_number_is_remembered(self):
        memory = "55566677788    Palace\n"
        directory = build_directory(
            KEY,
            [{"text": "live https://us02web.zoom.us/j/55566677788"}],
            rooms_txt=memory,
        )
        palace = next(r for r in directory["rooms"] if r["name"] == "Palace")
        self.assertEqual(palace["status"], "open")
        self.assertEqual(palace["room_number"], "55566677788")
        self.assertFalse(palace.get("needs_name"))

    def test_unknown_number_shows_until_named(self):
        directory = build_directory(
            KEY,
            [{"text": "https://zoom.us/j/12121212121"}],
            rooms_txt="# empty\n",
        )
        unknown = next(r for r in directory["rooms"] if r.get("needs_name"))
        self.assertEqual(unknown["room_number"], "12121212121")
        self.assertFalse(unknown.get("name"))

        named = build_directory(
            KEY,
            [{"text": "https://zoom.us/j/12121212121"}],
            rooms_txt="12121212121    Circuit\n",
        )
        circuit = next(r for r in named["rooms"] if r["name"] == "Circuit")
        self.assertEqual(circuit["status"], "open")
        self.assertEqual(circuit["room_number"], "12121212121")
        self.assertFalse(any(r.get("needs_name") and r.get("room_number") == "12121212121" for r in named["rooms"]))

    def test_write_rooms_txt_keeps_names_and_adds_unknowns(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "ROOMS.txt"
            path.write_text("55566677788    Palace\n", encoding="utf-8")
            write_rooms_txt(
                path,
                [{"meeting_id": "55566677788", "name": "Palace"}],
                extra_ids=["12121212121"],
            )
            text = path.read_text(encoding="utf-8")
            entries = parse_rooms_txt(text)
            by_id = {e["meeting_id"]: e["name"] for e in entries}
            self.assertEqual(by_id["55566677788"], "Palace")
            self.assertEqual(by_id["12121212121"], "")
            self.assertIn("12121212121", text)

    def test_rooms_txt_cannot_relabel_stale_id_as_ballroom(self):
        entries = parse_rooms_txt("2060220206    Ballroom\n")
        self.assertEqual(entries[0]["meeting_id"], "2060220206")
        self.assertEqual(entries[0]["name"], "")

    def test_multi_word_name_is_kept(self):
        entries = parse_rooms_txt("55566677788    The Grand Palace\n")
        self.assertEqual(entries[0]["name"], "The Grand Palace")

    def test_stale_id_does_not_show_as_needs_name(self):
        directory = build_directory(KEY, [{"text": "https://zoom.us/j/2060220206"}])
        self.assertFalse(any(r.get("room_number") == "2060220206" for r in directory["rooms"]))


if __name__ == "__main__":
    unittest.main()
