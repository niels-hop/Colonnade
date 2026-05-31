#!/usr/bin/env bash
#
# Bouwt Loop met het stabiele self-signed certificaat en installeert de app in
# /Applications zodat alle macOS-accounts op deze Mac dezelfde build draaien.
#
# Vereist (eenmalig): een code-signing certificaat met common name "Loop Self-Signed"
# in de login-keychain. Zie CLAUDE.md, sectie "Signing & deploy".
#
# Gebruik:
#   ./scripts/deploy.sh            # Release build -> /Applications/Loop.app
#   CONFIG=Debug ./scripts/deploy.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="${CONFIG:-Release}"
SIGN_IDENTITY="Loop Self-Signed"
DEST="/Applications/Loop.app"

cd "$REPO_ROOT"

# 1. Controleer dat het signing-certificaat bestaat.
#    Geen -v: een self-signed cert is "untrusted" en valt buiten de valid-only lijst,
#    maar codesign kan er prima mee tekenen (TCC pint de leaf-hash, niet de CA-trust).
if ! security find-identity -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "FOUT: code-signing certificaat '$SIGN_IDENTITY' niet gevonden in de keychain."
    echo "      Maak het eenmalig aan via Keychain Access (zie CLAUDE.md)."
    exit 1
fi

# 2. Build (SwiftFormat draait automatisch via de build phase).
echo "==> Bouwen ($CONFIG)..."
xcodebuild -scheme Loop -configuration "$CONFIG" build

# 3. Vind de gebouwde app.
BUILT_DIR="$(xcodebuild -scheme Loop -configuration "$CONFIG" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
APP="$BUILT_DIR/Loop.app"
if [[ ! -d "$APP" ]]; then
    echo "FOUT: gebouwde app niet gevonden op $APP"
    exit 1
fi

# 4. Sluit een draaiende Loop af (anders kan de kopie mislukken / blijft oude versie actief).
echo "==> Eventuele draaiende Loop afsluiten..."
osascript -e 'tell application "Loop" to quit' 2>/dev/null || true
pkill -x Loop 2>/dev/null || true
sleep 1

# 5. Installeer in /Applications. nhop is admin en /Applications is groep-schrijfbaar,
#    dus dit lukt normaal zonder sudo, ook als de bestaande app van een ander account is.
echo "==> Installeren naar $DEST..."
if [[ -d "$DEST" ]]; then
    if ! rm -rf "$DEST" 2>/dev/null; then
        echo "Kan bestaande $DEST niet verwijderen (waarschijnlijk eigendom van een ander account)."
        echo "Voer eenmalig handmatig uit en draai daarna dit script opnieuw:"
        echo "    sudo rm -rf $DEST"
        exit 1
    fi
fi
cp -R "$APP" "$DEST"

# 6. Verifieer de handtekening (moet stabiel + geldig zijn, niet adhoc).
echo "==> Handtekening verifiëren..."
codesign --verify --deep --strict --verbose=2 "$DEST"
codesign -dvv "$DEST" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier" || true

echo ""
echo "Klaar. Loop staat in $DEST."
echo "Per account nog éénmalig: Systeeminstellingen -> Privacy & Beveiliging -> Toegankelijkheid -> Loop aanvinken."
echo "Daarna blijft de toestemming staan over rebuilds heen (stabiele handtekening)."
