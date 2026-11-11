#!/usr/bin/env bash
# Turns plain release notes (standard input) into the HTML that Sparkle shows in the update window.
# Lines that start with "- " become a list; other lines become paragraphs; blank lines are dropped.
# <, >, and & are escaped, so a commit subject cannot add markup.
set -euo pipefail

in_list=0
while IFS= read -r line || [[ -n $line ]]; do
  line=${line//&/&amp;}
  line=${line//</&lt;}
  line=${line//>/&gt;}
  if [[ $line == '- '* ]]; then
    (( in_list )) || echo "<ul>"
    in_list=1
    echo "<li>${line#- }</li>"
  else
    if (( in_list )); then echo "</ul>"; fi
    in_list=0
    [[ -z ${line// /} ]] || echo "<p>$line</p>"
  fi
done
if (( in_list )); then echo "</ul>"; fi
