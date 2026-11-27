# Contributing to GoogolForge

Thanks for helping. GoogolForge stays free, offline and stdlib-only.

## Rules
1. **Tests first.** Every module has a `selftest` command. Add a test for your change and run:
   `cd src && for f in *.py; do python -B $f selftest; done`
2. **Python standard library only.** No pip dependencies in `src/`.
3. **Termux-safe.** Use `${TMPDIR:-/tmp}`, never assume `/tmp`.
4. **No secrets.** CI blocks commits that contain keys or tokens.
5. **Honest scores.** Benchmark claims must come from the sealed judge (`forge bench`), with the model and device named.
6. **Respect the holdout.** Never tune prompts or heuristics on `forge bench --holdout` (its tasks, results or hidden inputs). It exists to check that a gain is real.

## Pull requests
Keep them small, explain what changed and why, and paste your selftest and bench output.
