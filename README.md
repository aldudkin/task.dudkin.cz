#### Funkční požadavky

- Sběr logů z: ECS (hlavní požadavek), EC2 (syslog, nginx access log…), Kubernetes, serverů mimo AWS.
- Čtení logů koncovým uživatelem (developerem) přes UI s dotazovacím jazykem.
- CLI přístup výhodou.
- Plný text logu není potřeba indexovat — stačí grep. Naopak vyhledávání podle
  času musí být indexované.
- 5 TB dat/denně, převážně AWS služby (musí se brát v potaz zpoplatnění egress trafiku v AWS).

#### AWS egress příplatek
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
| ECS EC2| Per-service autoscaling, Hlavní zdroj logů, Možnost rezervovat compute předem se slevou a používat spot instance pro fault-tolerant workloady| Optimální volba pro prod z hlediska ceny |
| ECS Fargate| Per-service autoscaling, Hlavní zdroj logů, žádná správa nodů (Fargate) | Optimální volba pro PoC |

Příklady výpočtů ceny compute time

Cena jedné nepřetržitě běžící Fargate úlohy (ARM/Graviton, 2 vCPU, 8 GB, eu-central-1, 730 h/měs):

| Položka | Výpočet | Cena/měs |
|---|---|---|
| vCPU | 730 h × 2 vCPU × 0,03725 USD | 54,39 USD |
| Paměť | 730 h × 8 GB × 0,00409 USD | 23,89 USD |
| Ephemeral storage | 20 GB (prvních 20 GB zdarma) | 0,00 USD |
| **Celkem** | | **78,28 USD** |

Cena jedné nepřetržitě běžící m7g.large EC2 instance (2 vCPU, 8 GB, eu-central-1, 730 h/měs):

| Položka | Výpočet | Cena/měs |
|---|---|---|
| On-Demand cena | 730 h × 0,0978 USD | 71,39 USD |
| EBS storage | 20 GB × 0,0952 USD | 1,90 USD |
| **Celkem** | | **73,29 USD** |

Výpočet nezahrnuje EC2 Instance Savings Plans, které nabízejí hlubší slevy než Compute Savings Plans pro Fargate — pro trvalou zátěž tak EC2 backend z hlediska ceny dává větší smysl.

#### Úložiště pro logy

| Možnost | Vlastnosti | Verdikt |
|---|---|---|
| File system (EBS/NVMe) | Nízká latence, žádné poplatky za request, ale drahé za GB a kapacita roste s retencí | Suboptimální |
| S3 | Vyšší latence, levné úložiště, poplatky za requesty (Loki Memcached cache jako optimalizace počtu GET) | Optimální |

#### S3 Encryption at rest

| Možnost | Správa klíče | Bezpečnost (šifra je u obou AES-256) | Placená služba? | Verdikt |
|---|---|---|---|---|
| SSE-KMS | Uživatel (vlastní KMS klíč) | druhý zámek (`kms:Decrypt`) + audit v CloudTrail + revokace pro compliance + S3 admin nemůže číst data| ano (klíč ~$1/měs + per-request volání) | Suboptimální |
| SSE-S3 (AES256) | AWS, automaticky a skrytě | Chrání at-rest; transparentní — každý, kdo má `s3:GetObject`, čte | ne | Optimální pro podmínky ze zadání|
