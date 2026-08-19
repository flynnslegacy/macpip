#!/bin/bash
# Creates a local, self-signed code-signing certificate ("MacPiP Local Dev") in
# your login keychain so build_app.sh can sign MacPiP with a *stable* identity
# instead of an ad-hoc one. Ad-hoc signatures change on every rebuild, which
# makes macOS treat each build as a "new" app and re-ask for Screen Recording
# permission. A stable identity fixes that.
#
# This script only generates the certificate and imports it into your
# keychain — it does NOT grant it system trust (that's a security-sensitive
# action only you should confirm). One manual step remains after running this:
# see the instructions printed at the end.
set -euo pipefail

CERT_NAME="MacPiP Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

print_trust_instructions() {
    echo ""
    echo "Dernière étape (manuelle, une seule fois) :"
    echo "  1. Ouvre Trousseaux d'accès (Keychain Access)."
    echo "  2. Cherche \"$CERT_NAME\"."
    echo "  3. Double-clique dessus, déplie \"Approbation\" (Trust)."
    echo "  4. Règle \"Signature de code\" (Code Signing) sur \"Toujours faire confiance\"."
    echo "  5. Ferme la fenêtre — macOS te demandera ton mot de passe pour confirmer."
    echo ""
    echo "Une fois fait, relance scripts/build_app.sh : il signera automatiquement"
    echo "avec cette identité stable au lieu de la signature ad-hoc."
}

if security find-certificate -c "$CERT_NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Un certificat \"$CERT_NAME\" existe déjà dans le trousseau."
    if security find-identity -v -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$CERT_NAME"; then
        echo "Il est approuvé pour la signature de code — rien à faire."
    else
        echo "Il n'est pas encore approuvé pour la signature de code."
        print_trust_instructions
    fi
    exit 0
fi

echo "Génération d'une identité de signature locale \"$CERT_NAME\"…"

openssl req -x509 -newkey rsa:2048 \
    -keyout "$WORK_DIR/dev.key" \
    -out "$WORK_DIR/dev.crt" \
    -days 3650 -nodes \
    -subj "/CN=$CERT_NAME" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "basicConstraints=critical,CA:true" \
    -addext "keyUsage=critical,digitalSignature" >/dev/null 2>&1

openssl pkcs12 -export -legacy \
    -out "$WORK_DIR/dev.p12" \
    -inkey "$WORK_DIR/dev.key" \
    -in "$WORK_DIR/dev.crt" \
    -passout pass:temporary >/dev/null 2>&1

security import "$WORK_DIR/dev.p12" \
    -k "$KEYCHAIN" \
    -P temporary \
    -T /usr/bin/codesign

echo ""
echo "Certificat importé dans le trousseau de connexion."
print_trust_instructions
