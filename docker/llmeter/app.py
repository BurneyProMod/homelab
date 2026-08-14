#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo

PORT = int(os.getenv("PORT", "8080"))
DB_PATH = Path(os.getenv("DB_PATH", "/data/llmeter.db"))
SESSIONS_DIR = Path(os.getenv("SESSIONS_DIR", "/pi-sessions"))
TZ = ZoneInfo(os.getenv("TZ", "America/Chicago"))
SCAN_SECONDS = int(os.getenv("SCAN_SECONDS", "30"))
BALANCE_POLL_SECONDS = int(os.getenv("BALANCE_POLL_SECONDS", "300"))

PROVIDER_CONFIG = {
    "deepseek": {
        "capacity": float(os.getenv("DEEPSEEK_TARGET_USD", "20")),
        "start": os.getenv("DEEPSEEK_BUDGET_START", "1970-01-01T00:00:00+00:00"),
    },
    "kimi": {
        "capacity": float(os.getenv("KIMI_TARGET_USD", "20")),
        "start": os.getenv("KIMI_BUDGET_START", "1970-01-01T00:00:00+00:00"),
    },
    "openai": {
        "capacity": float(os.getenv("OPENAI_BUDGET_USD", "20")),
        "start": os.getenv("OPENAI_BUDGET_START", "1970-01-01T00:00:00+00:00"),
    },
    "anthropic": {
        "capacity": float(os.getenv("ANTHROPIC_BUDGET_USD", "20")),
        "start": os.getenv("ANTHROPIC_BUDGET_START", "1970-01-01T00:00:00+00:00"),
    },
}

DEEPSEEK_KEY_FILE = Path(os.getenv("DEEPSEEK_KEY_FILE", "/run/secrets/llmeter/deepseek_api_key"))
KIMI_KEY_FILE = Path(os.getenv("KIMI_KEY_FILE", "/run/secrets/llmeter/moonshot_api_key"))

state_lock = threading.Lock()
runtime_state: dict[str, Any] = {
    "last_scan_at": None,
    "last_balance_poll_at": None,
    "scan_error": None,
    "balances": {
        "deepseek": {"balance_usd": None, "error": "Not polled yet", "updated_at": None},
        "kimi": {"balance_usd": None, "error": "Not polled yet", "updated_at": None},
    },
}


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def iso_to_ms(value: str) -> int:
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    return int(datetime.fromisoformat(text).timestamp() * 1000)


def normalize_provider(value: Any) -> str | None:
    raw = str(value or "").strip().lower()
    if "deepseek" in raw:
        return "deepseek"
    if "moonshot" in raw or "kimi" in raw:
        return "kimi"
    if "anthropic" in raw or "claude" in raw:
        return "anthropic"
    if "openai" in raw or "codex" in raw:
        return "openai"
    return None


def number(value: Any) -> float:
    try:
        return float(value or 0)
    except (TypeError, ValueError):
        return 0.0


def connect_db() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(DB_PATH, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=30000")
    return conn


def init_db() -> None:
    with connect_db() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS usage_events (
                event_id TEXT PRIMARY KEY,
                timestamp_ms INTEGER NOT NULL,
                provider TEXT NOT NULL,
                provider_raw TEXT,
                model TEXT,
                input_tokens INTEGER NOT NULL DEFAULT 0,
                output_tokens INTEGER NOT NULL DEFAULT 0,
                cache_read_tokens INTEGER NOT NULL DEFAULT 0,
                cache_write_tokens INTEGER NOT NULL DEFAULT 0,
                total_tokens INTEGER NOT NULL DEFAULT 0,
                cost_input REAL NOT NULL DEFAULT 0,
                cost_output REAL NOT NULL DEFAULT 0,
                cost_cache_read REAL NOT NULL DEFAULT 0,
                cost_cache_write REAL NOT NULL DEFAULT 0,
                cost_total REAL NOT NULL DEFAULT 0,
                session_file TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_usage_provider_timestamp
                ON usage_events(provider, timestamp_ms);

            CREATE TABLE IF NOT EXISTS file_state (
                path TEXT PRIMARY KEY,
                size INTEGER NOT NULL,
                mtime_ns INTEGER NOT NULL,
                scanned_at TEXT NOT NULL
            );
            """
        )


def event_timestamp_ms(entry: dict[str, Any], message: dict[str, Any]) -> int:
    value = message.get("timestamp", entry.get("timestamp"))
    if isinstance(value, (int, float)):
        return int(value)
    if isinstance(value, str) and value.strip():
        try:
            return iso_to_ms(value)
        except (ValueError, TypeError):
            pass
    return int(time.time() * 1000)


def scan_sessions() -> None:
    try:
        if not SESSIONS_DIR.exists():
            raise FileNotFoundError(f"Pi sessions directory not found: {SESSIONS_DIR}")

        with connect_db() as conn:
            known = {
                row["path"]: (row["size"], row["mtime_ns"])
                for row in conn.execute("SELECT path, size, mtime_ns FROM file_state")
            }

            for path in SESSIONS_DIR.rglob("*.jsonl"):
                try:
                    stat = path.stat()
                except FileNotFoundError:
                    continue

                path_text = str(path)
                if known.get(path_text) == (stat.st_size, stat.st_mtime_ns):
                    continue

                with path.open("r", encoding="utf-8", errors="replace") as handle:
                    for line_number, line in enumerate(handle, start=1):
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            entry = json.loads(line)
                        except json.JSONDecodeError:
                            # A live session can temporarily end with an incomplete line.
                            continue

                        if entry.get("type") != "message":
                            continue

                        message = entry.get("message") or {}
                        if message.get("role") != "assistant":
                            continue

                        provider_raw = message.get("provider", entry.get("provider"))
                        provider = normalize_provider(provider_raw)
                        if not provider:
                            continue

                        usage = message.get("usage") or {}
                        cost = usage.get("cost") or {}
                        timestamp_ms = event_timestamp_ms(entry, message)
                        model = str(message.get("model", entry.get("model", "")))

                        stable_source = "|".join(
                            [
                                path_text,
                                str(entry.get("id", "")),
                                str(timestamp_ms),
                                str(provider_raw or ""),
                                model,
                                str(line_number),
                            ]
                        )
                        event_id = hashlib.sha256(stable_source.encode()).hexdigest()

                        values = (
                            event_id,
                            timestamp_ms,
                            provider,
                            str(provider_raw or ""),
                            model,
                            int(number(usage.get("input"))),
                            int(number(usage.get("output"))),
                            int(number(usage.get("cacheRead"))),
                            int(number(usage.get("cacheWrite"))),
                            int(number(usage.get("totalTokens"))),
                            number(cost.get("input")),
                            number(cost.get("output")),
                            number(cost.get("cacheRead")),
                            number(cost.get("cacheWrite")),
                            number(cost.get("total")),
                            path_text,
                        )

                        conn.execute(
                            """
                            INSERT OR IGNORE INTO usage_events (
                                event_id, timestamp_ms, provider, provider_raw, model,
                                input_tokens, output_tokens, cache_read_tokens,
                                cache_write_tokens, total_tokens,
                                cost_input, cost_output, cost_cache_read,
                                cost_cache_write, cost_total, session_file
                            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                            """,
                            values,
                        )

                conn.execute(
                    """
                    INSERT INTO file_state(path, size, mtime_ns, scanned_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(path) DO UPDATE SET
                        size = excluded.size,
                        mtime_ns = excluded.mtime_ns,
                        scanned_at = excluded.scanned_at
                    """,
                    (path_text, stat.st_size, stat.st_mtime_ns, now_iso()),
                )

        with state_lock:
            runtime_state["last_scan_at"] = now_iso()
            runtime_state["scan_error"] = None
    except Exception as exc:
        with state_lock:
            runtime_state["scan_error"] = str(exc)


def read_secret(path: Path) -> str:
    return path.read_text(encoding="utf-8").strip()


def request_json(url: str, api_key: str) -> dict[str, Any]:
    request = Request(
        url,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Accept": "application/json",
            "User-Agent": "llmeter-homelab/1.0",
        },
    )
    try:
        with urlopen(request, timeout=15) as response:
            return json.loads(response.read().decode("utf-8"))
    except HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")[:300]
        raise RuntimeError(f"HTTP {exc.code}: {body}") from exc
    except URLError as exc:
        raise RuntimeError(str(exc.reason)) from exc


def fetch_deepseek_balance() -> float:
    payload = request_json("https://api.deepseek.com/user/balance", read_secret(DEEPSEEK_KEY_FILE))
    balances = payload.get("balance_infos") or []
    for item in balances:
        if str(item.get("currency", "")).upper() == "USD":
            return number(item.get("total_balance"))
    if len(balances) == 1:
        return number(balances[0].get("total_balance"))
    raise RuntimeError("DeepSeek response did not include a usable balance")


def fetch_kimi_balance() -> float:
    payload = request_json("https://api.moonshot.ai/v1/users/me/balance", read_secret(KIMI_KEY_FILE))
    data = payload.get("data") or {}
    value = data.get("available_balance")
    if value is None:
        raise RuntimeError("Kimi response did not include data.available_balance")
    return number(value)


def poll_balances() -> None:
    results: dict[str, dict[str, Any]] = {}
    for provider, function in (
        ("deepseek", fetch_deepseek_balance),
        ("kimi", fetch_kimi_balance),
    ):
        try:
            results[provider] = {
                "balance_usd": round(function(), 6),
                "error": None,
                "updated_at": now_iso(),
            }
        except Exception as exc:
            results[provider] = {
                "balance_usd": None,
                "error": str(exc),
                "updated_at": now_iso(),
            }

    with state_lock:
        runtime_state["balances"].update(results)
        runtime_state["last_balance_poll_at"] = now_iso()


def start_of_today_ms() -> int:
    local_now = datetime.now(TZ)
    start = local_now.replace(hour=0, minute=0, second=0, microsecond=0)
    return int(start.astimezone(timezone.utc).timestamp() * 1000)


def query_stats(provider: str, start_ms: int = 0) -> dict[str, float | int]:
    with connect_db() as conn:
        row = conn.execute(
            """
            SELECT
                COALESCE(SUM(input_tokens), 0) AS input_tokens,
                COALESCE(SUM(output_tokens), 0) AS output_tokens,
                COALESCE(SUM(cache_read_tokens), 0) AS cache_read_tokens,
                COALESCE(SUM(cache_write_tokens), 0) AS cache_write_tokens,
                COALESCE(SUM(total_tokens), 0) AS total_tokens,
                COALESCE(SUM(cost_total), 0) AS cost_total,
                COUNT(*) AS calls
            FROM usage_events
            WHERE provider = ? AND timestamp_ms >= ?
            """,
            (provider, start_ms),
        ).fetchone()
    return dict(row)


def provider_status(provider: str) -> dict[str, Any]:
    config = PROVIDER_CONFIG[provider]
    capacity = max(number(config["capacity"]), 0)
    budget_start_ms = iso_to_ms(str(config["start"]))
    all_time = query_stats(provider)
    budget_period = query_stats(provider, budget_start_ms)
    today = query_stats(provider, start_of_today_ms())

    balance_error = None
    if provider in {"deepseek", "kimi"}:
        with state_lock:
            balance_data = dict(runtime_state["balances"][provider])
        live_balance = balance_data.get("balance_usd")
        balance_error = balance_data.get("error")
        if live_balance is None:
            remaining = max(capacity - number(budget_period["cost_total"]), 0)
            source = "pi_estimate"
        else:
            remaining = max(number(live_balance), 0)
            source = "provider_balance"
    else:
        remaining = max(capacity - number(budget_period["cost_total"]), 0)
        source = "pi_session_ledger"

    percent = 0.0 if capacity <= 0 else min(max((remaining / capacity) * 100, 0), 100)

    return {
        "capacity_usd": round(capacity, 4),
        "remaining_usd": round(remaining, 4),
        "remaining_percent": round(percent, 2),
        "spent_budget_period_usd": round(number(budget_period["cost_total"]), 6),
        "spent_today_usd": round(number(today["cost_total"]), 6),
        "spent_all_time_usd": round(number(all_time["cost_total"]), 6),
        "calls_all_time": int(all_time["calls"]),
        "input_tokens_all_time": int(all_time["input_tokens"]),
        "output_tokens_all_time": int(all_time["output_tokens"]),
        "cache_read_tokens_all_time": int(all_time["cache_read_tokens"]),
        "cache_write_tokens_all_time": int(all_time["cache_write_tokens"]),
        "total_tokens_all_time": int(all_time["total_tokens"]),
        "budget_start": config["start"],
        "source": source,
        "balance_error": balance_error,
    }


def status_payload() -> dict[str, Any]:
    providers = {name: provider_status(name) for name in PROVIDER_CONFIG}
    capacity = sum(number(item["capacity_usd"]) for item in providers.values())
    remaining = sum(number(item["remaining_usd"]) for item in providers.values())
    percent = 0.0 if capacity <= 0 else min(max((remaining / capacity) * 100, 0), 100)

    with state_lock:
        state = {
            "last_scan_at": runtime_state["last_scan_at"],
            "last_balance_poll_at": runtime_state["last_balance_poll_at"],
            "scan_error": runtime_state["scan_error"],
        }

    return {
        "updated_at": now_iso(),
        "timezone": str(TZ),
        "providers": providers,
        "aggregate": {
            "capacity_usd": round(capacity, 4),
            "remaining_usd": round(remaining, 4),
            "remaining_percent": round(percent, 2),
            "spent_today_usd": round(sum(number(p["spent_today_usd"]) for p in providers.values()), 6),
        },
        "runtime": state,
    }


def prometheus_payload() -> str:
    status = status_payload()
    lines = [
        "# HELP llmeter_remaining_usd Remaining API budget or provider balance in USD.",
        "# TYPE llmeter_remaining_usd gauge",
    ]
    for provider, values in status["providers"].items():
        lines.append(f'llmeter_remaining_usd{{provider="{provider}"}} {values["remaining_usd"]}')

    lines.extend([
        "# HELP llmeter_remaining_percent Remaining percentage of configured capacity.",
        "# TYPE llmeter_remaining_percent gauge",
    ])
    for provider, values in status["providers"].items():
        lines.append(f'llmeter_remaining_percent{{provider="{provider}"}} {values["remaining_percent"]}')

    lines.extend([
        "# HELP llmeter_spent_today_usd Pi-recorded spend since local midnight.",
        "# TYPE llmeter_spent_today_usd gauge",
    ])
    for provider, values in status["providers"].items():
        lines.append(f'llmeter_spent_today_usd{{provider="{provider}"}} {values["spent_today_usd"]}')

    lines.extend([
        "# HELP llmeter_total_tokens Pi-recorded all-time tokens.",
        "# TYPE llmeter_total_tokens gauge",
    ])
    for provider, values in status["providers"].items():
        lines.append(f'llmeter_total_tokens{{provider="{provider}"}} {values["total_tokens_all_time"]}')

    return "\n".join(lines) + "\n"


DASHBOARD = r"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>LLMeter</title>
  <style>
    :root { color-scheme: dark; font-family: system-ui, sans-serif; }
    body { margin: 0; background: #111318; color: #f2f4f8; }
    main { max-width: 1080px; margin: auto; padding: 24px; }
    header { display: flex; justify-content: space-between; align-items: baseline; gap: 16px; }
    h1 { margin: 0 0 4px; }
    #updated { color: #9aa4b2; font-size: .9rem; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit,minmax(230px,1fr)); gap: 16px; margin-top: 22px; }
    .card { background: #1a1f28; border: 1px solid #2c3440; border-radius: 14px; padding: 18px; }
    .name { text-transform: capitalize; font-size: 1.1rem; font-weight: 700; }
    .money { font-size: 1.65rem; margin: 12px 0 6px; }
    .meta { color: #aeb8c5; font-size: .88rem; line-height: 1.55; }
    .track { height: 13px; background: #303846; border-radius: 999px; overflow: hidden; margin: 14px 0 10px; }
    .bar { height: 100%; background: linear-gradient(90deg,#4ea1ff,#5fe0aa); transition: width .4s ease; }
    .error { color: #ff9b9b; margin-top: 8px; font-size: .82rem; }
    button { background: #2b72d6; color: white; border: 0; border-radius: 9px; padding: 9px 14px; cursor: pointer; }
  </style>
</head>
<body>
<main>
  <header>
    <div><h1>LLMeter</h1><div id="updated">Loading…</div></div>
    <button onclick="refreshNow()">Refresh now</button>
  </header>
  <div class="grid" id="cards"></div>
</main>
<script>
const dollars = value => new Intl.NumberFormat('en-US',{style:'currency',currency:'USD',maximumFractionDigits:2}).format(value || 0);
const escapeHtml = value => String(value || '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
async function load() {
  const response = await fetch('/api/status', {cache:'no-store'});
  const data = await response.json();
  document.getElementById('updated').textContent = `Updated ${new Date(data.updated_at).toLocaleString()}`;
  document.getElementById('cards').innerHTML = Object.entries(data.providers).map(([name,p]) => `
    <section class="card">
      <div class="name">${escapeHtml(name)}</div>
      <div class="money">${dollars(p.remaining_usd)} / ${dollars(p.capacity_usd)}</div>
      <div class="track"><div class="bar" style="width:${p.remaining_percent}%"></div></div>
      <div class="meta">
        ${p.remaining_percent.toFixed(1)}% remaining<br>
        Today: ${dollars(p.spent_today_usd)}<br>
        Pi recorded: ${dollars(p.spent_all_time_usd)}<br>
        Source: ${escapeHtml(p.source)}
      </div>
      ${p.balance_error ? `<div class="error">${escapeHtml(p.balance_error)}</div>` : ''}
    </section>`).join('');
}
async function refreshNow() {
  await fetch('/api/refresh', {method:'POST'});
  await load();
}
load();
setInterval(load, 15000);
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    server_version = "LLMeter/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f'{self.address_string()} - {fmt % args}', flush=True)

    def send_bytes(self, status: int, body: bytes, content_type: str) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, status: int, payload: dict[str, Any]) -> None:
        self.send_bytes(status, json.dumps(payload).encode("utf-8"), "application/json; charset=utf-8")

    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        if path == "/healthz":
            self.send_json(200, {"status": "ok"})
        elif path == "/api/status":
            self.send_json(200, status_payload())
        elif path == "/metrics":
            self.send_bytes(200, prometheus_payload().encode("utf-8"), "text/plain; version=0.0.4")
        elif path == "/":
            self.send_bytes(200, DASHBOARD.encode("utf-8"), "text/html; charset=utf-8")
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self) -> None:
        path = self.path.split("?", 1)[0]
        if path == "/api/refresh":
            scan_sessions()
            poll_balances()
            self.send_json(200, status_payload())
        else:
            self.send_json(404, {"error": "not found"})


def periodic(function, seconds: int) -> None:
    while True:
        try:
            function()
        except Exception as exc:
            print(f"{function.__name__}: {exc}", flush=True)
        time.sleep(seconds)


def main() -> None:
    init_db()
    scan_sessions()
    poll_balances()

    threading.Thread(target=periodic, args=(scan_sessions, SCAN_SECONDS), daemon=True).start()
    threading.Thread(target=periodic, args=(poll_balances, BALANCE_POLL_SECONDS), daemon=True).start()

    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"LLMeter listening on 0.0.0.0:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
