use std::collections::{BTreeMap, HashMap, HashSet};
use std::env;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::sync::LazyLock;
use std::time::SystemTime;

use aho_corasick::AhoCorasick;
use chrono::{DateTime, Days, NaiveDate, TimeZone, Utc};
use chrono_tz::Tz;
use clap::Parser;
use comfy_table::{Cell, CellAlignment, ContentArrangement, Row, Table, modifiers, presets};
use rayon::prelude::*;
use serde_json::Value;
use walkdir::WalkDir;

const PRICE_DATE: &str = "2026-09-09";
const FAST_MULTIPLIER: f64 = 2.5;
const INJECTED_PROMPT_PREFIXES: [&str; 3] = [
    "# AGENTS.md instructions",
    "<environment_context>",
    "<codex_internal_context",
];

static RELEVANT_MARKERS: LazyLock<AhoCorasick> = LazyLock::new(|| {
    AhoCorasick::new([
        "session_meta",
        "thread_settings_applied",
        "thread_goal_updated",
        "turn_context",
        "token_count",
        "user_message",
        "\"role\":\"user\"",
        "\"role\": \"user\"",
    ])
    .expect("static marker set is valid")
});

#[derive(Clone, Copy, Debug, Default, PartialEq)]
struct Stats {
    requests: u64,
    cached: u64,
    cache_write: u64,
    billable_input: i64,
    output: u64,
    reasoning: u64,
    tokens: u64,
    cost: f64,
}

impl Stats {
    fn add_usage(&mut self, usage: Usage, cost: f64) {
        self.requests += 1;
        self.cached += usage.cached_input_tokens;
        self.cache_write += usage.cache_write_input_tokens;
        self.billable_input += usage.input_tokens as i64
            - usage.cached_input_tokens as i64
            - usage.cache_write_input_tokens as i64;
        self.output += usage.output_tokens;
        self.reasoning += usage.reasoning_output_tokens;
        self.tokens += usage.input_tokens + usage.output_tokens;
        self.cost += cost;
    }

    fn merge(&mut self, other: Self) {
        self.requests += other.requests;
        self.cached += other.cached;
        self.cache_write += other.cache_write;
        self.billable_input += other.billable_input;
        self.output += other.output;
        self.reasoning += other.reasoning;
        self.tokens += other.tokens;
        self.cost += other.cost;
    }
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
struct Usage {
    input_tokens: u64,
    cached_input_tokens: u64,
    cache_write_input_tokens: u64,
    output_tokens: u64,
    reasoning_output_tokens: u64,
    total_tokens: u64,
}

impl Usage {
    fn from_value(value: &Value) -> Self {
        Self {
            input_tokens: uint(value, "input_tokens"),
            cached_input_tokens: uint(value, "cached_input_tokens"),
            cache_write_input_tokens: uint(value, "cache_write_input_tokens"),
            output_tokens: uint(value, "output_tokens"),
            reasoning_output_tokens: uint(value, "reasoning_output_tokens"),
            total_tokens: uint(value, "total_tokens"),
        }
    }

    fn has_usage(self) -> bool {
        self.input_tokens != 0
            || self.cached_input_tokens != 0
            || self.cache_write_input_tokens != 0
            || self.output_tokens != 0
            || self.reasoning_output_tokens != 0
    }

    fn vector(self) -> [u64; 6] {
        [
            self.input_tokens,
            self.cached_input_tokens,
            self.cache_write_input_tokens,
            self.output_tokens,
            self.reasoning_output_tokens,
            self.total_tokens,
        ]
    }
}

#[derive(Debug, Default)]
struct SessionStats {
    stats: Stats,
    threads: HashSet<Option<String>>,
}

#[derive(Debug)]
struct PromptCandidate {
    timestamp: DateTime<Utc>,
    prompt: String,
    uncertain: bool,
}

#[derive(Debug, Default)]
struct Analysis {
    daily: BTreeMap<NaiveDate, Stats>,
    fast: Stats,
    assumed_standard_tier: u64,
    unpriced_models: HashMap<String, u64>,
    sessions: HashMap<String, SessionStats>,
    prompts: HashMap<String, PromptCandidate>,
}

impl Analysis {
    fn total(&self) -> Stats {
        self.daily
            .values()
            .copied()
            .fold(Stats::default(), |mut total, stats| {
                total.merge(stats);
                total
            })
    }

    fn merge(&mut self, other: Self) {
        for (day, stats) in other.daily {
            self.daily.entry(day).or_default().merge(stats);
        }
        self.fast.merge(other.fast);
        self.assumed_standard_tier += other.assumed_standard_tier;

        for (model, count) in other.unpriced_models {
            *self.unpriced_models.entry(model).or_default() += count;
        }
        for (session_id, session) in other.sessions {
            let target = self.sessions.entry(session_id).or_default();
            target.stats.merge(session.stats);
            target.threads.extend(session.threads);
        }
        for (session_id, candidate) in other.prompts {
            self.consider_prompt(session_id, candidate);
        }
    }

    fn consider_prompt(&mut self, session_id: String, candidate: PromptCandidate) {
        let should_replace = self.prompts.get(&session_id).is_none_or(|current| {
            candidate.timestamp < current.timestamp
                || (candidate.timestamp == current.timestamp
                    && current.uncertain
                    && !candidate.uncertain)
        });
        if should_replace {
            self.prompts.insert(session_id, candidate);
        }
    }
}

#[derive(Debug, Parser)]
#[command(
    version,
    about = "Summarize recent Codex JSONL token usage and its official USD equivalent."
)]
struct Args {
    /// Codex sessions directory
    #[arg(long, value_name = "PATH", default_value_os_t = default_sessions_dir())]
    sessions_dir: PathBuf,

    /// Number of local calendar days
    #[arg(long, default_value_t = 7, value_parser = clap::value_parser!(u64).range(1..))]
    days: u64,

    /// Number of highest-token root sessions; 0 disables the section
    #[arg(long, default_value_t = 10)]
    top_sessions: usize,

    /// IANA timezone used to group requests by date
    #[arg(
        long,
        value_name = "ZONE",
        env = "TZ",
        default_value = "Asia/Singapore"
    )]
    timezone: Tz,
}

fn uint(value: &Value, field: &str) -> u64 {
    value.get(field).and_then(Value::as_u64).unwrap_or(0)
}

fn parse_timestamp(value: &Value) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(value.as_str()?)
        .ok()
        .map(|timestamp| timestamp.with_timezone(&Utc))
}

fn content_text(item: &Value) -> Option<&str> {
    match item.get("type").and_then(Value::as_str) {
        Some("input_text" | "text") => item.get("text").and_then(Value::as_str),
        Some("input_image" | "image" | "image_url") => Some("[image]"),
        Some("input_audio" | "audio") => Some("[audio]"),
        _ => None,
    }
}

fn response_user_prompt(payload: &Value) -> (Option<String>, bool) {
    let Some(content) = payload.get("content").and_then(Value::as_array) else {
        return (None, true);
    };
    let kinds = payload
        .get("internal_chat_message_metadata_passthrough")
        .and_then(|metadata| metadata.get("content_item_kinds"))
        .and_then(Value::as_array);

    if let Some(kinds) = kinds.filter(|kinds| !kinds.is_empty()) {
        let text = content
            .iter()
            .zip(kinds)
            .filter_map(|(item, kind)| {
                kind.as_str()
                    .filter(|kind| kind.starts_with("user."))
                    .and_then(|_| content_text(item))
            })
            .filter(|part| !part.is_empty())
            .collect::<Vec<_>>()
            .join("\n")
            .trim()
            .to_owned();
        return ((!text.is_empty()).then_some(text), false);
    }

    let text = content
        .iter()
        .filter_map(content_text)
        .collect::<Vec<_>>()
        .join("\n")
        .trim()
        .to_owned();
    if text.is_empty()
        || INJECTED_PROMPT_PREFIXES
            .iter()
            .any(|prefix| text.trim_start().starts_with(prefix))
    {
        (None, true)
    } else {
        (Some(text), true)
    }
}

fn event_user_prompt(payload: &Value) -> Option<String> {
    if let Some(message) = payload.get("message").and_then(Value::as_str) {
        let message = message.trim();
        if !message.is_empty() {
            return Some(message.to_owned());
        }
    }
    payload
        .get("images")
        .and_then(Value::as_array)
        .filter(|images| !images.is_empty())
        .map(|_| "[image]".to_owned())
}

fn request_cost(model: Option<&str>, tier: Option<&str>, usage: Usage) -> Option<f64> {
    let (input_price, cached_price, output_price) = match model? {
        "gpt-6-astra" => (10.0, 1.0, 50.0),
        "gpt-5.6-sol" => (4.0, 0.4, 20.0),
        "gpt-5.6-terra" => (2.0, 0.2, 12.0),
        "gpt-5.6-luna" => (0.2, 0.02, 1.2),
        _ => return None,
    };
    let billable_input = usage.input_tokens as i64
        - usage.cached_input_tokens as i64
        - usage.cache_write_input_tokens as i64;

    let multiplier = if tier == Some("priority") {
        FAST_MULTIPLIER
    } else {
        1.0
    };
    Some(
        multiplier
            * (billable_input as f64 * input_price
                + usage.cached_input_tokens as f64 * cached_price
                + usage.output_tokens as f64 * output_price)
            / 1_000_000.0,
    )
}

fn analyze_file(path: &Path, start: DateTime<Utc>, end: DateTime<Utc>, timezone: Tz) -> Analysis {
    let Ok(file) = File::open(path) else {
        return Analysis::default();
    };
    let mut result = Analysis::default();
    let mut reader = BufReader::with_capacity(128 * 1024, file);
    let mut line = Vec::with_capacity(4096);
    let mut model: Option<String> = None;
    let mut tier: Option<String> = None;
    let mut previous_total: Option<[u64; 6]> = None;
    let mut root_session_id: Option<String> = None;
    let mut thread_id: Option<String> = None;
    let mut is_root_thread = false;
    let mut saw_session_meta = false;

    loop {
        line.clear();
        match reader.read_until(b'\n', &mut line) {
            Ok(0) | Err(_) => break,
            Ok(_) => {}
        }
        if !RELEVANT_MARKERS.is_match(&line) {
            continue;
        }
        let Ok(event) = serde_json::from_slice::<Value>(&line) else {
            continue;
        };
        let event_type = event.get("type").and_then(Value::as_str);
        let payload = event.get("payload").unwrap_or(&Value::Null);

        if event_type == Some("session_meta") && !saw_session_meta {
            saw_session_meta = true;
            thread_id = payload.get("id").and_then(Value::as_str).map(str::to_owned);
            root_session_id = payload
                .get("session_id")
                .and_then(Value::as_str)
                .map(str::to_owned)
                .or_else(|| thread_id.clone());
            is_root_thread = payload.get("thread_source").and_then(Value::as_str) == Some("user")
                || thread_id == root_session_id;
            continue;
        }

        let payload_type = payload.get("type").and_then(Value::as_str);
        if event_type == Some("event_msg") && payload_type == Some("thread_settings_applied") {
            if let Some(settings) = payload.get("thread_settings") {
                if let Some(value) = settings.get("model").and_then(Value::as_str) {
                    model = Some(value.to_owned());
                }
                if let Some(value) = settings.get("service_tier").and_then(Value::as_str) {
                    tier = Some(value.to_owned());
                }
            }
            continue;
        }
        if event_type == Some("turn_context") {
            if let Some(value) = payload.get("model").and_then(Value::as_str) {
                model = Some(value.to_owned());
            }
            if let Some(value) = payload.get("service_tier").and_then(Value::as_str) {
                tier = Some(value.to_owned());
            }
            continue;
        }

        let prompt = if is_root_thread
            && event_type == Some("event_msg")
            && payload_type == Some("user_message")
        {
            event_user_prompt(payload).map(|prompt| (prompt, false))
        } else if is_root_thread
            && event_type == Some("event_msg")
            && payload_type == Some("thread_goal_updated")
        {
            payload
                .get("goal")
                .and_then(|goal| goal.get("objective"))
                .and_then(Value::as_str)
                .map(str::trim)
                .filter(|objective| !objective.is_empty())
                .map(|objective| (objective.to_owned(), false))
        } else if is_root_thread
            && event_type == Some("response_item")
            && payload_type == Some("message")
            && payload.get("role").and_then(Value::as_str) == Some("user")
        {
            let (prompt, uncertain) = response_user_prompt(payload);
            prompt.map(|prompt| (prompt, uncertain))
        } else {
            None
        }
        .filter(|(prompt, _)| !prompt.trim_start().starts_with("$context-file"));
        if let (Some(session_id), Some((prompt, uncertain)), Some(timestamp)) = (
            root_session_id.as_ref(),
            prompt,
            event.get("timestamp").and_then(parse_timestamp),
        ) {
            let candidate = PromptCandidate {
                timestamp,
                prompt,
                uncertain,
            };
            result.consider_prompt(session_id.clone(), candidate);
        }

        if event_type != Some("event_msg") || payload_type != Some("token_count") {
            continue;
        }
        let Some(info) = payload.get("info").filter(|value| !value.is_null()) else {
            continue;
        };
        let Some(cumulative) = info
            .get("total_token_usage")
            .filter(|value| !value.is_null())
        else {
            continue;
        };
        let cumulative_vector = Usage::from_value(cumulative).vector();
        if previous_total == Some(cumulative_vector) {
            continue;
        }
        previous_total = Some(cumulative_vector);

        let Some(usage_value) = info
            .get("last_token_usage")
            .filter(|value| !value.is_null())
        else {
            continue;
        };
        let usage = Usage::from_value(usage_value);
        if !usage.has_usage() {
            continue;
        }
        let Some(timestamp) = event.get("timestamp").and_then(parse_timestamp) else {
            continue;
        };
        if timestamp < start || timestamp >= end {
            continue;
        }

        let cost = match request_cost(model.as_deref(), tier.as_deref(), usage) {
            Some(cost) => cost,
            None => {
                *result
                    .unpriced_models
                    .entry(model.clone().unwrap_or_else(|| "unknown".to_owned()))
                    .or_default() += 1;
                0.0
            }
        };
        let local_date = timestamp.with_timezone(&timezone).date_naive();
        result
            .daily
            .entry(local_date)
            .or_default()
            .add_usage(usage, cost);
        if let Some(session_id) = root_session_id.as_ref() {
            let session = result.sessions.entry(session_id.clone()).or_default();
            session.stats.add_usage(usage, cost);
            session.threads.insert(thread_id.clone());
        }

        let is_fast = tier.as_deref() == Some("priority");
        if is_fast {
            result.fast.add_usage(usage, cost);
        }
        if tier.is_none() {
            result.assumed_standard_tier += 1;
        }
    }

    result
}

fn collect_jsonl_files(directory: &Path, earliest_mtime: SystemTime) -> Vec<PathBuf> {
    WalkDir::new(directory)
        .into_iter()
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_file())
        .filter(|entry| {
            entry
                .path()
                .extension()
                .is_some_and(|extension| extension == "jsonl")
        })
        .filter(|entry| {
            entry
                .metadata()
                .ok()
                .and_then(|metadata| metadata.modified().ok())
                .is_none_or(|modified| modified >= earliest_mtime)
        })
        .map(|entry| entry.into_path())
        .collect()
}

fn analyze(
    sessions_dir: &Path,
    start: DateTime<Utc>,
    end: DateTime<Utc>,
    timezone: Tz,
) -> Analysis {
    let earliest_mtime: SystemTime = start.into();
    let files = collect_jsonl_files(sessions_dir, earliest_mtime);
    files
        .par_iter()
        .map(|path| analyze_file(path, start, end, timezone))
        .reduce(Analysis::default, |mut total, file| {
            total.merge(file);
            total
        })
}

fn group_digits(digits: &str) -> String {
    let mut output = String::with_capacity(digits.len() + digits.len() / 3);
    let first_group = digits.len() % 3;
    if first_group != 0 {
        output.push_str(&digits[..first_group]);
        if digits.len() > first_group {
            output.push(',');
        }
    }
    for (index, chunk) in digits.as_bytes()[first_group..].chunks(3).enumerate() {
        if index != 0 {
            output.push(',');
        }
        output.push_str(std::str::from_utf8(chunk).expect("digits are UTF-8"));
    }
    output
}

fn format_u64(value: u64) -> String {
    group_digits(&value.to_string())
}

fn format_decimal(value: f64, precision: usize) -> String {
    let raw = format!("{:.*}", precision, value.abs());
    let (integer, fraction) = raw.split_once('.').unwrap_or((&raw, ""));
    let sign = if value.is_sign_negative() { "-" } else { "" };
    if precision == 0 {
        format!("{sign}{}", group_digits(integer))
    } else {
        format!("{sign}{}.{fraction}", group_digits(integer))
    }
}

fn format_millions(value: i64) -> String {
    format!("{}M", format_decimal(value as f64 / 1_000_000.0, 3))
}

fn cache_write_report_line(cache_write: u64) -> Option<String> {
    if cache_write == 0 {
        return None;
    }
    let amount = if cache_write >= 1_000_000 {
        format_millions(cache_write as i64)
    } else {
        format_u64(cache_write)
    };
    Some(format!(
        "Cache-write input (free under Codex pricing): {amount}"
    ))
}

fn percentage(part: f64, whole: f64) -> f64 {
    if whole == 0.0 {
        0.0
    } else {
        100.0 * part / whole
    }
}

fn print_top_sessions(result: &Analysis, count: usize) {
    if count == 0 {
        return;
    }
    let mut ranked = result.sessions.iter().collect::<Vec<_>>();
    ranked.sort_unstable_by(|(left_id, left), (right_id, right)| {
        right
            .stats
            .cost
            .total_cmp(&left.stats.cost)
            .then_with(|| left_id.cmp(right_id))
    });
    ranked.truncate(count);

    let mut table = report_table();
    table
        .load_preset(presets::UTF8_FULL_CONDENSED)
        .apply_modifier(modifiers::UTF8_ROUND_CORNERS)
        .set_content_arrangement(ContentArrangement::Dynamic)
        .set_header([
            right_cell("#"),
            Cell::new("First prompt"),
            right_cell("Requests"),
            right_cell("Threads"),
            right_cell("Tokens"),
            right_cell("USD"),
        ]);

    for (index, (session_id, session)) in ranked.into_iter().enumerate() {
        let prompt = match result.prompts.get(session_id) {
            Some(candidate) => {
                let prefix = if candidate.uncertain {
                    "[heuristic] "
                } else {
                    ""
                };
                let prompt = candidate
                    .prompt
                    .split_whitespace()
                    .collect::<Vec<_>>()
                    .join(" ");
                format!("{prefix}{prompt}")
            }
            None => "[not found]".to_owned(),
        };
        let mut row = Row::from(vec![
            right_cell(index + 1),
            Cell::new(prompt).set_delimiter('\n'),
            right_cell(format_u64(session.stats.requests)),
            right_cell(format_u64(session.threads.len() as u64)),
            right_cell(format_millions(session.stats.tokens as i64)),
            right_cell(format!("${}", format_decimal(session.stats.cost, 2))),
        ]);
        row.max_height(1);
        table.add_row(row);
    }

    println!("\nTop {} sessions by USD\n{table}", table.row_count());
}

fn right_cell(value: impl ToString) -> Cell {
    Cell::new(value).set_alignment(CellAlignment::Right)
}

fn report_table() -> Table {
    let mut table = Table::new();
    table
        .load_preset(presets::UTF8_FULL)
        .apply_modifier(modifiers::UTF8_ROUND_CORNERS);
    table
}

fn print_report(
    result: &Analysis,
    first_date: NaiveDate,
    last_date: NaiveDate,
    timezone_name: &str,
    sessions_dir: &Path,
    top_sessions: usize,
) {
    println!("Codex usage ({first_date} through {last_date}, {timezone_name})");
    println!("Source: {}", sessions_dir.display());
    let mut usage_table = report_table();
    usage_table.set_header([
        Cell::new("Date"),
        right_cell("Requests"),
        right_cell("Billable"),
        right_cell("Cached"),
        right_cell("Output"),
        right_cell("Total"),
        right_cell("USD"),
    ]);

    let mut day = first_date;
    loop {
        let stats = result.daily.get(&day).copied().unwrap_or_default();
        usage_table.add_row([
            Cell::new(day),
            right_cell(format_u64(stats.requests)),
            right_cell(format_millions(stats.billable_input)),
            right_cell(format_millions(stats.cached as i64)),
            right_cell(format_millions(stats.output as i64)),
            right_cell(format_millions(stats.tokens as i64)),
            right_cell(format!("${}", format_decimal(stats.cost, 2))),
        ]);
        if day == last_date {
            break;
        }
        day = day
            .checked_add_days(Days::new(1))
            .expect("date range is valid");
    }

    let total = result.total();
    usage_table.add_row([
        Cell::new("Total"),
        right_cell(format_u64(total.requests)),
        right_cell(format_millions(total.billable_input)),
        right_cell(format_millions(total.cached as i64)),
        right_cell(format_millions(total.output as i64)),
        right_cell(format_millions(total.tokens as i64)),
        right_cell(format!("${}", format_decimal(total.cost, 2))),
    ]);
    println!("\n{usage_table}\n");

    let mut breakdown_table = report_table();
    breakdown_table.set_header([
        Cell::new("Category"),
        right_cell("Requests"),
        right_cell("Request share"),
        right_cell("USD"),
        right_cell("USD share"),
    ]);
    breakdown_table.add_row([
        Cell::new("Fast"),
        right_cell(format_u64(result.fast.requests)),
        right_cell(format!(
            "{:.2}%",
            percentage(result.fast.requests as f64, total.requests as f64)
        )),
        right_cell(format!("${}", format_decimal(result.fast.cost, 2))),
        right_cell(format!("{:.2}%", percentage(result.fast.cost, total.cost))),
    ]);
    println!("{breakdown_table}\n");
    println!(
        "Reasoning output (included in output): {}",
        format_millions(total.reasoning as i64)
    );
    if let Some(line) = cache_write_report_line(total.cache_write) {
        println!("{line}");
    }
    if result.assumed_standard_tier != 0 {
        println!(
            "Note: {} requests had no service tier; priced as Standard.",
            format_u64(result.assumed_standard_tier)
        );
    }
    if !result.unpriced_models.is_empty() {
        let mut models = result.unpriced_models.iter().collect::<Vec<_>>();
        models.sort_unstable_by_key(|(model, _)| *model);
        let models = models
            .into_iter()
            .map(|(model, count)| format!("{model} ({})", format_u64(*count)))
            .collect::<Vec<_>>()
            .join(", ");
        eprintln!("Warning: USD total excludes unpriced models: {models}");
    }
    println!(
        "USD uses official prices as of {PRICE_DATE}; it is a token-price equivalent, not the subscription bill."
    );
    print_top_sessions(result, top_sessions);
}

fn expand_tilde(path: PathBuf) -> PathBuf {
    let Some(path_text) = path.to_str() else {
        return path;
    };
    if (path_text == "~" || path_text.starts_with("~/"))
        && let Some(home) = env::var_os("HOME")
    {
        return if path_text == "~" {
            PathBuf::from(home)
        } else {
            PathBuf::from(home).join(&path_text[2..])
        };
    }
    path
}

fn default_sessions_dir() -> PathBuf {
    let default_codex_home = env::var_os("CODEX_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("~/.syncd-dotfiles/.codex"));
    expand_tilde(default_codex_home.join("sessions"))
}

fn run() -> Result<(), String> {
    let mut args = Args::parse();
    args.sessions_dir = expand_tilde(args.sessions_dir);
    if !args.sessions_dir.is_dir() {
        return Err(format!(
            "sessions directory does not exist: {}",
            args.sessions_dir.display()
        ));
    }
    let timezone = args.timezone;
    let now = DateTime::<Utc>::from(SystemTime::now());
    let local_today = now.with_timezone(&timezone).date_naive();
    let first_date = local_today
        .checked_sub_days(Days::new(args.days - 1))
        .ok_or("--days produces an invalid date range")?;
    let start = timezone
        .from_local_datetime(
            &first_date
                .and_hms_opt(0, 0, 0)
                .expect("midnight is a valid naive time"),
        )
        .earliest()
        .ok_or_else(|| format!("local midnight does not exist in {}", args.timezone))?
        .with_timezone(&Utc);
    let result = analyze(&args.sessions_dir, start, now, timezone);
    print_report(
        &result,
        first_date,
        local_today,
        &args.timezone.to_string(),
        &args.sessions_dir,
        args.top_sessions,
    );
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("codex-usage: error: {error}");
            ExitCode::from(2)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::fs;
    use std::io::Write;

    fn event(timestamp: &str, payload: Value, event_type: &str) -> String {
        serde_json::to_string(&json!({
            "timestamp": timestamp,
            "type": event_type,
            "payload": payload,
        }))
        .unwrap()
    }

    fn usage(input: u64, cached: u64, output: u64, cache_write: u64) -> Value {
        json!({
            "input_tokens": input,
            "cached_input_tokens": cached,
            "cache_write_input_tokens": cache_write,
            "output_tokens": output,
            "reasoning_output_tokens": 0,
            "total_tokens": input + output,
        })
    }

    #[test]
    fn deduplicates_notifications_and_prices_fast_requests() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("2026/08/01/rollout.jsonl");
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        let first = usage(100, 20, 10, 0);
        let second = usage(300_000, 200_000, 1_000, 0);
        let cumulative_second = usage(300_100, 200_020, 1_010, 0);
        let mut file = File::create(&path).unwrap();
        for line in [
            event(
                "2026-08-23T23:59:57Z",
                json!({"id": "root-session", "session_id": "root-session", "thread_source": "user"}),
                "session_meta",
            ),
            event(
                "2026-08-23T23:59:58Z",
                json!({
                    "type": "message", "role": "user",
                    "content": [{"type": "input_text", "text": "injected"}],
                    "internal_chat_message_metadata_passthrough": {"content_item_kinds": ["agents_md.instructions"]},
                }),
                "response_item",
            ),
            event(
                "2026-08-23T23:59:58.500Z",
                json!({
                    "type": "message", "role": "user",
                    "content": [{"type": "input_text", "text": "  $context-file:context-file docs/*.md"}],
                    "internal_chat_message_metadata_passthrough": {"content_item_kinds": ["user.text"]},
                }),
                "response_item",
            ),
            event(
                "2026-08-23T23:59:58.750Z",
                json!({
                    "type": "thread_goal_updated",
                    "goal": {"objective": "Goal task"},
                }),
                "event_msg",
            ),
            event(
                "2026-08-23T23:59:59Z",
                json!({
                    "type": "message", "role": "user",
                    "content": [{"type": "input_text", "text": "Real task"}],
                    "internal_chat_message_metadata_passthrough": {"content_item_kinds": ["user.text"]},
                }),
                "response_item",
            ),
            event(
                "2026-08-24T00:00:00Z",
                json!({"model": "gpt-5.6-sol"}),
                "turn_context",
            ),
            event(
                "2026-08-24T00:00:01Z",
                json!({"type": "token_count", "info": {"last_token_usage": first, "total_token_usage": first}}),
                "event_msg",
            ),
            event(
                "2026-08-24T00:00:02Z",
                json!({"type": "token_count", "info": {"last_token_usage": first, "total_token_usage": first}}),
                "event_msg",
            ),
            event(
                "2026-08-24T00:00:03Z",
                json!({"type": "thread_settings_applied", "thread_settings": {"model": "gpt-5.6-sol", "service_tier": "priority"}}),
                "event_msg",
            ),
            event(
                "2026-08-24T00:00:04Z",
                json!({"type": "token_count", "info": {"last_token_usage": second, "total_token_usage": cumulative_second}}),
                "event_msg",
            ),
        ] {
            writeln!(file, "{line}").unwrap();
        }

        let child_path = path.with_file_name("subagent.jsonl");
        let child = usage(50, 10, 5, 20);
        let mut child_file = File::create(child_path).unwrap();
        for line in [
            event(
                "2026-08-23T23:59:55Z",
                json!({"id": "child-thread", "session_id": "root-session", "thread_source": "subagent"}),
                "session_meta",
            ),
            event(
                "2026-08-23T23:59:56Z",
                json!({
                    "type": "message", "role": "user",
                    "content": [{"type": "input_text", "text": "Copied parent history"}],
                    "internal_chat_message_metadata_passthrough": {"content_item_kinds": ["user.text"]},
                }),
                "response_item",
            ),
            event(
                "2026-08-24T00:00:00Z",
                json!({"model": "gpt-5.6-sol"}),
                "turn_context",
            ),
            event(
                "2026-08-24T00:00:01Z",
                json!({"type": "token_count", "info": {"last_token_usage": child, "total_token_usage": child}}),
                "event_msg",
            ),
        ] {
            writeln!(child_file, "{line}").unwrap();
        }

        let result = analyze(
            directory.path(),
            "2026-08-23T00:00:00Z".parse().unwrap(),
            "2026-08-25T00:00:00Z".parse().unwrap(),
            "Asia/Singapore".parse().unwrap(),
        );

        let total = result.total();
        assert_eq!(total.requests, 3);
        assert_eq!(result.fast.requests, 1);
        assert!((total.cost - 1.250712).abs() < f64::EPSILON);
        assert_eq!(total.billable_input, 100_100);
        assert_eq!(total.cached, 200_030);
        assert_eq!(total.cache_write, 20);
        assert_eq!(
            total.tokens - total.output,
            (total.billable_input as u64) + total.cached + total.cache_write
        );
        let session = &result.sessions["root-session"];
        assert_eq!(session.stats.tokens, 301_165);
        assert_eq!(session.threads.len(), 2);
        assert_eq!(result.prompts["root-session"].prompt, "Goal task");
        assert!(!result.prompts["root-session"].uncertain);
    }

    #[test]
    fn formats_human_readable_numbers() {
        assert_eq!(format_u64(1_234_567), "1,234,567");
        assert_eq!(format_millions(1_234_567), "1.235M");
        assert_eq!(format_decimal(1234.5, 2), "1,234.50");
        assert_eq!(cache_write_report_line(0), None);
        assert_eq!(
            cache_write_report_line(20).as_deref(),
            Some("Cache-write input (free under Codex pricing): 20")
        );
        assert_eq!(
            cache_write_report_line(1_000_000).as_deref(),
            Some("Cache-write input (free under Codex pricing): 1.000M")
        );
    }

    #[test]
    fn calculates_model_and_tier_prices() {
        let standard = Usage {
            input_tokens: 100,
            cached_input_tokens: 20,
            output_tokens: 10,
            ..Usage::default()
        };
        assert_eq!(
            request_cost(Some("gpt-5.6-sol"), None, standard),
            Some(0.000528)
        );
        assert_eq!(request_cost(Some("unknown"), None, standard), None);

        let large = Usage {
            input_tokens: 300_000,
            cached_input_tokens: 200_000,
            output_tokens: 1_000,
            ..Usage::default()
        };
        assert_eq!(
            request_cost(Some("gpt-5.6-sol"), Some("priority"), large),
            Some(1.25)
        );
        assert_eq!(request_cost(Some("gpt-6-astra"), None, large), Some(1.25));
        assert_eq!(
            request_cost(Some("gpt-6-astra"), Some("priority"), large),
            Some(3.125)
        );
        assert_eq!(
            request_cost(Some("gpt-5.6-terra"), None, large),
            Some(0.252)
        );
    }
}
