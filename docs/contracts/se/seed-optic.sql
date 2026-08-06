-- Seedar de tre svenska avtalsmallarna i docs/contracts/se/ till en instans.
-- Verksamhetsdata, inte plattformskonfiguration — körs per instans, inte som migration.
-- Idempotent: kör om för att uppdatera texten efter en redigering av .md-filen.
RESET ROLE;

INSERT INTO contract_templates
  (name, description, contract_type, language, body_markdown, default_currency,
   default_renewal_type, default_renewal_notice_days, is_default, is_active, created_by)
VALUES (
  $namn$Dedikerad fiber — svartfiberavtal$namn$,
  $besk$Avtal om nyttjanderätt till fiberpar (svartfiber) för företagskund. Följer CESAR2-praxis: servicenivåer SN0–SN2, förseningsvite, ansvarstak i prisbasbelopp, Robust fiber v1.8.$besk$,
  'service', 'sv',
  $avtal$# Avtal om dedikerad fiberförbindelse (svartfiber)

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

Nedan gemensamt "Parterna" och var för sig "Part".

## 2. Definitioner

| Begrepp | Betydelse |
|---|---|
| **Förbindelsen** | Det fiberpar som upplåts enligt punkt 3, mellan Överlämningspunkterna |
| **Överlämningspunkt** | Den fysiska punkt där Förbindelsen överlämnas till Kunden, angiven i Bilaga 1 |
| **Avtalad Leveransdag** | Det datum Förbindelsen enligt punkt 5 ska vara levererad |
| **Faktisk Leveransdag** | Den dag Förbindelsen godkänts vid leveranskontroll enligt punkt 5.4 |
| **Fel** | Att Förbindelsen inte uppfyller avtalad dämpningsbudget eller är avbruten |
| **Servicetid** | Den tid under vilken felavhjälpning utförs enligt vald servicenivå |
| **Arbetsdag** | Helgfri måndag–fredag |

## 3. Avtalsföremålet

Leverantören upplåter till Kunden nyttjanderätt till **ett (1) fiberpar** mellan
Överlämningspunkterna enligt Bilaga 1, sträcka [STRÄCKANS BENÄMNING], längd
cirka [ANTAL] meter.

**Vad som ingår:** den fysiska fibern och dess kontinuitet. Leverantören
tillhandahåller **ingen transmission, aktiv utrustning eller
kapacitetstjänst.** Kunden ansvarar för all utrustning i Överlämningspunkterna
och för den optiska budgeten inom avtalade gränsvärden.

**Optiska gränsvärden** (mäts vid leverans enligt punkt 5.4):
- Total dämpning: högst [X,X] dB vid 1310 nm respektive [X,X] dB vid 1550 nm
- Antal skarvar: högst [ANTAL]
- Kontakttyp i Överlämningspunkt: [SC/APC alt. LC/APC]

Kunden får inte utan Leverantörens skriftliga medgivande upplåta Förbindelsen
vidare till tredje man. Vidareupplåtelse inom Kundens koncern är tillåten efter
skriftlig anmälan.

## 4. Anläggning och kvalitet

Nyanläggning utförs enligt **Robust fiber version 1.8** (Svenska
Stadsnätsföreningen, gällande från 2026-03-01) avseende förläggningsmetoder,
materialval, nodkrav och dokumentation. Egendeklaration och besiktningsprotokoll
lämnas till Kunden vid leverans.

Leverantören ansvarar för att erforderliga markavtal, ledningsrätt enligt
ledningsrättslagen (1973:1144), grävtillstånd och trafikanordningsplaner finns
före schaktstart, samt för ledningsanvisning via Ledningskollen.

## 5. Leverans

**5.1** Avtalad Leveransdag är **[DATUM]**.

**5.2** Parterna ska samverka för att erhålla nödvändiga tillstånd och
medgivanden. Kunden ansvarar för att fastighetsägares medgivande finns i egna
lokaler och att Överlämningspunkten är tillgänglig, strömförsörjd och klimatiserad.

**5.3 Försening som beror på Leverantören.** Vite utgår med **5 % av
årsavgiften per påbörjad förseningsvecka, dock högst 20 % av årsavgiften**.
Vitet är Kundens **enda påföljd** vid försening; skadestånd utgår inte därutöver.
Överstiger förseningen **20 Arbetsdagar** får Kunden häva avtalet utan kostnad.

**5.4 Leveranskontroll.** Leverantören mäter Förbindelsen (OTDR och
insertion loss) och överlämnar mätprotokoll. Kunden ska inom **10 Arbetsdagar**
godkänna eller skriftligen påtala brist. Uteblivet svar räknas som godkännande.
Faktisk Leveransdag är den dag godkännande skett eller fristen löpt ut.

**5.5 Försening som inte beror på Leverantören** (myndighetsbeslut, markägares
vägran, tredjepartsnät) ger ny Avtalad Leveransdag. Leverantören ska underrätta
Kunden **utan dröjsmål** när hindret blir känt — sker inte det utgår vite enligt
5.3 trots att hindret inte berodde på Leverantören.

## 6. Servicenivå

Vald servicenivå: **[SN 0 / SN 1 / SN 2]**

| | SN 0 | SN 1 | SN 2 |
|---|---|---|---|
| Servicetid | Helgfri vardag 07–17 | Dygnet runt | Dygnet runt |
| Tillgänglighet per år | 99,5 % | 99,7 % | 99,9 % |
| Påbörjad felavhjälpning | 4 h | 4 h | 4 h |
| Åtgärdstid | 12 h | 24 h | 8 h |
| Statusrapport | var 4:e h | var 4:e h | varje h |

Felanmälan tas emot dygnet runt i samtliga nivåer på [TELEFON] / [E-POST].

**6.1 Vite vid överskriden åtgärdstid.** Per påbörjad timme utöver åtgärdstiden:
SN 0 — 300 kr + 3 % av månadsavgiften; SN 1 — 500 kr + 3 %; SN 2 — 1 000 kr + 3 %.

**6.2 Vite vid underskriden tillgänglighet.** 1 % av årsavgiften vid
underskridande, 3 % vid 0,1 procentenheter under nivån, 5 % vid 0,2
procentenheter under.

**6.3 Tak.** Vite för ett och samma Fel överstiger aldrig **75 % av en
kvartalsavgift**. När taket nås får Kunden säga upp Förbindelsen med omedelbar
verkan. Vite krediteras inte automatiskt — Kunden ska **åberopa** det skriftligen
inom 30 dagar från felavhjälpningens avslut.

**6.4 Beräkning.** Tillgänglighet = 100 × (mätperiod − oplanerade avbrott) /
mätperiod. Planerat underhåll enligt 6.5, avbrott orsakade av Kunden eller
Kundens utrustning, samt force majeure räknas **inte** som avbrott.

**6.5 Planerat underhåll.** Servicefönster om högst **en natt, helgfri
måndag–torsdag kl. 00:00–06:00**, aviserat minst **10 Arbetsdagar** i förväg (20
Arbetsdagar om arbetet berör optokabel i kraftledning). Klarrapport lämnas efter
avslutat arbete.

## 7. Avgifter och betalning

| Post | Belopp |
|---|---|
| Engångsavgift (anslutning/anläggning) | [BELOPP] {{currency}} |
| Årsavgift | {{value}} {{currency}} |
| Faktureringsperiod | [Kvartalsvis / Årsvis] i förskott |

Betalningsvillkor 30 dagar netto. Dröjsmålsränta enligt räntelagen (1975:635).
Avgifterna är exklusive mervärdesskatt. Årsavgiften får justeras en gång per år
med förändringen i **SCB:s konsumentprisindex (KPI)**, med [MÅNAD] [ÅR] som
basmånad, meddelat minst tre månader i förväg.

## 8. Avtalstid och uppsägning

**8.1** Avtalet gäller från {{start_date}} och den initiala avtalsperioden är
**[ANTAL] månader räknat från Faktisk Leveransdag**.

**8.2** Uppsägning ska ske skriftligen — av **Kunden senast 3 månader** och av
**Leverantören senast 9 månader** före periodens utgång.

**8.3** Sägs avtalet inte upp övergår det till att gälla **tills vidare** med
samma uppsägningstider. Ingen ny bindningstid uppstår genom förlängning.

**8.4 Förtida lösen.** Kunden får lösa avtalet i förtid vid slutkunds konkurs
eller likvidation, vid flytt från anslutningsadressen, eller om ledningsrätt
eller markavtal upphör av skäl utanför Kundens kontroll. Ersättning utgår med
**halva den kvarvarande avtalstidens avgifter**.

## 9. Ansvar

**9.1** Leverantörens ansvar för direkt skada är begränsat till **tio (10)
prisbasbelopp per skadetillfälle** enligt socialförsäkringsbalken (2010:110).

**9.2** Leverantören ansvarar **inte** för indirekt skada, såsom
produktionsbortfall, utebliven vinst, förlust eller förvanskning av data, hinder
att uppfylla förpliktelser mot tredje man eller annan följdförlust.

**9.3** Begränsningarna i 9.1–9.2 gäller **inte** vid uppsåt eller grov
vårdslöshet, vid personskada, eller där tvingande lag föreskriver annat.

**9.4** Vite enligt punkt 5.3 och 6 avräknas mot skadestånd som utgår med
anledning av samma omständighet.

**9.5 Reklamation.** Krav ska framställas skriftligen inom **sex (6) månader**
från det att skadan upptäcktes och preciseras inom **två (2) månader** därefter.
Krav som framställs för sent är förlorat.

## 10. Force majeure

Part är befriad från påföljd om fullgörandet hindras av omständighet utanför
Parts kontroll — krig, myndighetsåtgärd, naturkatastrof, arbetskonflikt,
avbrott i allmänna kommunikationer eller kraftförsörjning, **samt fel eller
försening i tjänster från underleverantör på grund av sådan omständighet**.

Part ska underrätta motparten skriftligen både när hindret uppstår och när det
upphör, och vidta skäliga åtgärder för att begränsa verkningarna. Varar hindret
längre än **tre (3) månader** får motparten häva avtalet utan ersättningsskyldighet.

## 11. Regelefterlevnad, säkerhet och incidenter

Leverantören är anmäld hos PTS och följer PTSFS 2022:11 om säkerhet i nät och
tjänster, inklusive kraven på driftsäkerhet och redundans.

Vid incident som påverkar Förbindelsen underrättas Kunden **utan onödigt
dröjsmål**. Leverantörens rapportering till PTS (inledande rapport inom 72
timmar, kompletterande inom två veckor; integritetsincidenter inom 24 timmar)
sker parallellt och påverkar inte Kundens egen rapporteringsskyldighet.

Ingen Part hindras av sekretessåtagandena i punkt 12 från att fullgöra
rapporteringsskyldighet enligt lag eller myndighetsbeslut.

## 12. Sekretess

Vardera Part förbinder sig att inte utan motpartens medgivande röja
konfidentiell information om motpartens verksamhet. Åtagandet gäller under
avtalstiden och **tre (3) år** därefter. Leverantören omfattas därutöver av
tystnadsplikten i 9 kap. 31–35 §§ LEK.

## 13. Personuppgifter

Behandlar Leverantören personuppgifter för Kundens räkning gäller separat
personuppgiftsbiträdesavtal (Bilaga 3) enligt artikel 28 i dataskyddsförordningen
(EU) 2016/679. För uppgifter Leverantören behandlar som självständigt
personuppgiftsansvarig — abonnentuppgifter, trafikuppgifter enligt 9 kap. LEK —
gäller Leverantörens integritetspolicy.

## 14. Överlåtelse

Avtalet får inte överlåtas utan motpartens skriftliga medgivande. Leverantören
får dock överlåta avtalet till bolag inom samma koncern efter skriftlig
underrättelse.

## 15. Ändringar

Ändringar och tillägg ska vara skriftliga och undertecknade av båda Parter för
att gälla.

## 16. Tvist och tillämplig lag

Svensk rätt tillämpas. Tvist ska avgöras av **[allmän domstol med Stockholms
tingsrätt som första instans / skiljeförfarande enligt Stockholms Handelskammares
Skiljedomsinstituts regler för förenklat skiljeförfarande]**.

## 17. Bilagor

1. Sträckning, Överlämningspunkter och optiska gränsvärden
2. Kontaktvägar, felanmälan och eskaleringslista
3. Personuppgiftsbiträdesavtal (vid behov)
4. Prisbilaga vid tilläggsbeställningar

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

*Mallen bygger på svensk branschpraxis för fiberavtal (SSNF Avtalspaket CESAR2
v3.1 — Allmänna villkor och Servicenivåer), Robust fiber v1.8, LEK (2022:482)
och PTSFS 2022:11. Den är underlag, inte juridisk rådgivning — låt jurist
granska före skarp användning.*
$avtal$,
  'SEK', 'manual', 90, false, true,
  (SELECT user_id FROM user_roles WHERE role='admin' ORDER BY created_at LIMIT 1)
)
ON CONFLICT DO NOTHING;

UPDATE contract_templates SET
  body_markdown = $avtal$# Avtal om dedikerad fiberförbindelse (svartfiber)

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

Nedan gemensamt "Parterna" och var för sig "Part".

## 2. Definitioner

| Begrepp | Betydelse |
|---|---|
| **Förbindelsen** | Det fiberpar som upplåts enligt punkt 3, mellan Överlämningspunkterna |
| **Överlämningspunkt** | Den fysiska punkt där Förbindelsen överlämnas till Kunden, angiven i Bilaga 1 |
| **Avtalad Leveransdag** | Det datum Förbindelsen enligt punkt 5 ska vara levererad |
| **Faktisk Leveransdag** | Den dag Förbindelsen godkänts vid leveranskontroll enligt punkt 5.4 |
| **Fel** | Att Förbindelsen inte uppfyller avtalad dämpningsbudget eller är avbruten |
| **Servicetid** | Den tid under vilken felavhjälpning utförs enligt vald servicenivå |
| **Arbetsdag** | Helgfri måndag–fredag |

## 3. Avtalsföremålet

Leverantören upplåter till Kunden nyttjanderätt till **ett (1) fiberpar** mellan
Överlämningspunkterna enligt Bilaga 1, sträcka [STRÄCKANS BENÄMNING], längd
cirka [ANTAL] meter.

**Vad som ingår:** den fysiska fibern och dess kontinuitet. Leverantören
tillhandahåller **ingen transmission, aktiv utrustning eller
kapacitetstjänst.** Kunden ansvarar för all utrustning i Överlämningspunkterna
och för den optiska budgeten inom avtalade gränsvärden.

**Optiska gränsvärden** (mäts vid leverans enligt punkt 5.4):
- Total dämpning: högst [X,X] dB vid 1310 nm respektive [X,X] dB vid 1550 nm
- Antal skarvar: högst [ANTAL]
- Kontakttyp i Överlämningspunkt: [SC/APC alt. LC/APC]

Kunden får inte utan Leverantörens skriftliga medgivande upplåta Förbindelsen
vidare till tredje man. Vidareupplåtelse inom Kundens koncern är tillåten efter
skriftlig anmälan.

## 4. Anläggning och kvalitet

Nyanläggning utförs enligt **Robust fiber version 1.8** (Svenska
Stadsnätsföreningen, gällande från 2026-03-01) avseende förläggningsmetoder,
materialval, nodkrav och dokumentation. Egendeklaration och besiktningsprotokoll
lämnas till Kunden vid leverans.

Leverantören ansvarar för att erforderliga markavtal, ledningsrätt enligt
ledningsrättslagen (1973:1144), grävtillstånd och trafikanordningsplaner finns
före schaktstart, samt för ledningsanvisning via Ledningskollen.

## 5. Leverans

**5.1** Avtalad Leveransdag är **[DATUM]**.

**5.2** Parterna ska samverka för att erhålla nödvändiga tillstånd och
medgivanden. Kunden ansvarar för att fastighetsägares medgivande finns i egna
lokaler och att Överlämningspunkten är tillgänglig, strömförsörjd och klimatiserad.

**5.3 Försening som beror på Leverantören.** Vite utgår med **5 % av
årsavgiften per påbörjad förseningsvecka, dock högst 20 % av årsavgiften**.
Vitet är Kundens **enda påföljd** vid försening; skadestånd utgår inte därutöver.
Överstiger förseningen **20 Arbetsdagar** får Kunden häva avtalet utan kostnad.

**5.4 Leveranskontroll.** Leverantören mäter Förbindelsen (OTDR och
insertion loss) och överlämnar mätprotokoll. Kunden ska inom **10 Arbetsdagar**
godkänna eller skriftligen påtala brist. Uteblivet svar räknas som godkännande.
Faktisk Leveransdag är den dag godkännande skett eller fristen löpt ut.

**5.5 Försening som inte beror på Leverantören** (myndighetsbeslut, markägares
vägran, tredjepartsnät) ger ny Avtalad Leveransdag. Leverantören ska underrätta
Kunden **utan dröjsmål** när hindret blir känt — sker inte det utgår vite enligt
5.3 trots att hindret inte berodde på Leverantören.

## 6. Servicenivå

Vald servicenivå: **[SN 0 / SN 1 / SN 2]**

| | SN 0 | SN 1 | SN 2 |
|---|---|---|---|
| Servicetid | Helgfri vardag 07–17 | Dygnet runt | Dygnet runt |
| Tillgänglighet per år | 99,5 % | 99,7 % | 99,9 % |
| Påbörjad felavhjälpning | 4 h | 4 h | 4 h |
| Åtgärdstid | 12 h | 24 h | 8 h |
| Statusrapport | var 4:e h | var 4:e h | varje h |

Felanmälan tas emot dygnet runt i samtliga nivåer på [TELEFON] / [E-POST].

**6.1 Vite vid överskriden åtgärdstid.** Per påbörjad timme utöver åtgärdstiden:
SN 0 — 300 kr + 3 % av månadsavgiften; SN 1 — 500 kr + 3 %; SN 2 — 1 000 kr + 3 %.

**6.2 Vite vid underskriden tillgänglighet.** 1 % av årsavgiften vid
underskridande, 3 % vid 0,1 procentenheter under nivån, 5 % vid 0,2
procentenheter under.

**6.3 Tak.** Vite för ett och samma Fel överstiger aldrig **75 % av en
kvartalsavgift**. När taket nås får Kunden säga upp Förbindelsen med omedelbar
verkan. Vite krediteras inte automatiskt — Kunden ska **åberopa** det skriftligen
inom 30 dagar från felavhjälpningens avslut.

**6.4 Beräkning.** Tillgänglighet = 100 × (mätperiod − oplanerade avbrott) /
mätperiod. Planerat underhåll enligt 6.5, avbrott orsakade av Kunden eller
Kundens utrustning, samt force majeure räknas **inte** som avbrott.

**6.5 Planerat underhåll.** Servicefönster om högst **en natt, helgfri
måndag–torsdag kl. 00:00–06:00**, aviserat minst **10 Arbetsdagar** i förväg (20
Arbetsdagar om arbetet berör optokabel i kraftledning). Klarrapport lämnas efter
avslutat arbete.

## 7. Avgifter och betalning

| Post | Belopp |
|---|---|
| Engångsavgift (anslutning/anläggning) | [BELOPP] {{currency}} |
| Årsavgift | {{value}} {{currency}} |
| Faktureringsperiod | [Kvartalsvis / Årsvis] i förskott |

Betalningsvillkor 30 dagar netto. Dröjsmålsränta enligt räntelagen (1975:635).
Avgifterna är exklusive mervärdesskatt. Årsavgiften får justeras en gång per år
med förändringen i **SCB:s konsumentprisindex (KPI)**, med [MÅNAD] [ÅR] som
basmånad, meddelat minst tre månader i förväg.

## 8. Avtalstid och uppsägning

**8.1** Avtalet gäller från {{start_date}} och den initiala avtalsperioden är
**[ANTAL] månader räknat från Faktisk Leveransdag**.

**8.2** Uppsägning ska ske skriftligen — av **Kunden senast 3 månader** och av
**Leverantören senast 9 månader** före periodens utgång.

**8.3** Sägs avtalet inte upp övergår det till att gälla **tills vidare** med
samma uppsägningstider. Ingen ny bindningstid uppstår genom förlängning.

**8.4 Förtida lösen.** Kunden får lösa avtalet i förtid vid slutkunds konkurs
eller likvidation, vid flytt från anslutningsadressen, eller om ledningsrätt
eller markavtal upphör av skäl utanför Kundens kontroll. Ersättning utgår med
**halva den kvarvarande avtalstidens avgifter**.

## 9. Ansvar

**9.1** Leverantörens ansvar för direkt skada är begränsat till **tio (10)
prisbasbelopp per skadetillfälle** enligt socialförsäkringsbalken (2010:110).

**9.2** Leverantören ansvarar **inte** för indirekt skada, såsom
produktionsbortfall, utebliven vinst, förlust eller förvanskning av data, hinder
att uppfylla förpliktelser mot tredje man eller annan följdförlust.

**9.3** Begränsningarna i 9.1–9.2 gäller **inte** vid uppsåt eller grov
vårdslöshet, vid personskada, eller där tvingande lag föreskriver annat.

**9.4** Vite enligt punkt 5.3 och 6 avräknas mot skadestånd som utgår med
anledning av samma omständighet.

**9.5 Reklamation.** Krav ska framställas skriftligen inom **sex (6) månader**
från det att skadan upptäcktes och preciseras inom **två (2) månader** därefter.
Krav som framställs för sent är förlorat.

## 10. Force majeure

Part är befriad från påföljd om fullgörandet hindras av omständighet utanför
Parts kontroll — krig, myndighetsåtgärd, naturkatastrof, arbetskonflikt,
avbrott i allmänna kommunikationer eller kraftförsörjning, **samt fel eller
försening i tjänster från underleverantör på grund av sådan omständighet**.

Part ska underrätta motparten skriftligen både när hindret uppstår och när det
upphör, och vidta skäliga åtgärder för att begränsa verkningarna. Varar hindret
längre än **tre (3) månader** får motparten häva avtalet utan ersättningsskyldighet.

## 11. Regelefterlevnad, säkerhet och incidenter

Leverantören är anmäld hos PTS och följer PTSFS 2022:11 om säkerhet i nät och
tjänster, inklusive kraven på driftsäkerhet och redundans.

Vid incident som påverkar Förbindelsen underrättas Kunden **utan onödigt
dröjsmål**. Leverantörens rapportering till PTS (inledande rapport inom 72
timmar, kompletterande inom två veckor; integritetsincidenter inom 24 timmar)
sker parallellt och påverkar inte Kundens egen rapporteringsskyldighet.

Ingen Part hindras av sekretessåtagandena i punkt 12 från att fullgöra
rapporteringsskyldighet enligt lag eller myndighetsbeslut.

## 12. Sekretess

Vardera Part förbinder sig att inte utan motpartens medgivande röja
konfidentiell information om motpartens verksamhet. Åtagandet gäller under
avtalstiden och **tre (3) år** därefter. Leverantören omfattas därutöver av
tystnadsplikten i 9 kap. 31–35 §§ LEK.

## 13. Personuppgifter

Behandlar Leverantören personuppgifter för Kundens räkning gäller separat
personuppgiftsbiträdesavtal (Bilaga 3) enligt artikel 28 i dataskyddsförordningen
(EU) 2016/679. För uppgifter Leverantören behandlar som självständigt
personuppgiftsansvarig — abonnentuppgifter, trafikuppgifter enligt 9 kap. LEK —
gäller Leverantörens integritetspolicy.

## 14. Överlåtelse

Avtalet får inte överlåtas utan motpartens skriftliga medgivande. Leverantören
får dock överlåta avtalet till bolag inom samma koncern efter skriftlig
underrättelse.

## 15. Ändringar

Ändringar och tillägg ska vara skriftliga och undertecknade av båda Parter för
att gälla.

## 16. Tvist och tillämplig lag

Svensk rätt tillämpas. Tvist ska avgöras av **[allmän domstol med Stockholms
tingsrätt som första instans / skiljeförfarande enligt Stockholms Handelskammares
Skiljedomsinstituts regler för förenklat skiljeförfarande]**.

## 17. Bilagor

1. Sträckning, Överlämningspunkter och optiska gränsvärden
2. Kontaktvägar, felanmälan och eskaleringslista
3. Personuppgiftsbiträdesavtal (vid behov)
4. Prisbilaga vid tilläggsbeställningar

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

*Mallen bygger på svensk branschpraxis för fiberavtal (SSNF Avtalspaket CESAR2
v3.1 — Allmänna villkor och Servicenivåer), Robust fiber v1.8, LEK (2022:482)
och PTSFS 2022:11. Den är underlag, inte juridisk rådgivning — låt jurist
granska före skarp användning.*
$avtal$,
  description   = $besk$Avtal om nyttjanderätt till fiberpar (svartfiber) för företagskund. Följer CESAR2-praxis: servicenivåer SN0–SN2, förseningsvite, ansvarstak i prisbasbelopp, Robust fiber v1.8.$besk$,
  updated_at    = now()
WHERE name = $namn$Dedikerad fiber — svartfiberavtal$namn$;

INSERT INTO contract_templates
  (name, description, contract_type, language, body_markdown, default_currency,
   default_renewal_type, default_renewal_notice_days, is_default, is_active, created_by)
VALUES (
  $namn$Skyddad internetanslutning — tjänsteavtal$namn$,
  $besk$Avtal om internetaccess med DDoS-skydd, brandvägg och hotdetektering. Incidentfrister anpassade till kundens rapporteringsplikt enligt cybersäkerhetslagen (2025:1506); ingen garanti mot intrång.$besk$,
  'service', 'sv',
  $avtal$# Avtal om skyddad internetanslutning

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
$avtal$,
  'SEK', 'manual', 90, false, true,
  (SELECT user_id FROM user_roles WHERE role='admin' ORDER BY created_at LIMIT 1)
)
ON CONFLICT DO NOTHING;

UPDATE contract_templates SET
  body_markdown = $avtal$# Avtal om skyddad internetanslutning

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
$avtal$,
  description   = $besk$Avtal om internetaccess med DDoS-skydd, brandvägg och hotdetektering. Incidentfrister anpassade till kundens rapporteringsplikt enligt cybersäkerhetslagen (2025:1506); ingen garanti mot intrång.$besk$,
  updated_at    = now()
WHERE name = $namn$Skyddad internetanslutning — tjänsteavtal$namn$;

INSERT INTO contract_templates
  (name, description, contract_type, language, body_markdown, default_currency,
   default_renewal_type, default_renewal_notice_days, is_default, is_active, created_by)
VALUES (
  $namn$Privat AI — drift av kundägd hårdvara i DDC$namn$,
  $besk$Avtal där kunden äger hårdvaran och leverantören hostar och driftar den. Reglerar separationsrätt vid konkurs, avstående från retentionsrätt, PUB utan logisk åtkomst, AI-förordningens rollfördelning och säker radering vid exit.$besk$,
  'service', 'sv',
  $avtal$# Avtal om drift av kundägd AI-utrustning i distribuerat datacenter

**Avtalsnummer:** [AVTALSNR]
**Upprättat:** {{today}}

## 1. Parter

**Leverantör**
[LEVERANTÖRENS FIRMA], org.nr [ORGNR]
[ADRESS]

**Kund**
{{counterparty.name}}
E-post: {{counterparty.email}}
Org.nr: [KUNDENS ORGNR]
Adress: [KUNDENS ADRESS]

## 2. Bakgrund och avtalets syfte

Kunden **äger** den utrustning som förtecknas i Bilaga 1 (nedan "Utrustningen").
Leverantören **förvarar och driftar** Utrustningen i sitt distribuerade
datacenter (DDC) och tillhandahåller de tjänster som anges i punkt 5.

Modellerna med öppna vikter och den data Kunden behandlar lämnar aldrig Kundens
domän. Leverantören har fysisk åtkomst till Utrustningen men **inte logisk
åtkomst** till Kundens data — se punkt 8.

## 3. Definitioner

| Begrepp | Betydelse |
|---|---|
| **Utrustningen** | Den hårdvara Kunden äger, förtecknad i Bilaga 1 med serienummer |
| **Utrymmet** | Det rack, den bur eller den yta i DDC som tilldelats Kunden |
| **Avtalad Effekt** | Den elektriska effekt i kW som Utrustningen tilldelats enligt Bilaga 2 |
| **Remote hands** | Fysiska handgrepp Leverantören utför på Kundens instruktion |
| **Driftfönster** | Planerat underhåll enligt punkt 6.4 |

## 4. Äganderätt — den viktigaste bestämmelsen

**4.1 Förvärvet.** Kunden förvärvar Utrustningen **direkt från
hårdvaruleverantören**. Faktura, följesedel och garantihandlingar ställs i
Kundens namn. Leverantören är aldrig säljare av Utrustningen och tar aldrig
äganderätt till den. Utrustningen levereras till DDC **för Kundens räkning**,
och Leverantören är från mottagandet **depositarie** enligt 12 kap. handelsbalken.

> **Varför konstruktionen ser ut så här.** Köper Kunden av Leverantören och
> Utrustningen aldrig lämnar Leverantörens lokaler saknas tradition, och Kundens
> äganderätt håller då **inte** mot Leverantörens borgenärer vid en konkurs. Det
> är en förutsättning för detta avtal att förvärvet sker enligt 4.1. Ska
> Leverantören ändå sälja utrustningen krävs antingen reellt rådighetsavskärande
> eller hela förfarandet enligt lagen (1845:50 s.1) om handel med lösören —
> då ska detta avtal inte användas som det står.

**4.2 Individualisering.** Utrustningen förtecknas i Bilaga 1 med fabrikat,
modell och **serienummer/service tag**. Förteckningen uppdateras och kvitteras av
båda Parter vid varje tillägg, byte eller uttag. Förteckningen är avgörande
bevisning för Kundens äganderätt och ska hållas aktuell.

**4.3 Märkning.** Leverantören förser varje enhet med varaktig märkning:
*"Egendom tillhörig {{counterparty.name}}, org.nr [KUNDENS ORGNR]"*. Utrymmet
märks motsvarande och hålls låst.

**4.4 Förbud mot sammanblandning.** Utrustningen får inte sammanblandas med
Leverantörens egen utrustning, poolas i delad kapacitet eller användas för annan
kund. Leverantören noterar Utrustningen i sitt anläggningsregister uttryckligen
som **annans egendom** och tar inte upp den i egen balansräkning.

**4.5 Avstående från retentionsrätt och panträtt.** Leverantören **avstår
uttryckligen** från den retentionsrätt som annars följer av 12 kap. 8 §
handelsbalken, och får inte pantsätta, upplåta säkerhetsrätt i, eller på annat
sätt förfoga över Utrustningen. Leverantören får inte hålla kvar Utrustningen på
grund av obetalda avgifter; obetalda avgifter drivs in på annat sätt.

**4.6 Utmätning och konkurs.** Skulle Utrustningen bli föremål för utmätning
eller ingå i Leverantörens konkursbo ska Leverantören **omedelbart** underrätta
Kunden och överlämna Bilaga 1 samt Kundens fakturor till Kronofogdemyndigheten
respektive konkursförvaltaren, och i övrigt medverka till att Kundens äganderätt
görs gällande.

**4.7 Företagshypotek.** Leverantören intygar att Utrustningen inte omfattas av
företagshypotek enligt lagen (2008:990) om företagshypotek, eftersom sådant
endast omfattar Leverantörens egen egendom.

## 5. Leverantörens åtaganden

| Tjänst | Omfattning |
|---|---|
| Utrymme | [ANTAL] rack / [ANTAL] HE i [ORT], redundans [N+1 / 2N] |
| Kraft | Avtalad Effekt [X] kW, A+B-matning, UPS och reservkraft |
| Kyla | Kapacitet motsvarande Avtalad Effekt, temperatur enligt ASHRAE-klass [A1/A2] |
| Nät | [ANTAL] cross-connects, [X] Gbit/s uppkoppling |
| Övervakning | Kraft, temperatur, fysisk åtkomst — larm till Kunden |
| Remote hands | [ANTAL] timmar per månad ingår; därutöver [PRIS] {{currency}}/timme |
| Fysisk säkerhet | Tillträdeskontroll, kamerabevakning, larm, loggning |

Datacentret drivs enligt **EN 50600 availability class [1–4]** och Leverantörens
ledningssystem för informationssäkerhet är certifierat enligt
[ISO/IEC 27001 alt. motsvarande].

## 6. Drift och tillgänglighet

**6.1 Tillgänglighet kraft och kyla:** [99,9 % / 99,982 %] per kalendermånad.
Leverantören ansvarar för Utrymmets infrastruktur — **inte** för Utrustningens
egen funktion, mjukvara eller Kundens modeller.

**6.2 Remote hands, inställelsetid:** kritiskt ärende inom **[1] timme** dygnet
runt, normalt ärende inom **[4] timmar** under kontorstid.

**6.3 Tillträde.** Kundens personal får tillträde efter föranmälan minst
[4] timmar i förväg, mot legitimation och med eskort. Tillträde loggas.
Akut tillträde beviljas dygnet runt efter identitetskontroll.

**6.4 Driftfönster:** högst [4] timmar per tillfälle, aviserat minst **10
arbetsdagar** i förväg. Arbete som kräver strömavbrott till Utrymmet planeras
i samråd med Kunden.

**6.5 Vite.** Vid underskriden tillgänglighet krediteras [X] % av
månadsavgiften per påbörjad procentenhet under nivån, dock högst **[25] %** av
månadsavgiften per månad. Vitet är Kundens **enda påföljd** vid otillgänglighet.

## 7. Risk, vård och försäkring

**7.1 Vårdplikt.** Leverantören ska vårda Utrustningen som en aktsam
depositarie enligt 12 kap. handelsbalken.

**7.2 Kundens försäkring.** Kunden ska hålla Utrustningen försäkrad till
återanskaffningsvärde genom egendoms- eller allriskförsäkring, och tillse att
försäkringsgivaren **avstår från regress** mot Leverantören annat än vid uppsåt
eller grov vårdslöshet. Försäkringsbevis lämnas på begäran.

**7.3 Leverantörens försäkring.** Leverantören håller ansvars- och
verksamhetsförsäkring med betryggande belopp.

**7.4 Riskfördelning.** Leverantören ansvarar för skada på Utrustningen som
orsakats av Leverantörens vårdslöshet inom ramen för punkt 12. Leverantören
ansvarar inte för skada orsakad av Utrustningens egna fel, Kundens konfiguration,
avbrott i extern elmatning utanför Leverantörens kontroll, eller force majeure.

**7.5 Säkerhetskopior.** Kunden ansvarar helt för säkerhetskopiering av data och
modeller. Leverantören ansvarar inte för dataförlust.

## 8. Personuppgifter och åtkomst

**8.1 Roll.** Leverantören behandlar personuppgifter för Kundens räkning genom
att förvara och drifta den utrustning där uppgifterna lagras, och är därmed
**personuppgiftsbiträde** enligt artikel 4.8 dataskyddsförordningen (EU)
2016/679. Personuppgiftsbiträdesavtal utgör Bilaga 3.

> Att Leverantören saknar logisk åtkomst innebär inte att biträdesrollen
> bortfaller — lagring är behandling. PUB-avtal tecknas därför även om
> Leverantören aldrig kan läsa Kundens data.

**8.2 Åtkomstbegränsningar.** Leverantören har fysisk men inte logisk åtkomst:

- Kunden krypterar samtliga lagringsmedia och innehar ensam krypteringsnycklarna.
- Leverantören har inte konto, konsol-, KVM- eller nätverksåtkomst till Utrustningen.
- Racket är låst och plomberat; plombering bryts endast på Kundens instruktion eller vid larm, och dokumenteras.
- Fysiskt arbete inne i Utrymmet utförs enligt tvåmansprincip och loggas.
- Ingen personal utanför EU/EES ges tillträde.

**8.3 Incidenter.** Leverantören underrättar Kunden utan onödigt dröjsmål, dock
senast inom **24 timmar**, om **fysisk** incident som kan påverka Utrustningen
eller uppgifterna — inbrott, stöld, obehörigt tillträde, bruten plombering,
brand- eller vattenskada — så att Kunden hinner fullgöra sin anmälningsskyldighet
enligt artikel 33 dataskyddsförordningen.

**8.4 Underbiträden.** Leverantören anlitar underbiträden (bevakning, städning,
jourtekniker) endast enligt Bilaga 3 och ansvarar för dessa som för egen personal.

## 9. AI-förordningen

**9.1 Rollfördelning.** Kunden är **leverantör respektive tillhandahållare**
(*provider* / *deployer*) av de AI-system som körs på Utrustningen enligt
förordning (EU) 2024/1689. Leverantören tillhandahåller endast utrymme, kraft,
kyla och fysisk drift och är därmed varken provider eller deployer.

**9.2 Ingen ombrandning.** Leverantören marknadsför inte, förser inte med eget
varumärke och gör inga väsentliga ändringar i Kundens AI-system. Skulle
Leverantören göra något av detta blir Leverantören provider enligt artikel 25,
vilket kräver skriftlig överenskommelse i förväg.

**9.3 Kundens åtaganden.** Kunden ansvarar för att AI-systemen uppfyller
tillämpliga krav — dokumentation, loggning, transparens enligt artikel 50,
riskhantering samt eventuella högriskkrav — och för att inte använda
Utrustningen för praxis som är förbjuden enligt artikel 5. Kunden håller
Leverantören skadeslös för krav från tredje man eller myndighet som grundas på
Kundens AI-användning.

**9.4 Avstängningsrätt.** Leverantören får stänga av Utrustningen om användningen
uppenbart strider mot artikel 5 eller mot lag, efter skriftlig anmodan om rättelse
och skälig frist — utom när dröjsmål innebär allvarlig risk.

## 10. Avgifter, el och energirapportering

| Post | Belopp |
|---|---|
| Etableringsavgift | [BELOPP] {{currency}} |
| Månadsavgift utrymme och drift | [BELOPP] {{currency}} |
| Avtalsvärde (period) | {{value}} {{currency}} |

**10.1 Elkostnad.** Elkostnad debiteras som genomlysning (pass-through) av
faktisk förbrukning inom Avtalad Effekt, till Leverantörens inköpspris jämte
nätavgift, energiskatt och påslag om [X] %. Skattenedsättningen för datorhallar
slopades den 1 juli 2023, och full energiskatt utgår.

**10.2 Överförbrukning.** Effektuttag utöver Avtalad Effekt debiteras med
[PRIS] {{currency}} per kW och månad. Leverantören ska varna innan begränsande
åtgärd vidtas.

**10.3 Energirapportering.** Kunden lämnar de uppgifter Leverantören behöver
för rapportering av datacentrets energiprestanda enligt lagen (2025:570) om
datacenters energiprestanda och tillhörande EU-krav.

Betalningsvillkor 30 dagar netto, exklusive mervärdesskatt. Prisjustering en
gång per år enligt SCB:s konsumentprisindex (KPI), meddelad tre månader i förväg.
Elpris och skatter justeras löpande enligt 10.1.

## 11. Avtalstid

Avtalet gäller från {{start_date}} till {{end_date}}, dock minst **[ANTAL]
månader**. Uppsägning ska ske skriftligen senast **[3–6] månader** före
periodens utgång. Sägs avtalet inte upp gäller det **tills vidare** med samma
uppsägningstid — ingen ny bindningstid uppstår.

## 12. Ansvar

**12.1** Leverantörens sammanlagda ansvar för direkt skada är begränsat till
**tolv (12) månaders avgift** enligt punkt 10, räknat på de tolv månader som
föregick skadan. För skada på Utrustningen gäller därutöver punkt 7.

**12.2** Leverantören ansvarar inte för indirekt skada — utebliven vinst,
produktionsbortfall, förlust eller förvanskning av data eller modeller,
anseendeskada eller krav från tredje man.

**12.3** Begränsningarna gäller inte vid uppsåt eller grov vårdslöshet, vid
personskada, eller där tvingande lag föreskriver annat.

**12.4 Reklamation:** krav ska framställas skriftligen inom **sex (6) månader**
från upptäckt och preciseras inom **två (2) månader** därefter.

## 13. Upphörande och utflytt

**13.1 Utflyttsfönster.** Kunden ska hämta Utrustningen inom **30 dagar** från
avtalets upphörande. Avgift enligt punkt 10 löper till dess utflytt är slutförd.

**13.2 Demontering.** Demontering utförs av [Leverantören mot timdebitering /
Kunden med eskort]. Utrymmet återställs i ursprungligt skick bortsett från
normalt slitage.

**13.3 Slutbesiktning.** Vid utflytt stäms Utrustningen av mot Bilaga 1 och
båda Parter kvitterar överlämnandet.

**13.4 Radering.** Ska lagringsmedia raderas i stället för att följa med Kunden
sker det enligt **NIST SP 800-88 Rev. 2** med tekniker enligt IEEE 2883-2022,
på nivån [Clear / Purge / Destroy]. Leverantören utfärdar **raderingsintyg per
serienummer**. Skrotning sker enligt reglerna om avfall från elektrisk och
elektronisk utrustning.

**13.5 Kvarlämnad utrustning.** Hämtas Utrustningen inte inom fristen sänder
Leverantören skriftlig anmodan med **30 dagars** frist. Därefter får Leverantören
flytta Utrustningen till magasin på Kundens bekostnad. Först efter ytterligare
**sex (6) månader** och en andra skriftlig anmodan får Leverantören avyttra
Utrustningen och avräkna kostnaderna mot köpeskillingen; överskott tillfaller
Kunden. Denna punkt ersätter den retentionsrätt Leverantören avstått från
enligt 4.5 och är Leverantörens enda befogenhet över Utrustningen.

## 14. Sekretess

Vardera Part förbinder sig att inte utan motpartens medgivande röja
konfidentiell information. Åtagandet gäller under avtalstiden och **tre (3) år**
därefter, och hindrar inte fullgörande av rapporteringsskyldighet enligt lag.

## 15. Force majeure

Part är befriad från påföljd om fullgörandet hindras av omständighet utanför
Parts kontroll, inklusive avbrott i extern kraftförsörjning och fel hos
underleverantör på grund av sådan omständighet. Varar hindret längre än tre
månader får motparten häva avtalet utan ersättningsskyldighet. Kundens rätt att
hämta Utrustningen enligt punkt 13 påverkas aldrig av force majeure.

## 16. Överlåtelse

Avtalet får inte överlåtas utan motpartens skriftliga medgivande. Överlåter
Leverantören sin verksamhet eller sitt datacenter ska Kundens rättigheter enligt
punkt 4 och 13 säkerställas i överlåtelsehandlingen.

## 17. Tvist och tillämplig lag

Svensk rätt tillämpas. Tvist avgörs av **[allmän domstol med Stockholms
tingsrätt som första instans / skiljeförfarande enligt SCC:s regler]**.

## 18. Bilagor

1. **Utrustningsförteckning** med fabrikat, modell och serienummer — uppdateras löpande
2. Utrymme, Avtalad Effekt, kyla och nätanslutning
3. Personuppgiftsbiträdesavtal
4. Tillträdes- och säkerhetsrutiner
5. Prislista för remote hands och tilläggstjänster

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

*Mallen bygger på traditionsprincipen i svensk sakrätt (NJA 2007 s. 413,
NJA 2008 s. 684), 12 kap. handelsbalken om deposition, dataskyddsförordningen
(EU) 2016/679, AI-förordningen (EU) 2024/1689, EN 50600, lagen (2025:570) om
datacenters energiprestanda samt NIST SP 800-88 Rev. 2.*

***Låt jurist granska punkt 4 innan mallen används skarpt.** Separationsrätten
till kundägd utrustning som står hos leverantören är den juridiskt känsligaste
delen av avtalet, och konstruktionen förutsätter att Kunden förvärvar direkt
från hårdvaruleverantören enligt 4.1.*
$avtal$,
  'SEK', 'manual', 90, false, true,
  (SELECT user_id FROM user_roles WHERE role='admin' ORDER BY created_at LIMIT 1)
)
ON CONFLICT DO NOTHING;

UPDATE contract_templates SET
  body_markdown = $avtal$# Avtal om drift av kundägd AI-utrustning i distribuerat datacenter

**Avtalsnummer:** [AVTALSNR]
**Upprättat:** {{today}}

## 1. Parter

**Leverantör**
[LEVERANTÖRENS FIRMA], org.nr [ORGNR]
[ADRESS]

**Kund**
{{counterparty.name}}
E-post: {{counterparty.email}}
Org.nr: [KUNDENS ORGNR]
Adress: [KUNDENS ADRESS]

## 2. Bakgrund och avtalets syfte

Kunden **äger** den utrustning som förtecknas i Bilaga 1 (nedan "Utrustningen").
Leverantören **förvarar och driftar** Utrustningen i sitt distribuerade
datacenter (DDC) och tillhandahåller de tjänster som anges i punkt 5.

Modellerna med öppna vikter och den data Kunden behandlar lämnar aldrig Kundens
domän. Leverantören har fysisk åtkomst till Utrustningen men **inte logisk
åtkomst** till Kundens data — se punkt 8.

## 3. Definitioner

| Begrepp | Betydelse |
|---|---|
| **Utrustningen** | Den hårdvara Kunden äger, förtecknad i Bilaga 1 med serienummer |
| **Utrymmet** | Det rack, den bur eller den yta i DDC som tilldelats Kunden |
| **Avtalad Effekt** | Den elektriska effekt i kW som Utrustningen tilldelats enligt Bilaga 2 |
| **Remote hands** | Fysiska handgrepp Leverantören utför på Kundens instruktion |
| **Driftfönster** | Planerat underhåll enligt punkt 6.4 |

## 4. Äganderätt — den viktigaste bestämmelsen

**4.1 Förvärvet.** Kunden förvärvar Utrustningen **direkt från
hårdvaruleverantören**. Faktura, följesedel och garantihandlingar ställs i
Kundens namn. Leverantören är aldrig säljare av Utrustningen och tar aldrig
äganderätt till den. Utrustningen levereras till DDC **för Kundens räkning**,
och Leverantören är från mottagandet **depositarie** enligt 12 kap. handelsbalken.

> **Varför konstruktionen ser ut så här.** Köper Kunden av Leverantören och
> Utrustningen aldrig lämnar Leverantörens lokaler saknas tradition, och Kundens
> äganderätt håller då **inte** mot Leverantörens borgenärer vid en konkurs. Det
> är en förutsättning för detta avtal att förvärvet sker enligt 4.1. Ska
> Leverantören ändå sälja utrustningen krävs antingen reellt rådighetsavskärande
> eller hela förfarandet enligt lagen (1845:50 s.1) om handel med lösören —
> då ska detta avtal inte användas som det står.

**4.2 Individualisering.** Utrustningen förtecknas i Bilaga 1 med fabrikat,
modell och **serienummer/service tag**. Förteckningen uppdateras och kvitteras av
båda Parter vid varje tillägg, byte eller uttag. Förteckningen är avgörande
bevisning för Kundens äganderätt och ska hållas aktuell.

**4.3 Märkning.** Leverantören förser varje enhet med varaktig märkning:
*"Egendom tillhörig {{counterparty.name}}, org.nr [KUNDENS ORGNR]"*. Utrymmet
märks motsvarande och hålls låst.

**4.4 Förbud mot sammanblandning.** Utrustningen får inte sammanblandas med
Leverantörens egen utrustning, poolas i delad kapacitet eller användas för annan
kund. Leverantören noterar Utrustningen i sitt anläggningsregister uttryckligen
som **annans egendom** och tar inte upp den i egen balansräkning.

**4.5 Avstående från retentionsrätt och panträtt.** Leverantören **avstår
uttryckligen** från den retentionsrätt som annars följer av 12 kap. 8 §
handelsbalken, och får inte pantsätta, upplåta säkerhetsrätt i, eller på annat
sätt förfoga över Utrustningen. Leverantören får inte hålla kvar Utrustningen på
grund av obetalda avgifter; obetalda avgifter drivs in på annat sätt.

**4.6 Utmätning och konkurs.** Skulle Utrustningen bli föremål för utmätning
eller ingå i Leverantörens konkursbo ska Leverantören **omedelbart** underrätta
Kunden och överlämna Bilaga 1 samt Kundens fakturor till Kronofogdemyndigheten
respektive konkursförvaltaren, och i övrigt medverka till att Kundens äganderätt
görs gällande.

**4.7 Företagshypotek.** Leverantören intygar att Utrustningen inte omfattas av
företagshypotek enligt lagen (2008:990) om företagshypotek, eftersom sådant
endast omfattar Leverantörens egen egendom.

## 5. Leverantörens åtaganden

| Tjänst | Omfattning |
|---|---|
| Utrymme | [ANTAL] rack / [ANTAL] HE i [ORT], redundans [N+1 / 2N] |
| Kraft | Avtalad Effekt [X] kW, A+B-matning, UPS och reservkraft |
| Kyla | Kapacitet motsvarande Avtalad Effekt, temperatur enligt ASHRAE-klass [A1/A2] |
| Nät | [ANTAL] cross-connects, [X] Gbit/s uppkoppling |
| Övervakning | Kraft, temperatur, fysisk åtkomst — larm till Kunden |
| Remote hands | [ANTAL] timmar per månad ingår; därutöver [PRIS] {{currency}}/timme |
| Fysisk säkerhet | Tillträdeskontroll, kamerabevakning, larm, loggning |

Datacentret drivs enligt **EN 50600 availability class [1–4]** och Leverantörens
ledningssystem för informationssäkerhet är certifierat enligt
[ISO/IEC 27001 alt. motsvarande].

## 6. Drift och tillgänglighet

**6.1 Tillgänglighet kraft och kyla:** [99,9 % / 99,982 %] per kalendermånad.
Leverantören ansvarar för Utrymmets infrastruktur — **inte** för Utrustningens
egen funktion, mjukvara eller Kundens modeller.

**6.2 Remote hands, inställelsetid:** kritiskt ärende inom **[1] timme** dygnet
runt, normalt ärende inom **[4] timmar** under kontorstid.

**6.3 Tillträde.** Kundens personal får tillträde efter föranmälan minst
[4] timmar i förväg, mot legitimation och med eskort. Tillträde loggas.
Akut tillträde beviljas dygnet runt efter identitetskontroll.

**6.4 Driftfönster:** högst [4] timmar per tillfälle, aviserat minst **10
arbetsdagar** i förväg. Arbete som kräver strömavbrott till Utrymmet planeras
i samråd med Kunden.

**6.5 Vite.** Vid underskriden tillgänglighet krediteras [X] % av
månadsavgiften per påbörjad procentenhet under nivån, dock högst **[25] %** av
månadsavgiften per månad. Vitet är Kundens **enda påföljd** vid otillgänglighet.

## 7. Risk, vård och försäkring

**7.1 Vårdplikt.** Leverantören ska vårda Utrustningen som en aktsam
depositarie enligt 12 kap. handelsbalken.

**7.2 Kundens försäkring.** Kunden ska hålla Utrustningen försäkrad till
återanskaffningsvärde genom egendoms- eller allriskförsäkring, och tillse att
försäkringsgivaren **avstår från regress** mot Leverantören annat än vid uppsåt
eller grov vårdslöshet. Försäkringsbevis lämnas på begäran.

**7.3 Leverantörens försäkring.** Leverantören håller ansvars- och
verksamhetsförsäkring med betryggande belopp.

**7.4 Riskfördelning.** Leverantören ansvarar för skada på Utrustningen som
orsakats av Leverantörens vårdslöshet inom ramen för punkt 12. Leverantören
ansvarar inte för skada orsakad av Utrustningens egna fel, Kundens konfiguration,
avbrott i extern elmatning utanför Leverantörens kontroll, eller force majeure.

**7.5 Säkerhetskopior.** Kunden ansvarar helt för säkerhetskopiering av data och
modeller. Leverantören ansvarar inte för dataförlust.

## 8. Personuppgifter och åtkomst

**8.1 Roll.** Leverantören behandlar personuppgifter för Kundens räkning genom
att förvara och drifta den utrustning där uppgifterna lagras, och är därmed
**personuppgiftsbiträde** enligt artikel 4.8 dataskyddsförordningen (EU)
2016/679. Personuppgiftsbiträdesavtal utgör Bilaga 3.

> Att Leverantören saknar logisk åtkomst innebär inte att biträdesrollen
> bortfaller — lagring är behandling. PUB-avtal tecknas därför även om
> Leverantören aldrig kan läsa Kundens data.

**8.2 Åtkomstbegränsningar.** Leverantören har fysisk men inte logisk åtkomst:

- Kunden krypterar samtliga lagringsmedia och innehar ensam krypteringsnycklarna.
- Leverantören har inte konto, konsol-, KVM- eller nätverksåtkomst till Utrustningen.
- Racket är låst och plomberat; plombering bryts endast på Kundens instruktion eller vid larm, och dokumenteras.
- Fysiskt arbete inne i Utrymmet utförs enligt tvåmansprincip och loggas.
- Ingen personal utanför EU/EES ges tillträde.

**8.3 Incidenter.** Leverantören underrättar Kunden utan onödigt dröjsmål, dock
senast inom **24 timmar**, om **fysisk** incident som kan påverka Utrustningen
eller uppgifterna — inbrott, stöld, obehörigt tillträde, bruten plombering,
brand- eller vattenskada — så att Kunden hinner fullgöra sin anmälningsskyldighet
enligt artikel 33 dataskyddsförordningen.

**8.4 Underbiträden.** Leverantören anlitar underbiträden (bevakning, städning,
jourtekniker) endast enligt Bilaga 3 och ansvarar för dessa som för egen personal.

## 9. AI-förordningen

**9.1 Rollfördelning.** Kunden är **leverantör respektive tillhandahållare**
(*provider* / *deployer*) av de AI-system som körs på Utrustningen enligt
förordning (EU) 2024/1689. Leverantören tillhandahåller endast utrymme, kraft,
kyla och fysisk drift och är därmed varken provider eller deployer.

**9.2 Ingen ombrandning.** Leverantören marknadsför inte, förser inte med eget
varumärke och gör inga väsentliga ändringar i Kundens AI-system. Skulle
Leverantören göra något av detta blir Leverantören provider enligt artikel 25,
vilket kräver skriftlig överenskommelse i förväg.

**9.3 Kundens åtaganden.** Kunden ansvarar för att AI-systemen uppfyller
tillämpliga krav — dokumentation, loggning, transparens enligt artikel 50,
riskhantering samt eventuella högriskkrav — och för att inte använda
Utrustningen för praxis som är förbjuden enligt artikel 5. Kunden håller
Leverantören skadeslös för krav från tredje man eller myndighet som grundas på
Kundens AI-användning.

**9.4 Avstängningsrätt.** Leverantören får stänga av Utrustningen om användningen
uppenbart strider mot artikel 5 eller mot lag, efter skriftlig anmodan om rättelse
och skälig frist — utom när dröjsmål innebär allvarlig risk.

## 10. Avgifter, el och energirapportering

| Post | Belopp |
|---|---|
| Etableringsavgift | [BELOPP] {{currency}} |
| Månadsavgift utrymme och drift | [BELOPP] {{currency}} |
| Avtalsvärde (period) | {{value}} {{currency}} |

**10.1 Elkostnad.** Elkostnad debiteras som genomlysning (pass-through) av
faktisk förbrukning inom Avtalad Effekt, till Leverantörens inköpspris jämte
nätavgift, energiskatt och påslag om [X] %. Skattenedsättningen för datorhallar
slopades den 1 juli 2023, och full energiskatt utgår.

**10.2 Överförbrukning.** Effektuttag utöver Avtalad Effekt debiteras med
[PRIS] {{currency}} per kW och månad. Leverantören ska varna innan begränsande
åtgärd vidtas.

**10.3 Energirapportering.** Kunden lämnar de uppgifter Leverantören behöver
för rapportering av datacentrets energiprestanda enligt lagen (2025:570) om
datacenters energiprestanda och tillhörande EU-krav.

Betalningsvillkor 30 dagar netto, exklusive mervärdesskatt. Prisjustering en
gång per år enligt SCB:s konsumentprisindex (KPI), meddelad tre månader i förväg.
Elpris och skatter justeras löpande enligt 10.1.

## 11. Avtalstid

Avtalet gäller från {{start_date}} till {{end_date}}, dock minst **[ANTAL]
månader**. Uppsägning ska ske skriftligen senast **[3–6] månader** före
periodens utgång. Sägs avtalet inte upp gäller det **tills vidare** med samma
uppsägningstid — ingen ny bindningstid uppstår.

## 12. Ansvar

**12.1** Leverantörens sammanlagda ansvar för direkt skada är begränsat till
**tolv (12) månaders avgift** enligt punkt 10, räknat på de tolv månader som
föregick skadan. För skada på Utrustningen gäller därutöver punkt 7.

**12.2** Leverantören ansvarar inte för indirekt skada — utebliven vinst,
produktionsbortfall, förlust eller förvanskning av data eller modeller,
anseendeskada eller krav från tredje man.

**12.3** Begränsningarna gäller inte vid uppsåt eller grov vårdslöshet, vid
personskada, eller där tvingande lag föreskriver annat.

**12.4 Reklamation:** krav ska framställas skriftligen inom **sex (6) månader**
från upptäckt och preciseras inom **två (2) månader** därefter.

## 13. Upphörande och utflytt

**13.1 Utflyttsfönster.** Kunden ska hämta Utrustningen inom **30 dagar** från
avtalets upphörande. Avgift enligt punkt 10 löper till dess utflytt är slutförd.

**13.2 Demontering.** Demontering utförs av [Leverantören mot timdebitering /
Kunden med eskort]. Utrymmet återställs i ursprungligt skick bortsett från
normalt slitage.

**13.3 Slutbesiktning.** Vid utflytt stäms Utrustningen av mot Bilaga 1 och
båda Parter kvitterar överlämnandet.

**13.4 Radering.** Ska lagringsmedia raderas i stället för att följa med Kunden
sker det enligt **NIST SP 800-88 Rev. 2** med tekniker enligt IEEE 2883-2022,
på nivån [Clear / Purge / Destroy]. Leverantören utfärdar **raderingsintyg per
serienummer**. Skrotning sker enligt reglerna om avfall från elektrisk och
elektronisk utrustning.

**13.5 Kvarlämnad utrustning.** Hämtas Utrustningen inte inom fristen sänder
Leverantören skriftlig anmodan med **30 dagars** frist. Därefter får Leverantören
flytta Utrustningen till magasin på Kundens bekostnad. Först efter ytterligare
**sex (6) månader** och en andra skriftlig anmodan får Leverantören avyttra
Utrustningen och avräkna kostnaderna mot köpeskillingen; överskott tillfaller
Kunden. Denna punkt ersätter den retentionsrätt Leverantören avstått från
enligt 4.5 och är Leverantörens enda befogenhet över Utrustningen.

## 14. Sekretess

Vardera Part förbinder sig att inte utan motpartens medgivande röja
konfidentiell information. Åtagandet gäller under avtalstiden och **tre (3) år**
därefter, och hindrar inte fullgörande av rapporteringsskyldighet enligt lag.

## 15. Force majeure

Part är befriad från påföljd om fullgörandet hindras av omständighet utanför
Parts kontroll, inklusive avbrott i extern kraftförsörjning och fel hos
underleverantör på grund av sådan omständighet. Varar hindret längre än tre
månader får motparten häva avtalet utan ersättningsskyldighet. Kundens rätt att
hämta Utrustningen enligt punkt 13 påverkas aldrig av force majeure.

## 16. Överlåtelse

Avtalet får inte överlåtas utan motpartens skriftliga medgivande. Överlåter
Leverantören sin verksamhet eller sitt datacenter ska Kundens rättigheter enligt
punkt 4 och 13 säkerställas i överlåtelsehandlingen.

## 17. Tvist och tillämplig lag

Svensk rätt tillämpas. Tvist avgörs av **[allmän domstol med Stockholms
tingsrätt som första instans / skiljeförfarande enligt SCC:s regler]**.

## 18. Bilagor

1. **Utrustningsförteckning** med fabrikat, modell och serienummer — uppdateras löpande
2. Utrymme, Avtalad Effekt, kyla och nätanslutning
3. Personuppgiftsbiträdesavtal
4. Tillträdes- och säkerhetsrutiner
5. Prislista för remote hands och tilläggstjänster

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

*Mallen bygger på traditionsprincipen i svensk sakrätt (NJA 2007 s. 413,
NJA 2008 s. 684), 12 kap. handelsbalken om deposition, dataskyddsförordningen
(EU) 2016/679, AI-förordningen (EU) 2024/1689, EN 50600, lagen (2025:570) om
datacenters energiprestanda samt NIST SP 800-88 Rev. 2.*

***Låt jurist granska punkt 4 innan mallen används skarpt.** Separationsrätten
till kundägd utrustning som står hos leverantören är den juridiskt känsligaste
delen av avtalet, och konstruktionen förutsätter att Kunden förvärvar direkt
från hårdvaruleverantören enligt 4.1.*
$avtal$,
  description   = $besk$Avtal där kunden äger hårdvaran och leverantören hostar och driftar den. Reglerar separationsrätt vid konkurs, avstående från retentionsrätt, PUB utan logisk åtkomst, AI-förordningens rollfördelning och säker radering vid exit.$besk$,
  updated_at    = now()
WHERE name = $namn$Privat AI — drift av kundägd hårdvara i DDC$namn$;

SELECT name || '  (' || length(body_markdown) || ' tecken)' FROM contract_templates ORDER BY name;