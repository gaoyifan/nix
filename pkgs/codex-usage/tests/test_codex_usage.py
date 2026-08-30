import json
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from datetime import datetime, timezone
from pathlib import Path
from zoneinfo import ZoneInfo


sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import codex_usage


def event(timestamp, payload, event_type="event_msg"):
    return json.dumps({"timestamp": timestamp, "type": event_type, "payload": payload})


def usage(input_tokens, cached_tokens, output_tokens, cache_write_tokens=0):
    return {
        "input_tokens": input_tokens,
        "cached_input_tokens": cached_tokens,
        "cache_write_input_tokens": cache_write_tokens,
        "output_tokens": output_tokens,
        "reasoning_output_tokens": 0,
        "total_tokens": input_tokens + output_tokens,
    }


class AnalyzeTest(unittest.TestCase):
    def test_deduplicates_notifications_and_prices_long_fast_requests(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "2026" / "08" / "01" / "rollout.jsonl"
            path.parent.mkdir(parents=True)
            first = usage(100, 20, 10)
            second = usage(300_000, 200_000, 1_000)
            cumulative_first = first
            cumulative_second = {field: first[field] + second[field] for field in codex_usage.USAGE_FIELDS}
            path.write_text(
                "\n".join(
                    [
                        event(
                            "2026-08-23T23:59:57Z",
                            {
                                "id": "root-session",
                                "session_id": "root-session",
                                "thread_source": "user",
                            },
                            "session_meta",
                        ),
                        event(
                            "2026-08-23T23:59:58Z",
                            {
                                "type": "message",
                                "role": "user",
                                "content": [{"type": "input_text", "text": "injected"}],
                                "internal_chat_message_metadata_passthrough": {
                                    "content_item_kinds": ["agents_md.instructions"]
                                },
                            },
                            "response_item",
                        ),
                        event(
                            "2026-08-23T23:59:59Z",
                            {
                                "type": "message",
                                "role": "user",
                                "content": [{"type": "input_text", "text": "Real task"}],
                                "internal_chat_message_metadata_passthrough": {"content_item_kinds": ["user.text"]},
                            },
                            "response_item",
                        ),
                        event(
                            "2026-08-24T00:00:00Z",
                            {"model": "gpt-5.6-sol"},
                            "turn_context",
                        ),
                        event(
                            "2026-08-24T00:00:01Z",
                            {
                                "type": "token_count",
                                "info": {
                                    "last_token_usage": first,
                                    "total_token_usage": cumulative_first,
                                },
                            },
                        ),
                        event(
                            "2026-08-24T00:00:02Z",
                            {
                                "type": "token_count",
                                "info": {
                                    "last_token_usage": first,
                                    "total_token_usage": cumulative_first,
                                },
                            },
                        ),
                        event(
                            "2026-08-24T00:00:03Z",
                            {
                                "type": "thread_settings_applied",
                                "thread_settings": {
                                    "model": "gpt-5.6-sol",
                                    "service_tier": "priority",
                                },
                            },
                        ),
                        event(
                            "2026-08-24T00:00:04Z",
                            {
                                "type": "token_count",
                                "info": {
                                    "last_token_usage": second,
                                    "total_token_usage": cumulative_second,
                                },
                            },
                        ),
                    ]
                )
                + "\n"
            )
            child_path = path.with_name("subagent.jsonl")
            child_usage = usage(50, 10, 5, cache_write_tokens=20)
            child_path.write_text(
                "\n".join(
                    [
                        event(
                            "2026-08-23T23:59:55Z",
                            {
                                "id": "child-thread",
                                "session_id": "root-session",
                                "thread_source": "subagent",
                            },
                            "session_meta",
                        ),
                        event(
                            "2026-08-23T23:59:56Z",
                            {
                                "type": "message",
                                "role": "user",
                                "content": [{"type": "input_text", "text": "Copied parent history"}],
                                "internal_chat_message_metadata_passthrough": {"content_item_kinds": ["user.text"]},
                            },
                            "response_item",
                        ),
                        event(
                            "2026-08-24T00:00:00Z",
                            {"model": "gpt-5.6-sol"},
                            "turn_context",
                        ),
                        event(
                            "2026-08-24T00:00:01Z",
                            {
                                "type": "token_count",
                                "info": {
                                    "last_token_usage": child_usage,
                                    "total_token_usage": child_usage,
                                },
                            },
                        ),
                    ]
                )
                + "\n"
            )

            result = codex_usage.analyze(
                Path(directory),
                datetime(2026, 8, 23, tzinfo=timezone.utc),
                datetime(2026, 8, 25, tzinfo=timezone.utc),
                ZoneInfo("Asia/Singapore"),
            )

        self.assertEqual(result["total"]["requests"], 3)
        self.assertEqual(result["long"]["requests"], 1)
        self.assertEqual(result["fast"]["requests"], 1)
        self.assertEqual(result["long_fast"]["requests"], 1)
        self.assertAlmostEqual(result["total"]["cost"], 2.475712)
        self.assertEqual(result["total"]["billable_input"], 100_100)
        self.assertEqual(result["total"]["cached"], 200_030)
        self.assertEqual(result["total"]["cache_write"], 20)
        self.assertEqual(
            result["total"]["tokens"] - result["total"]["output"],
            result["total"]["billable_input"] + result["total"]["cached"] + result["total"]["cache_write"],
        )
        self.assertEqual(result["sessions"]["root-session"]["stats"]["tokens"], 301_165)
        self.assertEqual(len(result["sessions"]["root-session"]["rollouts"]), 2)
        self.assertEqual(result["prompts"]["root-session"][1], "Real task")
        self.assertFalse(result["prompts"]["root-session"][2])

        output = io.StringIO()
        with redirect_stdout(output):
            codex_usage.print_report(
                result,
                datetime(2026, 8, 24).date(),
                datetime(2026, 8, 24).date(),
                "Asia/Singapore",
                Path(directory),
                0,
            )
        self.assertIn("Cache-write input (free under Codex pricing): 20", output.getvalue())


if __name__ == "__main__":
    unittest.main()
