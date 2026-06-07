# 02 — Push and query (data creation round-trip)

**Goal:** prove the **write path** (agent → ALB → gateway → distributor → ingester)
and the **read path** (Grafana/logcli → ALB → gateway → query-frontend →
scheduler → querier → ingester) by pushing a log line and reading it back.

Single-tenant (`auth_enabled: false` → `org_id=fake`), so no `X-Scope-OrgID`
header is needed.

## Commands run

### 1. Push a log line (write path)

`values` is `[[ <unix_nano>, <line> ]]`. Timestamp = now, in **nanoseconds**.

```bash
NOW_NS=$(( $(date +%s) * 1000000000 ))
curl -s -o /dev/null -w "HTTP %{http_code}\n" -X POST "http://$ALB/loki/api/v1/push" \
  -H 'Content-Type: application/json' \
  --data-binary "{\"streams\":[{\"stream\":{\"job\":\"smoketest\",\"source\":\"claude\"},\"values\":[[\"$NOW_NS\",\"hello from the end-to-end test\"]]}]}"
```

Expected: `HTTP 204` (accepted, no body).

### 2. Query it back (read path)

```bash
START_NS=$(( NOW_NS - 300000000000 ))   # now - 5m
END_NS=$(( NOW_NS + 60000000000 ))      # now + 1m
curl -s -G "http://$ALB/loki/api/v1/query_range" \
  --data-urlencode 'query={job="smoketest"}' \
  --data-urlencode "start=$START_NS" --data-urlencode "end=$END_NS" \
  --data-urlencode 'limit=5' \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); r=d["data"]["result"]; print("streams returned:", len(r)); [print("  label:",s["stream"], "=>", [v[1] for v in s["values"]]) for s in r]'
```

Expected:

```
streams returned: 1
  label: {'detected_level': 'unknown', 'job': 'smoketest', 'service_name': 'smoketest', 'source': 'claude'} => ['hello from the end-to-end test']
```

(`detected_level` and `service_name` are auto-added by Loki 3.x.)

## Gotcha encountered: malformed JSON → HTTP 400

The first push attempt used `...]]}}` (missing the `]` that closes the `streams`
array) and returned **HTTP 400**. The distributor log gave the exact reason —
proving the request *reached* the distributor (write path wired), it was just
bad input:

```bash
aws logs filter-log-events --log-group-name "/ecs/loki-distributor" \
  --start-time $(( ($(date +%s) - 180) * 1000 )) \
  --query 'events[].message' --output text | tail -5
```

```
level=error ... component=distributor path=write msg="write operation failed"
details="couldn't parse push request: ... decode slice: expect ], but found }
... |...hello from the end-to-end test"]]}}|..." org_id=fake
```

Fix: balance the brackets → `...]]}]}`. A 400 here is a client/payload error,
not an infrastructure problem.

## Result

✅ Push `204`, query returned the exact line. Both paths and the full internal
gRPC mesh / Cloud Map DNS / memberlist ring are confirmed working. At this point
the line lives in the **ingester's in-memory head chunk** — see scenario 03 to
persist it to S3.
