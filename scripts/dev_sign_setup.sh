#!/usr/bin/env bash
# One-time: create a STABLE, trusted self-signed code-signing identity ("Soyle Dev")
# in the login keychain, so rebuilds keep the same code signature and macOS
# permission grants (Microphone / Input Monitoring) PERSIST across versions —
# no more re-authorising after every rebuild.
#
# macOS will ask for your login password ONCE (to trust the local cert for code
# signing). That's expected and safe — it's a local, self-signed dev certificate.
#
# Reversible: delete it later in Keychain Access, or:
#   security delete-identity -c "Soyle Dev" ~/Library/Keychains/login.keychain-db
set -euo pipefail
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

IDENTITY="Soyle Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl          # system LibreSSL (Apple-compatible PKCS#12)
P12PASS=soyle

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "OK: '$IDENTITY' is already a valid code-signing identity."
  security find-identity -v -p codesigning | grep "$IDENTITY"
  exit 0
fi

# Best-effort cleanup of any earlier failed import (ignore errors).
security delete-identity -c "Soyle Dev" "$KEYCHAIN" >/dev/null 2>&1 || true
security delete-certificate -c "Söyle Dev" "$KEYCHAIN" >/dev/null 2>&1 || true

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/o.cnf" <<CNF
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no
[ dn ]
CN = $IDENTITY
[ v3 ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/o.cnf" >/dev/null 2>&1
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout "pass:$P12PASS" >/dev/null 2>&1

# -A: allow all apps to use the key without per-use prompts (local dev key).
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$P12PASS" -A -T /usr/bin/codesign >/dev/null

echo ">>> macOS will ask for your password to trust the local certificate (code signing)."
echo ">>> Enter your Mac password and click \"Update Settings\"."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

echo
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "✅ '$IDENTITY' is ready and valid for signing."
  security find-identity -v -p codesigning | grep "$IDENTITY"
else
  echo "⚠️  The identity is not valid yet. Try again, or create it via Keychain Access →"
  echo "    Certificate Assistant → Create a Certificate → 'Soyle Dev', type 'Code Signing'."
  exit 1
fi
