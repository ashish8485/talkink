#!/usr/bin/env bash
# One-time: create a STABLE self-signed code-signing identity ("Söyle Dev") in the
# login keychain, so rebuilds keep the same code signature and macOS permission
# grants (Microphone / Input Monitoring) PERSIST across versions — no more
# re-authorising after every rebuild.
#
# Reversible: delete the cert later in Keychain Access, or:
#   security delete-identity -c "Söyle Dev" ~/Library/Keychains/login.keychain-db
set -euo pipefail
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

IDENTITY="Söyle Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "OK: identity '$IDENTITY' already present."
  security find-identity -v -p codesigning | grep "$IDENTITY"
  exit 0
fi

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

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/o.cnf" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout pass: >/dev/null 2>&1

# -A: allow all apps to use the key without per-use prompts (local dev key).
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "" -A -T /usr/bin/codesign

echo "OK: created code-signing identity '$IDENTITY'."
security find-identity -v -p codesigning | grep "$IDENTITY" || true
echo
echo "If codesign later pops a keychain prompt, click 'Always Allow' once."
