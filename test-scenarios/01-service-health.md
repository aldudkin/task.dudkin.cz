# 01 — Service health

**Goal:** confirm every component is running, the ALB target is healthy, and no
component is logging errors. Pure read-only checks.

## Commands run

### 1. ECS services — running vs desired

```bash
aws ecs list-services --cluster "$CLUSTER" --query 'serviceArns' --output text \
  | tr '\t' '\n' | sed 's#.*/##' | while read svc; do
    read run des < <(aws ecs describe-services --cluster "$CLUSTER" --services "$svc" \
      --query 'services[0].[runningCount,desiredCount]' --output text)
    echo "$svc: running=$run desired=$des"
  done
```

Expected — every service `running == desired == 1`:

```
loki-distributor: running=1 desired=1
loki-ingester: running=1 desired=1
loki-query-frontend: running=1 desired=1
loki-query-scheduler: running=1 desired=1
loki-querier: running=1 desired=1
loki-index-gateway: running=1 desired=1
loki-compactor: running=1 desired=1
loki-nginx-gateway: running=1 desired=1
```

### 2. ALB target health (the nginx gateway)

```bash
TG_ARN=$(aws elbv2 describe-target-groups --names loki-nginx-gateway-target-group \
  --query 'TargetGroups[0].TargetGroupArn' --output text)
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].{IP:Target.Id,State:TargetHealth.State}' --output table
```

Expected — `State = healthy` (the gateway answers the `/` health check locally,
so it is healthy even before any logs flow):

```
| IP             | State   |
| 172.31.36.162  | healthy |
```

### 3. Error scan (last 10 minutes, per component)

```bash
for c in distributor ingester query-frontend query-scheduler querier index-gateway compactor; do
  n=$(aws logs filter-log-events --log-group-name "/ecs/loki-$c" \
       --start-time $(( ($(date +%s) - 600) * 1000 )) \
       --filter-pattern 'level=error' --query 'length(events)' --output text)
  echo "loki-$c: error_lines=$n"
done
```

Expected — `error_lines=0` for every component.

## Result

✅ 8/8 services running, ALB target healthy, 0 error lines. Stack came up clean.
"No errors" is necessary but not sufficient — scenario 02 proves it actually works.
