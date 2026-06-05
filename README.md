#### Funkční požadavky

- Sběr logů z: ECS (hlavní požadavek), EC2 (syslog, nginx access log…), Kubernetes, serverů mimo AWS.
- Čtení logů koncovým uživatelem (developerem) přes UI s dotazovacím jazykem.
- CLI přístup výhodou.
- Plný text logu není potřeba indexovat — stačí grep. Naopak vyhledávání podle
  času musí být indexované.
- 5 TB dat/denně, převážně AWS služby (musí se brát v potaz zpoplatnění egress trafiku v AWS).

#### AWS egress připlatek
S předpokladem 5 TB denně z AWS Frankfurt → internet, čistě egress podle [AWS kalkulačky](https://calculator.aws/#/createCalculator/ec2-enhancement):
- Internet: 150 TB/měsíc = 11 571,20 USD

Fakticky to znemožňuje smysluplné použití Cloudflare R2 či jiné cloudové služby — uložení a zpracování dat je potřeba dělat v AWS.

- Za předpokladu, že všechna data zpracováváme uvnitř jednoho AWS regionu, k developerovi poteče jen vyrenderovaný výsledek (malý zlomek zpracovaných dat).

Klíčové rozlišení v AWS pricingu:

| Tok | Směr | Cena |
|---|---|---|
| Logy z ECS/EC2 v AWS → Loki v AWS | interní | $0/GB (žádný egress) |
| Logy z on-prem serverů / K8s → Loki v AWS | ingress | $0/GB (příchozí data jsou zdarma) |
| Loki ↔ S3 ve stejném regionu (Gateway Endpoint) | interní | $0/GB |
| Grafana/logcli → developer (přes internet) | egress | $0,09/GB, ale malý objem |

#### Logovací řešení — Loki

| | Loki | OpenSearch |
|---|---|---|
| **Obsah block storage** | Index cache | Celý searchable index |
| **Škáluje s čím** | Ingest rate (konstantní vůči objemu udržovaných dat) | Velikost indexu a objem dat vynásobené počtem redundantních replik (v případě Loki se logy replikují automaticky v S3) |
| **Důsledek** | Malý fixní lokální disk | Velké a rostoucí požadavky na NVMe storage |

> "Unlike other logging systems, Grafana Loki is built around the idea of only indexing metadata about your logs: labels (just like Prometheus labels). Log data itself is then compressed and stored in chunks in object stores such as S3 or GCS, or even locally on the filesystem. A small index and highly compressed chunks simplifies the operation and significantly lowers the cost of Loki." [Zdroj](https://grafana.com/docs/loki/latest/configure/storage/)

OpenSearch má navíc inverted index (pro full-text), který Loki nepočítá → menší storage i ingest compute, cenou je scan za běhu místo předpočítaných struktur — *stále splňuje zadání*.


#### Mapování požadavků na řešení

| Požadavek | Řešení v Loki ekosystému |
|---|---|
| Sběr z ECS | AWS FireLens (sidecar), output do Loki |
| Sběr z EC2 / K8s / mimo AWS | Grafana Alloy agent |
| UI + dotazovací jazyk | LogQL |
| CLI | logcli |
| Rychlé hledání podle času | TSDB index (labely + čas) |
| Custom tagování | Nativní labely |
| Levný ingest při 5 TB/den | Obsah na S3, index minimální → nízká cena |

#### Volba hostingu

| Možnost | Vlastnosti | Verdikt |
|---|---|---|
| On-prem / jiný cloud provider | Egress fees | Suboptimální |
| EKS | Per-service autoscaling, Overhead správy Kubernetes nodů — upgrady a poplatky za control plane | Suboptimální |
| ECS | Per-service autoscaling, Hlavní zdroj logů, žádná správa nodů (Fargate) | Optimální volba |


#### Úložiště pro logy

| Možnost | Vlastnosti | Verdikt |
|---|---|---|
| File system (EBS/NVMe) | Nízká latence, žádné poplatky za request, ale drahé za GB a kapacita roste s retencí | Suboptimální |
| S3 | Vyšší latence, levné úložiště, poplatky za requesty (Loki Memcached cache jako optimalizace počtu GET) | Optimální |

#### Encryption at rest

| Možnost | Správa klíče | Bezpečnost (šifra je u obou AES-256) | Placená služba? | Verdikt |
|---|---|---|---|---|
| SSE-S3 (AES256) | AWS, automaticky a skrytě | Chrání at-rest; transparentní — každý, kdo má `s3:GetObject`, čte | ne | Optimální pro podmínky za zadání|
| SSE-KMS | Uživatel (vlastní KMS klíč) | druhý zámek (`kms:Decrypt`) + audit v CloudTrail + revokace pro compliance + S3 admin nemůže číst data| ano (klíč ~$1/měs + per-request volání) | Suboptimální |
