#!/usr/bin/env bash
#
# Bouwt Colonnade met een stabiel code-signing certificaat en installeert de app in
# /Applications, zodat alle macOS-accounts op deze Mac dezelfde build draaien.
#
# Het certificaat komt uit Colonnade/Local.xcconfig (CODE_SIGN_IDENTITY = ...), of uit de
# omgevingsvariabele SIGN_IDENTITY. Zie README.md, sectie "Building from source".
#
# Gebruik:
#   ./scripts/deploy.sh            # Release build -> /Applications/Colonnade.app
#   CONFIG=Debug ./scripts/deploy.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="${CONFIG:-Release}"
DEST="/Applications/Colonnade.app"
LOCAL_XCCONFIG="$REPO_ROOT/Colonnade/Local.xcconfig"

cd "$REPO_ROOT"

# 1. Bepaal en controleer het signing-certificaat.
#    Geen -v: een self-signed cert is "untrusted" en valt buiten de valid-only lijst,
#    maar codesign kan er prima mee tekenen (TCC pint de leaf-hash, niet de CA-trust).
if [[ -z "${SIGN_IDENTITY:-}" && -f "$LOCAL_XCCONFIG" ]]; then
    SIGN_IDENTITY="$(awk -F' *= *' '/^CODE_SIGN_IDENTITY/{print $2; exit}' "$LOCAL_XCCONFIG")"
fi
if [[ -z "${SIGN_IDENTITY:-}" || "$SIGN_IDENTITY" == "-" ]]; then
    echo "FOUT: geen stabiel signing-certificaat ingesteld."
    echo "      Zet 'CODE_SIGN_IDENTITY = <naam>' in Colonnade/Local.xcconfig (zie README.md)."
    echo "      Met ad-hoc signing vergeet macOS de Toegankelijkheid-toestemming bij elke build."
    exit 1
fi
if ! security find-identity -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "FOUT: code-signing certificaat '$SIGN_IDENTITY' niet gevonden in de keychain."
    exit 1
fi

# 2. Build.
#    -skipMacroValidation: de Scribe-package levert een Swift-macro (@Loggable) die
#    Xcode anders interactief wil laten goedkeuren; in een CLI-build slaan we die check over.
echo "==> Bouwen ($CONFIG, getekend met '$SIGN_IDENTITY')..."
xcodebuild -project Colonnade.xcodeproj -scheme Colonnade -configuration "$CONFIG" \
    -skipMacroValidation CODE_SIGN_IDENTITY="$SIGN_IDENTITY" build

# 3. Vind de gebouwde app.
BUILT_DIR="$(xcodebuild -project Colonnade.xcodeproj -scheme Colonnade -configuration "$CONFIG" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
APP="$BUILT_DIR/Colonnade.app"
if [[ ! -d "$APP" ]]; then
    echo "FOUT: gebouwde app niet gevonden op $APP"
    exit 1
fi

# 4. Sluit een draaiende Colonnade af, en ook de voorganger van deze fork (Loop.app met
#    bundle-ID com.nielshop.Loop): twee apps op dezelfde trigger zitten elkaar in de weg.
echo "==> Draaiende Colonnade (en de oude Loop-build) afsluiten..."
osascript -e 'tell application id "com.nielshop.Colonnade" to quit' 2>/dev/null || true
osascript -e 'tell application id "com.nielshop.Loop" to quit' 2>/dev/null || true
pkill -x Colonnade 2>/dev/null || true
sleep 1

# 5. Installeer in /Applications. We *verplaatsen* de build uit DerivedData i.p.v. te kopiëren:
#    zo blijft er geen tweede Colonnade.app met hetzelfde bundle-ID achter die Spotlight en
#    LaunchServices in de war brengt. xcodebuild maakt 'm bij de volgende build weer aan.
echo "==> Installeren naar $DEST..."
if [[ -d "$DEST" ]]; then
    if ! rm -rf "$DEST" 2>/dev/null; then
        echo "Kan bestaande $DEST niet verwijderen (waarschijnlijk eigendom van een ander account)."
        echo "Voer eenmalig handmatig uit en draai daarna dit script opnieuw:"
        echo "    sudo rm -rf $DEST"
        exit 1
    fi
fi
mv "$APP" "$DEST"

# 6. Verifieer de handtekening (moet stabiel + geldig zijn, niet adhoc).
echo "==> Handtekening verifiëren..."
codesign --verify --deep --strict --verbose=2 "$DEST"
codesign -dvv "$DEST" 2>&1 | grep -E "Identifier|Authority|TeamIdentifier" || true

# 7. Start de zojuist geïnstalleerde app.
echo "==> Colonnade starten..."
open "$DEST"

echo ""
echo "Klaar. Colonnade staat in $DEST."
echo "Per account nog éénmalig: Systeeminstellingen -> Privacy & Beveiliging -> Toegankelijkheid -> Colonnade aanvinken."
if [[ -d "/Applications/Loop.app" ]]; then
    echo ""
    echo "Let op: /Applications/Loop.app (de oude build) staat er nog. Verwijder die en zijn"
    echo "login-item (Systeeminstellingen -> Algemeen -> Inloggen) zodra Colonnade goed draait."
fi
