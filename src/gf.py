#!/usr/bin/env python3
"""GoogolForge v2.0 - one command for everything."""
import os, pathlib, subprocess, sys
sys.dont_write_bytecode = True

VERSION = "3.0"
HOME = pathlib.Path(os.environ.get("GF_HOME", str(pathlib.Path.home() / "googolforge")))
PY = sys.executable
TOOLS = {  # subcommand: (file, how to run, description)
    "chat":        ("assistant.py", "py", "talk in plain English"),
    "web":         ("web.py", "py", "browser Dashboard in Chrome"),
    "learn":       ("academy.py", "py", "Academy: daily, lesson, quiz, drill, check, progress"),
    "academy":     ("academy.py", "py", "same as learn"),
    "bench":       ("bench.py", "py", "Benchmark Arena: score the AI (--quick, history)"),
    "shootout":    ("bench.py", "shootout", "Model Shootout: rank every AI model (--prompts, --full, --apply, pull, use)"),
    "autopublish": ("autopublish.sh", "sh", "on | off | status | now"),
    "new":         ("templates.py", "py", "new project: game | cli | api | bot | data  NAME"),
    "lessons":     ("repairmem.py", "py", "Self-Repair Memory: what the debugger learned (clear)"),
    "path":        ("path.py", "py", "Season 2: 30 days to your own AI tool (go, done)"),
    "voice":       ("voice.sh", "sh", "speak a command (--loop to keep listening)"),
}
PRO = {"explain", "mutate", "index", "recall", "rag", "team", "duel", "ci"}  # forge3.py tools
PLUGINS = HOME / "plugins"
SELFTESTS = [("Forge engine", "forge.py"), ("Academy", "academy.py"), ("Assistant", "assistant.py"),
             ("Dashboard", "web.py"), ("Benchmark", "bench.py"), ("Self-Repair Memory", "repairmem.py"),
             ("Templates", "templates.py"), ("Season 2 path", "path.py"), ("Pro tools v3", "forge3.py")]

HELP = f"""GoogolForge v{VERSION}

  Easiest:   forge chat          (or just: gf)  then type what you want
  Browser:   forge web
  Build:     forge pipeline "goal" | status | run | retry | debug FILE | review FILE | report
  Learn:     forge learn daily | quiz | drill | check | progress
  Season 2:  forge path   forge path go   forge path done
  Start:     forge new game|cli|api|bot|data NAME
  Voice:     forge voice   forge voice --loop
  Memory:    forge lessons   (what the debugger has learned)
  Pro v3:    forge team "goal" | mutate FILE | explain FILE | index | rag "question" | duel | ci
  Bench+:    forge bench --elite (best)   forge bench --hard   forge bench --team
  Plugins:   forge plugins   (drop a .py file in ~/googolforge/plugins to add a command)
  Measure:   forge bench          forge bench --quick      forge bench history
  Shootout:  forge shootout       forge shootout --prompts forge shootout --apply   forge shootout pull
  Publish:   forge publish        forge autopublish on
  Health:    forge doctor         forge test (every self-check at once)
  More:      forge version        forge help-all (every engine command)"""


def run(args):
    try:
        return subprocess.run(args).returncode
    except KeyboardInterrupt:
        return 130


def test_all():
    passed = 0
    for name, f in SELFTESTS:
        p = HOME / f
        ok = p.exists() and subprocess.run([PY, "-B", str(p), "selftest"], stdout=subprocess.DEVNULL,
                                           stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL).returncode == 0
        passed += ok
        print(f"  {'OK  ' if ok else 'FAIL'} {name}" + ("" if p.exists() else " (not installed)"))
    ap = HOME / "autopublish.sh"
    ok = ap.exists() and subprocess.run(["bash", "-n", str(ap)]).returncode == 0
    passed += ok
    print(f"  {'OK  ' if ok else 'FAIL'} Auto-publish")
    total = len(SELFTESTS) + 1
    print(f"\nGoogolForge v{VERSION}: {passed}/{total} systems healthy")
    return 0 if passed == total else 1


def main(argv):
    cmd, rest = (argv[0], argv[1:]) if argv else ("help", [])
    if cmd in ("help", "-h", "--help"):
        print(HELP)
        return 0
    if cmd == "help-all":
        return run([PY, str(HOME / "forge.py"), "help"])
    if cmd in ("version", "--version"):
        print(f"GoogolForge v{VERSION}")
        return 0
    if cmd == "test":
        return test_all()
    if cmd in PRO:
        return run([PY, "-B", str(HOME / "forge3.py"), cmd] + rest)
    if cmd == "plugins":
        found = sorted(PLUGINS.glob("*.py")) if PLUGINS.exists() else []
        print("Plugins:" if found else "No plugins yet. Add one: ~/googolforge/plugins/NAME.py, then run forge NAME")
        for f in found:
            first = (f.read_text(errors="ignore").splitlines() or [""])[0].strip('#"\' ')
            print(f"  forge {f.stem:<12} {first[:60]}")
        return 0
    plug = PLUGINS / f"{cmd}.py"
    if cmd.isidentifier() and plug.exists():
        return run([PY, "-B", str(plug)] + rest)
    if cmd in TOOLS:
        f, kind, _ = TOOLS[cmd]
        p = HOME / f
        if not p.exists():
            print(f"{f} isn't installed. Re-run googolforge_setup.sh.")
            return 1
        if kind == "shootout":
            return run([PY, "-B", str(p), "shootout"] + rest)
        return run(([PY, "-B", str(p)] if kind == "py" else ["bash", str(p)]) + rest)
    return run([PY, str(HOME / "forge.py"), cmd] + rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
