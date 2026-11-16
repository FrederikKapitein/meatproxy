# Tuinstra Meatproxy

> Approved by a human. Reviewed by nobody.

De native Apple-apps van **Tuinstra Meatproxy** (D45): een parodie-zusterbedrijf van
Tuinstra.DEV, waar de agents alles bouwen en de mens alleen nog ja zegt. Dit is de **Mac-app**: de collector, het gedeelde model, de twee werelden
in SpriteKit (Office in blocky, Orbit in de Starfield-stijl) en de Game HUD in SwiftUI. Het ontwerp en alle besluiten
staan op het designbord: <https://claude.ai/artifact/WSotGHsjjyc6CspeuAndzs>.

## Starten

Xcode 26 of nieuwer (Swift 6). Geen Xcode-project nodig: het is een Swift-package.

```bash
swift run Meatproxy              # je eigen sessies, live, elke 3 seconden
swift run Meatproxy --fixture    # verzonnen demodata, voor demo's en screenshots die je deelt
swift run Meatproxy --dump       # wat de collector ziet, zoals python3 live.py
swift test                       # collector, model en wereld (lopen, routes, servers)
```

Een PNG zonder venster: `Meatproxy --snapshot out.png --fixture [--focus claude|chatgpt|engine] [--floor next|<id>] [--orbit]`.
Een PNG van het hele venster, met de HUD: `SF_WINDOW_SHOT=out.png [SF_WINDOW_SHOT_ACTION=…] Meatproxy --fixture`
(het pad gaat via een omgevingsvariabele, omdat AppKit een pad op de commandoregel als document probeert te openen).
Acties, met komma's en twee seconden ertussen: `next`, `up`, `building:claude`, `engine`, `floor:<project-id>`, `session:<id>`,
`orbit`, `office`, `decision:<project-id>|<D-id>`, `workstream:<project-id>|<W-id>`, `zoom:<factor>`, `hover:x,y` en
`click:x,y` (een echte muisgebeurtenis op x, y punten vanaf linksboven, in de wereld), `uiclick:x,y` (een klik via het
venster, dus ook op knoppen in de HUD),
`walker:<k>` / `clickwalker:<k>` (de muis op wandelaar k op de campus), `move:<sessie>:<kamer>` (iemand loopt naar een
andere kamer) en `wait:<seconden>`. `SF_WINDOW_SHOT_BURST="4@2"` maakt vier opnamen twee seconden na elkaar
(`out-0.png` …); een opname houdt de app even op, dus beweging beoordeel je beter met losse runs op verschillende
`SF_WINDOW_SHOT_AFTER`. Bijvoorbeeld:

```bash
SF_WINDOW_SHOT=floor.png SF_WINDOW_SHOT_ACTION="floor:claude:/demo/shopfront" SF_WINDOW_SHOT_AFTER=12 swift run Meatproxy --fixture
SF_WINDOW_SHOT=orbit.png SF_WINDOW_SHOT_ACTION="orbit,session:a1" SF_WINDOW_SHOT_AFTER=14 swift run Meatproxy --fixture
```

## Bediening

Eén grammatica voor alle werelden (D24): klik vliegt erheen, scrollen of knijpen zoomt doorlopend en het niveau volgt
de zoom, slepen pant, `Esc` of **Up** gaat één niveau omhoog, `N` of de gele teller vliegt naar de volgende die op je
wacht, ⌘1 en ⌘2 wisselen tussen Campus en Orbit. Niveaus in Office: campus → gebouw (provider) → een verdieping van
binnen (project) → een persoon (sessie) → een helper (sub-agent). In Orbit: alle galaxies → galaxy → zonnestelsel →
planeet → maan, in één doorlopende zoom (D14).

## Instellingen en de Engine room

⌘, of het tandwiel rechtsboven opent de instellingen: een lade van rechts in het venster zelf. Onder **Engine room**
zet je je servers, deploys en backups: een host zoals je hem na `ssh` typt (`user@host` of een alias uit
`~/.ssh/config`), een naam en een soort. De app checkt ze elke minuut met `ssh -o BatchMode=yes`: met je eigen sleutels
en agent, nooit met een wachtwoord of passphrase, en met de gewone host-key-controle. Toevoegen kan pas na een test
die zonder wachtwoord inlogt; lukt dat niet, dan zegt de lade waarom (en bij een ontbrekende sleutel: `ssh-copy-id`).
De ingebouwde check leest alleen load, schijf en geheugen (waarschuwing vanaf 90% schijf, load 1,5 per core of minder
dan 10% vrij geheugen); een eigen check mag ook (exit 0 OK, 1 waarschuwing, anders down). De lijst staat in
`~/Library/Application Support/Meatproxy/servers.json`: alleen hosts, geen wachtwoorden of sleutels. Met
`--fixture` zie je verzonnen servers en wordt er niets gelezen of bewaard.

## Projecten en verdiepingen

Elke projectmap met recente sessies krijgt vanzelf een verdieping (D46); daarvoor hoef je niets in te stellen. Zet een
project vast (de speld in de inspector, of *On campus* in Settings onder **Projects**) om het zonder recente sessie te
houden. Losse chats (thuismap, scratch-mappen) delen één verdieping *Chats*, die je in Settings uitzet. Alles staat in
`~/Library/Application Support/Meatproxy/projects.json`.

## Dark Software Factories

Een project wordt een Dark Software Factory als je het aanzet (D44): met de schakelaar bovenin de inspector van het
project, of in Settings onder **Projects** (daar kan ook een map die nu niet op de campus staat). Alleen aangezette
projecten zijn factories; ze staan in `projects.json`. Aanzetten
verandert niets in het project en maakt geen bestanden: de CEO schrijft ze in `factory/`, naast `code/`. Zolang er geen
zijn, toont de factory *No CEO yet*. De app leest het datacontract uit `factory/README.md` van die factory: de laatste briefing (`briefings/YYYY-MM-DD.md`), de werkstromen
(`workstreams/W-NNN-*.md`, met hun fase en de stappen terug uit `## Log`), de vragen (`decisions/D-NNNN-*.md`) en de
autonomie (`autonomy.yml`; `STOP` op regel 1 pauzeert). Een aangezette factory heeft altijd een verdieping, ook zonder sessie in
de laatste uren.

- **Office:** elke werkstroom is een kaartje aan de achterwand van de kamer van zijn fase; de verdieping is zo donker
  als de factory autonoom is; de balie pulseert zolang er een vraag open staat.
- **Orbit:** elke werkstroom is een planeet om de ster van de factory, met het landschap van zijn fase.
- **Inspector:** eerst de briefing, dan de open vragen, de gates met hun reeks ja's en de werkstromen van PLAN tot DONE.
- **Antwoorden:** een open vraag (`status: open`) telt mee in Needs you. De kaart toont Why, Evidence, On yes en On no,
  een notitie en Yes of No; na Send yes of Send no schrijft de app `status`, `answered` en de notitie onder `## Answer`,
  atomair en verder niets. Een vraag die niet meer open is, wordt nooit beantwoord.

### De heartbeat

Meatproxy wekt de CEO van een factory zelf (D47), zonder geplande taken in Claude of ChatGPT: op zijn ritme (standaard
werkdagen 07:10), drie minuten na je antwoorden, met **Run now** en bij een nieuwe mislukte CI-run op main, master of
develop (via je eigen `gh`). De CEO draait headless in de projectmap, `claude -p --permission-mode acceptEdits` of
`codex exec -s workspace-write`, met de allowlist van het project zelf (`.claude/settings.json`), die de app met
`--settings` meegeeft: Claude Code negeert de instellingen van een map die je nog niet vertrouwd hebt, maar volgt altijd
de opdrachtregel. Zonder allowlist kan hij weinig en waarschuwt de kaart. Elk project heeft één CEO: de verdieping toont
alleen de laatste run, altijd dezelfde persoon. Logs en stand staan in `~/Library/Application Support/Meatproxy/heartbeats`. Standaard slaat het hart alleen
als de app draait; *Heartbeat when closed* in Settings installeert een launch agent
(`~/Library/LaunchAgents/dev.tuinstra.meatproxy.heartbeat.plist`) die elke vijf minuten `Meatproxy --heartbeat` draait.

Vangrails (D48), zodat een factory je plan niet opbrandt:
- elk project heeft zijn eigen CEO: factories wachten nooit op elkaar, alleen op hun eigen lopende run;
- per factory hooguit 6 automatische runs per dag en 20 minuten rust tussen runs (instelbaar);
- `--max-turns 60` per Claude-run en 45 minuten per run;
- na twee CI-wekkers op rij wacht een factory op **Resume**;
- een planlimiet in de uitvoer pauzeert die runtime tot de reset;
- **Pause all factories** stopt alles.

**Run now** is van jou en slaat de vangrails per factory over.

Een CEO-run van buiten de app die in een scratch-map begint en in zijn eerste bericht of met `cd` naar de factory verwijst,
staat op de verdieping van de factory (D37). Met `--fixture` staat een verzonnen factory aan, *Pebble Puzzles*, uit
een tijdelijke map die bij elke start opnieuw wordt geschreven: antwoorden daar raakt niets echts.

## Contracten

Wat Meatproxy en een agent van elkaar verwachten staat in een contract met een versie (D50), niet in losse afspraken:

- [`docs/contracts/factory.md`](docs/contracts/factory.md): `meatproxy-factory`, versie 3. Een factory zegt in
  `factory/contract.yml` welke versie hij volgt; ideeën voor de CEO (`factory/ideas/`) werken vanaf versie 2, je
  mandaat (`factory/mandate.yml`: autonomie per onderdeel, de rol van de CEO, je voorkeuren) vanaf versie 3 (D56).
- [`docs/contracts/engine-room.md`](docs/contracts/engine-room.md): `meatproxy-engine-room`, versie 1: de werkplaats
  van de DevOps-agent, de alarmen en de ops-tool.

## Engine room: alarmen en de DevOps-agent

Een server of site die twee checks achter elkaar slecht is, slechter wordt of weer goed is, wordt een melding op deze
Mac (D49). Per server: alarmen aan of uit, publieke adressen (elke vijf minuten: antwoord en TLS-certificaat) en wat de
DevOps-agent er mag: laat met rust, diagnoseer en vraag, of veilige reparaties. De agent (aan te zetten in Settings ›
Engine room) komt alleen via `Meatproxy --ops <server> <actie>` op een server; die tool controleert zelf per server
wat mag en logt elke actie. Wat niet mag wordt een ja/nee-vraag in Needs you.

```bash
.build/debug/Meatproxy --ops list
```

## De terminal

⌘J opent de terminal onderin het venster (D57, SwiftTerm). Elke tab draait één gecontroleerde opdracht:

- **Take over** op een sessie: `claude --resume <id>` (of `codex resume <id>`) in de map waar die begon. Een lopende
  CEO-run stopt eerst netjes; de heartbeat van die factory wacht tot je de tab sluit.
- **Terminal** bij een server: ssh met je eigen sleutels.
- **Watch** bij een CEO- of DevOps-run: het log, terwijl het groeit.

## De app als bundel

```bash
scripts/make-app.sh
```

maakt `build/Meatproxy.app` (bundle id `dev.tuinstra.meatproxy`, het merk-icoon, ad-hoc getekend; niet genotariseerd).
Alleen in de bundel komen meldingen als echte systeemmeldingen met het icoon, Open en Run DevOps now (D54).

## Merk

Het merk staat in het merkboek (`assets/brand-explore/meatproxy-brand.html` in de projectmap) en in D45. In de app:

- **Naam:** het venster en het About-paneel heten Tuinstra Meatproxy; menu's en het programma kort `Meatproxy`.
- **Lockup:** het vinkje, TUINSTRA op een geel tabje en Meatproxy, in Inter 800 en 900 (`Brand/fonts`, OFL, alleen
  voor dit proces geladen). Kop van de linkerkolom (klik: About) en, groot, het laadscherm.
- **Beeldmerk:** het pixelvinkje van 16 × 16 (`Brand.check`), een gele kant op een geelbruine richel recht eronder: een
  Ja-knop die je indrukt. Op hele apparaatpixels getekend. Het Dock-icoon is `Brand/AppIcon.png`.
- **Kleur:** de Tuinstra Dark-neutralen (#121212, #1A1A1A, #242424, tekst #F3F3F3 en #AEAEAE) en één geel, #FFD83D:
  de primaire actie (Ja, Send yes, Add server, de teller) en wat op je wacht. Groen en rood alleen voor een stand,
  amber voor een serverwaarschuwing, altijd met het woord erbij.
- **Bediening:** knoppen zijn opgetild (`TactileButtonStyle`): rand van 1 px, massieve richel recht eronder (primair
  3 px, neutraal 2 px), zakken bij indrukken op hun richel en veren terug; ook via hun sneltoets. Invoervelden zijn
  opgetild (`.lifted(focused:)`) en tonen focus met een ring. Schakelaars en segmenten zijn opgetild; het gekozen
  segment is een neutrale toets met een dunne gele rand. Kaarten geven 1 px. Links blijven gewone tekst. Hoeken: 4
  voor badges, 6 voor bediening, 10 voor kaarten, 12 voor panelen.
- **Raster:** de bovenbalk is de titelbalk (52 pt, gelijk met de verkeerslichten); alles op 16 pt van de rand en 12 pt
  uit elkaar; schakelaar en zoom op de middenas.
- **Beweging** (`Motion.swift`): het vinkje bouwt zich op en stempelt zolang de campus laadt, de lockup vliegt naar zijn
  plek en de HUD komt gestaffeld binnen; de gekozen toets glijdt, de teller rolt, rijen schuiven, een antwoord stempelt.
  Met *Verminder beweging* staat alles stil.
- **Tekst:** de systeemletter, zoals op alle Apple-oppervlakken van Tuinstra; mono alleen voor ids, hosts, tijden en
  getallen. Meme mode (Settings › Factories) maakt van Ja en Nee LGTM en Not today; Send yes en Send no blijven letterlijk.
- **Instellingen** staan in `~/Library/Application Support/Meatproxy/`; de oude map `Software Factory` gaat bij de eerste
  start (ook van `--dump`) daarheen.

## Opbouw

| Package | Wat | Platform |
| --- | --- | --- |
| `FactoryCore` | Model (provider → project → sessie → sub-agent), states, de rollen (D41), de kamer per sessie en het ↩ (D39), de vijf niveaus, `WorldBuilder`, demodata | alle |
| `FactoryCollector` | Leest `~/.claude/projects` en `~/.codex/sessions`, alleen-lezen; port van `live.py`; project = de map onder `~/Projects`, elders de git-root, en een sessie blijft waar hij begon (D37) | macOS |
| `FactoryScenes` | De werelden: `ArtEngine` (de art in een verborgen WebKit-view), `CampusScene`, `FloorScene`, `OrbitScene`, `WorldController` | alle (invoer nu macOS) |
| `Meatproxy` | De Game HUD (D31): Needs you, inspector, niveaus, Campus/Orbit, teller | macOS |

### De art: één bron, met het designbord

De art staat in `Sources/FactoryScenes/Art/src/art/` en is dezelfde als op het designbord:

- `blocky-cast.js` maakt de mensen: rollen, poses, vier kanten en een generator per rol (D41).
- `blocky-world.js` bouwt het atrium (D38), een providergebouw en de campus (D32).
- `orbit-gen.js` maakt elk hemellichaam uit een vaste id (D42).

De app draait die scripts in een verborgen WebKit-view (`ArtEngine`, via `Art/engine.html`). `Art/src/app/engine.js`
tekent ze laag voor laag op een canvas en geeft PNG's terug:

- de vloer en de grond als één beeld;
- elk meubel, elke muur en elk gebouw als eigen sprite met een dieptesleutel, gepakt op atlaspagina's;
- licht en bordjes als lagen erover;
- per persoon alle frames (lopen, staan, typen, zitten, één pose per stand, vier kanten);
- per hemellichaam een beeld per grootte en lichtrichting.

SpriteKit sorteert, laat mensen van kamer naar kamer lopen (door de deur, rond de hal), animeert en zoomt. Orbit houdt
het heelal in eigen coördinaten (doubles, zoals het bord) en zet elk frame alleen schermposities in SpriteKit, zodat
de zoom van ruim duizend keer scherp en precies blijft.

Wijzig je de art, dan werkt de app na een nieuwe build mee. Er is geen sync-stap meer: het webprototype is alleen
referentie (D40). Bekijken in de browser: `tools/blocky-cast.html` (`?team=1`, `?hero=Rue`), `tools/blocky-floor.html`,
`tools/blocky-campus.html` en `tools/orbit-gen.html`, via een statische server in deze map. `Art/engine.html` zelf
werkt ook in de browser: roep daar `sf.floor()`, `sf.campus(…)`, `sf.figure(…)` of `sf.body(…)` aan in de console.

Wat er de collector uit gaat zijn alleen korte labels (titels, soort actie, bestandsnamen, het programma van een
commando), nooit bestandsinhoud, uitvoer of volledige commandoregels.

## Verschil met live.py

Een beurt telt ook als open zodra de agent tools gebruikt. In een groot sessiebestand kan de prompt die de beurt
begon buiten de laatste 3 MB vallen; `live.py` zag zo'n lange beurt daardoor als klaar.

## Nog niet

iPad/iPhone/Watch, CloudKit-sync (D8), de ja/nee-brug voor toestemmingen van sessies (D11; factory-vragen kunnen wel), het wormgat voor een project bij twee providers (D16), de satelliet voor jou als
stakeholder in Orbit (D41), geluid (D28, staat standaard uit), opslag van 30 dagen geschiedenis (D29), de minimap en
een echte Find (⌘K). De eerste keer dat je een verdieping opent, stappen de mensen binnen zodra hun figuur getekend is
(een paar seconden); daarna staan ze er meteen.

> Still needed. Legally.

## Bijdragen en licentie

Werk gaat via een branch en een pull request; GitHub Actions draait `swift build` en `swift test` op macOS (D60).
Alles in deze repo is verzonnen of generiek: echte sessies, projecten, servers en meldingen horen hier niet in.
Screenshots en demo's maak je met `--fixture`.

MIT, zie [LICENSE](LICENSE).
