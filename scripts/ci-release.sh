#!/bin/zsh
# Builds, signs, notarizes, checks, and publishes one Navi release. The Release workflow on GitHub
# (.github/workflows/release.yml) runs it after scripts/release-plan.sh picks the version.
#
# Steps, in order. A failed step stops the run before anything is published:
#   1. Check: the tag and the release are new; the Sparkle key matches SPARKLE_PUBLIC_KEY in project.yml.
#   2. Test every package (SKIP_TESTS=1 skips this when CI already ran them).
#   3. Archive Release with the version and build number set on the command line (project.yml
#      is not changed, so there is nothing to commit), export with Developer ID, notarize,
#      staple.
#   4. Check the app: version, build, update feed and key, entitlements, hardened runtime,
#      signature, Developer ID team, notarization ticket, Gatekeeper.
#   5. Sign the update with the Sparkle key, write appcast.xml, and check the feed the way
#      Navi checks it (scripts/sparkle-check.swift).
#   6. Make the GitHub release: tag vX.Y.Z on the built commit, Navi.zip, appcast.xml.
#
# MODE:
#   publish    all steps (default)
#   rehearse   steps 1–5 with the real keys and Apple notarization; nothing is published
#   dry-run    no Apple keys: ad hoc signature, no notarization, nothing published. Uses
#              SPARKLE_PRIVATE_KEY when set, or a throwaway key. CI runs this on every PR.
#
# Environment:
#   VERSION, BUILD, NOTES                      from scripts/release-plan.sh
#   ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID    App Store Connect API key (not for dry-run)
#   SPARKLE_PRIVATE_KEY                        EdDSA key that signs the update (base64 seed)
# publish and rehearse need a "Developer ID Application" identity for team 77SAW76597 in a keychain.
set -euo pipefail

root=${0:A:h:h}
cd "$root"
repo=donovanhiland/navi
team=77SAW76597
mode=${MODE:-publish}
version=${VERSION:?Set VERSION}
build=${BUILD:?Set BUILD}
notes=${NOTES:-}
tag="v$version"
commit=$(git rev-parse HEAD)
work="$root/build.noindex/release"
dist="$root/dist"
sparkle_bin="$root/build.noindex/SourcePackages/artifacts/sparkle/Sparkle/bin"
url_prefix="https://github.com/$repo/releases/download/$tag/"

step() { print "› $*" }
die() { print -u2 "Stopped: $*"; exit 1 }
sparkle_check() { swift "$root/scripts/sparkle-check.swift" "$@" }

[[ $mode == (publish|rehearse|dry-run) ]] || die "MODE must be publish, rehearse, or dry-run, not '$mode'"
signed=1
[[ $mode == dry-run ]] && signed=0
[[ -n $notes || $mode != publish ]] || die "NOTES is empty"
[[ -n $notes ]] || notes="Navi $version ($mode)"
if (( signed )); then
  : ${ASC_KEY_PATH:?} ${ASC_KEY_ID:?} ${ASC_ISSUER_ID:?} ${SPARKLE_PRIVATE_KEY:?}
fi

step "Checking $tag (build $build) at ${commit:0:7}, mode $mode"
if [[ $mode == publish ]]; then
  [[ -z $(git status --porcelain) ]] || die "the working tree has changes"
  git rev-parse -q --verify "refs/tags/$tag" >/dev/null && die "tag $tag already exists"
  gh release view "$tag" --repo "$repo" >/dev/null 2>&1 && die "release $tag already exists"
fi
project_key=$(sed -n 's/^ *SPARKLE_PUBLIC_KEY: *//p' project.yml)
[[ -n $project_key ]] || die "project.yml has no SPARKLE_PUBLIC_KEY"
expected_key=$project_key
if [[ -n ${SPARKLE_PRIVATE_KEY:-} ]]; then
  sparkle_public=$(print -rn -- "$SPARKLE_PRIVATE_KEY" | sparkle_check public-key -)
  [[ $sparkle_public == $expected_key ]] \
    || die "the Sparkle private key does not match SPARKLE_PUBLIC_KEY in project.yml; Navi would refuse the update"
else
  # dry-run without the real key: a throwaway key runs the same steps and checks.
  SPARKLE_PRIVATE_KEY=$(openssl rand -base64 32)
  expected_key=$(print -rn -- "$SPARKLE_PRIVATE_KEY" | sparkle_check public-key -)
  step "Using a throwaway Sparkle key"
fi

if [[ ${SKIP_TESTS:-0} != 1 ]]; then
  step "Testing"
  for package in Packages/*/; do
    [[ -d $package/Tests ]] || continue
    step "  ${package:t}"
    (cd "$package" && swift test)
  done
fi

step "Archiving Release"
rm -rf "$work" "$dist"
mkdir -p "$work" "$dist"
archive="$work/Navi.xcarchive"
# Signed modes use the Release identity in project.yml (Developer ID, app target only).
# dry-run signs everything ad hoc, which package resource bundles accept.
overrides=()
(( signed )) || overrides=(CODE_SIGN_IDENTITY=-)
xcodegen generate >/dev/null
xcodebuild -project Navi.xcodeproj -scheme Navi -configuration Release \
  -derivedDataPath build.noindex -archivePath "$archive" -quiet archive \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build" SPARKLE_PUBLIC_KEY="$expected_key" \
  "${overrides[@]}"

if (( signed )); then
  step "Signing with Developer ID"
  cat > "$work/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$work/ExportOptions.plist" \
    -exportPath "$work/export" -quiet
  app="$work/export/Navi.app"

  step "Notarizing (usually 2–10 minutes)"
  ditto -c -k --keepParent "$app" "$work/upload.zip"
  xcrun notarytool submit "$work/upload.zip" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" \
    --issuer "$ASC_ISSUER_ID" --wait --timeout 30m --output-format plist > "$work/notary.plist"
  notary_status=$(plutil -extract status raw "$work/notary.plist")
  if [[ $notary_status != Accepted ]]; then
    submission=$(plutil -extract id raw "$work/notary.plist")
    xcrun notarytool log "$submission" --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" >&2 || true
    die "Apple notarization says $notary_status"
  fi
  xcrun stapler staple -q "$app"
else
  app="$archive/Products/Applications/Navi.app"
fi

step "Checking the app"
info="$app/Contents/Info.plist"
plist_value() { plutil -extract "$1" raw "$info" 2>/dev/null || true }
[[ $(plist_value CFBundleIdentifier) == com.donovanhiland.navi ]] || die "the bundle ID is not com.donovanhiland.navi"
[[ $(plist_value CFBundleShortVersionString) == $version ]] || die "the app does not say version $version"
[[ $(plist_value CFBundleVersion) == $build ]] || die "the app does not say build $build"
[[ $(plist_value SUFeedURL) == "https://github.com/$repo/releases/latest/download/appcast.xml" ]] \
  || die "the app's SUFeedURL is wrong, so it would never see updates"
[[ $(plist_value SUPublicEDKey) == $expected_key ]] || die "the app's SUPublicEDKey is not $expected_key"
if [[ $mode != dry-run && $expected_key != $project_key ]]; then
  die "a real release must use the key in project.yml"
fi
codesign --verify --deep --strict "$app" || die "the signature does not verify"
codesign -d --entitlements - --xml "$app" 2>/dev/null > "$work/entitlements.plist"
for entitlement in com.apple.security.device.audio-input com.apple.security.device.camera; do
  # PlistBuddy, not plutil: plutil reads the dots in the key as a path.
  [[ $(/usr/libexec/PlistBuddy -c "Print :$entitlement" "$work/entitlements.plist" 2>/dev/null) == true ]] \
    || die "the app is missing $entitlement; the hardened runtime would block it"
done
codesign -d --verbose=2 "$app" > "$work/codesign.txt" 2>&1
grep -q 'flags=.*runtime' "$work/codesign.txt" || die "the hardened runtime is off; notarization needs it"
if (( signed )); then
  grep -q '^Authority=Developer ID Application:' "$work/codesign.txt" || die "the app is not signed with Developer ID"
  grep -q "^TeamIdentifier=$team\$" "$work/codesign.txt" || die "the app is not signed by team $team"
  xcrun stapler validate -q "$app" || die "the notarization ticket is not stapled"
  spctl --assess --type execute "$app" || die "Gatekeeper would block the app"
fi
ditto -c -k --keepParent "$app" "$dist/Navi.zip"

step "Signing the update and writing appcast.xml"
feed="$dist/release"
mkdir -p "$feed"
cp "$dist/Navi.zip" "$feed/Navi.zip"
print -r -- "$notes" | scripts/release-notes-html.sh > "$feed/Navi.html"   # generate_appcast uses it as the notes
print -rn -- "$SPARKLE_PRIVATE_KEY" | "$sparkle_bin/generate_appcast" \
  --ed-key-file - --download-url-prefix "$url_prefix" --embed-release-notes "$feed"
sparkle_check verify-appcast "$feed/appcast.xml" "$feed/Navi.zip" "$expected_key" "$version" "$build" "$url_prefix"

if [[ $mode != publish ]]; then
  print "Done ($mode): $feed has Navi.zip and appcast.xml. Nothing was published."
  exit 0
fi

step "Publishing $tag"
gh release create "$tag" "$feed/Navi.zip" "$feed/appcast.xml" --repo "$repo" \
  --target "$commit" --title "Navi $version" --notes "$notes

Download: https://github.com/$repo/releases/latest/download/Navi.zip
Unzip, move Navi to Applications, and open it. After that, Navi updates itself."

step "Checking the published feed"
published=$(mktemp -d)
for _ in {1..10}; do
  curl -fsSL "https://github.com/$repo/releases/latest/download/appcast.xml" -o "$published/appcast.xml" \
    && grep -q "<sparkle:version>$build<" "$published/appcast.xml" && break
  sleep 6
done
curl -fsSL "${url_prefix}Navi.zip" -o "$published/Navi.zip"
sparkle_check verify-appcast "$published/appcast.xml" "$published/Navi.zip" "$expected_key" "$version" "$build" "$url_prefix"

print "Done: https://github.com/$repo/releases/tag/$tag"
