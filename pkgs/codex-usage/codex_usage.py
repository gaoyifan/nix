#!/usr/bin/env python3

import argparse
import json
import os
import sys
from collections import defaultdict
from datetime import datetime, time, timedelta, timezone
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


VERSION = "2"
PRICE_DATE = "2026-08-30"
LONG_CONTEXT_THRESHOLD = 272_000
FAST_MULTIPLIER = 2.5
PRICES = {
    "gpt-5.6-sol": (4.0, 0.4, 20.0),
    "gpt-5.6-luna": (0.2, 0.02, 1.2),
}
USAGE_FIELDS = (
    "input_tokens",
    "cached_input_tokens",
    "cache_write_input_tokens",
    "output_tokens",
    "reasoning_output_tokens",
    "total_tokens",
)
INJECTED_PROMPT_PREFIXES = (
    "# AGENTS.md instructions",
    "<environment_context>",
    "<codex_internal_context",
)


def new_stats():
    return {
        "requests": 0,
        "cached": 0,
        "cache_write": 0,
        "billable_input": 0,
        "output": 0,
        "reasoning": 0,
        "tokens": 0,
        "cost": 0.0,
    }


def add_usage(stats, usage, cost):
    input_tokens = usage.get("input_tokens", 0)
    cached_tokens = usage.get("cached_input_tokens", 0)
    cache_write_tokens = usage.get("cache_write_input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)

    stats["requests"] += 1
    stats["cached"] += cached_tokens
    stats["cache_write"] += cache_write_tokens
    stats["billable_input"] += input_tokens - cached_tokens - cache_write_tokens
    stats["output"] += output_tokens
    stats["reasoning"] += usage.get("reasoning_output_tokens", 0)
    stats["tokens"] += input_tokens + output_tokens
    stats["cost"] += cost


def request_cost(model, tier, usage):
    prices = PRICES.get(model)
    if prices is None:
        return None

    input_price, cached_price, output_price = prices
    input_tokens = usage.get("input_tokens", 0)
    cached_tokens = usage.get("cached_input_tokens", 0)
    cache_write_tokens = usage.get("cache_write_input_tokens", 0)
    billable_input_tokens = input_tokens - cached_tokens - cache_write_tokens

    if input_tokens > LONG_CONTEXT_THRESHOLD:
        input_price *= 2
        cached_price *= 2
        output_price *= 1.5

    multiplier = FAST_MULTIPLIER if tier == "priority" else 1
    return (
        multiplier
        * (
            billable_input_tokens * input_price
            + cached_tokens * cached_price
            + usage.get("output_tokens", 0) * output_price
        )
        / 1_000_000
    )


def parse_timestamp(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def content_text(item):
    if not isinstance(item, dict):
        return ""
    if item.get("type") in ("input_text", "text"):
        return item.get("text", "")
    if item.get("type") in ("input_image", "image", "image_url"):
        return "[image]"
    if item.get("type") in ("input_audio", "audio"):
        return "[audio]"
    return ""


def response_user_prompt(payload):
    content = payload.get("content") or []
    metadata = payload.get("internal_chat_message_metadata_passthrough") or {}
    kinds = metadata.get("content_item_kinds")

    if kinds:
        parts = [
            content_text(item)
            for item, kind in zip(content, kinds)
            if isinstance(kind, str) and kind.startswith("user.")
        ]
        text = "\n".join(part for part in parts if part).strip()
        return (text, False) if text else (None, False)

    text = "\n".join(content_text(item) for item in content).strip()
    if not text or text.lstrip().startswith(INJECTED_PROMPT_PREFIXES):
        return None, True
    return text, True


def event_user_prompt(payload):
    message = payload.get("message")
    if isinstance(message, str) and message.strip():
        return message.strip()
    if payload.get("images"):
        return "[image]"
    return None


def analyze(sessions_dir, start, end, local_timezone):
    daily = defaultdict(new_stats)
    total = new_stats()
    long_context = new_stats()
    fast = new_stats()
    long_fast = new_stats()
    assumed_standard_tier = 0
    unpriced_models = defaultdict(int)
    sessions = defaultdict(lambda: {"stats": new_stats(), "rollouts": set()})
    prompts = {}

    for path in sessions_dir.rglob("*.jsonl"):
        model = None
        tier = None
        previous_total = None
        root_session_id = None
        thread_id = None
        is_root_thread = False
        saw_session_meta = False

        try:
            lines = path.open(encoding="utf-8")
        except OSError:
            continue

        with lines:
            for line in lines:
                if not any(
                    marker in line
                    for marker in (
                        "session_meta",
                        "thread_settings_applied",
                        "turn_context",
                        "token_count",
                        "user_message",
                        '"role":"user"',
                        '"role": "user"',
                    )
                ):
                    continue

                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue

                event_type = event.get("type")
                payload = event.get("payload") or {}

                if event_type == "session_meta" and not saw_session_meta:
                    saw_session_meta = True
                    thread_id = payload.get("id")
                    root_session_id = payload.get("session_id") or thread_id
                    is_root_thread = payload.get("thread_source") == "user" or thread_id == root_session_id
                    continue

                if event_type == "event_msg" and payload.get("type") == "thread_settings_applied":
                    settings = payload.get("thread_settings") or {}
                    model = settings.get("model") or model
                    tier = settings.get("service_tier") or tier
                    continue

                if event_type == "turn_context":
                    model = payload.get("model") or model
                    tier = payload.get("service_tier") or tier
                    continue

                prompt = None
                uncertain_prompt = False
                if is_root_thread and event_type == "event_msg" and payload.get("type") == "user_message":
                    prompt = event_user_prompt(payload)
                elif (
                    is_root_thread
                    and event_type == "response_item"
                    and payload.get("type") == "message"
                    and payload.get("role") == "user"
                ):
                    prompt, uncertain_prompt = response_user_prompt(payload)

                if prompt:
                    try:
                        prompt_timestamp = parse_timestamp(event["timestamp"])
                    except (KeyError, TypeError, ValueError):
                        pass
                    else:
                        candidate = (prompt_timestamp, prompt, uncertain_prompt)
                        current = prompts.get(root_session_id)
                        if (
                            current is None
                            or candidate[0] < current[0]
                            or (candidate[0] == current[0] and current[2] and not candidate[2])
                        ):
                            prompts[root_session_id] = candidate

                if event_type != "event_msg" or payload.get("type") != "token_count":
                    continue

                info = payload.get("info")
                if not info:
                    continue

                cumulative = info.get("total_token_usage")
                if not cumulative:
                    continue

                cumulative_vector = tuple(cumulative.get(field, 0) for field in USAGE_FIELDS)
                if cumulative_vector == previous_total:
                    continue
                previous_total = cumulative_vector

                usage = info.get("last_token_usage")
                if not usage:
                    continue

                if not any(usage.get(field, 0) for field in USAGE_FIELDS[:-1]):
                    continue

                try:
                    timestamp = parse_timestamp(event["timestamp"])
                except (KeyError, TypeError, ValueError):
                    continue

                if not start <= timestamp < end:
                    continue

                cost = request_cost(model, tier, usage)
                if cost is None:
                    unpriced_models[model or "unknown"] += 1
                    cost = 0

                local_date = timestamp.astimezone(local_timezone).date()
                add_usage(daily[local_date], usage, cost)
                add_usage(total, usage, cost)
                if root_session_id:
                    add_usage(sessions[root_session_id]["stats"], usage, cost)
                    sessions[root_session_id]["rollouts"].add(thread_id)

                is_long = usage.get("input_tokens", 0) > LONG_CONTEXT_THRESHOLD
                is_fast = tier == "priority"
                if is_long:
                    add_usage(long_context, usage, cost)
                if is_fast:
                    add_usage(fast, usage, cost)
                if is_long and is_fast:
                    add_usage(long_fast, usage, cost)
                if tier is None:
                    assumed_standard_tier += 1

    return {
        "daily": daily,
        "total": total,
        "long": long_context,
        "fast": fast,
        "long_fast": long_fast,
        "assumed_standard_tier": assumed_standard_tier,
        "unpriced_models": unpriced_models,
        "sessions": sessions,
        "prompts": prompts,
    }


def format_millions(value):
    return f"{value / 1_000_000:,.3f}M"


def percentage(part, whole):
    return 0 if whole == 0 else 100 * part / whole


def truncate_prompt(prompt, length=180):
    normalized = " ".join(prompt.split())
    return normalized if len(normalized) <= length else normalized[: length - 3] + "..."


def print_top_sessions(result, count):
    if count == 0:
        return

    ranked = sorted(
        result["sessions"].items(),
        key=lambda item: item[1]["stats"]["tokens"],
        reverse=True,
    )[:count]
    print()
    print(f"Top {len(ranked)} sessions by tokens")
    for rank, (session_id, session) in enumerate(ranked, 1):
        stats = session["stats"]
        print(
            f"{rank:>2}. {session_id}  {stats['requests']:,} requests  "
            f"{len(session['rollouts']):,} rollouts  {format_millions(stats['tokens'])}  "
            f"${stats['cost']:,.2f}"
        )
        candidate = result["prompts"].get(session_id)
        if candidate:
            _, prompt, uncertain = candidate
            suffix = " [heuristic]" if uncertain else ""
            print(f"    First prompt{suffix}: {truncate_prompt(prompt)}")
        else:
            print("    First prompt: [not found]")


def print_report(result, first_date, last_date, timezone_name, sessions_dir, top_sessions):
    total = result["total"]
    print(f"Codex usage ({first_date} through {last_date}, {timezone_name})")
    print(f"Source: {sessions_dir}")
    print()
    print(f"{'Date':<10} {'Requests':>9} {'Billable':>12} {'Cached':>13} {'Output':>11} {'Total':>13} {'USD':>10}")
    for day in (first_date + timedelta(days=offset) for offset in range((last_date - first_date).days + 1)):
        stats = result["daily"][day]
        print(
            f"{day.isoformat():<10} {stats['requests']:>9,} "
            f"{format_millions(stats['billable_input']):>12} "
            f"{format_millions(stats['cached']):>13} "
            f"{format_millions(stats['output']):>11} "
            f"{format_millions(stats['tokens']):>13} "
            f"${stats['cost']:>9,.2f}"
        )
    print(
        f"{'Total':<10} {total['requests']:>9,} "
        f"{format_millions(total['billable_input']):>12} "
        f"{format_millions(total['cached']):>13} "
        f"{format_millions(total['output']):>11} "
        f"{format_millions(total['tokens']):>13} "
        f"${total['cost']:>9,.2f}"
    )
    print()

    for label, key in (("Input >272K", "long"), ("Fast", "fast")):
        stats = result[key]
        print(
            f"{label}: {stats['requests']:,} requests "
            f"({percentage(stats['requests'], total['requests']):.2f}%), "
            f"${stats['cost']:,.2f} "
            f"({percentage(stats['cost'], total['cost']):.2f}% of USD equivalent)"
        )
    print(f"Input >272K and Fast: {result['long_fast']['requests']:,} requests")
    print(f"Reasoning output (included in output): {format_millions(total['reasoning'])}")
    if total["cache_write"]:
        cache_write = (
            format_millions(total["cache_write"]) if total["cache_write"] >= 1_000_000 else f"{total['cache_write']:,}"
        )
        print(f"Cache-write input (free under Codex pricing): {cache_write}")

    if result["assumed_standard_tier"]:
        print(f"Note: {result['assumed_standard_tier']:,} requests had no service tier; priced as Standard.")
    if result["unpriced_models"]:
        models = ", ".join(f"{model} ({count:,})" for model, count in sorted(result["unpriced_models"].items()))
        print(f"Warning: USD total excludes unpriced models: {models}", file=sys.stderr)
    print(f"USD uses official prices as of {PRICE_DATE}; it is a token-price equivalent, not the subscription bill.")
    print_top_sessions(result, top_sessions)


def main(argv=None):
    default_codex_home = Path(os.environ.get("CODEX_HOME", "~/.syncd-dotfiles/.codex")).expanduser()
    parser = argparse.ArgumentParser(
        description="Summarize recent Codex JSONL token usage and its official USD equivalent."
    )
    parser.add_argument("--version", action="version", version=f"codex-usage {VERSION}")
    parser.add_argument(
        "--sessions-dir",
        type=Path,
        default=default_codex_home / "sessions",
        help="Codex sessions directory (default: $CODEX_HOME/sessions)",
    )
    parser.add_argument("--days", type=int, default=7, help="number of local calendar days (default: 7)")
    parser.add_argument(
        "--top-sessions",
        type=int,
        default=10,
        help="number of highest-token root sessions to show; 0 disables the section (default: 10)",
    )
    parser.add_argument(
        "--timezone",
        default=os.environ.get("TZ", "Asia/Singapore"),
        help="IANA timezone used to group requests by date (default: Asia/Singapore)",
    )
    args = parser.parse_args(argv)

    if args.days < 1:
        parser.error("--days must be at least 1")
    if args.top_sessions < 0:
        parser.error("--top-sessions must be at least 0")
    sessions_dir = args.sessions_dir.expanduser()
    if not sessions_dir.is_dir():
        parser.error(f"sessions directory does not exist: {sessions_dir}")
    try:
        local_timezone = ZoneInfo(args.timezone)
    except ZoneInfoNotFoundError:
        parser.error(f"unknown timezone: {args.timezone}")

    now = datetime.now(timezone.utc)
    local_today = now.astimezone(local_timezone).date()
    first_date = local_today - timedelta(days=args.days - 1)
    start = datetime.combine(first_date, time.min, local_timezone).astimezone(timezone.utc)
    result = analyze(sessions_dir, start, now, local_timezone)
    print_report(result, first_date, local_today, args.timezone, sessions_dir, args.top_sessions)


if __name__ == "__main__":
    main()
