# Contributing to Colonnade

Thanks for your interest! Colonnade has one job: arranging windows horizontally at full height with **two keys plus the mouse**. Contributions that sharpen that interaction are very welcome. Features that add a second, separate way of working usually aren't a fit.

## Before you start

Open an issue first for anything larger than a small fix. Describe the problem and the change you have in mind. Wait for a thumbs-up before investing a lot of time, so work doesn't overlap or go against the project's direction.

Bug reports are just as valuable as code. The issue form asks for your screen setup, because most dock behaviour depends on the aspect ratio.

## Building

```bash
git clone https://github.com/<your-name>/Colonnade.git
cd Colonnade
open Colonnade.xcodeproj
```

- No Apple Developer account is needed. Builds are ad-hoc signed by default.
- Want macOS to remember the Accessibility permission across rebuilds? Create a self-signed code-signing certificate and put `CODE_SIGN_IDENTITY = <its name>` in `Colonnade/Local.xcconfig` (gitignored). The README walks through it.
- On the command line, pass `-skipMacroValidation` (a dependency ships a Swift macro).

Run the tests with:

```bash
xcodebuild -project Colonnade.xcodeproj -scheme Colonnade -skipMacroValidation test
```

The dock's behaviour lives in a pure reducer (`Colonnade/Horizontal Layout/UltrawideDockInteraction.swift`) with thorough unit tests. If you change how the pointer maps to placements, add a test there.

## Code style

- Format with [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) (`swiftformat .`). CI runs it in lint mode.
- Document *why* in comments, not *what*. Follow the density of the surrounding code.
- Commit messages start with an emoji: 🐞 bug fix, ✨ feature, 🌐 localisation, 📝 docs, 🚚 moves/renames.

## Localisation

Strings live in `Colonnade/Localizable.xcstrings`. Add or fix a translation in Xcode's string catalog editor and open a PR. Many translations were inherited from Loop and may still need review.

## AI assistance

AI tools are fine to use, but say so in your PR: which tool, and for what. You are responsible for understanding and testing every line you submit.

## Code of conduct

Participation is governed by the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

By contributing you agree that your contributions are licensed under the [GPL-3.0](LICENSE), the same license as Colonnade and Loop.
