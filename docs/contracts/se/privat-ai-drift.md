# Avtal om drift av kundägd AI-utrustning i distribuerat datacenter

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
