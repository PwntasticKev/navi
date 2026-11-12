#!/usr/bin/env bash
# Decides what the next Navi release is. The Release workflow runs it on a cheap Linux runner
# before the macOS job, so a night with nothing new never starts a Mac or loads the keys.
#
#   scripts/release-plan.sh [<version>] [<notes>]
#
# Prints key=value lines (and adds them to $GITHUB_OUTPUT on GitHub):
#   due=true|false   false when main has no commits since the last release tag
#   version=1.2.3    the given version, or the last tag's patch + 1
#   build=123        the number of commits on HEAD. It only grows, so Sparkle always sees
#                    a newer build, and nothing has to be stored in the repo.
#   notes<<NOTES_END the given notes, or "- <subject>" for each commit since the last tag
# Needs the full history and the tags (actions/checkout with fetch-depth: 0).
set -euo pipefail

version=${1:-}
notes=${2:-}
last_tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)
last=${last_tag#v}
range=${last_tag:+$last_tag..}HEAD

due=true
if [[ -n $last_tag && $(git rev-list --count "$range") == 0 ]]; then
  due=false
fi
if [[ -z $notes ]]; then
  notes=$(git log --no-merges --format='- %s' "$range" | grep -v '^- chore(release):' || true)
  [[ -n $notes ]] || due=false
fi
if [[ -z $version ]]; then
  IFS=. read -r major minor patch <<< "${last:-0.0.0}"
  version="$major.$minor.$((patch + 1))"
fi
if ! [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must look like 1.2.3, not '$version'" >&2
  exit 1
fi
if [[ -n $last ]]; then
  newest=$(printf '%s\n%s\n' "$last" "$version" | sort -V | tail -1)
  if [[ $version == "$last" || $newest != "$version" ]]; then
    echo "$version is not newer than the last release, $last" >&2
    exit 1
  fi
fi

output="due=$due
version=$version
build=$(git rev-list --count HEAD)
notes<<NOTES_END
$notes
NOTES_END"
printf '%s\n' "$output"
if [[ -n ${GITHUB_OUTPUT:-} ]]; then printf '%s\n' "$output" >> "$GITHUB_OUTPUT"; fi
