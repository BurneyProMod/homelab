#!/usr/bin/env bash
# summarize-logs.sh - daily homelab log digest via burndev Ollama.
#
# Gathers one day's lines from the Synology homelab rsyslog tree
# (logs/rsyslog/<host>/<facility>.log[.N[.gz]]), triages them so the
# input fits the model context, and writes a markdown digest to
# logs/summaries/YYYY-MM-DD.md next to the log tree.
#
# Usage: summarize-logs.sh [YYYY-MM-DD]   # default: yesterday (local time)
#
# Log timestamps look like "2026-08-09T01:17:01-05:00", so the date
# prefix filter matches the local calendar day.

set -u

LOG_ROOT=/mnt/synology/homelab/logs/rsyslog
OUT_ROOT=/mnt/synology/homelab/logs/summaries
OLLAMA_URL=http://192.168.1.50:11434/api/chat
MODEL=qwen3.5:9b
NUM_CTX=32768
RETENTION=30

# Per-host input budgets in bytes (opnsense alone produces ~48MB/day).
PRIORITY_CAP=12000     # error/warn lines
SAMPLE_CAP=4000        # remaining lines, after priorities
NOISE_SAMPLE_CAP=600   # firewall filterlog chatter sample
TOTAL_CAP=100000       # global guard on the assembled prompt

DATE=${1:-$(date -d yesterday +%F)}
PRIORITY_RE='error|warn|fail|fatal|crit|alert|emerg|panic|oops|segfault|oom|denied|reject|timeout|unavail|exception'

log() { echo "$(date '+%F %T') $*"; }

if [[ ! "$DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    log "ERROR: bad date '$DATE' (expected YYYY-MM-DD)"
    exit 1
fi
if [[ ! -d "$LOG_ROOT" ]]; then
    log "ERROR: $LOG_ROOT is not mounted"
    exit 1
fi

mkdir -p "$OUT_ROOT"
WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT

sections=""
hosts_seen=0
noise_total=0
total_input=0

for dir in "$LOG_ROOT"/*/; do
    host=$(basename "$dir")
    raw="$WORK/$host.raw"
    : > "$raw"

    # Gather the day's lines from every log file (plain and gz rotations),
    # collapse adjacent duplicate lines into [xN] counts.
    while IFS= read -r f; do
        case "$f" in
            *.gz) zcat "$f" 2>/dev/null ;;
            *)    cat "$f" 2>/dev/null ;;
        esac
    done < <(find "$dir" -type f -name '*.log*' 2>/dev/null) \
        | grep -a "^$DATE" \
        | uniq -c \
        | sed -E 's/^ *([0-9]+) /[x\1] /' \
        >> "$raw" 2>/dev/null

    [[ -s "$raw" ]] || continue

    total=$(wc -l < "$raw")
    hosts_seen=$((hosts_seen + 1))

    priority=$(grep -aiE "$PRIORITY_RE" "$raw" | head -c "$PRIORITY_CAP")
    noise=""
    noise_n=0
    if [[ "$host" == "opnsense" || "$host" == "OPNsense.lan" ]]; then
        noise_n=$(grep -aic 'filterlog' "$raw")
        noise_total=$((noise_total + noise_n))
        noise=$(grep -ai 'filterlog' "$raw" | head -c "$NOISE_SAMPLE_CAP")
        other=$(grep -aivE "$PRIORITY_RE" "$raw" | grep -aiv 'filterlog' | head -c "$SAMPLE_CAP")
    else
        other=$(grep -aivE "$PRIORITY_RE" "$raw" | head -c "$SAMPLE_CAP")
    fi

    section=$(printf '## %s\n_%s lines after dedupe_%s%s%s\n' \
        "$host" "$total" \
        "$([[ -n "$priority" ]] && printf '\n\n### Priority\n%s' "$priority")" \
        "$([[ -n "$other" ]] && printf '\n\n### Other\n%s' "$other")" \
        "$([[ -n "$noise" ]] && printf '\n\n### Firewall chatter (count %s)\n%s' "$noise_n" "$noise")")
    sections+="$section"$'\n\n'
    total_input=$((total_input + ${#section}))
done

if [[ $hosts_seen -eq 0 ]]; then
    log "no log data for $DATE; nothing to summarize"
    cat > "$OUT_ROOT/$DATE.md" <<EOF
# Homelab log digest - $DATE

No log data was found for this date.
EOF
    exit 0
fi

prompt_file="$WORK/prompt.txt"
{
    printf 'You are an analyst for a homelab. Below are syslog excerpts for the local date %s collected from several hosts. Lines are prefixed with per-host section headers. Consecutive duplicate lines were collapsed into counts like [xN]. Firewall chatter for opnsense is counted and sampled, not exhaustive.\n\n' "$DATE"
    printf 'Produce a concise markdown daily digest:\n'
    printf -- '- A "## Summary" section at the top: the 3-6 most notable events across all hosts.\n'
    printf -- '- One "### <host>" subsection per host that had data: notable events, errors, warnings, anomalies, and recurring patterns. State "No notable events" when a host section shows none.\n'
    printf -- '- Do not invent events or speculate. Be factual and short. Output only the digest, no preamble.\n\n'
    printf '%s' "$sections"
} > "$prompt_file"

# Truncate defensively if the per-host caps were exceeded.
if [[ $(wc -c < "$prompt_file") -gt $TOTAL_CAP ]]; then
    truncate -s "$TOTAL_CAP" "$prompt_file"
fi

payload=$(python3 - "$MODEL" "$NUM_CTX" "$prompt_file" <<'PYEOF'
import json, sys
model, num_ctx, pf = sys.argv[1], int(sys.argv[2]), sys.argv[3]
prompt = open(pf).read()
print(json.dumps({
    "model": model,
    "messages": [
        {"role": "system", "content": "You write concise factual summaries. Never invent log events."},
        {"role": "user", "content": prompt},
    ],
    "stream": False,
    "think": False,
    "options": {"num_ctx": num_ctx, "temperature": 0.2},
}))
PYEOF
)

log "calling $MODEL ($(wc -c < "$prompt_file") byte prompt) for $DATE"
resp=$(curl -sf -m 600 "$OLLAMA_URL" -H 'Content-Type: application/json' -d "$payload") || {
    log "ERROR: Ollama call failed (curl exit $?)"
    cat > "$OUT_ROOT/$DATE.md" <<EOF
# Homelab log digest - $DATE

The summary could not be generated: Ollama on 192.168.1.50:11434 did not respond.
EOF
    exit 1
}

summary=$(printf '%s' "$resp" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d.get("message", {}).get("content") or d.get("response") or "")
')
if [[ -z "$summary" ]]; then
    log "ERROR: empty response from Ollama"
    exit 1
fi

{
    printf '# Homelab log digest - %s\n\n' "$DATE"
    printf 'Sources: %s host(s) with data, %s firewall chatter lines counted across all hosts.\n\n' "$hosts_seen" "$noise_total"
    printf '%s\n' "$summary"
} > "$OUT_ROOT/$DATE.md"

# Retention: keep the newest RETENTION summaries.
ls -t "$OUT_ROOT"/*.md 2>/dev/null | tail -n +$((RETENTION + 1)) | xargs -r rm -f

log "wrote $OUT_ROOT/$DATE.md (${hosts_seen} hosts)"
