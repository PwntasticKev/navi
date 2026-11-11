#!/bin/zsh
# One-time setup: puts the release keys in the GitHub repo's Actions secrets. Prints no key.
#
#   scripts/release-secrets.sh <developer-id.p12> <AuthKey_XXXX.p8> <key-id> <issuer-id>
#
# developer-id.p12  "Developer ID Application" certificate and its private key, exported from
#                   Keychain Access (it asks for a password; this script asks for it too).
# AuthKey_XXXX.p8   App Store Connect API key (Users and Access → Integrations → Team Keys,
#                   role Developer). The key ID and issuer ID are on the same page.
# The Sparkle key is read from your login keychain (the one that signed earlier updates).
set -euo pipefail

p12=${1:?Usage: scripts/release-secrets.sh <p12> <p8> <key-id> <issuer-id>}
p8=${2:?Usage: scripts/release-secrets.sh <p12> <p8> <key-id> <issuer-id>}
key_id=${3:?Usage: scripts/release-secrets.sh <p12> <p8> <key-id> <issuer-id>}
issuer_id=${4:?Usage: scripts/release-secrets.sh <p12> <p8> <key-id> <issuer-id>}
root=${0:A:h:h}
repo=donovanhiland/navi
generate_keys="$root/build.noindex/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys"
[[ -x $generate_keys ]] || { print -u2 "Build Navi once first (scripts/dev.sh), so Sparkle's tools are there."; exit 1 }

read -rs "p12_password?Password of $p12: "
print
openssl pkcs12 -in "$p12" -passin "pass:$p12_password" -nokeys -legacy 2>/dev/null \
  | grep -q "Developer ID Application" \
  || openssl pkcs12 -in "$p12" -passin "pass:$p12_password" -nokeys 2>/dev/null | grep -q "Developer ID Application" \
  || { print -u2 "$p12 has no Developer ID Application certificate, or the password is wrong."; exit 1 }

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
sparkle="$scratch/sparkle-key"   # generate_keys -x does not write over a file that exists
"$generate_keys" -x "$sparkle" >/dev/null

base64 -i "$p12" | gh secret set DEVELOPER_ID_P12 --repo "$repo"
print -rn -- "$p12_password" | gh secret set DEVELOPER_ID_P12_PASSWORD --repo "$repo"
gh secret set ASC_KEY_P8 --repo "$repo" < "$p8"
print -rn -- "$key_id" | gh secret set ASC_KEY_ID --repo "$repo"
print -rn -- "$issuer_id" | gh secret set ASC_ISSUER_ID --repo "$repo"
gh secret set SPARKLE_PRIVATE_KEY --repo "$repo" < "$sparkle"
print "Done. Secrets on $repo:"
gh secret list --repo "$repo"
