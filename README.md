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

## Genius mode (v3.6): Smart Router + Edge-Case Hunter + Rule Lawyer + Stress Probe

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

## HumanEval+ slice (v3.7)

`forge bench --heplus` runs 40 fixed tasks from [EvalPlus HumanEval+](https://github.com/evalplus/humanevalplus_release) v0.1.10 (every 4th task, up to 120 hidden inputs each). The model only sees each function's signature and docstring; the sealed judge tells a retry only the error type. Use `--quick` for the first 8 tasks. In GitHub Actions: arena > Run workflow > set `heplus`.

40 tasks instead of 6 means one lucky or unlucky task moves the score by 2.5 points, not 17. The data is in `data/heplus40.json` and is rebuilt with `tools/build_heplus.py`. HumanEval+ is by the EvalPlus authors, Apache-2.0 (see `data/NOTICE`).
