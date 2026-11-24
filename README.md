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

`selftest.yml` runs every module's self-test on each push. `security.yml` runs a Bandit scan and a secret scan.

Website: `docs/` (GitHub Pages). Contributing: see `CONTRIBUTING.md`.

## Pixel 8 tuning (v3.1)
Every model call now sends `num_thread` (default **5**, the reported sweet spot for the Pixel 8's Tensor G3; more threads can slow it down).
To try another value, add `"threads": 4` (or 6) to `~/googolforge/config.json`, then compare with `forge bench --quick`.

## Genius mode (v3.3): Smart Router
`forge bench --genius --hard` uses four different opening drafts from the fast 1.5B model. The strongest installed model writes spec tests without ever seeing the hidden tests, and the drafts are scored CodeT-style. A task escalates to `qwen2.5-coder:3b` only when every draft still fails its own tests. Easy tasks stay fast. Models stay loaded for 30 minutes (`"keep_alive"` in config.json). Set `"strong"` in config.json to choose a different escalation model.
