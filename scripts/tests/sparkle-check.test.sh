#!/usr/bin/env bash
# Tests scripts/sparkle-check.swift against Sparkle's own signing tool. macOS only; needs Sparkle's
# tools in build.noindex (any Navi build or `xcodebuild -resolvePackageDependencies` puts them there).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
check() { swift "$root/scripts/sparkle-check.swift" "$@"; }
bin="$root/build.noindex/SourcePackages/artifacts/sparkle/Sparkle/bin"
work=$(mktemp -d)
openssl rand -base64 32 > "$work/key"
public=$(check public-key "$work/key")
printf 'update bytes' > "$work/Navi.zip"
signature=$("$bin/sign_update" --ed-key-file "$work/key" -p "$work/Navi.zip")
prefix="https://example.com/v1.2.3/"

feed() {
  cat > "$work/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <sparkle:version>${1:-42}</sparkle:version>
      <sparkle:shortVersionString>${2:-1.2.3}</sparkle:shortVersionString>
      <enclosure url="${3:-${prefix}Navi.zip}" length="${4:-12}" type="application/octet-stream" sparkle:edSignature="${5:-$signature}"/>
    </item>
  </channel>
</rss>
XML
}
verify() { check verify-appcast "$work/appcast.xml" "$work/Navi.zip" "${1:-$public}" 1.2.3 42 "$prefix"; }

test_public_key_matches_sparkle() {
  # A signature from Sparkle's sign_update verifies with the key this script derives.
  check verify-file "$work/Navi.zip" "$signature" "$public" || { echo "  sign_update signature rejected"; failures=$((failures + 1)); }
}

test_good_feed_passes() {
  feed
  verify || { echo "  good feed rejected"; failures=$((failures + 1)); }
}

test_wrong_key_fails() {
  feed
  other=$(openssl rand -base64 32 | check public-key -)
  assert_fails "another public key" verify "$other"
}

test_tampered_zip_fails() {
  feed
  cp "$work/Navi.zip" "$work/Navi.zip.bak"
  printf 'update bytez' > "$work/Navi.zip"
  assert_fails "changed zip" verify
  mv "$work/Navi.zip.bak" "$work/Navi.zip"
}

test_wrong_fields_fail() {
  feed 41; assert_fails "wrong build" verify
  feed 42 1.2.4; assert_fails "wrong version" verify
  feed 42 1.2.3 "https://example.com/other/Navi.zip"; assert_fails "wrong URL" verify
  feed 42 1.2.3 "${prefix}Navi.zip" 13; assert_fails "wrong length" verify
  feed 42 1.2.3 "${prefix}Navi.zip" 12 "AAAA"; assert_fails "bad signature" verify
}

test_bad_private_key_fails() {
  assert_fails "short key" check public-key <(printf 'c2hvcnQ=')
}

run_tests
