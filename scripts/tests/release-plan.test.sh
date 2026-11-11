#!/usr/bin/env bash
# Tests scripts/release-plan.sh against throwaway git repos. Runs on Linux and macOS.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
plan="$root/scripts/release-plan.sh"

new_repo() {
  repo=$(mktemp -d)
  git -C "$repo" init -q -b main
  git -C "$repo" config user.name test
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config commit.gpgsign false
  git -C "$repo" config tag.gpgsign false
}
commit() { git -C "$repo" commit -q --allow-empty -m "$1"; }
run_plan() { (cd "$repo" && "$plan" "$@"); }
field() { sed -n "s/^$1=//p"; }
notes() { sed -n '/^notes<<NOTES_END$/,/^NOTES_END$/p' | sed '1d;$d'; }

test_first_release() {
  new_repo
  commit "feat: first"
  out=$(run_plan)
  assert_eq "true" "$(field due <<<"$out")" "due"
  assert_eq "0.0.1" "$(field version <<<"$out")" "version"
  assert_eq "1" "$(field build <<<"$out")" "build"
  assert_eq "- feat: first" "$(notes <<<"$out")" "notes"
}

test_next_patch_and_notes_since_tag() {
  new_repo
  commit "feat: old"
  git -C "$repo" tag v0.2.0
  commit "fix: one"
  commit "chore(release): 0.2.0 (build 3)"
  commit "feat: two"
  out=$(run_plan)
  assert_eq "true" "$(field due <<<"$out")" "due"
  assert_eq "0.2.1" "$(field version <<<"$out")" "version"
  assert_eq "4" "$(field build <<<"$out")" "build"
  assert_eq $'- feat: two\n- fix: one' "$(notes <<<"$out")" "notes skip release bumps"
}

test_nothing_new_is_not_due() {
  new_repo
  commit "feat: old"
  git -C "$repo" tag v1.0.0
  out=$(run_plan)
  assert_eq "false" "$(field due <<<"$out")" "due"
}

test_only_release_bumps_is_not_due() {
  new_repo
  commit "feat: old"
  git -C "$repo" tag v1.0.0
  commit "chore(release): 1.0.0 (build 2)"
  out=$(run_plan)
  assert_eq "false" "$(field due <<<"$out")" "due"
}

test_merges_left_out_of_notes() {
  new_repo
  commit "feat: base"
  git -C "$repo" tag v0.1.0
  git -C "$repo" checkout -q -b topic
  commit "feat: on topic"
  git -C "$repo" checkout -q main
  git -C "$repo" merge -q --no-ff topic -m "Merge pull request #1 from someone/topic"
  out=$(run_plan)
  assert_eq "- feat: on topic" "$(notes <<<"$out")" "notes"
}

test_given_version_and_notes() {
  new_repo
  commit "feat: old"
  git -C "$repo" tag v0.2.0
  commit "feat: new"
  out=$(run_plan 0.10.0 "Big one")
  assert_eq "true" "$(field due <<<"$out")" "due"
  assert_eq "0.10.0" "$(field version <<<"$out")" "version sorts as a version, not as text"
  assert_eq "Big one" "$(notes <<<"$out")" "notes"
}

test_given_notes_without_new_commits_is_not_due() {
  new_repo
  commit "feat: old"
  git -C "$repo" tag v0.2.0
  out=$(run_plan 0.2.1 "Rebuild")
  assert_eq "false" "$(field due <<<"$out")" "no new commits is never due"
}

test_rejects_old_same_and_bad_versions() {
  new_repo
  commit "feat: old"
  git -C "$repo" tag v0.2.0
  commit "fix: new"
  assert_fails "older version" run_plan 0.1.9 x
  assert_fails "same version" run_plan 0.2.0 x
  assert_fails "not a version" run_plan 1.2 x
  assert_fails "v prefix" run_plan v1.2.3 x
}

test_writes_github_output() {
  new_repo
  commit "feat: one"
  output_file=$(mktemp)
  (cd "$repo" && GITHUB_OUTPUT=$output_file "$plan" >/dev/null)
  assert_eq "0.0.1" "$(field version <"$output_file")" "version in GITHUB_OUTPUT"
  assert_eq "- feat: one" "$(notes <"$output_file")" "notes in GITHUB_OUTPUT"
}

run_tests
