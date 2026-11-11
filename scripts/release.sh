#!/bin/zsh
# Starts a Navi release on GitHub now, instead of waiting for the nightly run, and follows it.
#
#   scripts/release.sh                     # next patch version, notes from the commits since the last release
#   scripts/release.sh 0.3.0 "What changed, in a sentence or two."
#
# GitHub builds origin/main, so push your work first. The Release workflow
# (.github/workflows/release.yml) plans the version (scripts/release-plan.sh), then tests, builds,
# signs with Developer ID, notarizes, signs the update with the Sparkle key, and makes the GitHub
# release vX.Y.Z with Navi.zip and appcast.xml (scripts/ci-release.sh). Nothing is committed.
#
# One-time setup of the GitHub secrets: scripts/release-secrets.sh.
#
# Links that always point at the newest version:
#   https://github.com/donovanhiland/navi/releases/latest/download/Navi.zip   (send this to friends)
#   https://github.com/donovanhiland/navi/releases/latest/download/appcast.xml (Navi checks this)
set -euo pipefail

version=${1:-}
notes=${2:-}
root=${0:A:h:h}
cd "$root"
repo=donovanhiland/navi

git fetch -q origin main --tags
if [[ -n $(git log --oneline origin/main..main 2>/dev/null) ]]; then
  print -u2 "Your main has commits that are not on GitHub. Push them first, or they are not in the release."
  exit 1
fi
# The same plan the workflow makes, so a bad version stops here.
git -c advice.detachedHead=false worktree add -q --detach "${TMPDIR:-/tmp}/navi-plan.$$" origin/main
trap 'git worktree remove --force "${TMPDIR:-/tmp}/navi-plan.$$"' EXIT
(cd "${TMPDIR:-/tmp}/navi-plan.$$" && scripts/release-plan.sh "$version" "$notes") | sed -n '1,2p'

before=$(gh run list --repo "$repo" --workflow release.yml -L 1 --json databaseId -q '.[0].databaseId // 0')
gh workflow run release.yml --repo "$repo" --ref main -f version="$version" -f notes="$notes"
print "› Waiting for GitHub to start the run"
run=$before
for _ in {1..30}; do
  run=$(gh run list --repo "$repo" --workflow release.yml -L 1 --json databaseId -q '.[0].databaseId // 0')
  [[ $run != $before ]] && break
  sleep 2
done
[[ $run != $before ]] || { print -u2 "The run did not start. See https://github.com/$repo/actions"; exit 1 }

gh run watch "$run" --repo "$repo" --exit-status
print "Done: https://github.com/$repo/releases/latest"
