# PUBLISH-LOG — panel-kit

## 2026-09-08 — initial publish (PRIVATE)

- **Repo:** https://github.com/mundaneb3at/panel-kit
- **Visibility:** PRIVATE (repo owner flips it public manually — never an automated step).
- **Default branch:** `master` (fresh `git init` on this machine defaults to `master`, not `main`).
- **Pipeline followed:** `GITHUB.md` §2, verbatim.
  1. Scoped ship-list: the 12 files under `public\publish-ready\panel-kit\` (D6's list) — `.gitattributes`, `.gitignore`, `LICENSE`, `PANEL.template.md`, `README.md`, `example-hook.ps1`, `example-logs/{old,new}.log`, `panel.ps1`, `probes.ps1`, `setup.ps1`, `skills/panel/SKILL.md`.
  2. Fresh export: `_temp\panel-kit-export-2026-09-08\`, `git init` there. `git log --oneline` / `git remote -v` confirmed clean before any commit.
  3. Whole-tree scrub: `audits\panel-kit-2026-09-08\scrub.py` — plain case-folded substring matching (no regex through Bash), a planted canary (an owner-identifying test string) proven caught before the real scrub ran, a <5-file guard. Real scrub: 12 files, 0 leak hits, positive controls (`powershell`, `panel`) both fired.
  4. `.gitattributes` (`* -text`) added — was missing from the initial S1 extraction, added at G7. No empty directories, so no `.gitkeep` needed.
  5. `LICENSE`: CC0, reused verbatim from the standing precedent (`public\publish-ready\job-journey-kit\LICENSE`) per the D6 spec.
  6. `README.md`: written at G6, passed 3 stranger-persona reviews (S3 fan-out) with 2 real fixes applied (see `EXECUTION-LOG.md` G6).
  7. `gh repo create mundaneb3at/panel-kit --private --source . --push` — pushed clean.
  8. Verified from GitHub, not local state: `gh repo view --json visibility` = PRIVATE; live tree enumerated via `gh api .../git/trees/master?recursive=1` matched the 12-file local list exactly; live-content scrub (same leak patterns, read via the GitHub contents API, not local disk) = 0 hits, positive controls fired.
  9. **Clean-clone verify found a real bug**, fixed in a second commit before archiving: `git clone` resets every checked-out file's mtime to checkout time, which broke the `count:` glob-mode demo lane ("recent log errors" in `PANEL.template.md`) — both `example-logs\*.log` files got near-identical mtimes, so "newest file" resolution became arbitrary. This directly contradicted the README's claim that "every row is runnable as-is against a fresh clone." Fixed: `setup.ps1` now restores the intended `old.log`/`new.log` mtime ordering as part of install (idempotent, skips gracefully if a user's own project lacks these example files). Re-verified from a genuinely fresh clone (`_temp\panel-kit-clone-verify-2\`, not a `git pull`) — `panel -Raw` after `setup.ps1 -DryRun` correctly showed `recent log errors | GREEN | 1  (max 5)`.
  10. `diff -rq` export vs canonical (`public\publish-ready\panel-kit\`) — no differences, nothing to backport.
  11. Export + both clone-verify dirs + their fake-home test dirs archived to `_archive\2026-09-08\panel-kit-publish\` (never deleted).

- **Commits:**
  - `8e26d70` — Initial commit: panel-kit v1
  - `888bd36` — setup.ps1: restore example-logs mtimes after install
  - `62935c5` — Add PUBLISH-LOG.md (this file itself was D6-listed but missed on the first push; caught by the G8 refute pass)
  - `f521ada` — setup.ps1: trim whitespace when checking if bin dir is already on PATH (G8 hostile-review finding)

- **G8 refute pass (S4, 3 sonnet lanes):**
  - already-done-elsewhere: PLAUSIBLE — two narrower personal precursor tools existed in-house (`brain-index\automation-lanes.ps1`, `brain-index\local-lane-panel.ps1`), neither general-purpose/pluggable; no published-repo duplicate. Acknowledged lineage (this kit IS the intended generalization), not an accidental duplicate.
  - clone-match: REFUTED — fresh clone matched canonical byte-for-byte (the one PUBLISH-LOG.md self-reference lag noted and closed in this same commit), visibility PRIVATE confirmed independently.
  - hostile setup.ps1 review: 1 CONFIRMED (low-severity PATH-whitespace dup bug, fixed above), 4 REFUTED (clobber-prevention structurally unreachable overwrite path, PS 5.1 clean, missing-panel.ps1 guard works as intended, no silent-failure path).

- **Real user PATH registry:** confirmed clean (27 entries, no test-residue contamination) after every `-DryRun` test pass and again after the whole G7 sequence completed.

- **CAN'T-DO:** none. `gh auth status` was OK at G0, so G7 ran to completion.
