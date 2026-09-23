# Claude Development Notes

## Doel & Visie

**Colonnade** is een publieke macOS-app, ontstaan als fork van Loop (MrKai77/Loop, GPL-3.0). De app is
volledig gebouwd rond één interactie: **twee toetsen inhouden (de trigger) en met de muis kiezen waar het
venster heen gaat**. Houd dit als leidraad voor elke bug fix en nieuwe feature:

- **Primaire use case: super ultrawide schermen.** De dock (minimap) is daarvoor gemaakt en alles moet daarop
  geoptimaliseerd zijn.
- **Ook bruikbaar op de MacBook zelf** (zonder extern scherm). Niet stuk laten gaan op 16:10/16:9.
- **Alleen horizontaal rangschikken.** Vensters altijd over de **volledige hoogte**; de app verdeelt enkel de
  horizontale ruimte. Geen verticale splits, geen kwart-tegels.
- **Bediening blijft simpel:** trigger + muis is de hele app. De dock is het hoofdmechanisme; het radiaalmenu
  bestaat alleen nog als fallback (dock-modus "Nooit" of "Automatisch" op smalle schermen).
- **Meerdere macOS-accounts** (bij de maintainer: `nhop` en `werkDV`): geen aannames over één gebruiker;
  Accessibility-permissie is per account.
- **Bestaande functionaliteit niet breken.** Instelbaarheid toevoegen mag; gedrag wijzigen alleen bewust.

Bij twijfel over scope: kies de oplossing die de **"twee toetsen + muis"-bediening** behoudt en
**horizontale verdeling over volle hoogte** versterkt.

## Identiteit

- Naam **Colonnade**, bundle-ID `com.nielshop.Colonnade`, URL-scheme `colonnade://`.
- Repo/releases: `niels-hop/Colonnade` (constante in `Colonnade/Updates/ReleaseChecker.swift`).
- Upstream-attributie (GPL-3.0) staat in README en in Settings → About; laat de "Created by Kai Azim"-headers
  in bestanden uit Loop staan.
- `LegacyDataMigration` (in `Colonnade/App/`) kopieert eenmalig instellingen en Application Support-data uit de
  oude build `com.nielshop.Loop`. Nieuwe Defaults-keys hebben dus geen migratie nodig.

## Architectuuroverzicht

De motor zit in `Colonnade/Core/LoopManager.swift` (singleton `LoopManager.shared`; de interne naam "Loop" voor
een trigger-sessie is bewust behouden) en regelt de hele cyclus:

1. **Triggers** (`Colonnade/Core/Observers/`): `KeybindTrigger` en `MiddleClickTrigger` roepen `openLoop` /
   `closeLoop` aan.
2. **Event-monitoring**: `MouseInteractionObserver` stuurt muisbeweging, klik, sleep en scroll naar de dock.
3. **Indicators**: `WindowActionIndicatorService` beheert `UltrawideDockController`, `RadialMenuController`
   en `PreviewController`.
4. **Uitvoering**: dock-plannen via `Colonnade/Horizontal Layout/` (`HorizontalLayoutEngine`,
   `HorizontalLayoutRuntimeAdapter`, `HorizontalLayoutExecutor`); losse acties via `WindowEngine`.

### De dock (kernfeature)

- **Reducer:** `Colonnade/Horizontal Layout/UltrawideDockInteraction.swift` — pure event-reducer
  (move/pointerDown/drag/pointerUp/scroll/setFreeform/cancel → `UltrawideDockOutput`). Configuratie
  (bv. `clickWidthCycle`) wordt via `init` geïnjecteerd; **lees nooit `Defaults` in de reducer**.
- **UI:** `Colonnade/Window Action Indicators/Ultrawide Dock/` (Controller = NSPanel + pointer-mapping,
  ViewModel = presentatie, View = SwiftUI).
- **Instellingen** (`Colonnade/Extensions/Defaults+Extensions.swift`, sectie "Ultrawide Dock"):
  `ultrawideDockTriggerMode` (default `.alwaysOn`), `ultrawideDockAutomaticAspectRatio`,
  `ultrawideDockBaseWidth`, `ultrawideDockPointerSensitivity`, `ultrawideDockClickCycle`.

### Instellingenvenster

`Colonnade/Settings Window/SettingsTab.swift` definieert de tabs, gegroepeerd als Dock (Dock, Indelingen),
Bediening (Trigger & sneltoetsen, Gedrag), Weergave (Accentkleur, Voorbeeld, Radiaalmenu) en Colonnade
(Geavanceerd, Uitgesloten apps, Info). Dock-tabs staan in `Colonnade/Settings Window/Dock/`; de inspector toont
daar `DockIllustrationView`. Nieuwe UI-teksten krijgen een `nl-BE`-vertaling in `Localizable.xcstrings`.

### Updates

Geen auto-updater (die vereiste Kai's Apple Developer-certificaat). `ReleaseChecker` vraagt dagelijks de
laatste GitHub-release op en opent de downloadpagina. Een release maak je door een tag `vX.Y.Z` te pushen;
`.github/workflows/release.yml` bouwt en publiceert `Colonnade.zip`.

## Build & Run

```bash
xcodebuild -project Colonnade.xcodeproj -scheme Colonnade -configuration Debug -skipMacroValidation build
xcodebuild -project Colonnade.xcodeproj -scheme Colonnade -configuration Debug -skipMacroValidation test
```

`-skipMacroValidation` is nodig voor de Scribe-macro (`@Loggable`). Gebouwde app:
`~/Library/Developer/Xcode/DerivedData/Colonnade-*/Build/Products/Debug/Colonnade.app`.

## Signing & deploy

- Standaard **ad-hoc** (`CODE_SIGN_IDENTITY = -` in `Colonnade/Config.xcconfig`), zodat iedereen kan bouwen.
- Lokaal overschrijft het gitignored `Colonnade/Local.xcconfig` dit met een stabiel self-signed certificaat
  (op deze Mac: `Loop Self-Signed`), zodat Accessibility-toestemming over rebuilds heen blijft staan.
- `./scripts/deploy.sh` bouwt Release, sluit Colonnade én de oude `com.nielshop.Loop` af, installeert in
  `/Applications/Colonnade.app` en verifieert de handtekening.

### Single-install invariant

Bij iedere opdracht om te installeren of deployen:

1. Gebruik `./scripts/deploy.sh` (Release). Geen tweede kopie in een gebruikersmap; alle accounts draaien
   `/Applications/Colonnade.app`. **Vraag eerst toestemming**: deploy vervangt de werkende installatie.
2. Verifieer met `codesign --verify --deep --strict --verbose=2 /Applications/Colonnade.app` (bundle-ID
   `com.nielshop.Colonnade`, authority = het self-signed certificaat).
3. `mdfind 'kMDItemCFBundleIdentifier == "com.nielshop.Colonnade"'` moet alleen `/Applications/Colonnade.app`
   teruggeven (buiten DerivedData-builds).
4. De oude `/Applications/Loop.app` (`com.nielshop.Loop`) en zijn login-item alleen verwijderen na expliciete
   toestemming.
5. Rapporteer dat elk account Colonnade eenmalig moet aanvinken onder Toegankelijkheid en autostart apart
   instelt.

## Development

- SwiftFormat: `swiftformat .` (CI lint via `.github/workflows/lint.yml`).
- Commit-prefixen: 🐞 bug, ✨ feature, 🌐 i18n, 📝 docs, 🚚 verplaatsen/hernoemen.
- Tests: `ColonnadeTests/` compileert specifieke bronbestanden (geen app-host); houd de reducer en engine
  vrij van AppKit/Defaults zodat ze testbaar blijven.
