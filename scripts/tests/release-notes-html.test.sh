#!/usr/bin/env bash
# Tests scripts/release-notes-html.sh. Runs on Linux and macOS.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
html() { printf '%s' "$1" | "$root/scripts/release-notes-html.sh"; }

test_list() {
  assert_eq $'<ul>\n<li>one</li>\n<li>two</li>\n</ul>' "$(html $'- one\n- two\n')" "list"
}

test_paragraphs_and_lists_mix() {
  assert_eq $'<p>Intro</p>\n<ul>\n<li>a</li>\n</ul>\n<p>Outro</p>' "$(html $'Intro\n- a\n\nOutro')" "mix"
}

test_escapes_markup() {
  assert_eq $'<ul>\n<li>fix: &lt;b&gt; &amp; &lt;script&gt;</li>\n</ul>' "$(html '- fix: <b> & <script>')" "escape"
}

test_last_line_without_newline() {
  assert_eq '<p>No newline</p>' "$(html 'No newline')" "no trailing newline"
}

test_blank_lines_dropped() {
  assert_eq '<p>a</p>' "$(html $'\n  \na\n\n')" "blank lines"
}

run_tests
