# Avtalsmallar (svenska) — nät, säkerhet och datacenter

Tre avtalsmallar för en svensk operatör som säljer dedikerad fiber, skyddad
internetanslutning och privat AI-drift på kundägd hårdvara.

## Varför de ligger här och inte i en migration

De är **verksamhetsdata, inte plattformskonfiguration.** En ny FlowWink-instans
ska födas utan dem — ett bokföringsbolag har ingen nytta av en svartfibermall.
Reglerna i CLAUDE.md ("Distinguish platform config … from business config") gör
detta till en seedning per instans, inte en migration som körs överallt.

Filerna är källan; `seed-optic.sql` lägger in dem i `contract_templates` på den
instans där de hör hemma.

## Tokens

Mallarna använder bara de token `create_contract_from_template()` faktiskt
renderar:

| Token | Fylls med |
|---|---|
| `{{counterparty.name}}` | Kundens namn |
| `{{counterparty.email}}` | Kundens e-post |
| `{{today}}` | Dagens datum |
| `{{start_date}}` | Avtalets startdatum |
| `{{end_date}}` | Avtalets slutdatum |
| `{{value}}` | Avtalsvärde |
| `{{currency}}` | Valuta |
| `{{title}}` | Avtalets titel |

Allt annat som måste fyllas i står som `[HAKPARENTES]` — det är avsiktligt
synligt och gör ett halvfyllt avtal omöjligt att missa. Lägg **aldrig** till
egna `{{...}}`-token: de renderas inte, och ett `{{sträckans_längd}}` som blir
kvar i ett undertecknat avtal ser ut som ett fel hos leverantören.

## Juridisk status

**Mallarna är underlag, inte juridisk rådgivning.** De är skrivna mot svensk
rätt och svensk branschpraxis (se källhänvisningarna i varje mall), men tre
saker måste en jurist gå igenom innan de används skarpt:

1. **Separationsrätten i AI-mallen** — att kundens hårdvara står hos oss men
   ägs av kunden är den juridiskt svåraste konstruktionen av de tre. Mallen
   bygger på att kunden köper direkt av hårdvaruleverantören (spår B i
   avsnitt 4). Köper kunden av *oss* och utrustningen aldrig lämnar vårt
   datacenter finns ingen separationsrätt utan lösöreköplagens fulla procedur.
2. **DPI/innehållsanalys i säkerhetsmallen** — ligger nära LEK 9 kap. 31–35 §§
   om tystnadsplikt. Mallen har den som tillval på kundens dokumenterade
   instruktion, men klausulen bör granskas av telekomjurist.
3. **Er egen regelstatus** — som leverantör av allmänt kommunikationsnät är ni
   sannolikt anmälningspliktiga hos PTS *och* verksamhetsutövare enligt
   cybersäkerhetslagen (2025:1506). Det påverkar vad ni får lova i avtalen.

Personuppgiftsbiträdesavtal (PUB) och säkerhetsskyddsavtal (SUA) refereras som
bilagor men ingår inte här — de skrivs separat.
