#!/bin/bash
# Create the self-signed code signing identity that releases are signed with. Run
# once per release machine; every later build reuses it.
#
# Why this exists: the usage limits section reads Claude Code's OAuth token from the
# Keychain, and macOS ties a "Always Allow" grant to the *signature* of the app that
# asked. An ad-hoc signature is the binary's own hash, so every build is a different
# application to macOS and the grant is void — the user would be re-authorising
# after every `brew upgrade`. A stable identity makes it a one-time decision.
#
# The key never leaves the login keychain and is never committed. Losing it is not
# fatal but is not free either: the next release signed with a new certificate asks
# every existing user for permission again. Export a backup — see the closing note.
set -euo pipefail

IDENTITY="${CODESIGN_IDENTITY:-BongoTokenCat Local}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# LibreSSL, not Homebrew's OpenSSL 3: the PKCS#12 the latter writes by default uses
# ciphers `security import` cannot read.
OPENSSL=/usr/bin/openssl

is_valid_identity() {
    security find-identity -v -p codesigning | grep -F "\"$IDENTITY\"" >/dev/null
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Lets codesign reach the private key without a dialog on every build.
#
# Importing with -T names codesign as allowed, but on modern macOS the key also
# carries a partition list that the ACL is checked against, and an imported key
# starts with an empty one. Until this runs, codesign fails with the singularly
# unhelpful `errSecInternalComponent` — or worse, blocks on a dialog that never
# appears when the build runs anywhere but a logged-in Terminal.
#
# It asks for the login password because macOS will not hand out key access on a
# script's say-so. That is the one interactive moment in this setup.
authorise_codesign() {
    echo "==> authorising codesign to use the key"
    echo "    macOS will ask for your login password."
    security set-key-partition-list -S apple-tool:,apple:,codesign: \
        -s -l "$IDENTITY" "$KEYCHAIN" >/dev/null
}

# Idempotent by design, and the early exit is the point rather than a shortcut:
# reissuing would produce a different identity and undo exactly what the certificate
# is for. The authorisation still runs — it is the step most likely to be missing on
# a machine where the certificate is already there.
if is_valid_identity; then
    echo "'$IDENTITY' already exists — keeping it."
    authorise_codesign
    echo "ready."
    exit 0
fi

# A certificate that exists but is not trusted for code signing is the common
# half-finished state (an interrupted earlier run). Trust it rather than issue a
# second one.
if security find-certificate -c "$IDENTITY" -p "$KEYCHAIN" > "$WORK/existing.pem" 2>/dev/null \
    && [ -s "$WORK/existing.pem" ]; then
    echo "==> trusting the existing '$IDENTITY' certificate for code signing"
    security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/existing.pem" 2>/dev/null || true
    is_valid_identity && { echo "'$IDENTITY' is now a valid signing identity."; exit 0; }
    echo "✗ '$IDENTITY' exists but will not validate. Delete the certificate and its" >&2
    echo "  private key in Keychain Access, then run this again." >&2
    exit 1
fi

cat > "$WORK/openssl.cnf" <<CONF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CONF

echo "==> issuing a self-signed code signing certificate"
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -days 3650 -config "$WORK/openssl.cnf" 2>/dev/null

# The passphrase only has to survive the next two lines; the file is deleted with
# the work directory. An empty one makes `security import` fail its MAC check.
TRANSFER_PASSWORD="transfer"
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$IDENTITY" -out "$WORK/identity.p12" -passout pass:"$TRANSFER_PASSWORD" 2>/dev/null

echo "==> importing into the login keychain"
# -T lets codesign use the key without a Keychain prompt on every build.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$TRANSFER_PASSWORD" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem" 2>/dev/null || true

authorise_codesign

if is_valid_identity; then
    echo "'$IDENTITY' is ready."
else
    echo "✗ '$IDENTITY' did not come out as a valid signing identity." >&2
    exit 1
fi

cat <<DONE

next:
  ./scripts/build-app.sh now signs with this identity.

back it up, because reissuing it re-prompts every existing user:
  security export -k "$KEYCHAIN" -t identities -f pkcs12 -o bongo-signing-identity.p12
  (store it somewhere safe and keep it out of the repo)
DONE
