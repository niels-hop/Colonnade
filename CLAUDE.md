# Claude Development Notes

## Doel & Visie van deze fork

Dit is een **persoonlijke fork van Loop** (origineel: MrKai77/Loop) die wordt toegespitst op één gerichte
window-management workflow. Houd dit als leidraad voor elke bug fix en nieuwe feature:

- **Primaire use case: super ultrawide schermen.** Daar is de Ultrawide Dock voor gemaakt en daar moet alles
  op geoptimaliseerd zijn.
- **Ook bruikbaar op de MacBook zelf** (zonder extern scherm). De feature moet dus niet stuk gaan op gewone
  16:10 schermen — gewoon nuttig blijven.
- **Alleen horizontaal rangschikken.** Vensters worden altijd over de **volledige hoogte** geplaatst; de app
  verdeelt enkel de horizontale ruimte. Geen verticale splits, geen kwart-tegels.
- **Bediening blijft simpel, precies zoals nu:** twee toetsen ingedrukt houden (de trigger) en met de muis
  bepalen waar het venster heen gaat. Dat moet *de hele app/fork* zijn — de dock is geen extra modus naast de
  radial menu, maar het hoofdmechanisme. Stuur features richting dit ene, eenvoudige interactiemodel.
- **Moet ook werken op het andere account op deze MacBook (`werkdv`).** Dat betekent: vermijd aannames over
  één specifieke gebruiker en houd er rekening mee dat Accessibility-permissions per macOS-account apart
  toegekend moeten worden (zie "Eerste gebruik").

Bij twijfel over scope: kies de oplossing die de **simpele "twee toetsen + muis"-bediening** behoudt en die
**horizontale verdeling over volle hoogte** versterkt.

## Architectuuroverzicht

De motor zit in `Loop/Core/LoopManager.swift` (singleton `LoopManager.shared`) en regelt de hele cyclus:

1. **Triggers** (`Loop/Core/Triggers/`): `KeybindObserver` en `MiddleClickObserver` detecteren de
   trigger-toets en roepen `openLoop` / `closeLoop` aan.
2. **Event-monitoring**: zodra Loop open is starten `mouseMovedEventMonitor`, `leftClickMonitor` en
   `scrollWheelMonitor`. Muisbeweging bepaalt de gekozen `WindowAction`.
3. **Indicators** (los gekoppelde controllers): `RadialMenuController`, `PreviewController` en
   `UltrawideDockController`. `LoopManager` pusht dezelfde `setWindow`/`setAction` naar alle drie.
4. **Uitvoering** (`Loop/Window Management/Window Manipulation/WindowEngine.swift`): bij loslaten wordt de
   gekozen actie toegepast. `WindowRecords` houdt per venster de huidige actie bij.

### Ultrawide Dock (de kernfeature)

Bestanden in `Loop/Window Action Indicators/Ultrawide Dock/`:

- **`UltrawideDockController.swift`** — beheert het borderless `NSPanel`, schaalt de dock-breedte met de
  aspect ratio en snapt de muiscursor naar het midden bij openen.
- **`UltrawideDockViewModel.swift`** — het brein. **Anchor-snap-model**: berekent vrije horizontale ranges
  (stukken scherm die niet door een Loop-geplaatst venster bezet zijn) en maakt daar anchors van
  (`screenEdge`, `windowAdjacent`, `gapCenter`; edge leading/trailing/center). Muis-X kiest de dichtstbijzijnde
  anchor (`updateForMouseX`), klik cycelt door groottes (`cycleSize`), scrollwiel fine-tunet (`adjustSize`).
  Alles is full-height (`height: 1`).
- **`UltrawideDockView.swift`** — SwiftUI-weergave: glass-effect, bestaande vensters (gedimd op z-order),
  anchor-tickmarks en de actieve preview in accentkleur.

Integratie in `LoopManager`: `shouldUseUltrawideDock` beslist via `Defaults[.ultrawideDockTriggerMode]`
(`.automatic` = aspect ratio ≥ 2.0, `.alwaysOn`, `.never`). Settings: `BehaviorConfiguration.swift` (sectie
"Ultrawide Dock") + Picker in het menubar-menu (`LoopApp.swift`). Defaults staan in
`Loop/Extensions/Defaults+Extensions.swift`.

> Let op: de oude `Defaults[.useUltrawideDock]` bool is **deprecated** ten gunste van
> `ultrawideDockTriggerMode` — kandidaat om later op te ruimen.

## Setup
- **Code signing**: Self-signed certificaat `Loop Self-Signed` (geen Apple Developer account nodig). Zie "Signing & deploy".
- **SwiftFormat**: Vereist via Homebrew - `brew install swiftformat`
- **Xcode**: Developer directory moet wijzen naar Xcode.app, niet CommandLineTools

## Build & Run

> **Let op — Swift-macro:** sinds de upstream-merge gebruikt het project de `Scribe`-package
> met een Swift-macro (`@Loggable`). Xcode wil die eenmalig interactief laten goedkeuren; in
> CLI-builds geef je daarom `-skipMacroValidation` mee (zoals hieronder en in `deploy.sh`).

**Standaard build:**
```bash
xcodebuild -scheme Loop -configuration Debug -skipMacroValidation build
```

**Build + Open:**
```bash
xcodebuild -scheme Loop -configuration Debug -skipMacroValidation build && \
open ~/Library/Developer/Xcode/DerivedData/Loop-*/Build/Products/Debug/Loop.app
```

**Gebouwde app locatie:**
```
~/Library/Developer/Xcode/DerivedData/Loop-*/Build/Products/Debug/Loop.app
```

## Signing & deploy

Doel: Accessibility-toestemming hoeft niet meer bij elke build opnieuw, en de app draait op
beide accounts op deze Mac (`nhop` + `werkDV`).

**Achtergrond:** ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) gaf elke build een nieuwe cdhash,
waardoor macOS' TCC de Accessibility-toestemming telkens vergat. Daarom signen we nu met een
**stabiel self-signed certificaat**. TCC blijft per account werken (elk account geeft één keer
toestemming), maar die toestemming blijft nu staan over rebuilds heen.

**Eenmalig — certificaat aanmaken (op het `nhop`-account, dat bouwt):**
1. Open *Keychain Access* → menu *Keychain Access → Certificate Assistant → Create a Certificate…*
2. Name: `Loop Self-Signed` · Identity Type: `Self Signed Root` · Certificate Type: `Code Signing`
3. Maak aan, daarna verschijnt het in `security find-identity -v -p codesigning`.

De projectinstellingen verwachten dit certificaat: `CODE_SIGN_IDENTITY = "Loop Self-Signed"`,
`CODE_SIGN_STYLE = Manual`, bundle ID `com.nielshop.Loop` (hernoemd van `com.MrKai77.Loop` om
TCC-botsing met een eventuele officiële Loop te voorkomen). Het certificaat hoeft alleen in de
keychain van het bouwende account te staan; `werkDV` draait enkel de gekopieerde app.

**Deployen naar beide accounts:**
```bash
./scripts/deploy.sh          # Release build, signt + kopieert naar /Applications/Loop.app
CONFIG=Debug ./scripts/deploy.sh
```
Het script controleert het certificaat, bouwt, sluit een draaiende Loop af, installeert in
`/Applications` (nhop is admin → geen sudo nodig) en verifieert dat de handtekening geldig en
niet-adhoc is. Autostart (login item) staat per account apart in.

## Project Configuratie

**Dependencies (auto-resolved):**
- Luminare (main branch)
- Defaults (sindresorhus, main branch)
- swiftui-introspect (1.3.0)
- swift-syntax (602.0.0)
- swiftui-variadic-views (1.0.0)

**Schemes:**
- Loop (gebruik deze voor development)
- Loop (GH ACTIONS)
- Luminare

**Code signing settings (in project.pbxproj):**
- `DEVELOPMENT_TEAM = ""`
- `CODE_SIGN_IDENTITY = "Loop Self-Signed"`
- `CODE_SIGN_STYLE = Manual`
- `ENABLE_HARDENED_RUNTIME = NO`
- `PRODUCT_BUNDLE_IDENTIFIER = com.nielshop.Loop`

## Development

**SwiftFormat runs automatisch bij elke build** - project heeft `.swiftformat` config

**Vereisten bij PR:**
- Code moet SwiftFormat checks passeren
- Uitgebreide comments volgens project stijl (zie CONTRIBUTING.md)
- Emoji prefixes in commits: 🐞 (bug), ✨ (feature), 🌐 (i18n)

## Eerste gebruik
Loop vraagt om **Accessibility permissions** (System Settings → Privacy & Security → Accessibility)
