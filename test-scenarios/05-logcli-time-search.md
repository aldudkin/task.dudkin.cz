# 05 — CLI (logcli): cross-source + time-indexed search

**Goal:** prove three README requirements at once:
- **CLI access** — `logcli` (the requirement "CLI přístup výhodou").
- **Hledání napříč službami** — one query spanning all log sources at once.
- **"Vyhledávání podle času musí být indexované"** — show the **TSDB index** prunes
  chunks by time, so a narrow time window scans far less than a wide one.

By now Loki holds **four independent sources**, all under the `job` label:
`smoketest` (curl), `flog` + `loggen` (Alloy, scenario 04), `ecs-firelens`
(FireLens, `loki/firelens-demo.tf`). We'll search across them from the CLI.

## Setup

```bash
export AWS_DEFAULT_REGION=eu-central-1
export LOKI_ADDR="https://task.dudkin.cz"      # logcli appends /loki/api/v1/...
# (https://$LOKI_DOMAIN also works — routes through the same /loki/* ALB rule)
```

logcli queries hit the **read path** (`/loki/*` → gateway → query-frontend), the
same endpoint Grafana uses. Single-tenant, so no `--org-id` needed.

---

## 1. CLI access — discover what's there

```bash
logcli labels                 # all label names: job, host, env, source, container_name, ...
logcli labels job             # all sources: ecs-firelens, flog, loggen, smoketest
```

This alone satisfies the CLI requirement: full querying without the UI.

## 2. Cross-source search (hledání napříč službami)

One query, every source — the label model means you don't care *where* logs came from:

```bash
# every stream that has a job label (all four sources at once)
logcli query --since=15m --limit=20 '{job=~".+"}'

# grep across ALL sources for HTTP 500s (apache sources will match; heartbeats won't)
logcli query --since=15m '{job=~".+"} |= " 500 "'

# narrow to just the two log-shipping agents + the ECS app
logcli query --since=15m '{job=~"flog|loggen|ecs-firelens"}'
```

`{job=~".+"}` is the "across everything" matcher (`=~ ".+"` = any non-empty job).
The line filter `|= " 500 "` is the **grep** the design calls for — no full-text
index, just a scan of the matched streams.

## 3. Time-indexed search — prove the TSDB index prunes by time

Loki's **TSDB index** records, per stream, *which chunks cover which time ranges*.
A bounded query consults the index and fetches **only chunks overlapping the
window** — that's what "vyhledávání podle času je indexované" means in practice.

Run the *same* query over a **narrow** vs a **wide** window and compare what the
store actually touched (`--stats` prints engine statistics):

```bash
# narrow: last 5 minutes
logcli query --since=5m  --stats --quiet '{job="flog"}' 2>&1 | grep -iE 'Ingester.TotalChunks|Store.*Chunks|Summary.TotalBytes|TotalLinesProcessed'

# wide: last 3 hours
logcli query --since=3h  --stats --quiet '{job="flog"}' 2>&1 | grep -iE 'Ingester.TotalChunks|Store.*Chunks|Summary.TotalBytes|TotalLinesProcessed'
```

The 3h query reports **more chunks downloaded / more bytes processed** than the
5m one — because the index handed the querier a *larger* set of chunk references
for the wider window. Time isn't grepped; it's looked up.

Explicit absolute window (RFC3339) — what you'd use to zoom to an incident:

```bash
logcli query \
  --from="2026-06-07T14:00:00Z" --to="2026-06-07T14:15:00Z" \
  '{job=~"flog|ecs-firelens"}'
```

## What this proves

| README požadavek | Demonstrated by |
|---|---|
| **CLI přístup** | `logcli labels` / `logcli query` |
| **Hledání napříč službami** | `{job=~".+"}` over 4 sources |
| **Grep bez full-text indexu** | `\|= " 500 "` line filter |
| **Vyhledávání podle času = indexované** | `--stats` chunk/byte counts scale with the time window (TSDB index pruning) |

## Cleanup

Nothing to clean — logcli is read-only.
