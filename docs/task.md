Cílem je navrhnout systém pro logování v prostředí AWS za použití jiné technologie než jsou CloudWatch Logs. Navržené řešení by mělo být schopné sbírat logy z:
- AWS ECS (z běžících docker kontejnerů) - toto je hlavní požadavek
- AWS EC2 (syslog, nginx access log, …)
- server běžící mimo prostředí AWS
- Kubernetes
- …

Logovací systém by měl být dostatečně robustní v případném produkčním použití, snadno škálovatelné na potenciálních > 5TB zpráv denně a mělo by odpovídat současnému industry standardu. Koncový uživatel (např. developer) bude mít možnost logy číst skrze UI pomocí dotazovacího jazyku. Text logu není třeba indexovat, stačí vyhledávání pomocí grepu. Naopak vyhledávání podle času by mělo být dostatečně rychlé, takže pravděpodobně nějak indexované. Možnost čtení logů přes CLI je výhodou.

Nevýhody CloudWatch Logs, na než by mělo vybrané řešení cílit:
- drahý ingest
- nemožnost snadného vyhledávání napříč službami (log groups)
- custom tagování/labelování logovacích zpráv (nice-to-have, není nutné)

Vybrané řešení by tedy mělo splnit všechny zadané požadavky a zároveň být co nejlevnější při objemu logů ~5TB / den.

Úloha má 2 fáze:
1. připravit stručný návrh řešení, jak bys k tomuto problému přistoupil a jak bys to celé nastavil. Následně proběhne krátká konzultace, kde nám svůj design představíš (analýzu nám prosím pošli předem, ideálně i rovnou s funkčním PoC :))
2. reálné nasetupování v minimální funkční verzi na osobním pohovoru u nás na Andělu společně s třetím závěrečným kolem pohovoru