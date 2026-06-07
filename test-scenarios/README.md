# LLM-Generated Test scenarios

Manual verification of the Loki stack after `terraform apply` (from `loki/`).
These document exactly what was run to prove the deployment works end-to-end,
including data creation (push/query) and durable storage (flush to S3).

> All commands are read-only against AWS except scenario 03, which makes a
> **temporary, self-reverting** security-group change (clearly marked).

## Scenarios

| # | File | Proves |
|---|------|--------|
| 01 | [01-service-health.md](01-service-health.md) | All components running, ALB target healthy, no errors |
| 02 | [02-push-and-query.md](02-push-and-query.md) | Write path + read path (data creation round-trip) |
| 03 | [03-force-flush-s3.md](03-force-flush-s3.md) | Ingester flush → chunk persisted to S3 |

## Shared setup

Every scenario assumes these are exported (region `eu-central-1`, creds with
read access + the ability to push/query through the public ALB):

```bash
export AWS_DEFAULT_REGION=eu-central-1
export CLUSTER=loki-grafana
export BUCKET=loki-data-366112400496-eu-central-1
# ALB DNS is derived (it changes if the stack is destroyed/recreated):
export ALB=$(aws elbv2 describe-load-balancers --names loki-alb \
  --query 'LoadBalancers[0].DNSName' --output text)
echo "ALB = $ALB"
```

## Notes / gotchas discovered during testing

- **Loki image is distroless** (`grafana/loki`): no `/bin/sh`. The config is
  delivered by a busybox init container writing to a shared volume; `loki` is
  launched with an explicit `entryPoint`/`command`. (See `loki/loki-components.tf`.)
- **`scheduler_address` / index `server_address` must be plain `host:port`** —
  not gRPC's `dns:///` (rejected: "invalid target address") and not dskit's
  `dns+` (that prefix is only for memberlist/ring discovery).
- **`/flush` is internal**: it lives on the ingester's `:3100`, which the ALB
  does not route and the `loki-internal` SG does not expose. See scenario 03 for
  the temporary, scoped, auto-reverted access used to reach it.
