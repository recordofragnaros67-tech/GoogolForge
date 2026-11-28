# GoogolForge

A free, offline AI coding forge for Android phones. It runs in Termux with local Ollama models: no cloud, no API keys, no cost.

## Install (Termux on Android)

One line:

```bash
curl -fsSL https://raw.githubusercontent.com/recordofragnaros67-tech/GoogolForge/main/install.sh | bash
```

Or from a downloaded file: `bash googolforge_setup.sh`

The setup file installs everything and finishes with 14 health checks.

## What it does

| Command | What it does |
|---|---|
| `forge team "<task>"` | AI team: Architect, Coder, Tester and Referee build and test code |
| `forge mutate <file>` | Mutation testing: plants bugs and scores your tests out of 100 |
| `forge rag "<question>"` | Code memory: answers questions about your own code |
| `forge explain <file>` | Plain-English walkthrough of a file |
| `forge duel` | Head-to-head coding duel against the AI |
| `forge bench --elite` | Benchmark Arena with a sealed judge |
| `forge ci` | Adds a cloud test workflow to your repo |
| `forge publish` | Publishes your work to GitHub |
| `forge web` | Installable, token-protected Dashboard |

Plugins live in `~/googolforge/plugins/`.

## Measured results

Sealed judge (hidden tests are never shown to the model), qwen2.5-coder:1.5b, on an ARM64 test machine, not yet on a phone:

| Benchmark | Plain | Elite |
|---|---|---|
| Standard (10 tasks) | 80 | 90 |
| Hard (6 tasks) | 17 | 50 |

Phone (Pixel 8) results will be added after the first on-device run.

## Safety

AI-written code that uses risky calls (eval, exec, sockets, network) is blocked until you approve it. The publisher blocks commits that contain keys or tokens.

## Tests and security

`selftest.yml` runs every module's self-test on each push. `security.yml` runs Bandit, Ruff and a secret scan. `codeql.yml` runs GitHub CodeQL weekly and on every push.

Website: `docs/` (GitHub Pages). Contributing: see `CONTRIBUTING.md`.

## Pixel 8 tuning (v3.1)
Every model call now sends `num_thread` (default **5**, the reported sweet spot for the Pixel 8's Tensor G3; more threads can slow it down).
To try another value, add `"threads": 4` (or 6) to `~/googolforge/config.json`, then compare with `forge bench --quick`.

## Genius mode (v3.11): Smart Router + Edge-Case Hunter + Rule Lawyer + Stress Probe + Docstring Examples

v3.11 turns the `>>>` examples inside a task's docstring into self-checks (HumanEval-style tasks had none before). The examples are part of the task the model sees; no hidden data is used.

v3.5 adds a Rule Lawyer draft (obeys exact rules, knows Python pitfalls like // flooring), a loss log (`forge bench losses` shows the exact wrong answer after a run), and `--strong=MODEL` to escalate to a bigger model such as qwen2.5-coder:7b.

v3.6.4 gives each task only the pitfalls its own text calls for (generic warnings made models invent rules).

v3.6.3 turns the task's own worked examples (like `'3 4 + 2 *' -> 14`) into checks.

v3.6.2 adds a Second Opinion: an early win counts only if two drafts that pass every self-test give identical outputs; otherwise it escalates to the strong model.

v3.6.1 adds a Rule Lawyer autofix (when the task says "truncating toward zero", `a // b` becomes `int(a / b)`) and puts the Python pitfalls into every repair.

v3.6 adds a Stress Probe: property checks built only from the task text (a negative version of the task's own example must not crash; functions that undo each other must round-trip, including runs longer than 9). No answer key, no hidden tests.


The strongest model now acts like a tough exam setter: it lists the trickiest edge cases (empty input, negatives, multi-digit counts, round trips), writes tests for them from the task text only, and the coders must pass them. Broken tests with wrong function names are thrown out.

`forge bench --genius --hard` uses four different opening drafts from the fast 1.5B model. The strongest installed model writes spec tests without ever seeing the hidden tests, and the drafts are scored CodeT-style. A task escalates to `qwen2.5-coder:3b` only when every draft still fails its own tests. Easy tasks stay fast. Models stay loaded for 30 minutes (`"keep_alive"` in config.json). Set `"strong"` in config.json to choose a different escalation model.

## One-tap Genius exam on your phone (Termux)

```bash
curl -fsSL https://raw.githubusercontent.com/recordofragnaros67-tech/GoogolForge/main/scripts/genius_run.sh | bash
```

It updates GoogolForge, picks the strongest model your free RAM allows (7B, 3B or 1.5B), runs the sealed Hard exam in Genius mode, shows the wrong answers, and saves a report.

Pixel Proof Run (v3.8): the first real on-device scores, incl. the never-tuned holdout:
```
curl -fsSL https://raw.githubusercontent.com/recordofragnaros67-tech/GoogolForge/main/scripts/pixel_proof.sh -o pixel_proof.sh && bash pixel_proof.sh
```
Plans: `core` (default, selftest + 4 quick exams + holdout), `full` (adds Genius Hard, HumanEval+ 40, Genius holdout), `demo` (one 3-minute live exam).

## HumanEval+ slice (v3.7)

`forge bench --heplus` runs 40 fixed tasks from [EvalPlus HumanEval+](https://github.com/evalplus/humanevalplus_release) v0.1.10 (every 4th task, up to 120 hidden inputs each). The model only sees each function's signature and docstring; the sealed judge tells a retry only the error type. Use `--quick` for the first 8 tasks. In GitHub Actions: arena > Run workflow > set `heplus`.

40 tasks instead of 6 means one lucky or unlucky task moves the score by 2.5 points, not 17. The data is in `data/heplus40.json` and is rebuilt with `tools/build_heplus.py`. HumanEval+ is by the EvalPlus authors, Apache-2.0 (see `data/NOTICE`).

## Full HumanEval+, MBPP+ and a holdout set (v3.8)

| Command | Arena `set` | Tasks | Hidden inputs per task | Data |
|---|---|---|---|---|
| `forge bench --heplus` | `heplus` | 40 (every 4th HumanEval+ task) | up to 120 | `data/heplus40.json` |
| `forge bench --heplus-full` | `heplusfull` | all 164 HumanEval+ tasks | up to 80 | `data/heplus164.json.gz` (gzip) |
| `forge bench --mbppplus` | `mbppplus` | 40 MBPP+ tasks | up to 100 | `data/mbppplus40.json` |
| `forge bench --holdout` | `holdout` | 6 original hard tasks | 34 to 50 | `data/holdout6.json` |

All four use the same sealed judge: the model sees only the task prompt, a failure names only the hidden case number, and expected outputs come from the canonical or reference solutions. The self-test runs every reference solution against every hidden test of every set.

[MBPP+](https://github.com/evalplus/mbppplus_release) v0.2.0 (EvalPlus, Apache-2.0): the 40 tasks are evenly spaced among the tasks a plain equality check can judge fairly (the prompt's worked example matches the stored input exactly and the canonical solution reproduces it; set-order and not-None special cases are left out). Rebuild with `tools/build_mbppplus.py`.

**Holdout.** The 6 holdout tasks (interval coverage, pattern expansion, limited coins, meeting slots, a logic parser with implication, rectangle union area) were written for GoogolForge and are in no public benchmark. They are a holdout: never use their results, losses or hidden inputs to tune prompts, pitfalls, lint fixes, probes or routing. Tune on the other sets, then run `--holdout` to see whether a gain is real. Losses are not saved for this set. Each reference is checked against a brute-force solution in `tools/build_holdout.py`.

## Genius Lab dashboard (v3.9)

`forge web` now has a Genius Lab card. It has buttons for the Genius exam, What went wrong, the Quick exam, HumanEval+, the Holdout, and the Shootout. It also shows a color-coded table of this phone's own exam scores, read from `~/googolforge/bench_history.json`. Slow exams ask before they start. You can type too, for example "run the genius exam" or "what did the AI get wrong".

## Autopilot (v3.10)

`bash scripts/autopilot.sh` runs the routine in order: update, start the local AI, self-test, quick exam, Genius exam (only while charging), and a report. It resumes where it stopped and skips steps already done today. It finishes by suggesting your next moves based on this phone's own scores. `--suggest` prints only the suggestions. `--schedule` runs it every night at 3:00 through cronie, and `--unschedule` removes that. Nothing is published automatically.

## Grandmaster (v3.12): the whole routine with a local AI Coach

```
curl -fsSL https://raw.githubusercontent.com/recordofragnaros67-tech/GoogolForge/main/scripts/grandmaster.sh -o ~/grandmaster.sh && bash ~/grandmaster.sh
```

It prepares the phone (RAM, storage, battery), updates, starts the local AI, picks models by free RAM, runs the self-test and a baseline exam, then lets the phone's own AI Coach pick the next exams from a fixed, safe menu (it can't run anything else). Long exams run only while charging. It ends with a report, next-move suggestions and a notification. Options: `--yes` (no questions), `--dry` (plan only), `--minutes N`, `--rounds N`, `--schedule` (nightly at 3:30), `--report`. Scores are real sealed-judge results; nothing is published.
