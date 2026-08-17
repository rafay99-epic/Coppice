#!/bin/bash
# Creates the stable self-signed code-signing certificate Coppice releases use,
# and prints the base64 .p12 to paste into the repo secrets.
#
# Why this exists: macOS keys permission grants (Full Disk Access here) and
# Gatekeeper identity to the code signature. An ad-hoc signature is different on
# every build, so each auto-update would look like a brand-new app and silently
# drop the grant the user already gave. One stable identity means one designated
# requirement across every release, so the grant persists.
#
# There is no paid Apple Developer account behind this, so builds are not
# notarized — the Homebrew cask is the smooth install path.
#
# Usage: ./Scripts/make-signing-cert.sh [common-name]
set -euo pipefail

NAME="${1:-Coppice Signing}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Creating a self-signed code-signing certificate: $NAME"

cat > "$WORK/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
prompt             = no
x509_extensions    = v3

[ dn ]
CN = $NAME
O  = Syntax Lab Technology

[ v3 ]
basicConstraints       = critical,CA:false
keyUsage               = critical,digitalSignature
extendedKeyUsage       = critical,codeSigning
subjectKeyIdentifier   = hash
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
  -days 3650 -config "$WORK/cert.cnf" 2>/dev/null

PASSWORD="$(openssl rand -base64 24)"
openssl pkcs12 -export \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -out "$WORK/identity.p12" -passout "pass:$PASSWORD" \
  -name "$NAME" 2>/dev/null

echo
echo "Importing into your login keychain so local builds can use it…"
security import "$WORK/identity.p12" -k ~/Library/Keychains/login.keychain-db \
  -P "$PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s \
  -k "$(security find-generic-password -ws 'login' 2>/dev/null || true)" \
  ~/Library/Keychains/login.keychain-db >/dev/null 2>&1 || \
  echo "note: could not pre-authorise codesign; macOS will prompt on first use."

echo
echo "Local builds:"
echo "  export CODESIGN_IDENTITY=\"$NAME\""
echo
echo "Repository secrets (Settings → Secrets and variables → Actions):"
echo
echo "  MACOS_SIGN_CERT_PASSWORD"
echo "$PASSWORD"
echo
echo "  MACOS_SIGN_CERT_P12"
base64 < "$WORK/identity.p12"
echo
echo "Store both now. This script keeps nothing."
