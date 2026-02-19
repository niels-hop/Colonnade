# Claude Development Notes

## Setup
- **Code signing**: Uitgeschakeld voor lokale development (geen Apple Developer account nodig)
- **SwiftFormat**: Vereist via Homebrew - `brew install swiftformat`
- **Xcode**: Developer directory moet wijzen naar Xcode.app, niet CommandLineTools

## Build & Run

**Standaard build:**
```bash
xcodebuild -scheme Loop -configuration Debug build
```

**Build + Open:**
```bash
xcodebuild -scheme Loop -configuration Debug build && \
open ~/Library/Developer/Xcode/DerivedData/Loop-*/Build/Products/Debug/Loop.app
```

**Gebouwde app locatie:**
```
~/Library/Developer/Xcode/DerivedData/Loop-*/Build/Products/Debug/Loop.app
```

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
- `CODE_SIGN_IDENTITY = "-"`
- `CODE_SIGN_STYLE = Manual`
- `ENABLE_HARDENED_RUNTIME = NO`

## Development

**SwiftFormat runs automatisch bij elke build** - project heeft `.swiftformat` config

**Vereisten bij PR:**
- Code moet SwiftFormat checks passeren
- Uitgebreide comments volgens project stijl (zie CONTRIBUTING.md)
- Emoji prefixes in commits: 🐞 (bug), ✨ (feature), 🌐 (i18n)

## Eerste gebruik
Loop vraagt om **Accessibility permissions** (System Settings → Privacy & Security → Accessibility)
