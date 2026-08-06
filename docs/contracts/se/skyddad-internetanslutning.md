# Avtal om skyddad internetanslutning

**Avtalsnummer:** [AVTALSNR]
**Upprättat:** {{today}}

## 1. Parter

**Leverantör**
[LEVERANTÖRENS FIRMA], org.nr [ORGNR]
[ADRESS]
Anmäld hos Post- och telestyrelsen enligt 2 kap. 1 § lagen (2022:482) om
elektronisk kommunikation (LEK).

**Kund**
{{counterparty.name}}
E-post: {{counterparty.email}}
Org.nr: [KUNDENS ORGNR]
Adress: [KUNDENS ADRESS]

## 2. Tjänsten

Leverantören tillhandahåller internetanslutning med säkerhetsfunktioner enligt
Bilaga 1. Anslutningen är avskild i det fysiska lagret — egen kanalisation och
egen fiber, inte mjukvarupartitionering i ett delat nät.

| Komponent | Ingår | Beskrivning |
|---|---|---|
| Internetaccess | Ja | [X] Mbit/s symmetriskt, [antal] fasta IPv4-adresser, IPv6-prefix [/48 alt. /56] |
| DDoS-skydd | [Ja/Nej] | Volymetriskt skydd med automatisk mitigering |
| Brandvägg | [Ja/Nej] | [Managerad CPE / molnbaserad] regeluppsättning |
| Hotdetektering | [Ja/Nej] | Analys av flödesdata, larm till Kundens kontaktväg |
| Loggning | [Ja/Nej] | Säkerhetsloggar enligt punkt 8 |
| Innehållsanalys (DPI) | **[Nej som standard]** | Endast enligt punkt 8.4 |

**2.1 Tjänstens karaktär.** Leverantören utför tjänsten **fackmannamässigt och
med den omsorg som är sedvanlig i branschen**. Åtagandet är en
medelförpliktelse, inte en resultatförpliktelse.

**2.2 Ingen garanti mot intrång.** Säkerhetsfunktionerna minskar risken för
intrång, dataförlust och driftstörning — de **eliminerar den inte**. Leverantören
garanterar inte att angrepp förhindras, att skadlig kod stoppas eller att data
inte går förlorade. Kunden ansvarar för sitt eget informationssäkerhetsarbete,
sina säkerhetskopior och sin kontinuitetsplanering.

## 3. Kundens medverkan

SLA enligt punkt 5 gäller endast under förutsättning att Kunden:

- håller egna system uppdaterade och patchade enligt leverantörernas anvisningar,
- meddelar aktuella kontaktuppgifter för larm och incidenter och håller dessa uppdaterade,
- inte ändrar Leverantörens konfiguration utan skriftligt medgivande,
- utan dröjsmål lämnar den information Leverantören begär vid incidenthantering,
- ansvarar för sin egen användning av anslutningen och att den inte strider mot lag.

## 4. Leverans

Avtalad leveransdag är **[DATUM]**. Leveransen är godkänd när anslutningen är
uppkopplad, säkerhetsfunktionerna enligt punkt 2 är aktiverade och driftsatta,
och Kunden inte inom **10 arbetsdagar** skriftligen påtalat brist.

## 5. Servicenivå

**5.1 Tillgänglighet:** [99,5 % / 99,9 %] per kalendermånad för
internetaccessen, mätt i Leverantörens överlämningspunkt.

**5.2 Prioritetsklasser och svarstider (dygnet runt):**

| Klass | Definition | Svarstid | Åtgärd påbörjas |
|---|---|---|---|
| P1 Kritisk | Anslutningen nere, eller pågående angrepp med driftpåverkan | 1 h | Omedelbart |
| P2 Hög | Betydande funktionsnedsättning, redundans förlorad | 4 h | Inom servicetid |
| P3 Normal | Enstaka funktion ur drift utan driftpåverkan | 1 arbetsdag | Inom servicetid |
| P4 Låg | Frågor, ändringar, rapportbeställningar | 3 arbetsdagar | Enligt överenskommelse |

**5.3 DDoS-mitigering:** automatisk mitigering påbörjas inom **60 sekunder**
från detekterad volymetrisk attack; manuellt ingripande inom **15 minuter**
under P1.

**5.4 Vite.** Vid underskriden tillgänglighet krediteras [X] % av
månadsavgiften per påbörjad procentenhet under nivån, dock högst **[25] % av
månadsavgiften per månad**. Vitet är Kundens **enda påföljd** vid SLA-brott och
ska åberopas skriftligen inom 30 dagar.

**5.5 Undantag från SLA.** Planerat underhåll enligt 5.6, avbrott orsakade av
Kundens egen utrustning eller konfiguration, force majeure, samt angrepp av
exceptionell omfattning eller karaktär (inklusive statsunderstödda angrepp och
utnyttjande av sårbarheter för vilka rättelse ännu inte publicerats av
tillverkaren) räknas inte som avbrott.

**5.6 Planerat underhåll:** högst [4] timmar per tillfälle, förlagt
måndag–torsdag kl. 00:00–06:00, aviserat minst **10 arbetsdagar** i förväg.
Akut säkerhetsuppdatering får utföras utan föregående avisering; Kunden
underrättas snarast därefter.

## 6. Incidenthantering och rapportering

**6.1 Underrättelse till Kunden.** Leverantören underrättar Kunden om
säkerhetsincident som påverkar Kundens tjänst:

| Allvarlighetsgrad | Underrättelse senast |
|---|---|
| P1 — pågående angrepp eller konstaterat intrång | **4 timmar** från identifiering |
| P2 — misstänkt intrång eller betydande avvikelse | **12 timmar** från identifiering |
| Övriga | I månadsrapport |

Med "identifiering" avses den tidpunkt Leverantören fått kännedom om
omständigheter som ger skälig anledning att anta att en incident inträffat.

**6.2 Varför fristerna är korta.** Är Kunden verksamhetsutövare enligt
cybersäkerhetslagen (2025:1506) börjar Kundens frist för tidig varning löpa vid
Kundens identifiering. Leverantören ska larma i så god tid att Kunden hinner
fullgöra sina skyldigheter: **tidig varning inom 24 timmar**, **incidentanmälan
inom 72 timmar** och **slutrapport inom en månad** till NCSC/CERT-SE.

**6.3 Underlag.** Leverantören lämnar utan särskild ersättning det tekniska
underlag Kunden behöver för sin anmälan — tidslinje, berörda system, vidtagna
åtgärder och bedömd påverkan — samt medverkar i slutrapporteringen.

**6.4 Egen rapporteringsplikt.** Leverantören har egen anmälningsskyldighet
enligt cybersäkerhetslagen och LEK. Parterna ska samordna sina beskrivningar av
en gemensam incident så att rapporterna inte motsäger varandra. Sekretessen i
punkt 10 hindrar inte någondera Part från att fullgöra rapporteringsskyldighet
enligt lag eller myndighetsbeslut.

**6.5 Kontaktväg.** Leverantörens larmfunktion är bemannad dygnet runt:
[TELEFON] / [E-POST]. Kundens kontaktpersoner anges i Bilaga 2.

## 7. Säkerhetsarbete

Leverantören bedriver ett systematiskt informationssäkerhetsarbete enligt
[ISO/IEC 27001 alt. motsvarande ramverk] och tillämpar riskhanteringsåtgärder
enligt 3 kap. cybersäkerhetslagen, inklusive säkerhet i leveranskedjan.
Leverantören ska på Kundens begäran, dock högst en gång per år, redovisa
gällande certifikat, revisionsrapporter och en förteckning över underleverantörer
som medverkar i tjänsten.

Kunden har rätt att på egen bekostnad genomföra revision av Leverantörens
efterlevnad av detta avtal, efter skriftlig begäran minst 30 dagar i förväg och
under sekretess.

## 8. Personuppgifter, loggar och kommunikationsskydd

**8.1 Roller.** När Leverantören loggar, filtrerar eller analyserar Kundens
trafik för Kundens räkning är Leverantören **personuppgiftsbiträde**.
Personuppgiftsbiträdesavtal enligt artikel 28 dataskyddsförordningen (EU)
2016/679 utgör Bilaga 3. För abonnent- och trafikuppgifter som Leverantören
behandlar enligt LEK är Leverantören **självständigt personuppgiftsansvarig**.

**8.2 Lagringstid.** Säkerhetsloggar lagras i **[6] månader** och därefter
raderas de. Tiden är satt utifrån behovet av att kunna utreda incidenter i
efterhand och får inte förlängas utan dokumenterad grund. Loggar med
IP-adresser och tidsstämplar är personuppgifter.

**8.3 Tystnadsplikt.** Leverantören omfattas av 9 kap. 31–35 §§ LEK och får
inte obehörigen föra vidare uppgift om abonnemang, innehåll i elektroniskt
meddelande eller uppgift som angår ett särskilt meddelande.

**8.4 Innehållsanalys (DPI).** Tjänsten omfattar som standard **endast
metadata och flödesdata**. Innehållsinspektion aktiveras enbart om det
uttryckligen beställts i Bilaga 1 och sker då **på Kundens dokumenterade
instruktion**. Kunden garanterar i så fall att Kunden har rättslig grund för
behandlingen och har informerat sina användare enligt tillämplig lag.

**8.5 Datalokalisering.** All behandling sker inom EU/EES. Överföring till
tredjeland sker inte utan Kundens skriftliga medgivande och då endast med
giltig överföringsgrund enligt kapitel V dataskyddsförordningen.

## 9. Säkerhetsskyddad verksamhet

Omfattar leveransen säkerhetskänslig verksamhet enligt säkerhetsskyddslagen
(2018:585) ska **säkerhetsskyddsavtal (SUA)** träffas separat innan sådan del av
leveransen påbörjas. Kunden ansvarar för att i god tid meddela Leverantören om
detta blir aktuellt och för samråd med tillsynsmyndigheten. Utan SUA får
Leverantören inte ges tillgång till säkerhetsskyddsklassificerade uppgifter.

## 10. Sekretess

Vardera Part förbinder sig att inte utan motpartens medgivande röja
konfidentiell information. Åtagandet gäller under avtalstiden och **tre (3) år**
därefter, och hindrar inte fullgörande av rapporteringsskyldighet enligt punkt 6.4.

## 11. Avgifter och betalning

| Post | Belopp |
|---|---|
| Engångsavgift | [BELOPP] {{currency}} |
| Månadsavgift | [BELOPP] {{currency}} |
| Avtalsvärde (period) | {{value}} {{currency}} |

Betalningsvillkor 30 dagar netto, exklusive mervärdesskatt. Dröjsmålsränta
enligt räntelagen (1975:635). Prisjustering en gång per år enligt SCB:s
konsumentprisindex (KPI), meddelad minst tre månader i förväg.

## 12. Avtalstid

Avtalet gäller från {{start_date}} till {{end_date}}, dock minst **[ANTAL]
månader** från leveransgodkännande. Uppsägning ska ske skriftligen senast
**3 månader** före periodens utgång. Sägs avtalet inte upp gäller det **tills
vidare** med tre månaders ömsesidig uppsägningstid — ingen ny bindningstid
uppstår.

Vardera Part får häva avtalet med omedelbar verkan om motparten begår väsentligt
avtalsbrott och inte vidtar rättelse inom 30 dagar från skriftlig anmodan, eller
om motparten försätts i konkurs eller inleder företagsrekonstruktion.

## 13. Ansvar

**13.1** Leverantörens sammanlagda ansvar för direkt skada är begränsat till
**[sex (6) / tolv (12)] månaders avgift** för den berörda tjänsten, räknat på
avgiften de tolv månader som föregick skadan.

**13.2** Leverantören ansvarar inte för indirekt skada, såsom utebliven vinst,
produktionsbortfall, förlust eller förvanskning av data, anseendeskada eller
krav från tredje man.

**13.3** Begränsningarna gäller inte vid uppsåt eller grov vårdslöshet, vid
personskada, eller där tvingande lag föreskriver annat.

**13.4 Reklamation:** krav ska framställas skriftligen inom **sex (6) månader**
från upptäckt och preciseras inom **två (2) månader** därefter.

## 14. Force majeure

Part är befriad från påföljd om fullgörandet hindras av omständighet utanför
Parts kontroll, inklusive fel eller försening hos underleverantör på grund av
sådan omständighet. Varar hindret längre än tre månader får motparten häva
avtalet utan ersättningsskyldighet.

## 15. Tvist och tillämplig lag

Svensk rätt tillämpas. Tvist avgörs av **[allmän domstol med Stockholms
tingsrätt som första instans / skiljeförfarande enligt SCC:s regler för
förenklat skiljeförfarande]**.

## 16. Bilagor

1. Tjänstespecifikation och konfiguration
2. Kontaktvägar, larmrutin och eskaleringslista
3. Personuppgiftsbiträdesavtal
4. Säkerhetsskyddsavtal (vid behov)

---

**Underskrifter**

Ort och datum: _______________________

**För Leverantören**
_______________________________
Namn: [NAMN], [TITEL]

**För {{counterparty.name}}**
_______________________________
Namn: _______________________

---

*Mallen bygger på cybersäkerhetslagen (2025:1506) och cybersäkerhetsförordningen
(2025:1507), LEK (2022:482), dataskyddsförordningen (EU) 2016/679,
säkerhetsskyddslagen (2018:585) samt branschpraxis för managerade
säkerhetstjänster. Den är underlag, inte juridisk rådgivning. Klausul 8.4 om
innehållsanalys bör granskas särskilt av telekomjurist.*
