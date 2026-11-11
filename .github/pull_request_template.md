<!--
Read CONTRIBUTING.md first. One problem per PR. Title: a conventional commit in plain words,
such as "fix(capture): the overlay leaves on mouse up".
-->

## Problem

<!-- What is wrong or missing, in a sentence or two. For a bug: what you did, what you expected,
what happened. Link the issue if there is one. -->

## Change

<!-- How this fixes it. If it touches more than one package, say why each change is needed. -->

## Verification

<!-- What you checked and what you saw. "Tests pass" alone is not enough.
- Tests you added or ran (which package, which suite).
- For UI changes: before and after screenshots. Add a short recording when motion or timing
  matters (overlays, cards, the dictation pill). Upload them to GitHub here; do not commit them.
- What you could not check (for example a second display, or Intel). -->

## Checklist

- [ ] One problem in this PR.
- [ ] `swift test` passes in each package I changed, and the app builds with no new warnings.
- [ ] Pure logic I added has a unit test (Swift Testing).
- [ ] `AGENTS.md` is updated if a decision or default changed.
- [ ] No code copied from GPL or BSL projects (macshot, Capso). Code from Hex keeps its MIT notice.

<!-- If an agent did the work, end with the model and the tool, for example "Claude Opus 5.5, Claude Code". -->
