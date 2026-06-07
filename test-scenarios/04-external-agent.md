# 04 — External (non-AWS) agent shipping logs

**Goal:** simulate the design's **"servers outside AWS"** log source — a Linux box
that is *not* in your VPC, generating logs continuously and shipping them to Loki
over the internet via the public ALB write endpoint, using **Grafana Alloy** (the
agent the design specifies for EC2 / K8s / on-prem).

This proves the end-to-end ingest path for a real, remote agent (not just `curl`).

## How traffic flows

```
[ non-AWS box ]  flog --> file --> Grafana Alloy
        |  HTTPS POST /loki/api/v1/push
        v
https://<your-domain>/loki/api/v1/push        (ACM cert, same domain as Grafana)
        |  :443 listener, rule "/loki/*" (priority 100) --> gateway TG
        v
nginx gateway :8080 --> distributor :3100 --> ingester --> S3
```

> **TLS:** agents push over **HTTPS on :443**, terminated at the ALB with the same
> ACM cert as Grafana (the `/loki/*` rule on the `:443` listener). Use the **cert
> hostname** (e.g. `grafana.<your-domain>`), **not** the raw `…elb.amazonaws.com`
> (that would cert-mismatch). The plaintext `:80` `/loki/*` path still works as a
> fallback for in-VPC / test agents.

## Prerequisites

```bash
export AWS_DEFAULT_REGION=eu-central-1
# The hostname your ACM cert covers (same domain as Grafana), pointed at the ALB in DNS:
export LOKI_DOMAIN=task.dudkin.cz
# Raw ALB DNS — only for operator-side curl checks over :80 (cert does NOT cover it):
export ALB=$(aws elbv2 describe-load-balancers --names loki-alb \
  --query 'LoadBalancers[0].DNSName' --output text)
echo "Agent write endpoint: https://$LOKI_DOMAIN/loki/api/v1/push"
```

The `loki-alb` SG allows `:80` and `:443` from `admin_cidr` (currently `0.0.0.0/0`),
so any internet host can reach it. Single-tenant (`auth_enabled: false`) → no
`X-Scope-OrgID` header needed; logs land under the `fake` tenant, same as Grafana
queries, so they show up in the UI automatically.

---

## Option A — fastest: Docker Compose on any non-AWS machine

Run this on your laptop, a home server, or a non-AWS VPS (Hetzner/DigitalOcean) —
anything outside the VPC. Two containers: `flog` generates fake Apache logs to a
file; `alloy` tails the file and ships to Loki.

`docker-compose.yml`:

```yaml
services:
  flog:                                   # steady fake-log generator
    image: mingrammer/flog
    command: ["-f","apache_combined","-l","-d","1s","-t","log","-o","/logs/app.log"]
    volumes: [ "logs:/logs" ]
    restart: unless-stopped

  alloy:                                  # the agent: tail file -> push to Loki
    image: grafana/alloy:latest
    command:
      - run
      - --server.http.listen-addr=0.0.0.0:12345
      - /etc/alloy/config.alloy
    volumes:
      - "logs:/logs"
      - "./config.alloy:/etc/alloy/config.alloy:ro"
    restart: unless-stopped

volumes:
  logs:
```

`config.alloy` (replace `LOKI_DOMAIN`):

```alloy
// Which file to tail + the labels each line gets.
local.file_match "app" {
  path_targets = [{
    __path__ = "/logs/app.log",
    job      = "flog",
    host     = "testbox-onprem",
    env      = "test",
  }]
}

loki.source.file "app" {
  targets    = local.file_match.app.targets
  forward_to = [loki.write.default.receiver]
}

loki.write "default" {
  endpoint {
    url = "https://LOKI_DOMAIN/loki/api/v1/push"
  }
}
```

Run it:

```bash
sed -i "s/LOKI_DOMAIN/$LOKI_DOMAIN/" config.alloy   # inject the cert hostname
docker compose up -d
docker compose logs -f alloy                        # watch for successful pushes (no 4xx/5xx)
```

---

## Option B — realistic: a Linux VM/VPS with systemd

Closest to a real on-prem server. Use a non-AWS VM (Multipass `multipass launch`,
a Hetzner/DO droplet, etc.), then:

```bash
sudo mkdir -p /var/log/testapp
sudo tee /usr/local/bin/loggen.sh >/dev/null <<'EOF'
#!/bin/sh
i=0
while true; do
  i=$((i + 1))
  echo "$(date -u -Iseconds) level=info msg=\"heartbeat\" host=$(hostname) req=$i" >> /var/log/testapp/app.log
  sleep 2
done
EOF
sudo chmod +x /usr/local/bin/loggen.sh

sudo tee /etc/systemd/system/loggen.service >/dev/null <<'EOF'
[Unit]
Description=steady test log generator
[Service]
ExecStart=/usr/local/bin/loggen.sh
Restart=always
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now loggen

# 2. Install Grafana Alloy (Debian/Ubuntu)
sudo mkdir -p /etc/apt/keyrings
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg >/dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update && sudo apt-get install -y alloy

# 3. Configure Alloy (same config.alloy as Option A, but __path__ = /var/log/testapp/app.log)
sudo tee /etc/alloy/config.alloy >/dev/null <<EOF
local.file_match "app" {
  path_targets = [{ __path__ = "/var/log/testapp/app.log", job = "loggen", host = "$(hostname)", env = "test" }]
}
loki.source.file "app" {
  targets    = local.file_match.app.targets
  forward_to = [loki.write.default.receiver]
}
loki.write "default" {
  endpoint { url = "https://$LOKI_DOMAIN/loki/api/v1/push" }
}
EOF
sudo systemctl enable --now alloy
sudo systemctl status alloy --no-pager
```

---

## Verify the logs arrived

Operator-side checks below use `http://$ALB` (raw ALB, no cert needed). The same
queries work over `https://$LOKI_DOMAIN` if you prefer the cert hostname.

```bash
# the agent's labels should now be discoverable
curl -s "http://$ALB/loki/api/v1/label/job/values" | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"])'
# expect to see "flog" (Option A) or "loggen" (Option B) alongside "smoketest"

# tail the stream
NOW_NS=$(( $(date +%s) * 1000000000 ))
curl -s -G "http://$ALB/loki/api/v1/query_range" \
  --data-urlencode 'query={host="testbox-onprem"}' \
  --data-urlencode "start=$(( NOW_NS - 300000000000 ))" --data-urlencode "end=$NOW_NS" \
  --data-urlencode 'limit=5' \
  | python3 -c 'import sys,json;[print(v[1]) for s in json.load(sys.stdin)["data"]["result"] for v in s["values"]]'
```

In **Grafana**: Explore → Loki → `{job="flog"}` (or `{job="loggen"}`), set the range
to *Last 15 minutes*, toggle **Live** to watch it stream in real time.

## What this proves

✅ A genuinely external agent (outside the VPC) can discover the public write
endpoint, push continuously, and have its logs flow through the same
ALB → gateway → distributor → ingester → S3 pipeline — exactly the "non-AWS
servers" requirement from the design.

## Cleanup

```bash
docker compose down -v        # Option A
sudo systemctl disable --now alloy loggen   # Option B
```
