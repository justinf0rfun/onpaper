import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "codex_app_server_text_turn_spike.py"
SPEC = importlib.util.spec_from_file_location("codex_app_server_text_turn_spike", SCRIPT_PATH)
spike = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(spike)


class CodexAppServerTextTurnSpikeTests(unittest.TestCase):
    def test_load_thread_id_from_selection_file_requires_matching_fingerprint(self):
        thread_id = "thread-1"
        payload = {
            "threads": [
                {
                    "index": 2,
                    "id": thread_id,
                    "idFingerprint": spike.stable_fingerprint(thread_id),
                }
            ]
        }

        with tempfile.TemporaryDirectory() as directory:
            selection_file = Path(directory) / "selection.json"
            selection_file.write_text(json.dumps(payload))

            selected = spike.load_thread_id_from_selection_file(
                str(selection_file),
                2,
                spike.stable_fingerprint(thread_id),
            )

        self.assertEqual(selected, thread_id)

    def test_load_thread_id_from_selection_file_rejects_mismatched_fingerprint(self):
        payload = {
            "threads": [
                {
                    "index": 0,
                    "id": "thread-1",
                    "idFingerprint": spike.stable_fingerprint("thread-1"),
                }
            ]
        }

        with tempfile.TemporaryDirectory() as directory:
            selection_file = Path(directory) / "selection.json"
            selection_file.write_text(json.dumps(payload))

            with self.assertRaises(spike.AppServerError):
                spike.load_thread_id_from_selection_file(str(selection_file), 0, "wrong")

    def test_notification_filter_rejects_other_thread(self):
        notification = {
            "method": "turn/completed",
            "params": {
                "threadId": "thread-2",
                "turn": {"id": "turn-1"},
            },
        }

        self.assertFalse(spike.notification_matches_target(notification, "thread-1", "turn-1"))

    def test_notification_filter_rejects_known_different_turn(self):
        notification = {
            "method": "turn/completed",
            "params": {
                "threadId": "thread-1",
                "turn": {"id": "turn-2"},
            },
        }

        self.assertFalse(spike.notification_matches_target(notification, "thread-1", "turn-1"))

    def test_notification_filter_rejects_non_lifecycle_notification(self):
        notification = {
            "method": "remoteControl/status/changed",
            "params": {},
        }

        self.assertFalse(spike.notification_matches_target(notification, "thread-1", None))

    def test_redaction_omits_identifier_prefixes(self):
        redacted = spike.redact_json(
            {
                "threadId": "thread-1",
                "clientUserMessageId": "message-1",
                "input": [{"type": "text", "text": "private"}],
            }
        )

        self.assertNotIn("prefix", redacted["threadId"])
        self.assertNotIn("prefix", redacted["clientUserMessageId"])
        self.assertEqual(redacted["input"][0]["text"], "[redacted]")

    def test_redaction_replaces_uuid_inside_error_message(self):
        redacted = spike.redact_json(
            {
                "message": "thread not found: 11111111-2222-3333-4444-555555555555",
            }
        )

        self.assertEqual(redacted["message"], "thread not found: [redacted-id]")

    def test_redacted_thread_list_includes_index_without_raw_id(self):
        redacted = spike.redact_threads([{"id": "thread-1", "name": "private"}])

        self.assertEqual(redacted[0]["index"], 0)
        self.assertEqual(redacted[0]["idFingerprint"], spike.stable_fingerprint("thread-1"))
        self.assertNotIn("id", redacted[0])
        self.assertNotIn("idPrefix", redacted[0])
        self.assertNotIn("name", redacted[0])


if __name__ == "__main__":
    unittest.main()
