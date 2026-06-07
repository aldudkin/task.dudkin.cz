# 03 — Force flush to S3 (durable storage)

**Goal:** prove the storage leg — that the ingester flushes chunks to the S3
bucket (the cost-saving core of the design). A freshly-pushed line sits in the
ingester's memory until `chunk_idle_period` (default 30m); Loki's `/flush` admin
endpoint forces it immediately.

## The access problem

`/flush` is on the **ingester's `:3100`**, which is intentionally not reachable:

- the ALB / nginx gateway only route `/loki/api/v1/push` and `/loki/...`, not `/flush`;
- the `loki-internal` SG only admits the gateway + the mesh, not the public internet;
- ECS Exec is unavailable — the distroless `grafana/loki` image has no shell.

So we open the ingester to **our IP only** (`/32`), for a few seconds, **outside
Terraform** (via the CLI) so it self-reverts with **zero net state drift**.

## 0. Confirm the bucket is empty (before)

```bash
aws s3 ls "s3://$BUCKET" --recursive | wc -l    # expect: 0
```

## 1. Temporary scoped access + flush + auto-revoke

A `trap` guarantees the temporary rule is removed even if the curl fails.

```bash
SG=$(aws ec2 describe-security-groups --filters Name=group-name,Values=loki-internal \
  --query 'SecurityGroups[0].GroupId' --output text)
MYIP=$(curl -s https://checkip.amazonaws.com | tr -d '\n')
TASK=$(aws ecs list-tasks --cluster "$CLUSTER" --service-name loki-ingester \
  --query 'taskArns[0]' --output text)
ENI=$(aws ecs describe-tasks --cluster "$CLUSTER" --tasks "$TASK" \
  --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value" --output text)
PUBIP=$(aws ec2 describe-network-interfaces --network-interface-ids "$ENI" \
  --query 'NetworkInterfaces[0].Association.PublicIp' --output text)
echo "SG=$SG  myIP=$MYIP  ingester=$PUBIP"

cleanup() { aws ec2 revoke-security-group-ingress --group-id "$SG" \
  --protocol tcp --port 3100 --cidr "$MYIP/32" >/dev/null 2>&1 && echo "temp rule revoked"; }
trap cleanup EXIT

aws ec2 authorize-security-group-ingress --group-id "$SG" \
  --protocol tcp --port 3100 --cidr "$MYIP/32" >/dev/null && echo "temp rule added"
sleep 2
curl -s -o /dev/null -w "flush HTTP %{http_code}\n" -XPOST "http://$PUBIP:3100/flush"
sleep 8
```

Expected: `flush HTTP 204`, then `temp rule revoked`.

## 2. Confirm the chunk landed (after)

```bash
aws s3 ls "s3://$BUCKET" --recursive --human-readable
```

Expected — one chunk object:

```
2026-06-07 14:41:01  415 Bytes  fake/2b7eb760989153f1/19ea21629b0:19ea21629b0:5e309c9b
```

### Object key anatomy

```
fake / 2b7eb760989153f1 / 19ea21629b0:19ea21629b0:5e309c9b
 |            |                          |
 tenant   stream fingerprint        chunk id (from:through:checksum)
(org_id)  (hash of the labels)
```

415 bytes = the single log line, **compressed**. (TSDB `index/…` objects appear
later on the shipper's own upload cycle; the chunk is the durable log data.)

## Security / cleanup notes

- The opening was scoped to a single `/32` (not the wide `admin_cidr`) and lived
  only for the duration of the flush.
- It was made with `aws ec2 authorize/revoke-security-group-ingress`, **not**
  Terraform — added and removed in the same run, so `terraform plan` shows **no
  drift** afterward. Verify with:

  ```bash
  aws ec2 describe-security-group-rules \
    --filters Name=group-id,Values=$SG \
    --query "SecurityGroupRules[?CidrIpv4=='$MYIP/32']"   # expect: []
  ```

## Result

✅ Chunk persisted to S3. The full pipeline — ingest → query → durable object
storage — is proven, including the cheap-storage property that is the whole
point of choosing Loki over CloudWatch Logs.
