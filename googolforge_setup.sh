#!/data/data/com.termux/files/usr/bin/bash
# ==========================================================
#  GoogolForge ONE-SHOT SETUP (Master Foundation v1.3 + Academy v1.0 + Assistant v1.4 + Dashboard v1.5 + Auto-Publish + v2.0 launcher & Benchmark Arena + Model Shootout + v2.1 expansion + v2.2 audit fixes + v3.0 Pro)
#  Run in Termux:  bash ~/storage/downloads/googolforge_setup.sh
#  Free, open-source, offline AI. Use Wi-Fi (about 2.3 GB of models).
# ==========================================================
set -e
echo "######## STEP A: phone prep ########"
termux-wake-lock 2>/dev/null || true
yes | pkg upgrade -y || true
[ -d ~/storage ] || termux-setup-storage || true
echo "######## STEP B: Master Foundation v1.3 ########"
# ==========================================================
#  GoogolForge Master Foundation v1.3 - Ultimate Termux Installer
#  Plan, code, test, judge, debug, review, lint, report, publish
#  100% free, open-source, offline AI via Ollama
# ==========================================================
set -e
echo "== [1/7] Installing free tools =="
pkg update -y
pkg install -y python git curl ollama gh zip
pip install --quiet pyflakes || echo "pyflakes skipped (optional)"
mkdir -p ~/googolforge/workspace
echo "== [2/7] Writing the engine =="
cat > ~/googolforge/forge.py <<'PYEOF'
#!/usr/bin/env python3
"""GoogolForge Master Foundation v1.3 - Elite Intelligence Engine (Termux edition).
Plan, code, test, judge, debug, review, lint, report, publish. Free and offline via Ollama."""
import datetime, json, os, pathlib, re, shutil, subprocess, sys, urllib.request, zipfile

HOME = pathlib.Path(os.environ.get("GF_HOME", str(pathlib.Path.home() / "googolforge")))
WORK = HOME / "workspace"
STATE = HOME / "tasks.json"
CONF = HOME / "config.json"
LOG = HOME / "progress.log"
REPORT = HOME / "REPORT.md"
NOPROXY = urllib.request.build_opener(urllib.request.ProxyHandler({}))
DEFAULTS = {"ollama": "http://127.0.0.1:11434", "coder": "qwen2.5-coder:1.5b",
            "judge": "llama3.2:1b", "tries": 3, "timeout": 60}
DANGER = ["shutil.rmtree", "os.remove", "os.unlink", "os.system", "subprocess",
          "rm -rf", "__import__", "eval(", "exec(", "socket", "requests.", "urllib"]

def conf():
    c = dict(DEFAULTS)
    if CONF.exists():
        try:
            c.update(json.loads(CONF.read_text()))
        except Exception:
            pass
    for k, env in (("ollama", "OLLAMA_URL"), ("coder", "GF_CODER"), ("judge", "GF_JUDGE")):
        if os.environ.get(env):
            c[k] = os.environ[env]
    return c

C = None

def log(msg):
    line = f"[{datetime.datetime.now():%Y-%m-%d %H:%M}] {msg}"
    print(line)
    with open(LOG, "a") as f:
        f.write(line + "\n")

# ---------- AI calls ----------
def ask(model, prompt, fmt=None, temp=0.2):
    body = {"model": model, "prompt": prompt, "stream": False, "options": {"temperature": temp, "num_predict": 1536, "repeat_penalty": 1.1, "num_thread": int(C.get("threads", 5))}}
    if fmt:
        body["format"] = fmt
    req = urllib.request.Request(C["ollama"] + "/api/generate", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        with NOPROXY.open(req, timeout=900) as r:
            return json.loads(r.read())["response"]
    except Exception as e:
        sys.exit(f"AI call failed ({e}). Is Ollama running? Try: forge-start, then forge doctor")

def parse_json(text):
    try:
        return json.loads(text)
    except Exception:
        m = re.search(r"\{.*\}", text or "", re.S)
        if m:
            try:
                return json.loads(m.group(0))
            except Exception:
                return {}
        return {}

def extract_code(text):
    m = re.search(r"```(?:python|py)?\s*\n(.*?)```", text or "", re.S)
    return (m.group(1) if m else (text or "")).strip() + "\n"

# ---------- state ----------
def load():
    return json.loads(STATE.read_text()) if STATE.exists() else {"goal": "", "tasks": []}

def save(state):
    STATE.write_text(json.dumps(state, indent=2))

def safe_name(name):
    name = os.path.basename(str(name)).strip()
    return name if re.fullmatch(r"[A-Za-z0-9_\-]+\.py", name) else ""

# ---------- core checks ----------
def test_code(path):
    """Calculate, don't hope: compile, then run the built-in self-tests."""
    c = subprocess.run([sys.executable, "-m", "py_compile", str(path)], capture_output=True, text=True)
    if c.returncode != 0:
        return False, "SYNTAX ERROR:\n" + c.stderr[-1500:]
    try:
        r = subprocess.run([sys.executable, str(path)], capture_output=True, text=True,
                           timeout=int(C["timeout"]), cwd=str(path.parent), stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return False, f"TIMEOUT: ran longer than {C['timeout']} seconds."
    out = (r.stdout + r.stderr)[-1500:]
    return r.returncode == 0 and "ALL TESTS PASSED" in r.stdout, out

def lint_file(path):
    issues = []
    c = subprocess.run([sys.executable, "-m", "py_compile", str(path)], capture_output=True, text=True)
    if c.returncode != 0:
        issues.append(c.stderr.strip()[-400:])
    if shutil.which("pyflakes"):
        p = subprocess.run(["pyflakes", str(path)], capture_output=True, text=True)
        issues += [l for l in (p.stdout + p.stderr).splitlines() if l.strip()]
    return issues

def judge(spec, code, test_out):
    """Independent QA from a different model family."""
    prompt = ("You are a strict independent code judge, like a chess arbiter. Decide if this code fully "
              "meets the spec, is correct, safe, and readable. Reply ONLY with JSON: "
              '{"verdict":"PASS" or "FAIL","score":0-100,"reasons":"short explanation"}\n'
              f"Spec: {spec}\nTest output:\n{test_out}\nCode:\n{code}")
    d = parse_json(ask(C["judge"], prompt, fmt="json"))
    try:
        score = int(d.get("score", 0))
    except Exception:
        score = 0
    return str(d.get("verdict", "FAIL")).upper() == "PASS", score, str(d.get("reasons", ""))

def approved(code, auto):
    flagged = [d for d in DANGER if d in code]
    if auto and not flagged:
        return True
    print("\n" + "=" * 50 + "\n" + code + "=" * 50)
    if flagged:
        print("WARNING, risky calls found:", ", ".join(flagged))
    try:
        return input("Run this code? [y/N] ").strip().lower() == "y"
    except EOFError:
        return False

def git_commit(msg):
    try:
        subprocess.run(["git", "-C", str(HOME), "add", "-A"], capture_output=True)
        subprocess.run(["git", "-C", str(HOME), "-c", "user.name=GoogolForge",
                        "-c", "user.email=forge@localhost", "commit", "-qm", msg], capture_output=True)
    except Exception:
        pass

# ---------- commands ----------
def plan(goal):
    """Opening preparation: break the goal into ordered moves."""
    prompt = ("You are a grandmaster software planner. Break this goal into 3 to 7 small, ordered coding "
              "tasks. Each task produces exactly ONE standalone Python file using only the standard "
              "library. Later files may import earlier ones. Reply ONLY with JSON: "
              '{"tasks":[{"file":"name.py","spec":"exactly what the file must do"}]}\nGoal: ' + goal)
    data = parse_json(ask(C["coder"], prompt, fmt="json"))
    tasks = []
    for t in data.get("tasks", []) if isinstance(data, dict) else []:
        name = safe_name(t.get("file", "")) if isinstance(t, dict) else ""
        if name and t.get("spec"):
            tasks.append({"id": len(tasks) + 1, "file": name, "spec": t["spec"],
                          "status": "pending", "tries": 0, "score": 0, "notes": ""})
    if not tasks:
        log("PLAN FAILED: no usable tasks. Rephrase the goal more simply and try again.")
        return False
    save({"goal": goal, "tasks": tasks})
    log(f"PLAN: {len(tasks)} tasks for goal: {goal}")
    status()
    return True

def write_code(spec, fname, feedback, context=""):
    prompt = ("Write ONE complete Python 3 file using only the standard library.\n"
              f"File name: {fname}\nSpec: {spec}\n{context}"
              "Rules: put self-tests with assert statements inside if __name__ == '__main__': and print "
              "exactly ALL TESTS PASSED at the end. Never call input(). No network, no deleting files, "
              "no shell commands. Reply with only the code in one ```python block.")
    if feedback:
        prompt += "\nThe previous attempt failed. Fix these problems:\n" + feedback[-1500:]
    return extract_code(ask(C["coder"], prompt))

def run(auto=False):
    """Middlegame: play every move in order, each one tested and judged."""
    state = load()
    if not state["tasks"]:
        print('No plan yet. Run: forge plan "your goal"')
        return
    done_files = []
    for task in state["tasks"]:
        if task["status"] == "done":
            done_files.append(task["file"])
            continue
        log(f"TASK {task['id']}: {task['file']} - {task['spec']}")
        ctx = ("Files already built in the same folder that you may import: " + ", ".join(done_files) + "\n") if done_files else ""
        feedback = task.get("notes", "") if task["status"] == "failed" else ""
        for attempt in range(1, int(C["tries"]) + 1):
            task["tries"] += 1
            code = write_code(task["spec"], task["file"], feedback, ctx)
            path = WORK / task["file"]
            path.write_text(code)
            if not approved(code, auto):
                task["status"], task["notes"] = "blocked", "You declined to run it."
                log(f"  blocked by you on attempt {attempt}")
                break
            ok, out = test_code(path)
            if not ok:
                feedback = "Tests failed:\n" + out
                log(f"  attempt {attempt}: tests FAILED")
                continue
            passed, score, reasons = judge(task["spec"], code, out)
            if passed:
                task.update(status="done", score=score, notes=reasons)
                done_files.append(task["file"])
                log(f"  attempt {attempt}: tests passed, judge PASS ({score}/100)")
                git_commit(f"Task {task['id']} done: {task['file']}")
                break
            feedback = "Judge rejected it: " + reasons
            log(f"  attempt {attempt}: judge FAIL ({score}/100) - {reasons}")
        else:
            task["status"], task["notes"] = "failed", feedback[-800:]
            log(f"  FAILED after {C['tries']} attempts")
        save(state)
    save(state)
    status()

def debug(fname, auto=False):
    """Grandmaster debugging: reproduce, isolate, fix one thing, re-test, judge."""
    path = pathlib.Path(fname)
    if not path.exists():
        path = WORK / fname
    if not path.exists():
        print("File not found:", fname)
        return
    original = path.read_text()
    backup = path.with_suffix(path.suffix + ".bak")
    backup.write_text(original)
    code = original
    has_tests = "ALL TESTS PASSED" in code
    for attempt in range(1, int(C["tries"]) + 1):
        if has_tests:
            ok, out = test_code(path)
        else:
            issues = lint_file(path)
            ok, out = (not issues), "\n".join(issues) or "No errors found by compile/lint."
        if ok and attempt > 1:
            passed, score, reasons = judge("Fix bugs without changing intended behavior.", code, out)
            log(f"DEBUG {path.name}: fixed on attempt {attempt - 1}, judge {'PASS' if passed else 'FAIL'} ({score}/100) {reasons}")
            git_commit(f"Debugged {path.name}")
            return
        if ok:
            print(f"{path.name}: no errors found. Use forge review {fname} for a deeper check.")
            return
        log(f"DEBUG {path.name} attempt {attempt}: error found, asking AI to fix")
        prompt = ("You are a grandmaster debugger. Reproduce the error mentally, find the single root cause, "
                  "and fix it with the smallest change. Keep all existing features and tests. "
                  "Reply with the full corrected file in one ```python block.\n"
                  f"Error output:\n{out[-1500:]}\nCode:\n{code}")
        code = extract_code(ask(C["coder"], prompt))
        if not approved(code, auto):
            path.write_text(original)
            print("Fix declined. Original restored.")
            return
        path.write_text(code)
    ok, out = test_code(path) if has_tests else (not lint_file(path), "")
    if ok:
        log(f"DEBUG {path.name}: fixed on final attempt")
        git_commit(f"Debugged {path.name}")
    else:
        path.write_text(original)
        log(f"DEBUG {path.name}: could not fix in {C['tries']} attempts. Original restored; backup at {backup.name}")

def review(fname):
    path = pathlib.Path(fname)
    if not path.exists():
        path = WORK / fname
    if not path.exists():
        print("File not found:", fname)
        return
    code = path.read_text()
    prompt = ("You are an elite code reviewer. Review this file. Reply ONLY with JSON: "
              '{"score":0-100,"bugs":["..."],"security":["..."],"improvements":["..."]}\nCode:\n' + code)
    d = parse_json(ask(C["judge"], prompt, fmt="json"))
    print(f"\nREVIEW: {path.name}  score {d.get('score', '?')}/100")
    for key in ("bugs", "security", "improvements"):
        items = d.get(key) or []
        print(f"  {key.upper()}:")
        for i in items if isinstance(items, list) else [items]:
            print(f"   - {i}")
    lint = lint_file(path)
    print("  LINT:", "clean" if not lint else "")
    for l in lint:
        print("   -", l)

def lint_all():
    files = sorted(WORK.glob("*.py"))
    bad = 0
    for f in files:
        issues = lint_file(f)
        print(f"{'OK  ' if not issues else 'FIX '} {f.name}")
        for i in issues:
            print("     -", i)
        bad += bool(issues)
    print(f"\n{len(files) - bad}/{len(files)} files clean." + ("" if shutil.which("pyflakes") else " (Install pyflakes for deeper checks: pip install pyflakes)"))

def chat(question):
    print(ask(C["coder"], "You are GoogolForge, a sharp, concise AI coding mentor. Answer clearly.\n" + question, temp=0.4))

def status():
    """Progress report."""
    state = load()
    tasks = state["tasks"]
    done = sum(t["status"] == "done" for t in tasks)
    pct = int(100 * done / len(tasks)) if tasks else 0
    bar = "#" * (pct // 5) + "-" * (20 - pct // 5)
    print(f"\nGOAL: {state['goal'] or '(none)'}")
    print(f"PROGRESS: [{bar}] {done}/{len(tasks)} ({pct}%)")
    icons = {"done": "[x]", "pending": "[ ]", "failed": "[!]", "blocked": "[-]"}
    for t in tasks:
        sc = f", score {t.get('score', 0)}" if t["status"] == "done" else ""
        print(f"  {icons.get(t['status'], '[?]')} {t['id']}. {t['file']} ({t['status']}, tries {t['tries']}{sc})")
    print()

def report():
    state = load()
    tasks = state["tasks"]
    done = [t for t in tasks if t["status"] == "done"]
    avg = int(sum(t.get("score", 0) for t in done) / len(done)) if done else 0
    lines = ["# GoogolForge Report", f"_{datetime.datetime.now():%Y-%m-%d %H:%M}_", "",
             f"**Goal:** {state['goal'] or '(none)'}", f"**Done:** {len(done)}/{len(tasks)}",
             f"**Average judge score:** {avg}/100", "", "| # | File | Status | Tries | Score |",
             "|---|---|---|---|---|"]
    lines += [f"| {t['id']} | {t['file']} | {t['status']} | {t['tries']} | {t.get('score', 0)} |" for t in tasks]
    if LOG.exists():
        lines += ["", "## Recent log", "```"] + LOG.read_text().splitlines()[-25:] + ["```"]
    REPORT.write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"\nSaved: {REPORT}")

def retry():
    state = load()
    n = 0
    for t in state["tasks"]:
        if t["status"] in ("failed", "blocked"):
            t["status"] = "pending"
            n += 1
    save(state)
    print(f"{n} task(s) back in the queue. Run: forge run")

def pipeline(goal):
    """Full automatic sequence: plan, build, lint, report."""
    log(f"PIPELINE START: {goal}")
    if plan(goal):
        run(auto=True)
        lint_all()
        report()
    log("PIPELINE END")

def export():
    dest_dir = pathlib.Path.home() / "storage" / "downloads"
    if not dest_dir.exists():
        dest_dir = HOME
        print("Tip: run termux-setup-storage once to export straight to your phone's Downloads.")
    dest = dest_dir / f"googolforge-{datetime.datetime.now():%Y%m%d-%H%M}.zip"
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
        for f in HOME.rglob("*"):
            if f.is_file() and ".git" not in f.parts and f.suffix != ".zip":
                z.write(f, f.relative_to(HOME))
    print("Exported:", dest)

def models(coder=None, judge_m=None):
    c = json.loads(CONF.read_text()) if CONF.exists() else {}
    if coder:
        c["coder"] = coder
    if judge_m:
        c["judge"] = judge_m
    CONF.write_text(json.dumps(c, indent=2))
    cc = conf()
    print(f"Coder: {cc['coder']}\nJudge: {cc['judge']}")

def doctor():
    try:
        with NOPROXY.open(C["ollama"] + "/api/tags", timeout=5) as r:
            names = [m["name"] for m in json.loads(r.read()).get("models", [])]
        print("Ollama: running. Models:", ", ".join(names) or "none")
        for m in (C["coder"], C["judge"]):
            print(f"  {m}: {'OK' if m in names else 'MISSING, run: ollama pull ' + m}")
    except Exception as e:
        print(f"Ollama is not running. Start it with: forge-start  ({e})")
    print("pyflakes:", "OK" if shutil.which("pyflakes") else "not installed (optional)")
    print("git:", "OK" if shutil.which("git") else "missing")

def selftest():
    """Engine checks itself, no AI needed."""
    import tempfile
    fails = 0
    def check(name, cond):
        nonlocal fails
        print(("PASS " if cond else "FAIL ") + name)
        fails += not cond
    check("parse_json plain", parse_json('{"a":1}') == {"a": 1})
    check("parse_json wrapped", parse_json('sure! {"a":2} ok') == {"a": 2})
    check("parse_json junk", parse_json("nope") == {})
    check("extract_code fenced", extract_code("x\n```python\nprint(1)\n```\ny") == "print(1)\n")
    check("safe_name good", safe_name("app_1.py") == "app_1.py")
    check("safe_name blocks paths", safe_name("../../etc/x.sh") == "")
    with tempfile.TemporaryDirectory() as d:
        good = pathlib.Path(d) / "g.py"
        good.write_text("assert 1+1==2\nprint('ALL TESTS PASSED')\n")
        check("test_code passes good code", test_code(good)[0])
        bad = pathlib.Path(d) / "b.py"
        bad.write_text("def x(:\n")
        check("test_code catches syntax error", not test_code(bad)[0])
        wrong = pathlib.Path(d) / "w.py"
        wrong.write_text("assert 1+1==3\nprint('ALL TESTS PASSED')\n")
        check("test_code catches failed assert", not test_code(wrong)[0])
    check("danger flags subprocess", any(x in "import subprocess" for x in DANGER))
    print(f"\nSELFTEST: {'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
    return fails == 0

HELP = '''Commands:
  forge pipeline "goal"   full auto: plan, build, lint, report
  forge plan "goal"       break a goal into tasks
  forge run [--auto]      build each task (asks before running code unless --auto)
  forge status            progress bar and task list
  forge retry             requeue failed tasks
  forge debug FILE [--auto]   AI finds and fixes bugs (backup kept)
  forge review FILE       AI judge scores bugs, security, improvements
  forge lint              compile and lint every file
  forge ask "question"    ask the AI mentor
  forge report            write REPORT.md
  forge export            zip your project (to Downloads if storage is set up)
  forge models [coder] [judge]   show or switch models
  forge doctor            check Ollama, models, tools
  forge selftest          engine checks itself
  forge publish           push to GitHub and update your free site'''

def main():
    global C
    HOME.mkdir(parents=True, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    C = conf()
    a = sys.argv[1:]
    cmd = a[0] if a else "help"
    rest = [x for x in a[1:] if x != "--auto"]
    auto = "--auto" in a
    if cmd in ("help", "-h", "--help"):
        print(__doc__ + "\n" + HELP)
    elif cmd == "plan" and rest:
        plan(" ".join(rest))
    elif cmd == "pipeline" and rest:
        pipeline(" ".join(rest))
    elif cmd == "run":
        run(auto)
    elif cmd == "status":
        status()
    elif cmd == "retry":
        retry()
    elif cmd == "debug" and rest:
        debug(rest[0], auto)
    elif cmd == "review" and rest:
        review(rest[0])
    elif cmd == "lint":
        lint_all()
    elif cmd == "ask" and rest:
        chat(" ".join(rest))
    elif cmd == "report":
        report()
    elif cmd == "export":
        export()
    elif cmd == "models":
        models(rest[0] if rest else None, rest[1] if len(rest) > 1 else None)
    elif cmd == "doctor":
        doctor()
    elif cmd == "selftest":
        sys.exit(0 if selftest() else 1)
    elif cmd == "publish":
        script = HOME / "publish.sh"
        if script.exists():
            subprocess.run(["bash", str(script)])
        else:
            print("publish.sh not found. Re-run the installer.")
    else:
        print("Unknown or incomplete command.\n" + HELP)

if __name__ == "__main__":
    main()
PYEOF
chmod +x ~/googolforge/forge.py
echo "== [3/7] Writing the publish script =="
cat > ~/googolforge/publish.sh <<'PUBEOF'
#!/data/data/com.termux/files/usr/bin/bash
# GoogolForge Objective 4: publish to GitHub + free website (GitHub Pages)
set -e
cd ~/googolforge || { echo "Run the v1.2 installer first."; exit 1; }
command -v gh >/dev/null && command -v git >/dev/null || pkg install -y gh git python curl
# 1. Sign in to GitHub (opens a one-time code flow the first time; auto mode never prompts)
if ! gh auth status >/dev/null 2>&1; then
  [ -n "$GF_AUTO" ] && { echo "Not signed in to GitHub. Run: gh auth login"; exit 3; }
  gh auth login -h github.com -p https -w
fi
LOGIN=$(gh api user -q .login)
UID_GH=$(gh api user -q .id)
git config user.name "$LOGIN"
git config user.email "${UID_GH}+${LOGIN}@users.noreply.github.com"
# 2. Keep private and bulky files out of the public repo
cat > .gitignore <<'GI'
ollama.log
progress.log
autopublish.log
chat_memory.json
config.json
academy/
*.bak
*.zip
.last_publish
.publish_out
.publock/
*.pyc
__pycache__/
web_token
code_index.json
*.pre-repairmem
GI
# Cloud test robot (GitHub Actions) - free for public repos
[ -f .github/workflows/forge-test.yml ] || python forge3.py ci >/dev/null 2>&1 || true
# Untrack private files that an older version may have pushed
git rm -r -q --cached --ignore-unmatch chat_memory.json config.json academy autopublish.log progress.log ollama.log web_token code_index.json >/dev/null 2>&1 || true
export GF_LOGIN="$LOGIN"
# 3. AI writes the tagline (local model, free); falls back if Ollama is off
mkdir -p docs
python - <<'PY'
import json, urllib.request, html, pathlib
tag = "Elite open-source AI, built move by move."
try:
    op = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    body = {"model": "llama3.2:1b", "stream": False, "options": {"temperature": 0.7},
            "prompt": "Write one bold tagline, under 12 words, no quotes, for GoogolForge AI Technologies, "
                      "a free open-source AI engine that plans, codes, tests and judges software."}
    req = urllib.request.Request("http://127.0.0.1:11434/api/generate", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    out = json.loads(op.open(req, timeout=120).read())["response"].strip().strip('"').splitlines()[0]
    if 3 < len(out) < 120:
        tag = out
except Exception:
    pass
divs = ["GoogolForge Master Foundation", "DragonForge AI", "Theban Arcana", "TeaForge AI",
        "GoogolForge Quantum", "GoogolForge Linux", "GoogolForge Academy",
        "GoogolForge Research Institute", "GoogolForge Security", "GoogolForge Cloud",
        "GoogolForge Commerce"]
cards = "".join(f"<li>{html.escape(d)}</li>" for d in divs)
import datetime, os
LOGIN = os.environ.get("GF_LOGIN", "")
ws = pathlib.Path("workspace")
builds = sorted(ws.glob("*.py"), key=lambda f: -f.stat().st_mtime)[:12] if ws.exists() else []
blist = "".join(f'<li><a href="https://github.com/{LOGIN}/googolforge/blob/main/workspace/{html.escape(f.name)}">{html.escape(f.name)}</a></li>' for f in builds) or "<li>First builds coming soon.</li>"
stamp = datetime.datetime.now().strftime("%B %d, %Y")
page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>GoogolForge AI Technologies</title>
<style>
body{{margin:0;font-family:system-ui,sans-serif;background:#0b0f1a;color:#e8ecf5;line-height:1.6}}
header{{padding:72px 24px 40px;text-align:center;background:radial-gradient(circle at top,#26324f,#0b0f1a)}}
h1{{font-size:2.4rem;margin:0}} .tag{{color:#f5b942;font-size:1.2rem}}
main{{max-width:760px;margin:auto;padding:24px}}
ul{{list-style:none;padding:0;display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px}}
li{{background:#151c2e;border:1px solid #2a3550;border-radius:10px;padding:14px}}
code{{background:#151c2e;padding:2px 6px;border-radius:4px}}
footer{{text-align:center;color:#7d8aa8;padding:32px;font-size:.9rem}}
</style></head><body>
<header><h1>GoogolForge AI Technologies</h1><p class="tag">{html.escape(tag)}</p></header>
<main>
<h2>Master Foundation v1.5: Elite Intelligence Engine</h2>
<p>Plans a goal, writes each piece with a local open-source AI, tests it, and has an independent AI judge sign off before it counts. Free, private, and runs on a phone. Includes GoogolForge Academy, a plain-English Assistant, and a browser Dashboard.</p>
<p>Try: <code>forge chat "build me a tip calculator"</code></p>
<h2>Latest builds</h2><ul>{blist}</ul>
<h2>The GoogolForge ecosystem</h2><ul>{cards}</ul>
</main><footer>&copy; GoogolForge AI Technologies &middot; updated {stamp}</footer></body></html>"""
pathlib.Path("docs/index.html").write_text(page)
pathlib.Path("README.md").write_text(
    "# GoogolForge Master Foundation v1.5\n\n" + tag + "\n\nFree, open-source AI engine: plan, code, test, judge.\n\n"
    "```\nforge plan \"your goal\"\nforge run\nforge status\n```\n")
print("Tagline:", tag)
PY
# 4. Commit and push
git branch -M main
git add -A
git commit -qm "GoogolForge: publish site and engine" || echo "Nothing new to commit"
if gh repo view "$LOGIN/googolforge" >/dev/null 2>&1; then
  git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$LOGIN/googolforge.git"
  git push -u origin main
else
  gh repo create googolforge --public --source=. --remote=origin --push \
    --description "GoogolForge AI Technologies - free open-source Elite Intelligence Engine"
fi
# 5. Turn on free hosting (GitHub Pages from /docs)
gh api -X POST "repos/$LOGIN/googolforge/pages" -f "source[branch]=main" -f "source[path]=/docs" >/dev/null 2>&1 \
  || echo "Pages already on (or will be in a minute)."
echo "== Live in 1 to 2 minutes: https://$LOGIN.github.io/googolforge/ =="
echo "== Code: https://github.com/$LOGIN/googolforge =="
PUBEOF
chmod +x ~/googolforge/publish.sh
echo "== [4/7] Setting up shortcuts =="
cd ~/googolforge && { [ -d .git ] || git init -q; }
if ! grep -q "googolforge/forge.py" ~/.bashrc 2>/dev/null; then
cat >> ~/.bashrc <<'RCEOF'
alias forge='python ~/googolforge/forge.py'
forge-start() {
  curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && { echo "Ollama already running"; return; }
  nohup ollama serve > ~/googolforge/ollama.log 2>&1 &
  for i in $(seq 1 30); do curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && { echo "Ollama running"; return; }; sleep 1; done
  echo "Ollama did not start. See ~/googolforge/ollama.log"
}
RCEOF
fi
source ~/.bashrc || true
echo "== [5/7] Starting the AI server =="
forge-start
echo "== [6/7] Downloading free models (about 2 GB, use Wi-Fi) =="
ollama pull qwen2.5-coder:1.5b
ollama pull llama3.2:1b
echo "== [7/7] Engine self-test and health check =="
python ~/googolforge/forge.py selftest
python ~/googolforge/forge.py doctor
echo ""
echo "== GoogolForge v1.3 ready. Open a new Termux session, then try: =="
echo "   forge-start"
echo "   forge pipeline \"a to-do list app with save and load\""
echo "   forge help"
echo "######## STEP C: Academy v1.0 ########"
# GoogolForge Academy v1.0 installer (run after the v1.3 installer)
set -e
pkg install -y python nano
mkdir -p ~/googolforge/academy
cat > ~/googolforge/academy.py <<'ACEOF'
#!/usr/bin/env python3
"""GoogolForge Academy v1.0 - free offline AI Python tutor (Termux edition).
Lessons, quizzes, and verified coding drills with XP, levels, and streaks."""
import datetime, json, os, pathlib, random, re, subprocess, sys, urllib.request
sys.dont_write_bytecode = True

HOME = pathlib.Path(os.environ.get("GF_HOME", str(pathlib.Path.home() / "googolforge")))
ACAD = HOME / "academy"
DRILLS = ACAD / "drills"
LESSONS = ACAD / "lessons"
PROG = ACAD / "progress.json"
CONF = HOME / "config.json"
NOPROXY = urllib.request.build_opener(urllib.request.ProxyHandler({}))
CURRICULUM = ["variables and types", "strings", "lists", "dictionaries", "if statements",
              "loops", "functions", "error handling", "files", "list comprehensions",
              "classes", "modules", "recursion", "sorting and searching", "testing with assert"]
LEVELS = [(0, "Pawn"), (100, "Knight"), (300, "Bishop"), (600, "Rook"), (1000, "Queen"),
          (1600, "King"), (2500, "Grandmaster")]

def conf():
    c = {"ollama": "http://127.0.0.1:11434", "coder": "qwen2.5-coder:1.5b", "judge": "llama3.2:1b"}
    if CONF.exists():
        try:
            c.update(json.loads(CONF.read_text()))
        except Exception:
            pass
    if os.environ.get("OLLAMA_URL"):
        c["ollama"] = os.environ["OLLAMA_URL"]
    return c

C = conf()

def ask(prompt, fmt=None, model=None, temp=0.3):
    body = {"model": model or C["coder"], "prompt": prompt, "stream": False,
            "options": {"temperature": temp, "num_predict": 1536, "repeat_penalty": 1.1, "num_thread": int(C.get("threads", 5))}}
    if fmt:
        body["format"] = fmt
    req = urllib.request.Request(C["ollama"] + "/api/generate", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        with NOPROXY.open(req, timeout=900) as r:
            return json.loads(r.read())["response"]
    except Exception as e:
        sys.exit(f"AI call failed ({e}). Start the AI with: forge-start")

def parse_json(text):
    try:
        return json.loads(text)
    except Exception:
        m = re.search(r"\{.*\}", text or "", re.S)
        try:
            return json.loads(m.group(0)) if m else {}
        except Exception:
            return {}

# ---------- progress ----------
def load():
    if PROG.exists():
        return json.loads(PROG.read_text())
    return {"xp": 0, "streak": 0, "last_day": "", "topics": {}, "quizzes": 0, "drills": 0, "lessons": 0}

def save(p):
    PROG.write_text(json.dumps(p, indent=2))

def level(xp):
    name = LEVELS[0][1]
    for need, n in LEVELS:
        if xp >= need:
            name = n
    nxt = next((need for need, _ in LEVELS if need > xp), None)
    return name, nxt

def award(p, xp, topic, what):
    today = datetime.date.today()
    last = p.get("last_day")
    if last != today.isoformat():
        yesterday = (today - datetime.timedelta(days=1)).isoformat()
        p["streak"] = p.get("streak", 0) + 1 if last == yesterday else 1
        p["last_day"] = today.isoformat()
    before = level(p["xp"])[0]
    p["xp"] += xp
    t = p["topics"].setdefault(topic, {"xp": 0, "best_quiz": 0, "drills": 0})
    t["xp"] += xp
    save(p)
    after = level(p["xp"])[0]
    print(f"+{xp} XP for {what}. Total {p['xp']} XP, streak {p['streak']} day(s).")
    if after != before:
        print(f"*** PROMOTION: you are now a {after}! ***")

def topic_or_next(args):
    if args:
        return " ".join(args)
    p = load()
    for t in CURRICULUM:
        if p["topics"].get(t, {}).get("xp", 0) < 60:
            return t
    return random.choice(CURRICULUM)

# ---------- lesson ----------
def lesson(topic):
    print(f"Preparing lesson: {topic} ...")
    text = ask("You are a grandmaster Python teacher. Teach this topic to a motivated beginner in under "
               "350 words: a one-line idea, a plain explanation, two short runnable code examples with "
               "their output, one common mistake, and a 3-point summary. Plain text, no markdown headers.\n"
               "Topic: " + topic, temp=0.4)
    LESSONS.mkdir(parents=True, exist_ok=True)
    f = LESSONS / (re.sub(r"[^a-z0-9]+", "-", topic.lower()).strip("-") + ".txt")
    f.write_text(text)
    print("\n" + text + f"\n\n(Saved to {f})")
    p = load()
    p["lessons"] += 1
    award(p, 10, topic, "a lesson")
    print(f"Next: academy quiz {topic}")

# ---------- quiz ----------
def valid_quiz(d):
    qs = d.get("questions") if isinstance(d, dict) else None
    if not isinstance(qs, list) or len(qs) < 3:
        return []
    good = []
    for q in qs:
        try:
            if isinstance(q["q"], str) and len(q["options"]) == 4 and int(q["answer"]) in range(4):
                good.append(q)
        except Exception:
            pass
    return good[:5]

def quiz(topic):
    print(f"Building quiz: {topic} ...")
    qs = []
    for _ in range(3):
        d = parse_json(ask("Write a 5-question multiple choice quiz on this Python topic for a beginner. "
                           "Reply ONLY with JSON: {\"questions\":[{\"q\":\"question\",\"options\":"
                           "[\"a\",\"b\",\"c\",\"d\"],\"answer\":0,\"why\":\"one-line explanation\"}]} "
                           "where answer is the index 0-3 of the correct option.\nTopic: " + topic,
                           fmt="json"))
        qs = valid_quiz(d)
        if qs:
            break
    if not qs:
        print("The AI couldn't build a clean quiz. Try again or pick a simpler topic.")
        return
    score = 0
    for i, q in enumerate(qs, 1):
        print(f"\nQ{i}. {q['q']}")
        for j, o in enumerate(q["options"]):
            print(f"   {'ABCD'[j]}) {o}")
        try:
            a = input("Your answer (A-D): ").strip().upper()[:1]
        except EOFError:
            a = ""
        right = "ABCD"[int(q["answer"])]
        if a == right:
            score += 1
            print("Correct!")
        else:
            print(f"Not quite. Answer: {right}. {q.get('why', '')}")
    pct = int(100 * score / len(qs))
    print(f"\nScore: {score}/{len(qs)} ({pct}%)")
    p = load()
    p["quizzes"] += 1
    t = p["topics"].setdefault(topic, {"xp": 0, "best_quiz": 0, "drills": 0})
    t["best_quiz"] = max(t["best_quiz"], pct)
    award(p, score * 5 + (15 if pct == 100 else 0), topic, "the quiz")
    print(f"Next: academy drill {topic}")

# ---------- drills (verified) ----------
def run_tests(folder, solution_code):
    (folder / "solution.py").write_text(solution_code)
    cache = folder / "__pycache__"
    if cache.exists():
        for c in cache.iterdir():
            c.unlink()
    try:
        r = subprocess.run([sys.executable, "-B", "test_drill.py"], cwd=str(folder), capture_output=True,
                           text=True, timeout=30, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT: your code ran longer than 30 seconds (infinite loop?)."
    out = (r.stdout + r.stderr)[-1200:]
    return r.returncode == 0 and "ALL TESTS PASSED" in r.stdout, out

def drill(topic):
    """The AI writes a drill AND proves its own tests pass before you see it."""
    print(f"Forging a verified drill: {topic} ...")
    n = len([d for d in DRILLS.glob("*") if d.is_dir()]) + 1 if DRILLS.exists() else 1
    folder = DRILLS / f"{n:03d}"
    folder.mkdir(parents=True, exist_ok=True)
    for attempt in range(1, 4):
        d = parse_json(ask(
            "Create one small Python coding exercise for a beginner on this topic. Reply ONLY with JSON: "
            "{\"title\":\"...\",\"task\":\"clear instructions naming the exact function to write\","
            "\"starter\":\"def name(...):\\n    pass\\n\",\"reference\":\"full correct solution\","
            "\"tests\":\"python code that starts with: from solution import * then 3 to 6 assert lines\"}"
            "\nUse only the standard library. Topic: " + topic, fmt="json"))
        need = all(isinstance(d.get(k), str) and d.get(k).strip() for k in ("title", "task", "starter", "reference", "tests"))
        if not need:
            continue
        tests = d["tests"]
        if "from solution import" not in tests:
            tests = "from solution import *\n" + tests
        (folder / "test_drill.py").write_text(tests.rstrip() + "\nprint('ALL TESTS PASSED')\n")
        ok, _ = run_tests(folder, d["reference"])
        if ok:
            break
    else:
        for x in folder.iterdir():
            if x.is_file():
                x.unlink()
        folder.rmdir() if not any(folder.iterdir()) else None
        print("Couldn't forge a verified drill this time. Run the command again.")
        return
    (folder / "reference.json").write_text(json.dumps({"reference": d["reference"]}))
    (folder / "solution.py").write_text(d["starter"])
    (folder / "TASK.txt").write_text(f"{d['title']}\nTopic: {topic}\n\n{d['task']}\n")
    meta = {"topic": topic, "title": d["title"], "done": False, "hints": 0}
    (folder / "meta.json").write_text(json.dumps(meta))
    print(f"\nDRILL {n:03d}: {d['title']}\n\n{d['task']}\n")
    print(f"Edit your answer:  nano {folder / 'solution.py'}")
    print(f"Then check it:     academy check {n}")

def find_drill(num):
    if num:
        f = DRILLS / f"{int(num):03d}"
    else:
        open_ = [x for x in sorted(DRILLS.glob("*")) if (x / "meta.json").exists() and not json.loads((x / "meta.json").read_text())["done"]]
        f = open_[-1] if open_ else None
    if not f or not (f / "meta.json").exists():
        print("No drill found. Start one with: academy drill")
        return None
    return f

def check(num=None):
    f = find_drill(num)
    if not f:
        return
    meta = json.loads((f / "meta.json").read_text())
    code = (f / "solution.py").read_text()
    ok, out = run_tests(f, code)
    if ok:
        print(f"ALL TESTS PASSED. Drill {f.name} complete!")
        if not meta["done"]:
            meta["done"] = True
            (f / "meta.json").write_text(json.dumps(meta))
            p = load()
            p["drills"] += 1
            p["topics"].setdefault(meta["topic"], {"xp": 0, "best_quiz": 0, "drills": 0})["drills"] += 1
            award(p, max(10, 30 - 5 * meta["hints"]), meta["topic"], "a drill")
        fb = ask("In 3 short lines, praise one strength of this beginner's working Python code and suggest "
                 "one improvement:\n" + code, model=C["judge"], temp=0.4)
        print("\nCoach:", fb.strip())
        return
    print("Not yet. Test output:\n" + out)
    meta["hints"] += 1
    (f / "meta.json").write_text(json.dumps(meta))
    hint = ask("You are a patient chess-coach style Python tutor. Give ONE short hint (max 3 lines) that "
               "points toward the bug WITHOUT writing the solution.\nTask:\n" + (f / "TASK.txt").read_text() +
               f"\nStudent code:\n{code}\nTest output:\n{out}", temp=0.3)
    print("\nHint:", hint.strip())

def solution(num=None):
    f = find_drill(num)
    if f:
        print(json.loads((f / "reference.json").read_text())["reference"])
        print("\n(Revealing the answer gives no XP for this drill.)")
        meta = json.loads((f / "meta.json").read_text())
        meta["hints"] = 99
        (f / "meta.json").write_text(json.dumps(meta))

# ---------- progress ----------
def progress():
    p = load()
    name, nxt = level(p["xp"])
    print(f"\nGOOGOLFORGE ACADEMY\nRank: {name}   XP: {p['xp']}" + (f"   next rank at {nxt}" if nxt else "   MAX RANK"))
    print(f"Streak: {p['streak']} day(s)   Lessons {p['lessons']}  Quizzes {p['quizzes']}  Drills {p['drills']}\n")
    for t in CURRICULUM:
        s = p["topics"].get(t, {"xp": 0, "best_quiz": 0, "drills": 0})
        bar = "#" * min(10, s["xp"] // 6) + "-" * (10 - min(10, s["xp"] // 6))
        print(f"  [{bar}] {t:<24} quiz {s['best_quiz']:>3}%  drills {s['drills']}")
    print("\nRecommended next: forge learn daily")

def daily():
    """One full Fischer-style training session: lesson, quiz, drill."""
    topic = topic_or_next([])
    print(f"=== DAILY TRAINING: {topic} ===")
    lesson(topic)
    quiz(topic)
    drill(topic)

def selftest():
    import tempfile
    fails = 0
    def chk(n, c):
        nonlocal fails
        print(("PASS " if c else "FAIL ") + n)
        fails += not c
    chk("level start", level(0)[0] == "Pawn")
    chk("level grandmaster", level(3000)[0] == "Grandmaster")
    chk("quiz validator rejects junk", valid_quiz({"questions": [{"q": 1}]}) == [])
    good = {"questions": [{"q": "x", "options": ["a", "b", "c", "d"], "answer": 1}] * 3}
    chk("quiz validator accepts good", len(valid_quiz(good)) == 3)
    with tempfile.TemporaryDirectory() as d:
        f = pathlib.Path(d)
        (f / "test_drill.py").write_text("from solution import *\nassert add(2,3)==5\nprint('ALL TESTS PASSED')\n")
        chk("tests pass correct code", run_tests(f, "def add(a,b): return a+b\n")[0])
        chk("tests fail wrong code", not run_tests(f, "def add(a,b): return a-b\n")[0])
        chk("tests catch infinite loop", not run_tests(f, "while True: pass\n")[0])
    print(f"\nSELFTEST: {'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
    return fails == 0

HELP = """Commands:
  academy daily            full session: lesson + quiz + drill on your next topic
  academy lesson [topic]   AI lesson (saved for offline reading)
  academy quiz [topic]     5-question quiz with explanations
  academy drill [topic]    verified coding exercise
  academy check [number]   test your drill answer, get a hint if it fails
  academy solution [num]   reveal the answer (no XP)
  academy progress         rank, XP, streak, topic map
  academy selftest         Academy checks itself
Topics follow the built-in Python path when you leave them blank."""

def main():
    ACAD.mkdir(parents=True, exist_ok=True)
    DRILLS.mkdir(parents=True, exist_ok=True)
    a = sys.argv[1:]
    cmd, rest = (a[0], a[1:]) if a else ("help", [])
    if cmd == "lesson":
        lesson(topic_or_next(rest))
    elif cmd == "quiz":
        quiz(topic_or_next(rest))
    elif cmd == "drill":
        drill(topic_or_next(rest))
    elif cmd == "check":
        check(rest[0] if rest else None)
    elif cmd == "solution":
        solution(rest[0] if rest else None)
    elif cmd == "progress":
        progress()
    elif cmd == "daily":
        daily()
    elif cmd == "selftest":
        sys.exit(0 if selftest() else 1)
    else:
        print(__doc__ + "\n" + HELP)

if __name__ == "__main__":
    main()
ACEOF
chmod +x ~/googolforge/academy.py
grep -q "googolforge/academy.py" ~/.bashrc 2>/dev/null || echo "alias academy='python ~/googolforge/academy.py'" >> ~/.bashrc
python ~/googolforge/academy.py selftest
echo "== Academy ready. Open a new Termux session, run forge-start, then: academy daily =="
echo "######## STEP D: Assistant v1.4 ########"
# GoogolForge Assistant v1.4 installer (run after install13.sh and academy_install.sh)
set -e
mkdir -p ~/googolforge
cat > ~/googolforge/assistant.py <<'ASEOF'
#!/usr/bin/env python3
"""GoogolForge Assistant v1.6 - talk to GoogolForge in plain English.
Two-layer router: fast rules first, then the AI. Every AI choice is checked
against a fixed command list before anything runs. Risky actions ask first."""
import json, os, pathlib, re, subprocess, sys, urllib.request
sys.dont_write_bytecode = True

HOME = pathlib.Path(os.environ.get("GF_HOME", str(pathlib.Path.home() / "googolforge")))
WORK = HOME / "workspace"
MEM = HOME / "chat_memory.json"
CONF = HOME / "config.json"
FORGE = HOME / "forge.py"
ACADEMY = HOME / "academy.py"
GF = HOME / "gf.py"
NOPROXY = urllib.request.build_opener(urllib.request.ProxyHandler({}))

# command: (program, needs, risky, description)
#   needs: none | text (a goal/topic/question) | file | number
CATALOG = {
    "pipeline": ("forge", "text", False, "build a whole project from a goal"),
    "plan":     ("forge", "text", False, "plan a project without building"),
    "run":      ("forge", "none", False, "build the planned tasks"),
    "status":   ("forge", "none", False, "show project progress"),
    "retry":    ("forge", "none", False, "reset failed tasks so they can run again"),
    "debug":    ("forge", "file", False, "find and fix bugs in a file"),
    "review":   ("forge", "file", False, "score a file with the judge AI"),
    "lint":     ("forge", "none", False, "check all code for errors"),
    "report":   ("forge", "none", False, "full project scorecard"),
    "export":   ("forge", "none", False, "zip the project to your phone"),
    "doctor":   ("forge", "none", False, "check the AI and models are ready"),
    "publish":  ("forge", "none", True,  "push to GitHub and your free website"),
    "ask":      ("forge", "text", False, "answer a coding question"),
    "daily":    ("academy", "none", False, "lesson + quiz + drill"),
    "lesson":   ("academy", "text?", False, "teach a Python topic"),
    "quiz":     ("academy", "text?", False, "quiz on a topic"),
    "drill":    ("academy", "text?", False, "coding exercise"),
    "check":    ("academy", "number?", False, "test your drill answer"),
    "solution": ("academy", "number?", True, "reveal a drill answer (no XP)"),
    "progress": ("academy", "none", False, "rank, XP and streak"),
    "bench":    ("gf", "none", False, "score the AI on hidden coding tests (quick)"),
    "shootout": ("gf", "none", True,  "rank every installed AI model (slow)"),
    "new":      ("gf", "template", False, "start a project from a template: game, cli, api, bot, data"),
    "path":     ("gf", "pathstep", False, "Season 2: today's mission (go = start, done = finish)"),
    "lessons":  ("gf", "none", False, "what the debugger has learned"),
    "health":   ("gf", "none", False, "self-test every GoogolForge system"),
    "mutate":   ("gf", "file", False, "plant bugs to see if your tests catch them"),
    "explain":  ("gf", "file", False, "explain a file line by line"),
    "index":    ("gf", "none", False, "build code memory of your project"),
    "rag":      ("gf", "text", False, "answer a question using your own code"),
    "team":     ("gf", "text", False, "Architect, Coder and Tester AIs build it together"),
    "duel":     ("gf", "duelstep", False, "you vs the AI on hidden tests (check = score it)"),
    "ci":       ("gf", "none", False, "set up the free GitHub cloud test robot"),
}
GF_ARGS = {"bench": ["bench", "--quick"], "shootout": ["shootout"], "lessons": ["lessons"], "health": ["test"]}
KINDS = {"game": "game", "cli": "cli", "todo": "cli", "to-do": "cli", "api": "api", "server": "api",
         "bot": "bot", "chatbot": "bot", "data": "data", "csv": "data", "stats": "data"}

RULES = [  # (regex, command, how to get the argument)
    (r"\b(mutat\w*|test my tests|how good are my tests)\b", "mutate", "file"),
    (r"\bexplain\b.*\.py\b|\bexplain (my|the|this)\b.*\b(code|file|program)\b|\bwalk me through\b", "explain", "file"),
    (r"\b(re)?index\b", "index", None),
    (r"\b(in|search|from) my (own )?(code|project)\b|\bwhere in my code\b", "rag", "goal"),
    (r"\b(ai )?team (build|make|create|code)\b|\bteam mode\b", "team", "teamgoal"),
    (r"\bduel\b", "duel", "duelstep"),
    (r"\b(cloud test\w*|test robot|github actions|ci)\b", "ci", None),
    (r"\b(what (have|did) (you|the debugger|it) learn\w*|repair memory|lessons learned|fix memory)\b", "lessons", None),
    (r"\b(test everything|check (all|everything)|all systems|system check|self.?test)\b", "health", None),
    (r"\b(shoot.?out|compare (the |all )?(ai )?models|best (ai )?model|which model)\b", "shootout", None),
    (r"\b(benchmark|bench|score the ai|how (good|smart) is the ai)\b", "bench", None),
    (r"\b(season ?2|season two|my path|30.?day|mission)\b", "path", "pathstep"),
    (r"\b(template|starter)\b|\bnew (game|cli|api|bot|chatbot|data|todo|to-do) (project|app|template)\b", "new", "template"),
    (r"\b(fix|debug|repair|broken|bug|error in|crash\w*|not working|doesn.?t work)\b", "debug", "file"),
    (r"\b(review|grade|score|rate)\b.*\b(code|file|\.py)\b", "review", "file"),
    (r"\b(publish|deploy|put .* online|go live|website live)\b", "publish", None),
    (r"\b(daily|today'?s (training|lesson|session)|train me)\b", "daily", None),
    (r"\b(my )?(progress|rank|xp|streak|level)\b", "progress", None),
    (r"\b(check|test) (my )?(drill|answer|solution)\b", "check", "number"),
    (r"\b(show|reveal|give)( me)? (the )?(answer|solution)\b", "solution", "number"),
    (r"\b(quiz|test me)\b", "quiz", "topic"),
    (r"\b(drill|exercise|practice|challenge)\b", "drill", "topic"),
    (r"\b(teach|lesson|explain how|learn about)\b", "lesson", "topic"),
    (r"\b(status|where am i|how far)\b", "status", None),
    (r"\b(report|scorecard|results)\b", "report", None),
    (r"\b(retry|try again|redo failed)\b", "retry", None),
    (r"\b(export|zip|backup|back up|save to (my )?phone)\b", "export", None),
    (r"\b(doctor|health check|is (the )?ai (ready|running))\b", "doctor", None),
    (r"\blint\b", "lint", None),
    (r"\b(continue|keep building|resume)\b", "run", None),
    (r"\b(build|make|create|write|code) (me )?(a|an|the|my)\b", "pipeline", "goal"),
    (r"^\s*(what|why|how|when|which|can|does|is|are)\b|\?\s*$", "ask", "goal"),
]


def conf():
    c = {"ollama": "http://127.0.0.1:11434", "coder": "qwen2.5-coder:1.5b", "judge": "llama3.2:1b"}
    if CONF.exists():
        try:
            c.update(json.loads(CONF.read_text()))
        except Exception:
            pass
    if os.environ.get("OLLAMA_URL"):
        c["ollama"] = os.environ["OLLAMA_URL"]
    return c


C = conf()


def ai(prompt, fmt=None, model=None):
    body = {"model": model or C["judge"], "prompt": prompt, "stream": False,
            "options": {"temperature": 0.1, "num_predict": 1536, "repeat_penalty": 1.1, "num_thread": int(C.get("threads", 5))}}
    if fmt:
        body["format"] = fmt
    req = urllib.request.Request(C["ollama"] + "/api/generate", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        with NOPROXY.open(req, timeout=300) as r:
            return json.loads(r.read())["response"]
    except Exception:
        return None


def parse_json(text):
    try:
        return json.loads(text)
    except Exception:
        m = re.search(r"\{.*\}", text or "", re.S)
        try:
            return json.loads(m.group(0)) if m else {}
        except Exception:
            return {}


# ---------- memory ----------
def mem_load():
    if MEM.exists():
        try:
            return json.loads(MEM.read_text())
        except Exception:
            pass
    return {"history": [], "last_file": "", "last_topic": ""}


def mem_save(m):
    m["history"] = m["history"][-20:]
    HOME.mkdir(parents=True, exist_ok=True)
    MEM.write_text(json.dumps(m, indent=2))


# ---------- argument helpers ----------
def find_file(text, m):
    hit = re.search(r"([\w\-/]+\.py)\b", text)
    if hit:
        name = pathlib.Path(hit.group(1)).name
        if (WORK / name).exists():
            return name
    files = sorted(WORK.glob("*.py"), key=lambda p: p.stat().st_mtime) if WORK.exists() else []
    if files:
        for f in files:  # a file named in plain words, e.g. "the calculator"
            if f.stem.lower() in text.lower():
                return f.name
    if m.get("last_file") and (WORK / m["last_file"]).exists():
        return m["last_file"]
    return files[-1].name if files else ""


def find_number(text):
    hit = re.search(r"\b(\d{1,3})\b", text)
    return hit.group(1) if hit else ""


FILLER = r"^(please |can you |could you |hey |ok |okay )*(build|make|create|write|code|teach|quiz|drill|give)( me)?( on| about)?( an| a| the)?\b\s*"


def find_topic(text):
    after = re.search(r"\b(?:on|about|for|with)\s+(.+)$", text, flags=re.I)
    if after:
        text = after.group(1)
    t = re.sub(r"\b(quiz|test me|drill|exercise|practice|challenge|lesson|teach me|teach|learn about|explain how)\b", " ", text, flags=re.I)
    t = re.sub(r"\b(please|me|a|an|on|about|in|some|give|python|to|do)\b", " ", t, flags=re.I)
    t = re.sub(r"[^\w\s]", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def find_template(text):
    low = text.lower()
    kind = next((v for k, v in KINDS.items() if re.search(r"\b" + re.escape(k) + r"\b", low)), "game")
    named = re.search(r"\b(?:called|named)\s+([a-z][\w\-]*)", low)
    name = re.sub(r"[^a-z0-9_]", "_", named.group(1)) if named else "my_" + kind
    return f"{kind} {name}"


def find_pathstep(text):
    low = text.lower()
    if re.search(r"\b(done|finished|complete[d]?|mark)\b", low):
        return "done"
    if re.search(r"\b(start|begin|go|let'?s)\b", low):
        return "go"
    return ""


def clean_goal(text):
    return re.sub(FILLER, "", text.strip(), flags=re.I).strip() or text.strip()


# ---------- routing ----------
def by_rules(text, m):
    low = text.lower()
    for pat, cmd, kind in RULES:
        if re.search(pat, low):
            arg = ""
            if kind == "file":
                arg = find_file(text, m)
            elif kind == "number":
                arg = find_number(text)
            elif kind == "topic":
                arg = find_topic(text)
            elif kind == "template":
                arg = find_template(text)
            elif kind == "pathstep":
                arg = find_pathstep(text)
            elif kind == "duelstep":
                arg = "check" if re.search(r"\b(check|score|done|finished|judge)\b", low) else ""
            elif kind == "teamgoal":
                arg = re.sub(r"^.*?\bteam (mode )?(build|make|create|code)?( me)?( an?| the)?\s*", "", text, flags=re.I).strip() or text.strip()
            elif kind == "goal":
                arg = clean_goal(text) if cmd == "pipeline" else text.strip()
            return {"command": cmd, "arg": arg, "via": "rules"}
    return None


def by_ai(text, m):
    menu = "\n".join(f"- {k}: {v[3]} (argument: {v[1]})" for k, v in CATALOG.items())
    recent = "\n".join(f"{h['you']} -> {h['cmd']}" for h in m["history"][-4:])
    files = ", ".join(p.name for p in sorted(WORK.glob("*.py"))[:15]) if WORK.exists() else ""
    out = ai("You route requests for a coding app. Pick exactly ONE command from this menu:\n" + menu +
             f"\nProject files: {files or 'none'}\nRecent:\n{recent or 'none'}\n"
             "Reply ONLY with JSON: {\"command\":\"name\",\"arg\":\"argument or empty\"}\n"
             "If unsure, use ask with the user's words as arg.\nRequest: " + text, fmt="json")
    d = parse_json(out)
    if not d:
        return None
    return {"command": str(d.get("command", "")).strip().lower(), "arg": str(d.get("arg", "")).strip(), "via": "ai"}


def validate(choice, text, m):
    """Layer two: the rule checker. Nothing outside the menu ever runs."""
    if not choice or choice["command"] not in CATALOG:
        return {"command": "ask", "arg": text.strip(), "via": "fallback"}
    need = CATALOG[choice["command"]][1]
    arg = re.sub(r"[\x00-\x1f]", " ", choice.get("arg", ""))[:300]
    if need == "file":
        name = pathlib.Path(arg).name if arg else ""
        if not name.endswith(".py") or not (WORK / name).exists():
            name = find_file(text, m)
        if not name:
            return {"command": "status", "arg": "", "via": choice["via"],
                    "note": "No code files yet. Build something first."}
        arg = name
    elif need.startswith("number"):
        arg = arg if arg.isdigit() else find_number(text)
    elif need == "template":
        parts = arg.lower().split()
        kind = KINDS.get(parts[0], "") if parts else ""
        name = re.sub(r"[^a-z0-9_]", "_", parts[1])[:40] if len(parts) > 1 else ""
        arg = f"{kind} {name or 'my_' + kind}" if kind else find_template(text)
    elif need == "duelstep":
        arg = "check" if arg.lower() == "check" else ""
    elif need == "pathstep":
        arg = arg.lower() if arg.lower() in ("go", "done") else find_pathstep(text)
    elif need == "text" and not arg:
        arg = text.strip()
    elif need == "none":
        arg = ""
    choice["arg"] = arg
    return choice


def route(text, m, use_ai=True):
    c = by_rules(text, m)
    if not c and use_ai:
        c = by_ai(text, m)
    return validate(c, text, m)


def command_line(c):
    prog, need, _, _ = CATALOG[c["command"]]
    if prog == "gf":
        base = [sys.executable, str(GF)]
        if c["command"] in GF_ARGS:
            return base + GF_ARGS[c["command"]]
        return base + [c["command"]] + (c["arg"].split() if c["arg"] else [])
    script = FORGE if prog == "forge" else ACADEMY
    args = [sys.executable, str(script), c["command"]]
    if c["arg"]:
        args += c["arg"].split() if need in ("text?",) else [c["arg"]]
    return args


def shown(c):
    prog = CATALOG[c["command"]][0]
    a = c["arg"]
    if a and " " in a:
        a = f'"{a}"'
    return f"{prog} {c['command']} {a}".strip()


def execute(c, m, text, dry=False):
    if c.get("note"):
        print(c["note"])
    print(f"-> {shown(c)}", flush=True)
    if CATALOG[c["command"]][2]:
        try:
            ok = input("This one's a big step. Run it? (y/n): ").strip().lower().startswith("y")
        except EOFError:
            ok = False
        if not ok:
            print("Skipped.")
            return
    m["history"].append({"you": text, "cmd": shown(c)})
    if CATALOG[c["command"]][1] == "file":
        m["last_file"] = c["arg"]
    mem_save(m)
    if dry:
        return
    try:
        subprocess.run(command_line(c))  # list form: no shell, no injection
    except KeyboardInterrupt:
        print("\nStopped.")


HELP = """Talk normally. Examples:
  build me a tip calculator          fix my calculator
  how's my project going?            review calculator.py
  quiz me on loops                   check my drill
  give me today's training           publish it
Type 'menu' for all commands, 'history' for recent ones, 'exit' to leave."""


def chat(dry=False):
    m = mem_load()
    print("GoogolForge Assistant. Tell me what you want in plain English.\n" + HELP)
    while True:
        try:
            text = input("\nyou> ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nSee you next session.")
            break
        if not text:
            continue
        low = text.lower()
        if low in ("exit", "quit", "bye", "q"):
            print("See you next session.")
            break
        if low in ("help", "?"):
            print(HELP)
            continue
        if low == "menu":
            for k, v in CATALOG.items():
                print(f"  {v[0]} {k:<9} {v[3]}")
            continue
        if low == "history":
            for h in m["history"][-10:]:
                print(f"  {h['you']}  ->  {h['cmd']}")
            continue
        execute(route(text, m), m, text, dry)


def selftest():
    import tempfile
    global WORK, MEM
    fails = 0

    def chk(name, cond):
        nonlocal fails
        print(("PASS " if cond else "FAIL ") + name)
        fails += not cond

    with tempfile.TemporaryDirectory() as d:
        WORK, MEM = pathlib.Path(d) / "workspace", pathlib.Path(d) / "mem.json"
        WORK.mkdir()
        (WORK / "calculator.py").write_text("x=1\n")
        (WORK / "game.py").write_text("y=2\n")
        m = mem_load()
        cases = [
            ("build me a tip calculator app", "pipeline", "tip calculator app"),
            ("fix my calculator", "debug", "calculator.py"),
            ("there's a bug in game.py", "debug", "game.py"),
            ("review calculator.py code", "review", "calculator.py"),
            ("how far along is my project", "status", ""),
            ("quiz me on loops", "quiz", "loops"),
            ("give me a drill on dictionaries", "drill", "dictionaries"),
            ("check my drill 3", "check", "3"),
            ("teach me recursion", "lesson", "recursion"),
            ("give me today's training", "daily", ""),
            ("what's my rank", "progress", ""),
            ("publish it", "publish", ""),
            ("back up my project", "export", ""),
            ("what is a list comprehension?", "ask", "what is a list comprehension?"),
            ("show me the solution", "solution", ""),
            ("my calculator keeps crashing", "debug", "calculator.py"),
            ("make an inventory tracker for my store", "pipeline", "inventory tracker for my store"),
            ("ready for practice on string methods", "drill", "string methods"),
            ("benchmark the ai", "bench", ""),
            ("which model is best?", "shootout", ""),
            ("give me a chatbot starter called helper", "new", "bot helper"),
            ("new todo app template", "new", "cli my_cli"),
            ("what's my season 2 mission", "path", ""),
            ("I finished today's mission", "path", "done"),
            ("let's start my 30-day path", "path", "go"),
            ("what have you learned from my bugs", "lessons", ""),
            ("check everything", "health", ""),
            ("how good are my tests in calculator.py", "mutate", "calculator.py"),
            ("explain my calculator code", "explain", "calculator.py"),
            ("index my project", "index", ""),
            ("in my code, where is the score saved?", "rag", "in my code, where is the score saved?"),
            ("team build a stopwatch app", "team", "stopwatch app"),
            ("start a duel", "duel", ""),
            ("check my duel", "duel", "check"),
            ("set up the cloud tests", "ci", ""),
        ]
        for text, cmd, arg in cases:
            r = route(text, m, use_ai=False)
            chk(f"'{text}' -> {cmd} {arg}".rstrip(), r["command"] == cmd and r["arg"] == arg)
        bad = validate({"command": "rm -rf", "arg": "/", "via": "ai"}, "delete everything", m)
        chk("unknown AI command falls back to ask", bad["command"] == "ask")
        inj = validate({"command": "debug", "arg": "../../etc/passwd; rm -rf ~", "via": "ai"}, "fix it", m)
        chk("bad file argument is replaced with a real project file", inj["arg"] in ("calculator.py", "game.py"))
        chk("risky commands are flagged", CATALOG["publish"][2] and CATALOG["solution"][2] and CATALOG["shootout"][2])
        t = validate({"command": "new", "arg": "rocket; rm -rf ~", "via": "ai"}, "make a game starter", m)
        chk("bad template argument is cleaned", t["arg"] == "game my_game")
        t = validate({"command": "new", "arg": "bot ../../evil", "via": "ai"}, "x", m)
        chk("template name can't escape the folder", t["arg"] == "bot ______evil")
        chk("duel step only allows check", validate({"command": "duel", "arg": "; rm", "via": "ai"}, "duel", m)["arg"] == "")
        chk("path step only allows go/done", validate({"command": "path", "arg": "rm", "via": "ai"}, "path", m)["arg"] == "")
        chk("gf commands build the right line", command_line({"command": "new", "arg": "game guess"})[-3:] == ["new", "game", "guess"]
            and command_line({"command": "bench", "arg": ""})[-2:] == ["bench", "--quick"])
        chk("commands run without a shell", isinstance(command_line({"command": "status", "arg": ""}), list))
        mem_save({"history": [{"you": "x", "cmd": "y"}] * 30, "last_file": "game.py", "last_topic": ""})
        chk("memory keeps the last 20 turns", len(mem_load()["history"]) == 20)
        chk("'fix it' remembers the last file", route("fix it", mem_load(), use_ai=False)["arg"] == "game.py")
    print(f"\nSELFTEST: {'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
    return fails == 0


def main():
    a = sys.argv[1:]
    if a and a[0] == "selftest":
        sys.exit(0 if selftest() else 1)
    if a and a[0] == "--dry":
        chat(dry=True)
    elif a:  # one-shot: forge chat "build me a game"
        m = mem_load()
        text = " ".join(a)
        execute(route(text, m), m, text)
    else:
        chat()


if __name__ == "__main__":
    main()
ASEOF
chmod +x ~/googolforge/assistant.py
if ! grep -q "googolforge/assistant.py" ~/.bashrc 2>/dev/null; then
cat >> ~/.bashrc <<'RCEOF'
# GoogolForge Assistant: "forge chat" or just "gf"
unalias forge 2>/dev/null
function forge {
  if [ "$1" = "chat" ]; then shift; python ~/googolforge/assistant.py "$@"
  else python ~/googolforge/forge.py "$@"; fi
}
alias gf='python ~/googolforge/assistant.py'
RCEOF
fi
python ~/googolforge/assistant.py selftest
echo "== Assistant ready. Open a new Termux session, run forge-start, then: forge chat  (or gf) =="
echo "######## STEP E: Dashboard v1.5 ########"
# GoogolForge Dashboard v1.5 installer (run after the Assistant installer)
set -e
pkg install -y termux-tools >/dev/null 2>&1 || true
mkdir -p ~/googolforge
cat > ~/googolforge/web.py <<'WEBEOF'
#!/usr/bin/env python3
"""GoogolForge Dashboard v1.7 - control GoogolForge from Chrome on your phone.
Private: listens only on 127.0.0.1 and every request needs a secret token.
Requests go through the Assistant's router and validator, so only menu commands run."""
import json, os, pathlib, secrets, subprocess, sys, threading, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
sys.dont_write_bytecode = True

HOME = pathlib.Path(os.environ.get("GF_HOME", str(pathlib.Path.home() / "googolforge")))
sys.path.insert(0, str(HOME))
import assistant as A  # noqa: E402

PORT = int(os.environ.get("GF_PORT", "8080"))
def saved_token():
    """One private token that survives restarts, so the home-screen app keeps working."""
    f = HOME / "web_token"
    try:
        t = f.read_text().strip()
        if len(t) >= 16:
            return t
    except Exception:
        pass
    t = secrets.token_urlsafe(16)
    try:
        HOME.mkdir(parents=True, exist_ok=True)
        f.write_text(t)
        os.chmod(f, 0o600)
    except Exception:
        pass
    return t


TOKEN = os.environ.get("GF_TOKEN") or saved_token()
ICON = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96"><rect width="96" height="96" rx="20" fill="#0d1117"/>'
        '<text x="48" y="62" font-size="44" text-anchor="middle" fill="#e3b341" font-family="sans-serif" '
        'font-weight="bold">GF</text></svg>')
SW = "self.addEventListener('fetch', e => {});"


def manifest():
    return {"name": "GoogolForge", "short_name": "GoogolForge", "display": "standalone",
            "background_color": "#0d1117", "theme_color": "#0d1117",
            "start_url": f"/?t={TOKEN}", "scope": "/",
            "icons": [{"src": f"/icon.svg?t={TOKEN}", "sizes": "any", "type": "image/svg+xml", "purpose": "any"}]}
JOBS, QUIZZES, LOCK = {}, {}, threading.Lock()
WEB_ONLY_TERMINAL = {"quiz"}          # handled by the page's own quiz screen
AUTO = {"run", "debug"}               # risky code still needs approval -> safely declined


def build_args(c):
    args = A.command_line(c)
    if c["command"] in AUTO:
        args.append("--auto")
    return args


def start_job(c, text):
    jid = secrets.token_hex(4)
    job = {"id": jid, "cmd": A.shown(c), "out": "", "done": False, "code": None, "started": time.time()}
    with LOCK:
        JOBS[jid] = job
        for old in sorted(JOBS.values(), key=lambda j: j["started"])[:-20]:
            JOBS.pop(old["id"], None)
    m = A.mem_load()
    m["history"].append({"you": text, "cmd": A.shown(c)})
    if A.CATALOG[c["command"]][1] == "file":
        m["last_file"] = c["arg"]
    A.mem_save(m)

    def work():
        env = dict(os.environ, PYTHONUNBUFFERED="1")
        try:
            p = subprocess.Popen(build_args(c), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 stdin=subprocess.DEVNULL, text=True, env=env)
            for line in p.stdout:
                with LOCK:
                    job["out"] = (job["out"] + line)[-60000:]
            job["code"] = p.wait()
        except Exception as e:
            job["out"] += f"\nCould not run: {e}"
            job["code"] = 1
        job["done"] = True

    threading.Thread(target=work, daemon=True).start()
    return job


def handle_request(body):
    """Core logic, separate from HTTP so it can be tested."""
    text = (body.get("text") or "").strip()[:500]
    if body.get("command"):
        c = A.validate({"command": str(body["command"]), "arg": str(body.get("arg", "")), "via": "button"},
                       text or str(body.get("arg", "")), A.mem_load())
    elif text:
        c = A.route(text, A.mem_load())
    else:
        return {"error": "Say what you want, or tap a button."}
    if c["command"] in WEB_ONLY_TERMINAL:
        return {"quiz": c["arg"] or "", "cmd": A.shown(c)}
    if A.CATALOG[c["command"]][2] and not body.get("confirm"):
        return {"confirm": True, "cmd": A.shown(c), "command": c["command"], "arg": c["arg"], "note": c.get("note", "")}
    job = start_job(c, text or A.shown(c))
    return {"job": job["id"], "cmd": job["cmd"], "note": c.get("note", "")}


def overview():
    o = {"goal": "", "done": 0, "total": 0, "files": [], "rank": "Pawn", "xp": 0, "streak": 0, "ai": False}
    try:
        st = json.loads((HOME / "tasks.json").read_text())
        o["goal"] = st.get("goal", "")
        o["total"] = len(st.get("tasks", []))
        o["done"] = sum(t.get("status") == "done" for t in st.get("tasks", []))
    except Exception:
        pass
    try:
        p = json.loads((HOME / "academy" / "progress.json").read_text())
        o["xp"], o["streak"] = p.get("xp", 0), p.get("streak", 0)
        for need, name in [(0, "Pawn"), (100, "Knight"), (300, "Bishop"), (600, "Rook"),
                           (1000, "Queen"), (1600, "King"), (2500, "Grandmaster")]:
            if o["xp"] >= need:
                o["rank"] = name
    except Exception:
        pass
    work = A.WORK
    if work.exists():
        o["files"] = [f.name for f in sorted(work.glob("*.py"), key=lambda f: -f.stat().st_mtime)][:12]
    try:
        with A.NOPROXY.open(A.C["ollama"] + "/api/tags", timeout=2):
            o["ai"] = True
    except Exception:
        pass
    return o


def make_quiz(topic):
    sys.path.insert(0, str(HOME))
    import academy as AC
    topic = topic or AC.topic_or_next([])
    for _ in range(3):
        qs = AC.valid_quiz(AC.parse_json(AC.ask(
            "Write a 5-question multiple choice quiz on this Python topic for a beginner. "
            "Reply ONLY with JSON: {\"questions\":[{\"q\":\"question\",\"options\":"
            "[\"a\",\"b\",\"c\",\"d\"],\"answer\":0,\"why\":\"one-line explanation\"}]} "
            "where answer is the index 0-3 of the correct option.\nTopic: " + topic, fmt="json")))
        if qs:
            qid = secrets.token_hex(4)
            QUIZZES[qid] = {"topic": topic, "questions": qs}
            for old in list(QUIZZES)[:-10]:
                QUIZZES.pop(old, None)
            return {"id": qid, "topic": topic, "questions": qs}
    return {"error": "The AI couldn't build a clean quiz. Tap again."}


def grade_quiz(body):
    """Grading happens on the server, so XP can't be faked from the page."""
    import academy as AC
    quiz = QUIZZES.pop(str(body.get("id", "")), None)
    if not quiz:
        return {"error": "Quiz expired. Start a new one."}
    qs, topic = quiz["questions"], quiz["topic"]
    picks = body.get("answers") or []
    score = sum(1 for q, a in zip(qs, picks) if str(a) == str(int(q["answer"])))
    if not qs:
        return {"error": "No quiz to grade."}
    pct = int(100 * score / len(qs))
    p = AC.load()
    p["quizzes"] += 1
    t = p["topics"].setdefault(topic, {"xp": 0, "best_quiz": 0, "drills": 0})
    t["best_quiz"] = max(t["best_quiz"], pct)
    AC.award(p, score * 5 + (15 if pct == 100 else 0), topic, "the quiz")
    return {"score": score, "total": len(qs), "pct": pct}


PAGE = r"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>GoogolForge</title><meta name="theme-color" content="#0d1117">
<link rel="manifest" id="mf"><link rel="icon" id="ic"><style>
:root{--bg:#0d1117;--card:#161b22;--line:#30363d;--txt:#e6edf3;--dim:#8b949e;--gold:#e3b341;--ok:#3fb950;--bad:#f85149}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--txt);font:16px system-ui,sans-serif}
header{padding:16px;border-bottom:1px solid var(--line)}h1{margin:0;font-size:20px;color:var(--gold)}
.sub{color:var(--dim);font-size:13px}main{padding:12px;max-width:720px;margin:auto}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px;margin-bottom:12px}
.stats{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;text-align:center}
.stats b{display:block;font-size:20px}.bar{height:8px;background:var(--line);border-radius:4px;overflow:hidden;margin-top:8px}
.bar i{display:block;height:100%;background:var(--gold)}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}
button{background:#21262d;color:var(--txt);border:1px solid var(--line);border-radius:10px;padding:12px 6px;font-size:14px}
button:active{background:#30363d}button.go{background:var(--gold);color:#000;border:0;font-weight:600}
.row{display:flex;gap:8px}input,select{flex:1;background:#0d1117;color:var(--txt);border:1px solid var(--line);border-radius:10px;padding:12px;font-size:16px}
pre{white-space:pre-wrap;word-break:break-word;background:#010409;border-radius:8px;padding:10px;font-size:13px;max-height:55vh;overflow:auto;margin:8px 0 0}
.dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px}.cmd{color:var(--gold);font-family:monospace;font-size:13px}
.q{margin:12px 0}.q label{display:block;padding:8px;border:1px solid var(--line);border-radius:8px;margin:6px 0}
.right{border-color:var(--ok)!important}.wrong{border-color:var(--bad)!important}h2{font-size:15px;margin:0 0 10px;color:var(--dim)}
</style></head><body>
<header><h1>GoogolForge</h1><div class="sub"><span id="ai" class="dot"></span><span id="ais">checking AI...</span></div></header>
<main>
<div class="card"><div id="goal" class="sub">No project yet</div><div class="bar"><i id="pbar" style="width:0"></i></div>
<div class="stats" style="margin-top:12px"><div><b id="prog">0/0</b><span class="sub">tasks</span></div>
<div><b id="rank">Pawn</b><span class="sub">rank</span></div><div><b id="xp">0</b><span class="sub">XP, streak <span id="streak">0</span></span></div></div></div>

<div class="card"><h2>Tell GoogolForge what you want</h2>
<div class="row"><input id="say" placeholder="build me a tip calculator" enterkeyhint="go"><button class="go" onclick="say()">Go</button></div></div>

<div class="card"><h2>Build</h2><div class="grid">
<button onclick="cmd('status')">Status</button><button onclick="cmd('run')">Keep building</button><button onclick="cmd('retry')">Retry failed</button>
<button onclick="cmd('report')">Report</button><button onclick="cmd('lint')">Check code</button><button onclick="cmd('doctor')">Health</button>
<button onclick="cmd('export')">Export zip</button><button onclick="cmd('publish')">Publish</button><button onclick="hist()">History</button></div>
<div class="row" style="margin-top:10px"><select id="file"><option value="">(no files yet)</option></select>
<button onclick="fcmd('debug')">Fix</button><button onclick="fcmd('review')">Review</button></div></div>

<div class="card"><h2>Learn</h2><div class="grid">
<button onclick="cmd('daily')">Daily lesson</button><button onclick="quiz('')">Quiz</button><button onclick="cmd('drill')">Drill</button>
<button onclick="cmd('check')">Check drill</button><button onclick="cmd('progress')">Progress</button><button onclick="cmd('lesson')">Lesson</button></div></div>
<div class="card"><h2>Level up</h2><div class="grid">
<button onclick="cmd('path')">Season 2</button><button onclick="cmd('path','done')">Mission done</button><button onclick="cmd('new','game my_game')">New game</button>
<button onclick="cmd('bench')">Benchmark</button><button onclick="cmd('shootout')">Shootout</button><button onclick="cmd('lessons')">Fix memory</button>
<button onclick="cmd('health')">Test all</button></div></div>
<div class="card"><h2>Pro tools</h2><div class="grid">
<button onclick="fcmd('mutate')">Test my tests</button><button onclick="fcmd('explain')">Explain file</button><button onclick="cmd('index')">Index my code</button>
<button onclick="cmd('duel')">Start duel</button><button onclick="cmd('duel','check')">Check duel</button><button onclick="cmd('ci')">Cloud tests</button></div>
<div class="sub">Team build: type "team build a stopwatch" above. Ask about your code: "in my code, where is the score saved?"</div></div>

<div class="card" id="outcard" style="display:none"><div class="cmd" id="outcmd"></div><pre id="out"></pre></div>
<div class="card" id="quizcard" style="display:none"></div>
</main><script>
const T=new URLSearchParams(location.search).get('t');let poll=null;
document.getElementById('mf').href='/manifest.json?t='+T;document.getElementById('ic').href='/icon.svg?t='+T;
if('serviceWorker' in navigator){navigator.serviceWorker.register('/sw.js?t='+T).catch(()=>{})}
async function api(path,body){const r=await fetch(path+(path.includes('?')?'&':'?')+'t='+T,body?{method:'POST',headers:{'Content-Type':'application/json','X-Token':T},body:JSON.stringify(body)}:{});return r.json()}
function show(c,txt){document.getElementById('outcard').style.display='';document.getElementById('outcmd').textContent=c;document.getElementById('out').textContent=txt;document.getElementById('outcard').scrollIntoView({behavior:'smooth'})}
async function send(b){const r=await api('/api/do',b);
 if(r.error)return show('',r.error);
 if(r.quiz!==undefined)return quiz(r.quiz);
 if(r.confirm){if(!confirm('This is a big step:\n'+r.cmd+'\nRun it?'))return show(r.cmd,'Skipped.');return send({command:r.command,arg:r.arg,confirm:true})}
 show('-> '+r.cmd,(r.note?r.note+'\n':'')+'Working...');watch(r.job,r.cmd)}
function watch(id,c){clearInterval(poll);poll=setInterval(async()=>{const j=await api('/api/job/'+id);
 show('-> '+c+(j.done?'  (finished)':'  (running)'),j.out||'Working...');const p=document.getElementById('out');p.scrollTop=p.scrollHeight;
 if(j.done){clearInterval(poll);refresh()}},1500)}
function say(){const v=document.getElementById('say').value.trim();if(v){send({text:v});document.getElementById('say').value=''}}
document.getElementById('say').addEventListener('keydown',e=>{if(e.key==='Enter')say()});
function cmd(c,a){send({command:c,arg:a||''})}
function fcmd(c){const f=document.getElementById('file').value;if(!f)return show('','Build something first.');send({command:c,arg:f})}
async function hist(){const h=await api('/api/history');show('history',h.map(x=>x.you+'  ->  '+x.cmd).join('\n')||'Nothing yet.')}
async function quiz(topic){const q=document.getElementById('quizcard');q.style.display='';q.innerHTML='<div class="sub">Building your quiz...</div>';q.scrollIntoView({behavior:'smooth'});
 const d=await api('/api/quiz',{topic});if(d.error){q.innerHTML='<div class="sub">'+d.error+'</div>';return}
 q.innerHTML='<h2>Quiz: '+esc(d.topic)+'</h2>'+d.questions.map((x,i)=>'<div class="q"><b>'+(i+1)+'. '+esc(x.q)+'</b>'+x.options.map((o,j)=>'<label id="l'+i+'_'+j+'"><input type="radio" name="q'+i+'" value="'+j+'"> '+esc(o)+'</label>').join('')+'<div class="sub" id="w'+i+'"></div></div>').join('')+'<button class="go" id="sub">Submit</button>';
 document.getElementById('sub').onclick=async()=>{const ans=d.questions.map((x,i)=>{const c=document.querySelector('input[name=q'+i+']:checked');return c?c.value:''});
  const g=await api('/api/grade',{id:d.id,answers:ans});if(g.error){q.insertAdjacentHTML('beforeend','<div class="sub">'+g.error+'</div>');return}
  d.questions.forEach((x,i)=>{document.getElementById('l'+i+'_'+x.answer).classList.add('right');if(ans[i]!==''&&ans[i]!=String(x.answer))document.getElementById('l'+i+'_'+ans[i]).classList.add('wrong');document.getElementById('w'+i).textContent=x.why||''});
  document.getElementById('sub').outerHTML='<div class="cmd">Score '+g.score+'/'+g.total+' ('+g.pct+'%)</div>';refresh()}}
function esc(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
async function refresh(){const o=await api('/api/overview');
 document.getElementById('ai').style.background=o.ai?'var(--ok)':'var(--bad)';document.getElementById('ais').textContent=o.ai?'AI ready':'AI off: run forge-start in Termux';
 document.getElementById('goal').textContent=o.goal?'Project: '+o.goal:'No project yet';document.getElementById('prog').textContent=o.done+'/'+o.total;
 document.getElementById('pbar').style.width=(o.total?100*o.done/o.total:0)+'%';document.getElementById('rank').textContent=o.rank;
 document.getElementById('xp').textContent=o.xp;document.getElementById('streak').textContent=o.streak;
 const s=document.getElementById('file'),cur=s.value;s.innerHTML=o.files.length?o.files.map(f=>'<option>'+esc(f)+'</option>').join(''):'<option value="">(no files yet)</option>';if(cur)s.value=cur}
refresh();setInterval(refresh,15000);
</script></body></html>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def ok(self, data, ctype="application/json", code=200):
        b = data if isinstance(data, bytes) else (json.dumps(data) if ctype == "application/json" else data).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Frame-Options", "DENY")
        self.end_headers()
        self.wfile.write(b)

    def authed(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        given = self.headers.get("X-Token") or (q.get("t") or [""])[0]
        return secrets.compare_digest(given, TOKEN)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if not self.authed():
            return self.ok("<h3>Locked. Open the link that <code>forge web</code> printed in Termux.</h3>", "text/html", 403)
        if path == "/":
            return self.ok(PAGE, "text/html")
        if path == "/manifest.json":
            return self.ok(json.dumps(manifest()), "application/manifest+json")
        if path == "/icon.svg":
            return self.ok(ICON, "image/svg+xml")
        if path == "/sw.js":
            return self.ok(SW, "text/javascript")
        if path == "/api/overview":
            return self.ok(overview())
        if path == "/api/history":
            return self.ok(A.mem_load()["history"][-15:])
        if path.startswith("/api/job/"):
            j = JOBS.get(path.rsplit("/", 1)[-1])
            return self.ok({"out": j["out"], "done": j["done"]} if j else {"out": "Job not found.", "done": True})
        self.ok({"error": "not found"}, code=404)

    def do_POST(self):
        if not self.headers.get("X-Token") or not secrets.compare_digest(self.headers.get("X-Token", ""), TOKEN):
            return self.ok({"error": "locked"}, code=403)
        try:
            body = json.loads(self.rfile.read(min(int(self.headers.get("Content-Length", 0)), 200000)) or b"{}")
        except Exception:
            return self.ok({"error": "bad request"}, code=400)
        path = urllib.parse.urlparse(self.path).path
        if path == "/api/do":
            return self.ok(handle_request(body))
        if path == "/api/quiz":
            return self.ok(make_quiz(str(body.get("topic", ""))[:80]))
        if path == "/api/grade":
            return self.ok(grade_quiz(body))
        self.ok({"error": "not found"}, code=404)


def serve():
    url = f"http://127.0.0.1:{PORT}/?t={TOKEN}"
    print("GoogolForge Dashboard is running (private to this phone).")
    print("Open this in Chrome (long-press it to copy):\n\n  " + url + "\n")
    print("Keep this Termux session open. Press Volume Down + C to stop.")
    try:
        subprocess.Popen(["termux-open-url", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()


def selftest():
    import tempfile, urllib.request, shutil
    global TOKEN, PORT
    fails = 0

    def chk(n, c):
        nonlocal fails
        print(("PASS " if c else "FAIL ") + n)
        fails += not c

    d = pathlib.Path(tempfile.mkdtemp())
    (d / "workspace").mkdir()
    (d / "workspace" / "calc.py").write_text("x=1\n")
    A.WORK, A.MEM = d / "workspace", d / "mem.json"
    TOKEN, PORT = "testtoken", 18080 + os.getpid() % 1000
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    op = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    base = f"http://127.0.0.1:{PORT}"

    def get(p, tok=True):
        try:
            with op.open(base + p + (("&" if "?" in p else "?") + "t=testtoken" if tok else "")) as r:
                return r.status, r.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, ""

    def post(p, b, tok="testtoken"):
        req = urllib.request.Request(base + p, data=json.dumps(b).encode(),
                                     headers={"Content-Type": "application/json", "X-Token": tok})
        try:
            with op.open(req) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, {}

    chk("page locked without token", get("/", tok=False)[0] == 403)
    s, body = get("/")
    chk("page opens with token", s == 200 and "GoogolForge" in body)
    chk("POST rejected with wrong token", post("/api/do", {"text": "status"}, tok="nope")[0] == 403)
    chk("overview works", json.loads(get("/api/overview")[1]).get("files") == ["calc.py"])
    r = post("/api/do", {"text": "publish it"})[1]
    chk("publish asks to confirm first", r.get("confirm") is True and "job" not in r)
    r = post("/api/do", {"command": "rm -rf", "arg": "/"})[1]
    chk("unknown command falls back to safe ask", r.get("cmd", "").startswith("forge ask"))
    r = post("/api/do", {"text": "quiz me on loops"})[1]
    chk("quiz goes to the web quiz screen", r.get("quiz") == "loops")
    r = post("/api/do", {"command": "debug", "arg": "../../etc/passwd"})[1]
    chk("file argument locked to project files", r.get("cmd") == "forge debug calc.py")
    chk("run and debug get --auto (risky code still declined)",
        build_args({"command": "debug", "arg": "calc.py"})[-1] == "--auto")
    job = start_job({"command": "status", "arg": ""}, "status")
    job["done"] = False
    chk("jobs are tracked", job["id"] in JOBS)
    chk("history saved", any(h["cmd"] == "forge status" for h in A.mem_load()["history"]))
    chk("text is HTML-escaped on the page", "function esc(" in PAGE and "innerHTML='<h2>Quiz: '+esc(" in PAGE)
    QUIZZES["q1"] = {"topic": "t", "questions": [{"q": "x", "options": ["a", "b", "c", "d"], "answer": 2}] * 3}
    import academy as AC
    AC.PROG = d / "prog.json"
    g = post("/api/grade", {"id": "q1", "answers": ["2", "2", "0"]})[1]
    chk("quiz graded on the server", g.get("score") == 2 and g.get("total") == 3)
    chk("a quiz can't be graded twice", "error" in post("/api/grade", {"id": "q1", "answers": ["2"] * 3})[1])
    srv.shutdown()
    shutil.rmtree(d, ignore_errors=True)
    print(f"\nSELFTEST: {'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
    return fails == 0


if __name__ == "__main__":
    if sys.argv[1:2] == ["selftest"]:
        sys.exit(0 if selftest() else 1)
    serve()
WEBEOF
chmod +x ~/googolforge/web.py
if ! grep -q "googolforge/web.py" ~/.bashrc 2>/dev/null; then
cat >> ~/.bashrc <<'RCEOF'
# GoogolForge Dashboard: "forge web"
unalias forge 2>/dev/null
function forge {
  case "$1" in
    chat) shift; python ~/googolforge/assistant.py "$@" ;;
    web)  shift; python ~/googolforge/web.py "$@" ;;
    *)    python ~/googolforge/forge.py "$@" ;;
  esac
}
RCEOF
fi
python ~/googolforge/web.py selftest
echo "== Dashboard ready. New Termux session: forge-start, then forge web =="

echo "######## STEP F: Auto-Publish v1.0 ########"
# GoogolForge Auto-Publish v1.0 installer (also updates publish.sh with privacy fixes)
set -e
mkdir -p ~/googolforge
cat > ~/googolforge/publish.sh <<'PUBEOF'
#!/data/data/com.termux/files/usr/bin/bash
# GoogolForge Objective 4: publish to GitHub + free website (GitHub Pages)
set -e
cd ~/googolforge || { echo "Run the v1.2 installer first."; exit 1; }
command -v gh >/dev/null && command -v git >/dev/null || pkg install -y gh git python curl
# 1. Sign in to GitHub (opens a one-time code flow the first time; auto mode never prompts)
if ! gh auth status >/dev/null 2>&1; then
  [ -n "$GF_AUTO" ] && { echo "Not signed in to GitHub. Run: gh auth login"; exit 3; }
  gh auth login -h github.com -p https -w
fi
LOGIN=$(gh api user -q .login)
UID_GH=$(gh api user -q .id)
git config user.name "$LOGIN"
git config user.email "${UID_GH}+${LOGIN}@users.noreply.github.com"
# 2. Keep private and bulky files out of the public repo
cat > .gitignore <<'GI'
ollama.log
progress.log
autopublish.log
chat_memory.json
config.json
academy/
*.bak
*.zip
.last_publish
.publish_out
.publock/
*.pyc
__pycache__/
web_token
code_index.json
*.pre-repairmem
GI
# Cloud test robot (GitHub Actions) - free for public repos
[ -f .github/workflows/forge-test.yml ] || python forge3.py ci >/dev/null 2>&1 || true
# Untrack private files that an older version may have pushed
git rm -r -q --cached --ignore-unmatch chat_memory.json config.json academy autopublish.log progress.log ollama.log web_token code_index.json >/dev/null 2>&1 || true
export GF_LOGIN="$LOGIN"
# 3. AI writes the tagline (local model, free); falls back if Ollama is off
mkdir -p docs
python - <<'PY'
import json, urllib.request, html, pathlib
tag = "Elite open-source AI, built move by move."
try:
    op = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    body = {"model": "llama3.2:1b", "stream": False, "options": {"temperature": 0.7},
            "prompt": "Write one bold tagline, under 12 words, no quotes, for GoogolForge AI Technologies, "
                      "a free open-source AI engine that plans, codes, tests and judges software."}
    req = urllib.request.Request("http://127.0.0.1:11434/api/generate", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    out = json.loads(op.open(req, timeout=120).read())["response"].strip().strip('"').splitlines()[0]
    if 3 < len(out) < 120:
        tag = out
except Exception:
    pass
divs = ["GoogolForge Master Foundation", "DragonForge AI", "Theban Arcana", "TeaForge AI",
        "GoogolForge Quantum", "GoogolForge Linux", "GoogolForge Academy",
        "GoogolForge Research Institute", "GoogolForge Security", "GoogolForge Cloud",
        "GoogolForge Commerce"]
cards = "".join(f"<li>{html.escape(d)}</li>" for d in divs)
import datetime, os
LOGIN = os.environ.get("GF_LOGIN", "")
ws = pathlib.Path("workspace")
builds = sorted(ws.glob("*.py"), key=lambda f: -f.stat().st_mtime)[:12] if ws.exists() else []
blist = "".join(f'<li><a href="https://github.com/{LOGIN}/googolforge/blob/main/workspace/{html.escape(f.name)}">{html.escape(f.name)}</a></li>' for f in builds) or "<li>First builds coming soon.</li>"
stamp = datetime.datetime.now().strftime("%B %d, %Y")
page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>GoogolForge AI Technologies</title>
<style>
body{{margin:0;font-family:system-ui,sans-serif;background:#0b0f1a;color:#e8ecf5;line-height:1.6}}
header{{padding:72px 24px 40px;text-align:center;background:radial-gradient(circle at top,#26324f,#0b0f1a)}}
h1{{font-size:2.4rem;margin:0}} .tag{{color:#f5b942;font-size:1.2rem}}
main{{max-width:760px;margin:auto;padding:24px}}
ul{{list-style:none;padding:0;display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px}}
li{{background:#151c2e;border:1px solid #2a3550;border-radius:10px;padding:14px}}
code{{background:#151c2e;padding:2px 6px;border-radius:4px}}
footer{{text-align:center;color:#7d8aa8;padding:32px;font-size:.9rem}}
</style></head><body>
<header><h1>GoogolForge AI Technologies</h1><p class="tag">{html.escape(tag)}</p></header>
<main>
<h2>Master Foundation v1.5: Elite Intelligence Engine</h2>
<p>Plans a goal, writes each piece with a local open-source AI, tests it, and has an independent AI judge sign off before it counts. Free, private, and runs on a phone. Includes GoogolForge Academy, a plain-English Assistant, and a browser Dashboard.</p>
<p>Try: <code>forge chat "build me a tip calculator"</code></p>
<h2>Latest builds</h2><ul>{blist}</ul>
<h2>The GoogolForge ecosystem</h2><ul>{cards}</ul>
</main><footer>&copy; GoogolForge AI Technologies &middot; updated {stamp}</footer></body></html>"""
pathlib.Path("docs/index.html").write_text(page)
pathlib.Path("README.md").write_text(
    "# GoogolForge Master Foundation v1.5\n\n" + tag + "\n\nFree, open-source AI engine: plan, code, test, judge.\n\n"
    "```\nforge plan \"your goal\"\nforge run\nforge status\n```\n")
print("Tagline:", tag)
PY
# 4. Commit and push
git branch -M main
git add -A
git commit -qm "GoogolForge: publish site and engine" || echo "Nothing new to commit"
if gh repo view "$LOGIN/googolforge" >/dev/null 2>&1; then
  git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$LOGIN/googolforge.git"
  git push -u origin main
else
  gh repo create googolforge --public --source=. --remote=origin --push \
    --description "GoogolForge AI Technologies - free open-source Elite Intelligence Engine"
fi
# 5. Turn on free hosting (GitHub Pages from /docs)
gh api -X POST "repos/$LOGIN/googolforge/pages" -f "source[branch]=main" -f "source[path]=/docs" >/dev/null 2>&1 \
  || echo "Pages already on (or will be in a minute)."
echo "== Live in 1 to 2 minutes: https://$LOGIN.github.io/googolforge/ =="
echo "== Code: https://github.com/$LOGIN/googolforge =="
PUBEOF
cat > ~/googolforge/autopublish.sh <<'APEOF'
#!/data/data/com.termux/files/usr/bin/bash
# GoogolForge Auto-Publish v1.0
#   forge autopublish on      check every 30 minutes, publish only clean new work
#   forge autopublish off     stop
#   forge autopublish status  on/off + last 8 log lines
#   forge autopublish now     publish right now (still runs the quality gate)
GF="$HOME/googolforge"; LOG="$GF/autopublish.log"; JOB="$GF/autopublish.sh run"
stamp() { date "+%Y-%m-%d %H:%M"; }
case "${1:-status}" in
  on)
    command -v crond >/dev/null || pkg install -y cronie termux-services
    ( crontab -l 2>/dev/null | grep -v "autopublish.sh"; echo "*/30 * * * * bash $JOB >> $LOG 2>&1" ) | crontab -
    sv-enable crond >/dev/null 2>&1 || pgrep crond >/dev/null || crond
    gh auth status >/dev/null 2>&1 || echo "Heads up: run  gh auth login  once, or nothing can publish."
    echo "Auto-publish ON: every 30 minutes, only when your code changed and passes checks."
    echo "Keep Termux running in the background (Settings > Apps > Termux > Battery > Unrestricted)." ;;
  off)
    crontab -l 2>/dev/null | grep -v "autopublish.sh" | crontab -
    echo "Auto-publish OFF." ;;
  status)
    crontab -l 2>/dev/null | grep -q "autopublish.sh" && echo "Auto-publish: ON" || echo "Auto-publish: OFF"
    [ -f "$LOG" ] && tail -n 8 "$LOG" || echo "No runs yet." ;;
  run|now)
    mkdir "$GF/.publock" 2>/dev/null || { echo "$(stamp) skipped: a publish is already running"; exit 0; }
    trap 'rmdir "$GF/.publock" 2>/dev/null' EXIT
    cd "$GF" || exit 1
    if ! gh auth status >/dev/null 2>&1; then echo "$(stamp) skipped: not signed in (run gh auth login)"; exit 0; fi
    HASH=$( { cat forge.py; ls workspace/*.py >/dev/null 2>&1 && cat workspace/*.py; } 2>/dev/null | sha256sum | cut -c1-16)
    if [ "$1" = "run" ] && [ "$HASH" = "$(cat .last_publish 2>/dev/null)" ]; then echo "$(stamp) no changes"; exit 0; fi
    # Quality gate: every file must compile; files with built-in tests must pass them
    BAD=""
    for f in workspace/*.py; do
      [ -e "$f" ] || continue
      python -B -m py_compile "$f" 2>/dev/null || { BAD="$BAD $(basename "$f")"; continue; }
      if grep -q "ALL TESTS PASSED" "$f"; then
        timeout 30 python -B "$f" </dev/null 2>/dev/null | grep -q "ALL TESTS PASSED" || BAD="$BAD $(basename "$f")"
      fi
    done
    if [ -n "$BAD" ]; then echo "$(stamp) held back: fix these first ->$BAD  (try: forge debug FILE)"; exit 0; fi
    termux-wake-lock 2>/dev/null || true
    if GF_AUTO=1 bash "$GF/publish.sh" > "$GF/.publish_out" 2>&1; then
      echo "$HASH" > .last_publish
      echo "$(stamp) published: $(grep -o 'https://[^ ]*github.io[^ ]*' .publish_out | head -1)"
    else
      echo "$(stamp) publish failed: $(tail -n 2 .publish_out | tr '\n' ' ')"
    fi
    rm -f .publish_out
    termux-wake-unlock 2>/dev/null || true ;;
  *) sed -n '2,6p' "$0" ;;
esac
APEOF
chmod +x ~/googolforge/publish.sh ~/googolforge/autopublish.sh
if ! grep -q "googolforge/autopublish.sh" ~/.bashrc 2>/dev/null; then
cat >> ~/.bashrc <<'RCEOF'
# GoogolForge: chat, web dashboard, auto-publish
unalias forge 2>/dev/null
function forge {
  case "$1" in
    chat) shift; python ~/googolforge/assistant.py "$@" ;;
    web)  shift; python ~/googolforge/web.py "$@" ;;
    autopublish) shift; bash ~/googolforge/autopublish.sh "$@" ;;
    *)    python ~/googolforge/forge.py "$@" ;;
  esac
}
RCEOF
fi
bash -n ~/googolforge/publish.sh && bash -n ~/googolforge/autopublish.sh && echo "Auto-publish installed. Turn it on with: forge autopublish on"

echo "######## STEP G: GoogolForge v2.0 launcher + Benchmark Arena ########"
# GoogolForge v2.0 installer: one launcher + Benchmark Arena
set -e
mkdir -p ~/googolforge
cat > ~/googolforge/bench.py <<'BENCHEOF'
#!/usr/bin/env python3
"""GoogolForge Benchmark Arena v1.4 (Genius style with Smart Router, Elite style, sealed hidden tests, Shootout, Hard mode, Team style) - turn "quality" into a number.
Ten fixed coding tasks with hidden tests. The coder model gets two tries per task
(the second sees the error, like the real engine). Scores are saved so every
model, prompt or version change is measured against the last one."""
import ast, datetime, json, os, pathlib, re, subprocess, sys, tempfile, time, urllib.request
sys.dont_write_bytecode = True

HOME = pathlib.Path(os.environ.get("GF_HOME", str(pathlib.Path.home() / "googolforge")))
HIST = HOME / "bench_history.json"
CONF = HOME / "config.json"
NOPROXY = urllib.request.build_opener(urllib.request.ProxyHandler({}))

# (name, level, spec, hidden tests)
TASKS = [
    ("reverse_words", 1, "def reverse_words(s): return the words of s in reverse order, joined by single spaces.",
     "assert reverse_words('a b c')=='c b a'\nassert reverse_words('hi')=='hi'\nassert reverse_words('  x   y ')=='y x'"),
    ("is_palindrome", 1, "def is_palindrome(s): True if s reads the same backwards, ignoring case, spaces and punctuation.",
     "assert is_palindrome('A man, a plan, a canal: Panama')\nassert not is_palindrome('hello')\nassert is_palindrome('')"),
    ("fizzbuzz", 1, "def fizzbuzz(n): return a list of strings for 1..n: 'Fizz' for multiples of 3, 'Buzz' for 5, 'FizzBuzz' for both, else the number as a string.",
     "assert fizzbuzz(5)==['1','2','Fizz','4','Buzz']\nassert fizzbuzz(15)[-1]=='FizzBuzz'\nassert fizzbuzz(0)==[]"),
    ("word_count", 2, "def word_count(text): return a dict mapping each lowercase word to how often it appears; words are letters only, ignore punctuation.",
     "assert word_count('Hi hi, there!')=={'hi':2,'there':1}\nassert word_count('')=={}"),
    ("flatten", 2, "def flatten(lst): flatten an arbitrarily nested list of lists into one flat list, keeping order.",
     "assert flatten([1,[2,[3,[4]]],5])==[1,2,3,4,5]\nassert flatten([])==[]\nassert flatten([[[]]])==[]"),
    ("roman", 2, "def to_roman(n): convert an integer 1..3999 to a Roman numeral string.",
     "assert to_roman(4)=='IV'\nassert to_roman(1994)=='MCMXCIV'\nassert to_roman(3999)=='MMMCMXCIX'"),
    ("merge_intervals", 3, "def merge_intervals(iv): given a list of [start, end] pairs, merge overlapping or touching ones and return them sorted.",
     "assert merge_intervals([[1,3],[2,6],[8,10]])==[[1,6],[8,10]]\nassert merge_intervals([[1,4],[4,5]])==[[1,5]]\nassert merge_intervals([])==[]"),
    ("balanced", 3, "def balanced(s): True if every (), [] and {} in s is properly opened and closed; other characters are ignored.",
     "assert balanced('{[()]}x')\nassert not balanced('(]')\nassert not balanced('((')\nassert balanced('')"),
    ("lru", 3, "class LRUCache: __init__(self, capacity); get(key) returns the value or -1; put(key, value) inserts and evicts the least recently used key when over capacity.",
     "c=LRUCache(2)\nc.put(1,1);c.put(2,2)\nassert c.get(1)==1\nc.put(3,3)\nassert c.get(2)==-1\nassert c.get(3)==3"),
    ("knight_moves", 3, "def knight_moves(start, end): minimum number of knight moves on an 8x8 chessboard between squares given like 'a1' and 'h8'.",
     "assert knight_moves('a1','a1')==0\nassert knight_moves('a1','b3')==1\nassert knight_moves('a1','h8')==6"),
]

HARD = [
    ("rpn_calc", 4, "def rpn(expr): evaluate a Reverse Polish Notation string of integers and + - * / (integer division truncating toward zero), e.g. '3 4 + 2 *' -> 14.",
     "assert rpn('3 4 + 2 *')==14\nassert rpn('7 2 /')==3\nassert rpn('-7 2 /')==-3\nassert rpn('5')==5"),
    ("tic_tac_toe", 4, "def winner(board): board is a list of 3 strings of 'X', 'O' or '.'; return 'X' or 'O' if that player has 3 in a row (rows, columns, diagonals), else None.",
     "assert winner(['XXX','OO.','...'])=='X'\nassert winner(['O..','.O.','..O'])=='O'\nassert winner(['X.O','X.O','..X']) is None\nassert winner(['..O','.O.','O..'])=='O'"),
    ("run_length", 4, "def encode(s) and def decode(s): run-length encoding like 'aaab' <-> '3a1b'; decode must reverse encode for any string of letters, counts may be more than 9.",
     "assert encode('aaab')=='3a1b'\nassert decode('3a1b')=='aaab'\nassert decode(encode('z'*12+'y'))=='z'*12+'y'\nassert encode('')==''"),
    ("matrix_spiral", 5, "def spiral(m): return the elements of a 2D list in clockwise spiral order starting top-left.",
     "assert spiral([[1,2,3],[4,5,6],[7,8,9]])==[1,2,3,6,9,8,7,4,5]\nassert spiral([[1,2],[3,4],[5,6]])==[1,2,4,6,5,3]\nassert spiral([])==[]\nassert spiral([[7]])==[7]"),
    ("topo_sort", 5, "def order(deps): deps maps each task to a list of tasks it depends on; return a list where every task comes after its dependencies, or raise ValueError if there is a cycle.",
     "r=order({'b':['a'],'c':['b'],'a':[]})\nassert r.index('a')<r.index('b')<r.index('c')\ntry:\n    order({'x':['y'],'y':['x']})\n    assert False\nexcept ValueError:\n    pass"),
    ("dijkstra", 5, "def shortest(graph, start, end): graph maps node -> dict of neighbor -> positive weight; return the smallest total weight from start to end, or -1 if unreachable.",
     "g={'A':{'B':1,'C':4},'B':{'C':2,'D':5},'C':{'D':1},'D':{}}\nassert shortest(g,'A','D')==4\nassert shortest(g,'D','A')==-1\nassert shortest(g,'A','A')==0"),
]


def conf():
    c = {"ollama": "http://127.0.0.1:11434", "coder": "qwen2.5-coder:1.5b"}
    if CONF.exists():
        try:
            c.update(json.loads(CONF.read_text()))
        except Exception:
            pass
    if os.environ.get("OLLAMA_URL"):
        c["ollama"] = os.environ["OLLAMA_URL"]
    return c


C = conf()


def ask(prompt, model):
    body = {"model": model, "prompt": prompt, "stream": False, "options": {"temperature": 0.1, "num_predict": 1536, "repeat_penalty": 1.1, "num_thread": int(C.get("threads", 5))}, "keep_alive": C.get("keep_alive", "30m")}
    req = urllib.request.Request(C["ollama"] + "/api/generate", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with NOPROXY.open(req, timeout=600) as r:
        return json.loads(r.read())["response"]


def extract(text):
    m = re.findall(r"```(?:python)?\n(.*?)```", text or "", re.S)
    return (max(m, key=len) if m else text or "").strip() + "\n"


def check(code, tests):
    with tempfile.TemporaryDirectory() as d:
        f = pathlib.Path(d) / "t.py"
        f.write_text(code + "\n" + tests + "\nprint('BENCH_OK')\n")
        try:
            r = subprocess.run([sys.executable, "-B", str(f)], capture_output=True, text=True,
                               timeout=15, stdin=subprocess.DEVNULL, cwd=d)
        except subprocess.TimeoutExpired:
            return False, "timed out"
        return "BENCH_OK" in r.stdout, (r.stderr or r.stdout)[-600:]


RULES = ("Standard library only, no input(), no prints, no example usage. "
         "Reply in one ```python block.\n")
STYLES = {
    "plain":  "Write ONLY the Python code for this. " + RULES,
    "expert": ("You are a senior Python engineer. Handle edge cases (empty input, single item, "
               "duplicates, boundaries). Write ONLY the code. " + RULES),
    "steps":  ("First list the edge cases in at most 3 short # comments, then write the code. " + RULES),
    "elite":  ("Write ONLY the Python code for this. " + RULES),
    "algo":   ("First name the classic algorithm or data structure that solves this in one # comment, "
               "then implement it carefully. " + RULES),
    "team":   ("You are the Coder on a team. Write ONLY the code and handle every edge case the Tester listed. " + RULES),
}
CANDIDATES = ["qwen2.5-coder:1.5b", "qwen2.5-coder:3b", "llama3.2:1b", "llama3.2:3b", "deepseek-coder:1.3b"]


def solve(spec, tests, model, asker=ask, style="plain"):
    prompt = STYLES.get(style, STYLES["plain"]) + spec
    if style == "team":  # a second model acts as Tester and lists edge cases first
        cases = asker("You are the Tester. List the 3 trickiest edge cases for this task, one short line each, "
                      "no code.\n" + spec, C.get("judge", model))
        prompt += "\nTester's edge cases:\n" + (cases or "")[:600]
    if style == "elite":
        return 1 if check(elite_code(spec, model, asker), tests)[0] else 0
    if style == "genius":
        return 1 if check(genius_code(spec, model, asker), tests)[0] else 0
    code = extract(asker(prompt, model))
    ok, err = check(code, tests)
    if ok:
        return 1
    # Sealed judge: the hidden tests never leak. The retry learns only the error TYPE.
    kind = (re.findall(r"^(\w+(?:Error|Exception)|AssertionError)", err, re.M) or ["a failed check"])[-1]
    code = extract(asker(prompt + f"\nYour last attempt failed a hidden test ({kind}). Re-read the task, "
                         f"check every edge case, and fix it.\nLast attempt:\n{code}", model))
    return 2 if check(code, tests)[0] else 0


def spec_tests(spec, model, asker):
    """The AI writes its OWN tests from the task text only (never sees the hidden tests)."""
    raw = asker("Write 6 Python assert statements that check a correct solution to this task, including edge "
                "cases (empty input, boundaries). Use exactly the function names in the task. Reply with only "
                "the asserts, one per line, no other code.\n" + spec, model)
    out = []
    for line in extract(raw).replace(", assert ", "\nassert ").splitlines():
        line = line.strip().rstrip(",;")
        try:
            t = ast.parse(line)
        except SyntaxError:
            continue
        if len(t.body) == 1 and isinstance(t.body[0], ast.Assert) and line not in out:
            out.append(line)
    return out[:8]


def self_score(code, asserts):
    """How many of the AI's own tests a candidate passes (each assert run on its own)."""
    if not asserts:
        return 0, ""
    passed, last = 0, ""
    for a in asserts:
        ok, err = check(code, a)
        passed += ok
        last = last if ok else f"{a}\n{err[-300:]}"
    return passed, last


def elite_code(spec, model, asker):
    """Elite style: 3 different drafts, AI-written spec tests pick the best, then up to 2 self-repairs."""
    drafts = [extract(asker(STYLES[s] + spec, model)) for s in ("plain", "expert", "steps")]
    mine = spec_tests(spec, model, asker)
    scored = sorted(((self_score(c, mine), i, c) for i, c in enumerate(drafts)), key=lambda x: (-x[0][0], x[1]))
    (best_n, fail), _, best = scored[0]
    for _ in range(2):
        if not mine or best_n == len(mine):
            break
        fixed = extract(asker(STYLES["plain"] + spec + f"\nThis attempt fails this check:\n{fail}\n"
                              "If the check itself contradicts the task, keep the code correct for the task.\n"
                              f"Attempt:\n{best}", model))
        n, f = self_score(fixed, mine)
        if n >= best_n:
            best, best_n, fail = fixed, n, f
    return best


def strong_model(model, lister=None):
    """The bigger coder the router escalates to: config 'strong', else qwen2.5-coder:3b if installed."""
    want = C.get("strong", "qwen2.5-coder:3b")
    if want == model:
        return None
    try:
        have = (lister or installed_models)()
    except Exception:
        return None
    return want if want in have else None


def pick(drafts, mine):
    """CodeT-style choice: tests passed first, then how many drafts behave the same way (agreement)."""
    sigs = []
    for c in drafts:
        sigs.append(tuple(check(c, a)[0] for a in mine) if mine else (check(c, "")[0],))
    best = None
    for i, (c, sg) in enumerate(zip(drafts, sigs)):
        key = (sum(sg), sigs.count(sg), -i)
        if best is None or key > best[0]:
            best = (key, c, sg)
    return best[1], best[0][0]


def hunt_tests(spec, model, asker):
    """Edge-Case Hunter (v3.4): the strongest model thinks like a tough examiner. It lists the trickiest
    edge cases as # comments, then writes asserts for normal AND edge cases from the task text only
    (the hidden tests stay sealed). Returns (edge_notes, asserts)."""
    raw = asker("You are a tough exam setter. First list the 4 trickiest edge cases of this task as # comments "
                "(think: empty input, single item, negative numbers, zero, multi-digit counts, ties, cycles, "
                "unreachable, boundaries). Then write 8 Python assert statements: 3 normal cases and at least "
                "one for each edge case. Work out every expected value by hand, following the task's exact "
                "rules. If the task has two functions that undo each other, add round-trip asserts like "
                "assert g(f(x)) == x. Use exactly the function names in the task. Reply with only the "
                "# comments and the asserts, one per line.\n" + spec, model) or ""
    edges = [ln.strip() for ln in raw.splitlines() if ln.strip().startswith("#")][:6]
    out = []
    for line in (extract(raw) + "\n" + raw).replace(", assert ", "\nassert ").splitlines():
        line = line.strip().rstrip(",;")
        if not line.startswith("assert"):
            continue
        try:
            t = ast.parse(line)
        except SyntaxError:
            continue
        if len(t.body) == 1 and isinstance(t.body[0], ast.Assert) and line not in out:
            out.append(line)
    return "\n".join(edges), out[:10]


def sane(asserts, drafts):
    """Drop a broken test: one that EVERY draft fails with NameError (wrong function name)."""
    keep = []
    for a in asserts:
        errs = [check(c, a) for c in drafts]
        if all((not ok) and "NameError" in (e or "") for ok, e in errs):
            continue
        keep.append(a)
    return keep


def genius_code(spec, model, asker, lister=None):
    """Genius style (v3.4, Edge-Case Hunter): Fischer-style preparation.
    1) 4 different opening drafts from the fast model (plain, expert, steps, algo).
    2) Spec tests written by the strongest model available (never sees hidden tests).
    3) CodeT choice: most self-tests passed, ties broken by agreement between drafts.
    4) Smart Router: if the best draft still fails its own tests, escalate to the strong model
       for 2 fresh drafts plus up to 2 sealed self-repairs."""
    strong = strong_model(model, lister)
    judge = strong or model
    drafts = [extract(asker(STYLES[s] + spec, model)) for s in ("plain", "expert", "steps", "algo")]
    edges, mine = hunt_tests(spec, judge, asker)
    mine = sane(mine, drafts)
    hint = ("\nEdge cases to handle:\n" + edges + "\n") if edges else ""
    best, n = pick(drafts, mine)
    if mine and n == len(mine):
        return best
    coder = strong or model
    if strong:
        drafts += [extract(asker(STYLES[s] + spec + hint, strong)) for s in ("expert", "algo")]
        best, n = pick(drafts, mine)
    for _ in range(2):
        if not mine or n == len(mine):
            break
        fail = self_score(best, mine)[1]
        fixed = extract(asker(STYLES["plain"] + spec + hint + f"\nThis attempt fails this check:\n{fail}\n"
                              "If the check itself contradicts the task, keep the code correct for the task.\n"
                              f"Attempt:\n{best}", coder))
        m = self_score(fixed, mine)[0]
        if m >= n:
            best, n = fixed, m
    return best


def run(model=None, quick=False, asker=ask, style="plain", quiet=False, hard=False):
    model = model or C["coder"]
    tasks = HARD if hard else (TASKS[:4] if quick else TASKS)
    say = (lambda *a, **k: None) if quiet else print
    say(f"BENCHMARK ARENA  model={model}  style={style}  tasks={len(tasks)}\n")
    first = second = 0
    t0 = time.time()
    rows = []
    for name, lvl, spec, tests in tasks:
        s = time.time()
        try:
            res = solve(spec, tests, model, asker, style)
        except Exception as e:
            say(f"AI call failed ({e}). Start it with: forge-start")
            return None
        first += res == 1
        second += res in (1, 2)
        mark = {1: "WIN  (1st try)", 2: "WIN  (after fix)", 0: "LOSS"}[res]
        say(f"  L{lvl} {name:<16} {mark:<17} {time.time() - s:5.1f}s")
        rows.append({"task": name, "result": res})
    n = len(tasks)
    score = round(100 * (first + 0.5 * (second - first)) / n)
    result = {"date": datetime.datetime.now().isoformat(timespec="minutes"), "model": model,
              "tasks": n, "first_try": first, "solved": second, "score": score,
              "seconds": round(time.time() - t0), "quick": quick, "hard": hard, "style": style, "rows": rows}
    hist = json.loads(HIST.read_text()) if HIST.exists() else []
    same = [h for h in hist if h["tasks"] == n and h["model"] == model and h.get("hard", False) == hard]
    best = max((h["score"] for h in same), default=None)
    hist.append(result)
    HOME.mkdir(parents=True, exist_ok=True)
    HIST.write_text(json.dumps(hist[-50:], indent=2))
    say(f"\nSolved {second}/{n} ({first} on the first try).  SCORE {score}/100  in {result['seconds']}s")
    if best is None:
        say("First run for this model recorded. Every future run is compared to it.")
    elif score > best:
        say(f"NEW RECORD! Previous best {best}.")
    else:
        say(f"Best so far: {best}.")
    return result


def installed_models():
    with NOPROXY.open(C["ollama"] + "/api/tags", timeout=10) as r:
        return [m["name"] for m in json.loads(r.read()).get("models", [])]


def pull(models=CANDIDATES):
    print("Downloading shootout candidates (use Wi-Fi; about 1 to 2 GB each):")
    for m in models:
        print(f"  ollama pull {m}")
        subprocess.run(["ollama", "pull", m])


def apply_winner(model):
    c = json.loads(CONF.read_text()) if CONF.exists() else {}
    old = c.get("coder", C["coder"])
    c["coder"] = model
    HOME.mkdir(parents=True, exist_ok=True)
    CONF.write_text(json.dumps(c, indent=2))
    print(f"Forge's coder model switched: {old} -> {model}  (undo: forge shootout use {old})")


def shootout(models=None, quick=True, styles=("plain",), apply=False, asker=ask, lister=installed_models):
    try:
        models = models or lister()
    except Exception as e:
        print(f"AI server not reachable ({e}). Start it with: forge-start")
        return []
    if not models:
        print("No models installed. Try: forge shootout pull")
        return []
    print(f"MODEL SHOOTOUT  {len(models)} model(s) x {len(styles)} style(s), {'quick 4' if quick else 'all 10'} tasks each\n")
    res = []
    for m in models:
        for st in styles:
            print(f"  running {m} / {st} ...", flush=True)
            r = run(m, quick, asker, st, quiet=True)
            if r:
                res.append(r)
    # rank: best score first; ties go to the model that is strong across ALL styles, then speed
    mean = {m: sum(r["score"] for r in res if r["model"] == m) / max(1, sum(r["model"] == m for r in res)) for m in models}
    res.sort(key=lambda r: (-r["score"], -mean.get(r["model"], 0), r["seconds"]))
    print(f"\n  {'#':<3}{'model':<24}{'style':<8}{'solved':<8}{'score':<7}time")
    for i, r in enumerate(res, 1):
        print(f"  {i:<3}{r['model']:<24}{r['style']:<8}{str(r['solved']) + '/' + str(r['tasks']):<8}{r['score']:<7}{r['seconds']}s")
    if not res:
        return res
    w = res[0]
    print(f"\nWINNER: {w['model']} with the '{w['style']}' style, score {w['score']}/100.")
    if any(r["model"] != w["model"] and r["score"] == w["score"] for r in res):
        print("Tie on top score; the winner is the model that did better across every style.")
    if apply:
        apply_winner(w["model"])
    elif w["model"] != C["coder"]:
        print(f"Forge currently uses {C['coder']}. Switch with: forge shootout --apply")
    return res


def history():
    hist = json.loads(HIST.read_text()) if HIST.exists() else []
    if not hist:
        print("No benchmark runs yet. Try: forge bench")
    for h in hist[-10:]:
        print(f"  {h['date']}  {h['model']:<24} {h['solved']}/{h['tasks']}  score {h['score']}")


def selftest():
    global HIST
    fails = 0

    def chk(n, c):
        nonlocal fails
        print(("PASS " if c else "FAIL ") + n)
        fails += not c

    chk("good code passes hidden tests", check("def reverse_words(s): return ' '.join(s.split()[::-1])", TASKS[0][3])[0])
    chk("wrong code fails hidden tests", not check("def reverse_words(s): return s", TASKS[0][3])[0])
    chk("infinite loop is stopped", not check("while True: pass", "")[0])
    chk("code is pulled from a reply", extract("Sure!\n```python\nx=1\n```") == "x=1\n")
    answers = {
        "reverse": "```python\ndef reverse_words(s): return ' '.join(s.split()[::-1])\n```",
        "palindrome": "```python\ndef is_palindrome(s):\n    t=[c.lower() for c in s if c.isalnum()]\n    return t==t[::-1]\n```",
    }

    def fake(prompt, model):
        if "reverse order" in prompt:
            return answers["reverse"]
        if "reads the same" in prompt:
            return answers["palindrome"] if "failed" in prompt else "```python\ndef is_palindrome(s): return s==s[::-1]\n```"
        return "```python\npass\n```"

    with tempfile.TemporaryDirectory() as d:
        HIST = pathlib.Path(d) / "h.json"
        r = run("fake", quick=True, asker=fake)
        chk("scores: 1 first-try win, 1 win after fix, 2 losses", r["first_try"] == 1 and r["solved"] == 2 and r["score"] == 38)
        chk("history saved", len(json.loads(HIST.read_text())) == 1)
    with tempfile.TemporaryDirectory() as d:
        HIST = pathlib.Path(d) / "h.json"
        global CONF
        oldconf, CONF = CONF, pathlib.Path(d) / "config.json"

        def fake2(prompt, model):  # 'big' solves everything, 'small' only after the expert hint
            good = answers["reverse"] if "reverse order" in prompt else answers["palindrome"] if "reads the same" in prompt else None
            if good and (model == "big" or "senior" in prompt):
                return good
            return "```python\npass\n```"
        r = shootout(None, True, ("plain", "expert"), True, fake2, lambda: ["small", "big"])
        chk("shootout ranks the stronger model first", r[0]["model"] == "big")
        chk("shootout measures prompt styles", any(x["model"] == "small" and x["style"] == "expert" and x["solved"] == 2 for x in r)
            and any(x["model"] == "small" and x["style"] == "plain" and x["solved"] == 0 for x in r))
        chk("--apply switches Forge to the winner", json.loads(CONF.read_text())["coder"] == "big")
        chk("no server gives a clear message", shootout(None, True, ("plain",), False, fake2, lambda: 1 / 0) == [])
        CONF = oldconf
    chk("all 10 reference tasks are solvable", all(check(REF[t[0]], t[3])[0] for t in TASKS))
    chk("all 6 hard tasks are solvable", all(check(REF[t[0]], t[3])[0] for t in HARD))
    seen = []

    def fake3(prompt, model):
        seen.append(prompt)
        return "- empty string\n- one word" if "Tester" in prompt and "trickiest" in prompt else answers["reverse"]
    def leaky(prompt, model):
        seen.append(prompt)
        return "```python\ndef reverse_words(s):\n    return s\n```"
    solve(TASKS[0][2], TASKS[0][3], "m", leaky, "plain")
    chk("sealed judge: hidden tests never leak into the retry", not any(TASKS[0][3].splitlines()[0][7:25] in p for p in seen))

    def fake_elite(prompt, model):
        if "assert statements" in prompt:
            return "assert reverse_words('a b')=='b a'\nassert reverse_words('x')=='x', assert reverse_words('')==''\nnot code"
        if "Think like" in prompt or "edge cases" in prompt:
            return answers["reverse"]
        return "```python\ndef reverse_words(s):\n    return s\n```"
    chk("elite style picks the draft that passes its own spec tests", solve(TASKS[0][2], TASKS[0][3], "m", fake_elite, "elite") == 1)
    chk("team style asks a Tester first and passes its edge cases on",
        solve(TASKS[0][2], TASKS[0][3], "m", fake3, "team") == 1 and "empty string" in seen[-1])
    calls = []
    C["strong"] = "big"
    def fake_router(prompt, model):
        calls.append(model)
        if "assert statements" in prompt:
            return "assert reverse_words('a b')=='b a'\nassert reverse_words('x')=='x'"
        if model == "big":
            return answers["reverse"]
        return "```python\ndef reverse_words(s):\n    return s\n```"
    chk("genius router escalates to the strong model when drafts fail",
        check(genius_code(TASKS[0][2], "small", fake_router, lambda: ["small", "big"]), TASKS[0][3])[0] and "big" in calls)
    calls.clear()
    def fake_easy(prompt, model):
        calls.append(model)
        if "assert statements" in prompt:
            return "assert reverse_words('a b')=='b a'"
        return answers["reverse"]
    genius_code(TASKS[0][2], "small", fake_easy, lambda: ["small", "big"])
    chk("genius router keeps easy tasks on the fast model", calls.count("big") == 1)
    chk("genius works with no strong model installed",
        check(genius_code(TASKS[0][2], "small", fake_easy, lambda: ["small"]), TASKS[0][3])[0])
    C.pop("strong", None)
    good, bad = extract(answers["reverse"]), "def reverse_words(s):\n    return s\n"
    chk("pick prefers the draft that passes more of its own tests",
        pick([bad, good, bad], ["assert reverse_words('a b')=='b a'"])[0] == good)
    chk("hunter reads edge notes and asserts from one answer",
        hunt_tests("t", "m", lambda p, m: "# empty string\n# one word\nassert reverse_words('')==''\nassert reverse_words('a b')=='b a'")
        == ("# empty string\n# one word", ["assert reverse_words('')==''", "assert reverse_words('a b')=='b a'"]))
    chk("sane() drops a test with the wrong function name",
        sane(["assert nope(1)==1", "assert reverse_words('a b')=='b a'"], [good]) == ["assert reverse_words('a b')=='b a'"])
    print(f"\nSELFTEST: {'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
    return fails == 0


REF = {  # known-good answers prove every hidden test is fair
    "reverse_words": "def reverse_words(s): return ' '.join(s.split()[::-1])",
    "is_palindrome": "def is_palindrome(s):\n    t=[c.lower() for c in s if c.isalnum()]\n    return t==t[::-1]",
    "fizzbuzz": "def fizzbuzz(n): return ['FizzBuzz' if i%15==0 else 'Fizz' if i%3==0 else 'Buzz' if i%5==0 else str(i) for i in range(1,n+1)]",
    "word_count": "import re\ndef word_count(text):\n    d={}\n    for w in re.findall('[a-z]+', text.lower()): d[w]=d.get(w,0)+1\n    return d",
    "flatten": "def flatten(l):\n    o=[]\n    for x in l: o+=flatten(x) if isinstance(x,list) else [x]\n    return o",
    "roman": "def to_roman(n):\n    v=[(1000,'M'),(900,'CM'),(500,'D'),(400,'CD'),(100,'C'),(90,'XC'),(50,'L'),(40,'XL'),(10,'X'),(9,'IX'),(5,'V'),(4,'IV'),(1,'I')]\n    s=''\n    for a,b in v:\n        while n>=a: s+=b; n-=a\n    return s",
    "merge_intervals": "def merge_intervals(iv):\n    o=[]\n    for a,b in sorted(iv):\n        if o and a<=o[-1][1]: o[-1][1]=max(o[-1][1],b)\n        else: o.append([a,b])\n    return o",
    "balanced": "def balanced(s):\n    p={')':'(',']':'[','}':'{'};st=[]\n    for c in s:\n        if c in '([{': st.append(c)\n        elif c in p:\n            if not st or st.pop()!=p[c]: return False\n    return not st",
    "lru": "from collections import OrderedDict\nclass LRUCache:\n    def __init__(s,c): s.c=c; s.d=OrderedDict()\n    def get(s,k):\n        if k not in s.d: return -1\n        s.d.move_to_end(k); return s.d[k]\n    def put(s,k,v):\n        s.d[k]=v; s.d.move_to_end(k)\n        if len(s.d)>s.c: s.d.popitem(last=False)",
    "rpn_calc": "def rpn(e):\n    st=[]\n    for t in e.split():\n        if t in '+-*/' :\n            b,a=st.pop(),st.pop()\n            st.append(a+b if t=='+' else a-b if t=='-' else a*b if t=='*' else int(a/b))\n        else: st.append(int(t))\n    return st[0]",
    "tic_tac_toe": "def winner(b):\n    L=[b[r] for r in range(3)]+[''.join(b[r][c] for r in range(3)) for c in range(3)]+[b[0][0]+b[1][1]+b[2][2],b[0][2]+b[1][1]+b[2][0]]\n    for p in 'XO':\n        if p*3 in L: return p\n    return None",
    "run_length": "import re\ndef encode(s):\n    return ''.join(str(len(m.group(0)))+m.group(1) for m in re.finditer(r'(.)\\1*', s))\ndef decode(s):\n    return ''.join(c*int(n) for n,c in re.findall(r'(\\d+)(\\D)', s))",
    "matrix_spiral": "def spiral(m):\n    o=[];m=[r[:] for r in m]\n    while m:\n        o+=m.pop(0)\n        m=[list(r) for r in zip(*m)][::-1]\n    return o",
    "topo_sort": "def order(d):\n    out=[];state={}\n    def visit(n):\n        if state.get(n)==1: raise ValueError('cycle')\n        if state.get(n)==2: return\n        state[n]=1\n        for x in d.get(n,[]): visit(x)\n        state[n]=2;out.append(n)\n    for n in d: visit(n)\n    return out",
    "dijkstra": "import heapq\ndef shortest(g,s,e):\n    pq=[(0,s)];best={s:0}\n    while pq:\n        d,n=heapq.heappop(pq)\n        if n==e: return d\n        if d>best.get(n,1e18): continue\n        for m,w in g.get(n,{}).items():\n            if d+w<best.get(m,1e18): best[m]=d+w;heapq.heappush(pq,(d+w,m))\n    return -1",
    "knight_moves": "def knight_moves(a,b):\n    from collections import deque\n    f=lambda q:(ord(q[0])-97,int(q[1])-1)\n    s,e=f(a),f(b);seen={s};dq=deque([(s,0)])\n    while dq:\n        (x,y),d=dq.popleft()\n        if (x,y)==e: return d\n        for dx,dy in [(1,2),(2,1),(-1,2),(-2,1),(1,-2),(2,-1),(-1,-2),(-2,-1)]:\n            n=(x+dx,y+dy)\n            if 0<=n[0]<8 and 0<=n[1]<8 and n not in seen: seen.add(n); dq.append((n,d+1))",
}

if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["selftest"]:
        sys.exit(0 if selftest() else 1)
    elif a[:1] == ["shootout"]:
        b = a[1:]
        if b[:1] == ["pull"]:
            pull(b[1:] or CANDIDATES)
        elif b[:1] == ["use"] and len(b) > 1:
            apply_winner(b[1])
        else:
            ms = [x for x in b if not x.startswith("--")]
            shootout(ms or None, "--full" not in b,
                     tuple(STYLES) if "--prompts" in b else ("plain",), "--apply" in b)
    elif a[:1] == ["history"]:
        history()
    else:
        rest = [x for x in a if not x.startswith("--")]
        style = "genius" if "--genius" in a else "elite" if "--elite" in a else "team" if "--team" in a else "plain"
        run(rest[0] if rest else None, "--quick" in a, style=style, hard="--hard" in a)
BENCHEOF
cat > ~/googolforge/gf.py <<'GFEOF'
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
  Bench+:    forge bench --genius (best)   forge bench --elite   forge bench --hard   forge bench --team
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
GFEOF
if ! grep -q "googolforge/gf.py" ~/.bashrc 2>/dev/null; then
cat >> ~/.bashrc <<'RCEOF'
# GoogolForge v2.0: one launcher for everything
unalias forge gf 2>/dev/null
function forge { python ~/googolforge/gf.py "$@"; }
function gf { python ~/googolforge/gf.py chat "$@"; }
RCEOF
fi
python ~/googolforge/gf.py version

echo "######## STEP H: v2.1 Self-Repair Memory, Templates, Season 2, Voice, Buttons ########"
# GoogolForge v2.1 expansion: Self-Repair Memory, Templates, Season 2, Voice, Home-screen buttons
set -e
mkdir -p ~/googolforge ~/.shortcuts
cat > ~/googolforge/repairmem.py <<'REPAIRMEM_PYEOF'
#!/usr/bin/env python3
"""GoogolForge Self-Repair Memory v1.0 - the debugger learns from every fix.
Each successful fix is saved as a lesson: the error's fingerprint plus the lines that changed.
When a similar error shows up later, the best past lessons go into the AI's prompt."""
import difflib, json, os, pathlib, re, sys
sys.dont_write_bytecode = True

HOME = pathlib.Path(os.environ.get("GF_HOME", str(pathlib.Path.home() / "googolforge")))
MEM = HOME / "repair_memory.json"
MAX = 200


def load():
    try:
        return json.loads(MEM.read_text())
    except Exception:
        return []


def save(items):
    HOME.mkdir(parents=True, exist_ok=True)
    MEM.write_text(json.dumps(items[-MAX:], indent=1))


def fingerprint(err):
    """Turn raw error output into (type, normalized words)."""
    lines = [l.strip() for l in (err or "").strip().splitlines() if l.strip()]
    last = ""
    for l in reversed(lines):
        if re.match(r"^[A-Za-z_][\w.]*(Error|Exception|Exit)\b", l) or l.startswith("AssertionError"):
            last = l
            break
    if not last:
        last = lines[-1] if lines else ""
    etype = re.match(r"^([\w.]+)", last).group(1) if re.match(r"^([\w.]+)", last) else "Unknown"
    msg = last[len(etype):]
    msg = re.sub(r"'[^']*'|\"[^\"]*\"", " Q ", msg)      # names and strings
    msg = re.sub(r"\d+", " N ", msg)                     # numbers
    words = sorted(set(w for w in re.findall(r"[a-zA-Z]+", msg.lower()) if len(w) > 1))
    return etype, words


def change_summary(before, after, limit=12):
    diff = [l for l in difflib.unified_diff((before or "").splitlines(), (after or "").splitlines(), lineterm="", n=0)
            if (l.startswith("+") or l.startswith("-")) and not l.startswith(("+++", "---"))]
    return "\n".join(diff[:limit])


def record(err, fname, before, after):
    etype, words = fingerprint(err)
    change = change_summary(before, after)
    if not change:
        return None
    items = load()
    items = [i for i in items if not (i["type"] == etype and i["words"] == words and i["change"] == change)]
    item = {"type": etype, "words": words, "file": fname, "change": change, "uses": 0}
    items.append(item)
    save(items)
    return item


def similar(err, k=3):
    etype, words = fingerprint(err)
    scored = []
    for i in load():
        if i["type"] != etype:
            continue
        a, b = set(words), set(i["words"])
        sim = len(a & b) / len(a | b) if (a | b) else 1.0
        if sim >= 0.3:
            scored.append((sim, i.get("uses", 0), i))
    scored.sort(key=lambda t: (-t[0], -t[1]))
    return [t[2] for t in scored[:k]]


def hints(err):
    found = similar(err)
    if not found:
        return ""
    items = load()
    for f in found:  # count how often each lesson is reused
        for i in items:
            if i == f:
                i["uses"] = i.get("uses", 0) + 1
    save(items)
    out = "\nPast fixes for similar errors in this project (use them if they apply):\n"
    for n, f in enumerate(found, 1):
        out += f"Fix {n} ({f['type']} in {f['file']}):\n{f['change']}\n"
    return out


def show():
    items = load()
    if not items:
        print("No repair lessons yet. They're saved automatically when forge debug or forge run fixes something.")
        return
    print(f"SELF-REPAIR MEMORY: {len(items)} lesson(s)\n")
    for i in items[-15:]:
        print(f"  {i['type']:<20} {i['file']:<18} used {i.get('uses', 0)}x   words: {' '.join(i['words'][:6])}")


def selftest():
    global MEM
    import tempfile
    fails = 0

    def chk(n, c):
        nonlocal fails
        print(("PASS " if c else "FAIL ") + n)
        fails += not c

    with tempfile.TemporaryDirectory() as d:
        MEM = pathlib.Path(d) / "m.json"
        e1 = 'Traceback...\n  File "a.py", line 3\nNameError: name \'totl\' is not defined'
        e2 = 'Traceback...\n  File "b.py", line 9\nNameError: name \'cnt\' is not defined'
        e3 = "TypeError: unsupported operand type(s) for +: 'int' and 'str'"
        chk("fingerprint ignores names and numbers", fingerprint(e1) == fingerprint(e2))
        chk("different errors differ", fingerprint(e1) != fingerprint(e3))
        chk("record saves the change", record(e1, "a.py", "x = totl + 1", "x = total + 1") is not None)
        chk("no change, no lesson", record(e1, "a.py", "same", "same") is None)
        chk("similar error finds the lesson", len(similar(e2)) == 1)
        chk("unrelated error finds nothing", similar(e3) == [])
        h = hints(e2)
        chk("hint contains the fix", "+x = total + 1" in h and "-x = totl + 1" in h)
        chk("reuse is counted", load()[0]["uses"] == 1)
        record(e1, "a.py", "x = totl + 1", "x = total + 1")
        chk("duplicates are not stored twice", len(load()) == 1)
        chk("assertion errors fingerprint", fingerprint("Traceback\nAssertionError")[0] == "AssertionError")
    print(f"\nSELFTEST: {'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
    return fails == 0


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["selftest"]:
        sys.exit(0 if selftest() else 1)
    elif a[:1] == ["clear"]:
        save([])
        print("Repair memory cleared.")
    else:
        show()
REPAIRMEM_PYEOF
cat > ~/googolforge/templates.py <<'TEMPLATES_PYEOF'
#!/usr/bin/env python3
"""GoogolForge Project Templates v1.0 - forge new <kind> <name>.
Every starter is a working program with its own self-tests, so forge debug, review,
the quality gate and auto-publish all work on it from minute one."""
import os, pathlib, re, subprocess, sys
sys.dont_write_bytecode = True

HOME = pathlib.Path(os.environ.get("GF_HOME", str(pathlib.Path.home() / "googolforge")))
WORK = HOME / "workspace"

T = {}
T["game"] = ('''"""{name}: number-guessing game. Play: python {name}.py --play"""
import random, sys

def hint(guess, secret):
    if guess < secret:
        return "higher"
    if guess > secret:
        return "lower"
    return "correct"

def score(tries, top=100):
    return max(0, top - (tries - 1) * 10)

def play(low=1, high=100):
    secret, tries = random.randint(low, high), 0
    print(f"Guess my number from {{low}} to {{high}}.")
    while True:
        try:
            g = int(input("guess> "))
        except ValueError:
            print("Numbers only.")
            continue
        tries += 1
        h = hint(g, secret)
        if h == "correct":
            print(f"Correct in {{tries}} tries! Score {{score(tries)}}")
            return tries
        print("Go", h)

if __name__ == "__main__":
    if "--play" in sys.argv:
        play()
    else:
        assert hint(3, 7) == "higher" and hint(9, 7) == "lower" and hint(7, 7) == "correct"
        assert score(1) == 100 and score(4) == 70 and score(50) == 0
        print("ALL TESTS PASSED")
''', "number-guessing game")

T["cli"] = ('''"""{name}: to-do list saved to a JSON file. Use: python {name}.py add "milk" | list | done 1"""
import json, pathlib, sys

FILE = pathlib.Path(__file__).with_suffix(".json")

def load(f=FILE):
    return json.loads(f.read_text()) if f.exists() else []

def save(items, f=FILE):
    f.write_text(json.dumps(items, indent=1))

def add(items, text):
    items.append({{"text": text.strip(), "done": False}})
    return items

def done(items, n):
    if not 1 <= n <= len(items):
        raise IndexError("no task number " + str(n))
    items[n - 1]["done"] = True
    return items

def show(items):
    return "\\n".join(f"{{i}}. [{{'x' if t['done'] else ' '}}] {{t['text']}}" for i, t in enumerate(items, 1)) or "(empty)"

if __name__ == "__main__":
    a = sys.argv[1:]
    if not a:
        it = done(add(add([], "a"), "b"), 2)
        assert show(it) == "1. [ ] a\\n2. [x] b"
        try:
            done(it, 5)
            assert False
        except IndexError:
            pass
        assert show([]) == "(empty)"
        print("ALL TESTS PASSED")
    else:
        items = load()
        if a[0] == "add":
            save(add(items, " ".join(a[1:])))
        elif a[0] == "done":
            save(done(items, int(a[1])))
        print(show(load()))
''', "to-do list app")

T["api"] = ('''"""{name}: tiny JSON web API (standard library). Run: python {name}.py --serve  then open http://127.0.0.1:8000/hello?name=Alex"""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs

NOTES = []

def handle(method, path, body=None):
    """Pure function: returns (status, data). Easy to test."""
    u = urlparse(path)
    q = parse_qs(u.query)
    if method == "GET" and u.path == "/hello":
        return 200, {{"message": "Hello, " + q.get("name", ["world"])[0] + "!"}}
    if method == "GET" and u.path == "/notes":
        return 200, {{"notes": NOTES}}
    if method == "POST" and u.path == "/notes":
        if not body or not str(body.get("text", "")).strip():
            return 400, {{"error": "text is required"}}
        NOTES.append(body["text"].strip())
        return 201, {{"saved": len(NOTES)}}
    return 404, {{"error": "not found"}}

class H(BaseHTTPRequestHandler):
    def send(self, code, data):
        b = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b)
    def do_GET(self):
        self.send(*handle("GET", self.path))
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        try:
            body = json.loads(self.rfile.read(n) or b"{{}}")
        except ValueError:
            return self.send(400, {{"error": "bad JSON"}})
        self.send(*handle("POST", self.path, body))

if __name__ == "__main__":
    if "--serve" in sys.argv:
        print("Serving on http://127.0.0.1:8000  (Ctrl+C to stop)")
        HTTPServer(("127.0.0.1", 8000), H).serve_forever()
    else:
        assert handle("GET", "/hello?name=Alex") == (200, {{"message": "Hello, Alex!"}})
        assert handle("POST", "/notes", {{"text": " hi "}}) == (201, {{"saved": 1}})
        assert handle("POST", "/notes", {{}})[0] == 400
        assert handle("GET", "/notes")[1] == {{"notes": ["hi"]}}
        assert handle("GET", "/nope")[0] == 404
        print("ALL TESTS PASSED")
''', "JSON web API")

T["bot"] = ('''"""{name}: rule-based chatbot. Chat: python {name}.py --chat"""
import re, sys

RULES = [
    (r"\\b(hi|hello|hey)\\b", "Hello! How can I help?"),
    (r"\\bname\\b", "I'm {name}, a GoogolForge bot."),
    (r"\\b(\\d+)\\s*([+*/-])\\s*(\\d+)\\b", None),
    (r"\\b(bye|goodbye)\\b", "Goodbye!"),
]

def calc(a, op, b):
    a, b = int(a), int(b)
    if op == "/" and b == 0:
        return "I can't divide by zero."
    return str({{"+": a + b, "-": a - b, "*": a * b, "/": round(a / b, 4)}}[op])

def reply(text):
    t = text.lower()
    for pat, ans in RULES:
        m = re.search(pat, t)
        if m:
            return ans if ans else calc(*m.groups())
    return "I don't know that yet. Teach me by adding a rule."

if __name__ == "__main__":
    if "--chat" in sys.argv:
        while True:
            try:
                msg = input("you> ")
            except EOFError:
                break
            r = reply(msg)
            print("bot>", r)
            if r == "Goodbye!":
                break
    else:
        assert reply("Hey there") == "Hello! How can I help?"
        assert reply("what is 6 * 7") == "42"
        assert reply("10/0") == "I can't divide by zero."
        assert reply("bye") == "Goodbye!"
        assert "don't know" in reply("tell me about quasars")
        print("ALL TESTS PASSED")
''', "rule-based chatbot")

T["data"] = ('''"""{name}: CSV statistics. Use: python {name}.py file.csv column"""
import csv, io, statistics, sys

def numbers(rows, col):
    out = []
    for r in rows:
        try:
            out.append(float(r[col]))
        except (KeyError, ValueError, TypeError):
            pass
    return out

def summary(nums):
    if not nums:
        return {{"count": 0}}
    return {{"count": len(nums), "min": min(nums), "max": max(nums),
            "mean": round(statistics.mean(nums), 3), "median": statistics.median(nums)}}

def read(text):
    return list(csv.DictReader(io.StringIO(text)))

if __name__ == "__main__":
    if len(sys.argv) == 3:
        with open(sys.argv[1], newline="") as f:
            print(summary(numbers(list(csv.DictReader(f)), sys.argv[2])))
    else:
        rows = read("name,score\\na,10\\nb,20\\nc,oops\\nd,30\\n")
        s = summary(numbers(rows, "score"))
        assert s == {{"count": 3, "min": 10.0, "max": 30.0, "mean": 20.0, "median": 20.0}}
        assert summary([]) == {{"count": 0}}
        assert numbers(rows, "missing") == []
        print("ALL TESTS PASSED")
''', "CSV statistics tool")


def new(kind, name):
    if kind not in T:
        print("Kinds:", ", ".join(f"{k} ({v[1]})" for k, v in T.items()))
        return None
    name = re.sub(r"[^a-z0-9_]", "_", (name or kind).lower()).strip("_") or kind
    if name[0].isdigit():
        name = "p_" + name
    WORK.mkdir(parents=True, exist_ok=True)
    f = WORK / f"{name}.py"
    if f.exists():
        print(f"{f.name} already exists. Pick another name.")
        return None
    f.write_text(T[kind][0].format(name=name))
    r = subprocess.run([sys.executable, "-B", str(f)], capture_output=True, text=True, timeout=20,
                       stdin=subprocess.DEVNULL, cwd=str(WORK))
    ok = "ALL TESTS PASSED" in r.stdout
    print(f"Created {f.name}: {T[kind][1]}. Self-tests: {'PASSED' if ok else 'FAILED'}")
    print(f"Next: forge review {f.name}   |   ask gf to add a feature   |   forge publish")
    return ok


def selftest():
    global WORK
    import tempfile
    fails = 0
    with tempfile.TemporaryDirectory() as d:
        WORK = pathlib.Path(d)
        for k in T:
            ok = new(k, "my " + k)
            print(("PASS " if ok else "FAIL ") + f"template {k} runs its own tests")
            fails += not ok
        dup = new("game", "my game") is None
        print(("PASS " if dup else "FAIL ") + "existing file is never overwritten")
        fails += not dup
        bad = new("rocket", "x") is None
        print(("PASS " if bad else "FAIL ") + "unknown kind is refused")
        fails += not bad
    print(f"\nSELFTEST: {'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
    return fails == 0


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["selftest"]:
        sys.exit(0 if selftest() else 1)
    new(a[0] if a else "", a[1] if len(a) > 1 else None)
TEMPLATES_PYEOF
cat > ~/googolforge/path.py <<'PATH_PYEOF'
#!/usr/bin/env python3
"""GoogolForge Academy Season 2: 30 Days to Your Own AI Tool.
Each day: one lesson, one verified drill, one build mission. Use: forge path | forge path go | forge path done"""
import datetime, json, os, pathlib, subprocess, sys
sys.dont_write_bytecode = True

HOME = pathlib.Path(os.environ.get("GF_HOME", str(pathlib.Path.home() / "googolforge")))
PROG = HOME / "academy" / "season2.json"

# (week theme, lesson/drill topic, build mission)
DAYS = [
    ("Week 1: Solid foundations", "variables, input and f-strings", "forge new game guess  then play it: python ~/googolforge/workspace/guess.py --play"),
    ("Week 1: Solid foundations", "lists and loops", 'gf: "add a high-score list to guess.py"'),
    ("Week 1: Solid foundations", "dictionaries", "forge new cli todo  then add 3 tasks"),
    ("Week 1: Solid foundations", "functions with return values", 'gf: "add a priority field to todo.py"'),
    ("Week 1: Solid foundations", "error handling with try/except", "forge debug todo.py  (break it on purpose first)"),
    ("Week 1: Solid foundations", "reading and writing files", 'forge pipeline "a diary app that saves entries to a file"'),
    ("Week 1: Solid foundations", "review week 1", "forge bench --quick  and note your score"),
    ("Week 2: Thinking like a programmer", "list comprehensions", "forge new data stats"),
    ("Week 2: Thinking like a programmer", "sorting with key functions", 'gf: "sort the todo list by priority"'),
    ("Week 2: Thinking like a programmer", "recursion", 'forge pipeline "a program that solves the Tower of Hanoi"'),
    ("Week 2: Thinking like a programmer", "searching: linear and binary search", "forge review stats.py"),
    ("Week 2: Thinking like a programmer", "testing with assert", "add 3 new asserts to any of your files, then forge test"),
    ("Week 2: Thinking like a programmer", "classes and objects", 'forge pipeline "a bank account class with deposits and withdrawals"'),
    ("Week 2: Thinking like a programmer", "review week 2", "forge publish  (or let autopublish do it)"),
    ("Week 3: Building real tools", "modules and imports", "split one of your programs into two files"),
    ("Week 3: Building real tools", "regular expressions", "forge new bot helper  then teach it 3 new rules"),
    ("Week 3: Building real tools", "JSON data", "forge new api notes"),
    ("Week 3: Building real tools", "HTTP basics: requests and responses", "run notes.py --serve and open it in Chrome"),
    ("Week 3: Building real tools", "dates and times with datetime", 'gf: "add due dates to todo.py"'),
    ("Week 3: Building real tools", "command-line arguments with sys.argv", 'forge pipeline "a unit converter that works from the command line"'),
    ("Week 3: Building real tools", "review week 3", "forge shootout  and keep the winner"),
    ("Week 4: Your own AI tool", "what a language model is: prompts and tokens", "forge ask \"explain tokens like I'm new\""),
    ("Week 4: Your own AI tool", "calling a local AI API with urllib", 'forge pipeline "a script that sends a question to Ollama and prints the answer"'),
    ("Week 4: Your own AI tool", "prompt design", "write 3 prompts for the same task and compare the answers"),
    ("Week 4: Your own AI tool", "parsing AI output safely", "add JSON parsing with error handling to your Ollama script"),
    ("Week 4: Your own AI tool", "testing AI programs", "add a mock AI function so your script has offline tests"),
    ("Week 4: Your own AI tool", "designing your capstone", 'pick one: AI study buddy, AI recipe helper, or AI code explainer'),
    ("Week 4: Your own AI tool", "building the capstone, part 1", "forge pipeline \"<your capstone>\""),
    ("Week 4: Your own AI tool", "building the capstone, part 2", "forge review + forge debug until it's clean"),
    ("Graduation", "review everything", "forge publish  your capstone, then forge bench to see how far you've come"),
]


def load():
    try:
        return json.loads(PROG.read_text())
    except Exception:
        return {"day": 1, "completed": {}}


def save(p):
    PROG.parent.mkdir(parents=True, exist_ok=True)
    PROG.write_text(json.dumps(p, indent=1))


def today(p=None):
    p = p or load()
    d = min(p["day"], len(DAYS))
    week, topic, build = DAYS[d - 1]
    bar = "#" * (len(p["completed"])) + "-" * (len(DAYS) - len(p["completed"]))
    print(f"SEASON 2: 30 Days to Your Own AI Tool    [{bar}] {len(p['completed'])}/30")
    if len(p["completed"]) >= len(DAYS):
        print("\nGRADUATED! You built and published your own AI tool. Grandmaster work.")
        return
    print(f"\nDay {d}  |  {week}")
    print(f"  1. Learn:  forge learn lesson \"{topic}\"")
    print(f"  2. Drill:  forge learn drill \"{topic}\"   then  forge learn check")
    print(f"  3. Build:  {build}")
    print("\nShortcut: forge path go (starts step 1).  Finished all 3? forge path done")


def done(p=None, date=None):
    p = p or load()
    if len(p["completed"]) >= len(DAYS):
        print("Season complete already.")
        return p
    d = p["day"]
    p["completed"][str(d)] = (date or datetime.date.today()).isoformat()
    p["day"] = d + 1
    save(p)
    print(f"Day {d} complete! {len(p['completed'])}/30.")
    if len(p["completed"]) < len(DAYS):
        print(f"Tomorrow: {DAYS[d][1]}")
    else:
        print("That was the final day. You graduated!")
    return p


def go():
    p = load()
    if len(p["completed"]) >= len(DAYS):
        return today(p)
    topic = DAYS[min(p["day"], len(DAYS)) - 1][1]
    subprocess.run([sys.executable, "-B", str(HOME / "academy.py"), "lesson", topic])


def selftest():
    global PROG
    import tempfile
    fails = 0

    def chk(n, c):
        nonlocal fails
        print(("PASS " if c else "FAIL ") + n)
        fails += not c

    chk("exactly 30 days", len(DAYS) == 30)
    chk("every day has a topic and a mission", all(t and b for _, t, b in DAYS))
    with tempfile.TemporaryDirectory() as dd:
        PROG = pathlib.Path(dd) / "s2.json"
        p = load()
        chk("starts on day 1", p["day"] == 1)
        p = done(p)
        chk("done advances and saves", load()["day"] == 2 and "1" in load()["completed"])
        for _ in range(40):
            p = done(p)
        chk("stops at graduation", len(load()["completed"]) == 30)
    print(f"\nSELFTEST: {'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
    return fails == 0


if __name__ == "__main__":
    a = sys.argv[1:]
    cmd = a[0] if a else "today"
    if cmd == "selftest":
        sys.exit(0 if selftest() else 1)
    elif cmd == "done":
        done()
    elif cmd == "go":
        go()
    elif cmd == "reset":
        save({"day": 1, "completed": {}})
        print("Season 2 reset to day 1.")
    else:
        today()
PATH_PYEOF
cat > ~/googolforge/patch_forge.py <<'PATCH_FORGE_PYEOF'
#!/usr/bin/env python3
"""Wire Self-Repair Memory into forge.py (safe to run twice)."""
import pathlib, sys

p = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path.home() / "googolforge" / "forge.py")
s = p.read_text()
if "# GF-REPAIRMEM" in s:
    print("forge.py already has Self-Repair Memory")
    sys.exit(0)
EDITS = [
    ("NOPROXY = urllib.request.build_opener(urllib.request.ProxyHandler({}))\n",
     "NOPROXY = urllib.request.build_opener(urllib.request.ProxyHandler({}))\n"
     "# GF-REPAIRMEM\ntry:\n    sys.path.insert(0, str(HOME))\n    import repairmem\nexcept Exception:\n    repairmem = None\n"),
    ('        prompt += "\\nThe previous attempt failed. Fix these problems:\\n" + feedback[-1500:]\n',
     '        prompt += "\\nThe previous attempt failed. Fix these problems:\\n" + feedback[-1500:]\n'
     '        prompt += repairmem.hints(feedback) if repairmem else ""\n'),
    ('        for attempt in range(1, int(C["tries"]) + 1):\n            task["tries"] += 1\n',
     '        prev_code = prev_err = None\n'
     '        for attempt in range(1, int(C["tries"]) + 1):\n            task["tries"] += 1\n'),
    ('                feedback = "Tests failed:\\n" + out\n                log(f"  attempt {attempt}: tests FAILED")\n',
     '                feedback = "Tests failed:\\n" + out\n                log(f"  attempt {attempt}: tests FAILED")\n'
     '                prev_code, prev_err = code, out\n'),
    ('                task.update(status="done", score=score, notes=reasons)\n',
     '                task.update(status="done", score=score, notes=reasons)\n'
     '                if repairmem and prev_code:\n'
     '                    repairmem.record(prev_err, task["file"], prev_code, code)\n'
     '                    log("  lesson saved to Self-Repair Memory")\n'),
    ('        log(f"DEBUG {path.name} attempt {attempt}: error found, asking AI to fix")\n',
     '        log(f"DEBUG {path.name} attempt {attempt}: error found, asking AI to fix")\n'
     '        first_err = out if attempt == 1 else first_err\n'),
    ('                  f"Error output:\\n{out[-1500:]}\\nCode:\\n{code}")\n',
     '                  f"Error output:\\n{out[-1500:]}\\nCode:\\n{code}")\n'
     '        prompt += repairmem.hints(out) if repairmem else ""\n'),
    ('            git_commit(f"Debugged {path.name}")\n            return\n',
     '            if repairmem:\n                repairmem.record(first_err, path.name, original, code)\n'
     '            git_commit(f"Debugged {path.name}")\n            return\n'),
    ('        log(f"DEBUG {path.name}: fixed on final attempt")\n',
     '        log(f"DEBUG {path.name}: fixed on final attempt")\n'
     '        if repairmem:\n            repairmem.record(first_err, path.name, original, path.read_text())\n'),
]
for old, new in EDITS:
    if s.count(old) != 1:
        print("Patch point not found; forge.py left unchanged:", old.strip()[:60])
        sys.exit(1)
    s = s.replace(old, new)
compile(s, str(p), "exec")
p.with_suffix(".py.pre-repairmem").write_text(p.read_text())
p.write_text(s)
print("Self-Repair Memory wired into forge.py (backup: forge.py.pre-repairmem)")
PATCH_FORGE_PYEOF
cat > ~/googolforge/gf.py <<'GF_PYEOF'
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
  Bench+:    forge bench --hard   forge bench --team
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
GF_PYEOF
cat > ~/googolforge/voice.sh <<'VOICE_SHEOF'
#!/data/data/com.termux/files/usr/bin/bash
# GoogolForge Voice v1.0: speak a command, the Assistant runs it, the phone answers out loud.
# Needs the Termux:API app (F-Droid) + pkg install termux-api, and the mic permission.
GF="$HOME/googolforge"
say() { echo "$1"; command -v termux-tts-speak >/dev/null && termux-tts-speak "$1" 2>/dev/null; }
if ! command -v termux-speech-to-text >/dev/null; then
  echo "Voice needs Termux:API."
  echo "1) Install the Termux:API app from F-Droid (same source as Termux)"
  echo "2) Run: pkg install -y termux-api"
  echo "3) Run forge voice again and allow the microphone"
  exit 1
fi
LOOP=0; [ "$1" = "--loop" ] && LOOP=1
while true; do
  say "Listening."
  TEXT="$(termux-speech-to-text 2>/dev/null | tr -d '\r' | tail -n 1)"
  if [ -z "$TEXT" ]; then
    say "I didn't catch that."
  else
    echo "you said> $TEXT"
    case "$(echo "$TEXT" | tr 'A-Z' 'a-z')" in
      stop|exit|quit|goodbye|"stop listening") say "Goodbye."; exit 0;;
    esac
    python "$GF/assistant.py" "$TEXT"
    say "Done."
  fi
  [ "$LOOP" = 1 ] || break
done
VOICE_SHEOF
chmod +x ~/googolforge/voice.sh
python ~/googolforge/patch_forge.py ~/googolforge/forge.py || echo "Note: Self-Repair Memory hooks skipped (forge.py differs from v1.3)."
pkg install -y termux-api >/dev/null 2>&1 || true
# Home-screen buttons (Termux:Widget app from F-Droid shows these)
for pair in "GF-Chat:chat" "GF-Dashboard:web" "GF-Daily:learn daily" "GF-Season2:path" "GF-Bench:bench --quick" "GF-Voice:voice"; do
  name="${pair%%:*}"; args="${pair#*:}"
  printf '#!/data/data/com.termux/files/usr/bin/bash\npgrep -f "ollama serve" >/dev/null || (ollama serve >/dev/null 2>&1 &)\nsleep 1\npython ~/googolforge/gf.py %s\necho; read -p "Press Enter to close" _\n' "$args" > ~/.shortcuts/"$name"
  chmod +x ~/.shortcuts/"$name"
done
python ~/googolforge/gf.py version

echo "######## STEP J: v3.0 Pro tools, cloud tests, plugins, installable Dashboard ########"
mkdir -p ~/googolforge/plugins
cat > ~/googolforge/forge3.py <<'FORGE3EOF'
#!/usr/bin/env python3
"""GoogolForge v3.0 Pro Tools: explain, mutate, memory (RAG), team, duel, ci.
All free and offline. Every AI step is checked by real tests wherever possible."""
import ast, copy, json, math, os, pathlib, random, re, subprocess, sys, tempfile, urllib.request
sys.dont_write_bytecode = True

HOME = pathlib.Path(os.environ.get("GF_HOME", str(pathlib.Path.home() / "googolforge")))
WORK = HOME / "workspace"
CONF = HOME / "config.json"
INDEX = HOME / "code_index.json"
DUEL = HOME / "academy" / "duels.json"
NOPROXY = urllib.request.build_opener(urllib.request.ProxyHandler({}))
DANGER = ["shutil.rmtree", "os.remove", "os.unlink", "os.system", "subprocess", "rm -rf", "__import__",
          "eval(", "exec(", "socket", "requests.", "urllib"]


def safe_to_run(code, confirm=input):
    flagged = [d for d in DANGER if d in code]
    if not flagged:
        return True
    print("WARNING, risky calls in the AI's code:", ", ".join(flagged))
    try:
        return confirm("Run it anyway? [y/N] ").strip().lower() == "y"
    except EOFError:
        return False


def conf():
    c = {"ollama": "http://127.0.0.1:11434", "coder": "qwen2.5-coder:1.5b", "judge": "llama3.2:1b",
         "embed": "nomic-embed-text"}
    try:
        c.update(json.loads(CONF.read_text()))
    except Exception:
        pass
    if os.environ.get("OLLAMA_URL"):
        c["ollama"] = os.environ["OLLAMA_URL"]
    return c


C = conf()


def post(path, body, timeout=600):
    req = urllib.request.Request(C["ollama"] + path, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    with NOPROXY.open(req, timeout=timeout) as r:
        return json.loads(r.read())


def ai(prompt, model=None, fmt=None):
    body = {"model": model or C["coder"], "prompt": prompt, "stream": False, "options": {"temperature": 0.2, "num_predict": 1536, "repeat_penalty": 1.1, "num_thread": int(C.get("threads", 5))}}
    if fmt:
        body["format"] = fmt
    return post("/api/generate", body)["response"]


def extract(text):
    m = re.findall(r"```(?:python)?\n(.*?)```", text or "", re.S)
    return (max(m, key=len) if m else text or "").strip() + "\n"


def run_py(path, timeout=20):
    try:
        r = subprocess.run([sys.executable, "-B", str(path)], capture_output=True, text=True,
                           timeout=timeout, stdin=subprocess.DEVNULL, cwd=str(pathlib.Path(path).parent))
        return "ALL TESTS PASSED" in r.stdout, (r.stdout + r.stderr)[-1500:]
    except subprocess.TimeoutExpired:
        return False, "timed out"


def find(fname):
    p = pathlib.Path(fname)
    return p if p.exists() else WORK / pathlib.Path(fname).name


# ---------------- explain ----------------
def explain(fname, level="beginner"):
    p = find(fname)
    if not p.exists():
        print("File not found:", fname)
        return
    lines = p.read_text().splitlines()
    print(f"EXPLAIN {p.name}  ({len(lines)} lines, {level} level)\n")
    for start in range(0, len(lines), 40):
        chunk = "\n".join(f"{start + i + 1}: {l}" for i, l in enumerate(lines[start:start + 40]))
        try:
            print(ai(f"Explain this Python code to a {level}. Go block by block, cite line numbers, "
                     "plain words, short sentences, no code rewrite.\n" + chunk))
        except Exception as e:
            print(f"AI not reachable ({e}). Start it with: forge-start")
            return
        print("-" * 40)


# ---------------- mutation testing ----------------
SWAP = {ast.Add: ast.Sub, ast.Sub: ast.Add, ast.Mult: ast.FloorDiv, ast.Lt: ast.LtE, ast.LtE: ast.Lt,
        ast.Gt: ast.GtE, ast.GtE: ast.Gt, ast.Eq: ast.NotEq, ast.NotEq: ast.Eq, ast.And: ast.Or, ast.Or: ast.And}


def mutation_sites(tree, main_guard):
    sites = []
    for node in ast.walk(tree):
        line = getattr(node, "lineno", 0)
        if line >= main_guard:
            continue
        if isinstance(node, (ast.BinOp, ast.BoolOp)) and type(node.op) in SWAP:
            sites.append((node, "op", line))
        elif isinstance(node, ast.Compare) and type(node.ops[0]) in SWAP:
            sites.append((node, "cmp", line))
        elif isinstance(node, ast.Constant) and type(node.value) is bool:
            sites.append((node, "bool", line))
        elif isinstance(node, ast.Constant) and type(node.value) is int:
            sites.append((node, "int", line))
        elif isinstance(node, ast.Return) and node.value is not None:
            sites.append((node, "ret", line))
    return sites


def describe(kind, node):
    return {"op": "operator swapped", "cmp": "comparison flipped", "bool": "True/False flipped",
            "int": "number changed by 1", "ret": "return value replaced by None"}[kind]


def mutants(src, limit=40):
    tree = ast.parse(src)
    guard = next((n.lineno for n in tree.body if isinstance(n, ast.If) and "__main__" in ast.unparse(n.test)), 10 ** 9)
    count = len(mutation_sites(tree, guard))
    idx = list(range(count))
    random.Random(7).shuffle(idx)
    for i in sorted(idx[:limit]):
        t = copy.deepcopy(tree)
        node, kind, line = mutation_sites(t, guard)[i]
        if kind == "op":
            node.op = SWAP[type(node.op)]()
        elif kind == "cmp":
            node.ops[0] = SWAP[type(node.ops[0])]()
        elif kind == "bool":
            node.value = not node.value
        elif kind == "int":
            node.value = node.value + 1
        elif kind == "ret":
            node.value = ast.Constant(None)
        yield line, describe(kind, node), ast.unparse(ast.fix_missing_locations(t))


def mutate(fname, limit=40):
    p = find(fname)
    if not p.exists():
        print("File not found:", fname)
        return None
    src = p.read_text()
    if "ALL TESTS PASSED" not in src:
        print("This file has no self-tests to judge. Add asserts that print ALL TESTS PASSED.")
        return None
    if not run_py(p)[0]:
        print("Tests fail on the original code. Fix it first: forge debug", p.name)
        return None
    killed, survivors, total = 0, [], 0
    with tempfile.TemporaryDirectory() as d:
        for line, what, code in mutants(src, limit):
            total += 1
            m = pathlib.Path(d) / p.name
            m.write_text(code)
            if run_py(m, 10)[0]:
                survivors.append((line, what))
            else:
                killed += 1
    if not total:
        print("Nothing to mutate.")
        return 100
    score = round(100 * killed / total)
    print(f"MUTATION TEST {p.name}: planted {total} bugs, your tests caught {killed}.  SCORE {score}/100")
    for line, what in survivors[:10]:
        print(f"  survived: line {line}, {what}  -> add a test that would notice this")
    if score >= 90:
        print("Elite test suite.")
    return score


# ---------------- code memory (RAG) ----------------
def chunks():
    out = []
    for f in sorted(WORK.glob("*.py")) if WORK.exists() else []:
        src = f.read_text(errors="ignore")
        try:
            tree = ast.parse(src)
            lines = src.splitlines()
            for n in tree.body:
                if isinstance(n, (ast.FunctionDef, ast.ClassDef, ast.AsyncFunctionDef)):
                    out.append({"file": f.name, "name": n.name,
                                "text": "\n".join(lines[n.lineno - 1:n.end_lineno])[:2500]})
        except SyntaxError:
            out.append({"file": f.name, "name": "(whole file)", "text": src[:2500]})
    return out


def words(t):
    return [w for w in re.findall(r"[a-z]+", re.sub(r"([a-z])([A-Z])", r"\1 \2", t).lower().replace("_", " ")) if len(w) > 1]


def embed(text):
    return post("/api/embeddings", {"model": C["embed"], "prompt": text[:2000]}, timeout=120)["embedding"]


def index(use_embed=True):
    cs = chunks()
    mode = "keywords"
    if use_embed and cs:
        try:
            for c in cs:
                c["vec"] = embed(c["file"] + " " + c["name"] + "\n" + c["text"])
            mode = "embeddings"
        except Exception:
            for c in cs:
                c.pop("vec", None)
    INDEX.write_text(json.dumps({"mode": mode, "chunks": cs}))
    print(f"Code memory: {len(cs)} functions/classes indexed ({mode}).")
    if mode == "keywords" and cs:
        print(f"Tip: for smarter search run  ollama pull {C['embed']}  then forge index again.")
    return mode


def cos(a, b):
    na, nb = math.sqrt(sum(x * x for x in a)), math.sqrt(sum(x * x for x in b))
    return sum(x * y for x, y in zip(a, b)) / (na * nb) if na and nb else 0.0


def recall(q, k=3):
    if not INDEX.exists():
        index()
    data = json.loads(INDEX.read_text())
    cs = data["chunks"]
    if not cs:
        return []
    if data["mode"] == "embeddings":
        try:
            qv = embed(q)
            return sorted(cs, key=lambda c: -cos(qv, c["vec"]))[:k]
        except Exception:
            pass
    docs = [words(c["file"] + " " + c["name"] + " " + c["text"]) for c in cs]
    avg = sum(map(len, docs)) / len(docs)
    qw = words(q)

    def bm25(d):
        s = 0.0
        for w in set(qw):
            df = sum(w in x for x in docs)
            tf = d.count(w)
            if tf:
                s += math.log(1 + (len(docs) - df + 0.5) / (df + 0.5)) * tf * 2.2 / (tf + 1.2 * (0.25 + 0.75 * len(d) / avg))
        return s
    scored = sorted(zip(map(bm25, docs), range(len(cs))), key=lambda t: -t[0])
    return [cs[i] for s, i in scored[:k] if s > 0]


def rag(q):
    hits = recall(q)
    ctx = "\n\n".join(f"# {h['file']} :: {h['name']}\n{h['text']}" for h in hits)
    print("Using:", ", ".join(f"{h['file']}:{h['name']}" for h in hits) or "no project code (empty workspace)")
    try:
        print(ai("Answer using the user's own project code below. Name the file and function you mean.\n"
                 f"{ctx}\n\nQuestion: {q}"))
    except Exception as e:
        print(f"AI not reachable ({e}). Start it with: forge-start")


# ---------------- AI team mode ----------------
def good_asserts(items, limit):
    """Keep only real, valid single assert statements (small models often emit junk)."""
    out = []
    for a in items:
        if not isinstance(a, str):
            continue
        for line in a.replace(", assert ", "\nassert ").splitlines():
            line = line.strip().rstrip(",;")
            try:
                tree = ast.parse(line)
            except SyntaxError:
                continue
            if len(tree.body) == 1 and isinstance(tree.body[0], ast.Assert) and line not in out:
                out.append(line)
    return out[:limit]


def called_names(src):
    try:
        return {n.func.id for n in ast.walk(ast.parse(src)) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)}
    except SyntaxError:
        return set()


def defined_names(src):
    try:
        t = ast.parse(src)
    except SyntaxError:
        return set()
    return {n.name for n in ast.walk(t) if isinstance(n, (ast.FunctionDef, ast.ClassDef, ast.AsyncFunctionDef))} | \
        {x.id for n in ast.walk(t) if isinstance(n, ast.Assign) for x in n.targets if isinstance(x, ast.Name)}


def strip_top_asserts(code):
    try:
        t = ast.parse(code)
    except SyntaxError:
        return code
    lines = code.splitlines()
    for n in reversed(t.body):
        if isinstance(n, ast.Assert) or (isinstance(n, ast.Expr) and isinstance(n.value, ast.Call)
                                         and getattr(n.value.func, "id", "") == "print"):
            del lines[n.lineno - 1:n.end_lineno]
    return "\n".join(lines).rstrip() + "\n"


def team(goal, fname=None, asker=ai, rounds=3):
    """Architect plans tests, Coder writes, Tester attacks, real tests decide."""
    WORK.mkdir(parents=True, exist_ok=True)
    name = fname or (re.sub(r"[^a-z0-9]+", "_", goal.lower()).strip("_")[:30] or "team_build") + ".py"
    print(f"AI TEAM building {name}\n  Architect: planning tests...")
    plan = asker("You are the Architect. For this goal, write 4 to 6 Python assert statements that a correct "
                 "solution must pass, calling the functions you expect. Reply ONLY with JSON "
                 '{"functions":"signatures and purpose","asserts":["assert ..."]}\nGoal: ' + goal, C["coder"], "json")
    try:
        d = json.loads(plan)
        asserts = good_asserts(d.get("asserts", []), 8)
        sigs = str(d.get("functions", ""))
    except Exception:
        asserts, sigs = [], ""
    print(f"  Architect: {len(asserts)} acceptance tests")
    print("  Tester: hunting edge cases...")
    extra = asker("You are the Tester. Write 3 extra tricky assert statements (empty input, boundaries, bad "
                  "values) for these functions. Reply ONLY with JSON {\"asserts\":[...]}\n" + sigs +
                  "\nGoal: " + goal, C["judge"], "json")
    try:
        asserts += [a for a in good_asserts(json.loads(extra).get("asserts", []), 4) if a not in asserts]
    except Exception:
        pass
    if not asserts:
        print("  Architect gave no usable tests, so nothing could be verified. Try: forge pipeline \"" + goal + "\"")
        return False
    feedback, path = "", WORK / name
    for r in range(1, rounds + 1):
        print(f"  Coder: round {r}...")
        code = extract(asker("You are the Coder. Write the Python module for this goal. Standard library only, no "
                             "input() at import, no network. Do NOT include tests or a __main__ block.\n"
                             f"Goal: {goal}\nFunctions: {sigs}\nIt must pass:\n{chr(10).join(asserts)}\n{feedback}",
                             C["coder"]))
        code = strip_top_asserts(code.split("if __name__")[0].rstrip() + "\n")
        have = defined_names(code) | set(dir(__builtins__))
        keep = [a for a in asserts if called_names(a) <= have]
        if len(keep) < len(asserts):
            print(f"  Referee: dropped {len(asserts) - len(keep)} test(s) that call functions the goal never asked for")
        if not keep:
            feedback = "Define the functions these tests call:\n" + "\n".join(asserts)
            continue
        asserts = keep
        tests = "\n".join("    " + a for a in asserts)
        full = code + f'\nif __name__ == "__main__":\n{tests}\n    print("ALL TESTS PASSED")\n'
        if not safe_to_run(full):
            print("  Referee: blocked risky code. Nothing was run.")
            return False
        path.write_text(full)
        ok, out = run_py(path)
        if ok:
            print(f"  Referee: all {len(asserts)} tests passed in round {r}. Saved {name}")
            return True
        feedback = "Your last version failed:\n" + out[-800:]
    print(f"  Referee: still failing after {rounds} rounds. Kept {name}; try forge debug {name}")
    return False


# ---------------- duel ----------------
def duel_new():
    sys.path.insert(0, str(HOME))
    import bench
    pool = bench.TASKS + getattr(bench, "HARD", [])
    st = json.loads(DUEL.read_text()) if DUEL.exists() else {"you": 0, "ai": 0, "draw": 0, "current": None}
    name, lvl, spec, _ = random.choice(pool)
    st["current"] = name
    DUEL.parent.mkdir(parents=True, exist_ok=True)
    DUEL.write_text(json.dumps(st))
    f = WORK / f"duel_{name}.py"
    WORK.mkdir(parents=True, exist_ok=True)
    f.write_text(f'"""DUEL (level {lvl}): {spec}\nWrite your solution below, then run: forge duel check"""\n\n')
    print(f"DUEL! Level {lvl}: {spec}\nYour file: {f}\nWhen ready: forge duel check   (the AI solves the same task)")


def duel_check(asker=None):
    sys.path.insert(0, str(HOME))
    import bench
    st = json.loads(DUEL.read_text()) if DUEL.exists() else {}
    cur = st.get("current")
    task = next((t for t in bench.TASKS + getattr(bench, "HARD", []) if t[0] == cur), None)
    if not task:
        print("No duel running. Start one: forge duel")
        return
    you = bench.check((WORK / f"duel_{cur}.py").read_text(), task[3])[0]
    try:
        ai_res = bench.solve(task[2], task[3], C["coder"], asker or bench.ask) == 1
    except Exception as e:
        print(f"AI not reachable ({e}). Start it with: forge-start")
        return
    key = "draw" if you == ai_res else ("you" if you else "ai")
    st[key] += 1
    st["current"] = None
    DUEL.write_text(json.dumps(st))
    print(f"You: {'PASS' if you else 'FAIL'}   AI: {'PASS' if ai_res else 'FAIL'}   ->  "
          f"{ {'you': 'YOU WIN!', 'ai': 'AI wins this one.', 'draw': 'Draw.'}[key] }")
    print(f"Record: you {st['you']}  AI {st['ai']}  draws {st['draw']}")


# ---------------- CI ----------------
CI_YML = """name: GoogolForge tests
on: [push, pull_request, workflow_dispatch]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Every GoogolForge self-test
        run: GF_HOME=$PWD python gf.py test
      - name: Every project file's own tests
        run: |
          fail=0
          for f in workspace/*.py; do
            [ -e "$f" ] || continue
            if grep -q "ALL TESTS PASSED" "$f"; then
              (cd workspace && timeout 60 python "$(basename "$f")") | grep -q "ALL TESTS PASSED" && echo "PASS $f" || { echo "FAIL $f"; fail=1; }
            fi
          done
          exit $fail
"""


def ci():
    p = HOME / ".github" / "workflows" / "forge-test.yml"
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(CI_YML)
    print("Cloud test robot ready. It runs on GitHub after your next publish (see the Actions tab of your repo).")


# ---------------- selftest ----------------
def selftest():
    global WORK, INDEX, DUEL, HOME
    fails = 0

    def chk(n, c):
        nonlocal fails
        print(("PASS " if c else "FAIL ") + n)
        fails += not c

    with tempfile.TemporaryDirectory() as d:
        HOME = pathlib.Path(d)
        WORK, INDEX, DUEL = HOME / "workspace", HOME / "idx.json", HOME / "duel.json"
        WORK.mkdir()
        weak = ('def grade(score):\n    if score >= 90:\n        return "A"\n    return "B"\n\n'
                'if __name__ == "__main__":\n    assert grade(95) == "A"\n    print("ALL TESTS PASSED")\n')
        strong = weak.replace('assert grade(95) == "A"',
                              'assert grade(95) == "A"\n    assert grade(90) == "A"\n    assert grade(89) == "B"\n    assert grade(91) == "A"')
        (WORK / "weak.py").write_text(weak)
        (WORK / "strong.py").write_text(strong)
        sw, ss = mutate("weak.py"), mutate("strong.py")
        chk("mutation testing scores weak tests lower than strong ones", sw is not None and ss is not None and sw < ss)
        chk("strong tests catch every planted bug", ss == 100)
        (WORK / "x.py").write_text("a=1\n")
        chk("files without tests are refused", mutate("x.py") is None)
        (WORK / "shop.py").write_text("def add_to_cart(cart, item):\n    cart.append(item)\n    return cart\n\n"
                                      "def total_price(cart):\n    return sum(i['price'] for i in cart)\n")
        (WORK / "game.py").write_text("def roll_dice(sides=6):\n    import random\n    return random.randint(1, sides)\n")
        index(use_embed=False)
        hit = recall("how is the cart total price computed")
        chk("code memory finds the right function", bool(hit) and hit[0]["name"] == "total_price")
        chk("code memory finds game code", recall("dice roll")[0]["file"] == "game.py")

        def fake(prompt, model=None, fmt=None):
            if "Architect" in prompt:
                return json.dumps({"functions": "def double(x)", "asserts": ["assert double(2) == 4", "assert double(0) == 0"]})
            if "Tester" in prompt:
                return json.dumps({"asserts": ["assert double(-3) == -6", "print('not an assert')"]})
            if "failed" in prompt:
                return "```python\ndef double(x):\n    return x * 2\n```"
            return "```python\ndef double(x):\n    return x + x if x > 0 else 0\n```"
        chk("AI team fixes a failing build using the referee's tests", team("double a number", "double.py", fake))
        chk("team keeps only real asserts", (WORK / "double.py").read_text().count("assert") == 3)
        chk("junk asserts from small models are repaired or dropped",
            good_asserts(["assert f(1), assert f(2)", "assert (", "x = 1", "assert f(1)"], 8) == ["assert f(1)", "assert f(2)"])

        def fake2(prompt, model=None, fmt=None):
            if "Architect" in prompt:
                return json.dumps({"functions": "is_leap(y)", "asserts": ["assert signle_leap(2020)", "assert is_leap(2000)", "assert not is_leap(1900)"]})
            if "Tester" in prompt:
                return json.dumps({"asserts": []})
            return "```python\ndef is_leap(y):\n    return y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)\nassert is_leap(4)\nprint(1)\n```"
        chk("tests calling made-up functions are dropped, real ones kept", team("leap", "leap.py", fake2)
            and (WORK / "leap.py").read_text().count("assert") == 2)
        chk("risky AI code is blocked unless you say yes", not safe_to_run("import os\nos.system('rm -rf ~')", lambda _: "n")
            and safe_to_run("x = 1"))
        ci_text = CI_YML
        chk("CI workflow runs every self-test", "gf.py test" in ci_text and "ALL TESTS PASSED" in ci_text)
    print(f"\nSELFTEST: {'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
    return fails == 0


HELP = """forge explain FILE [beginner|intermediate]   line-by-line explanation
forge mutate FILE          plant bugs to test your tests (score /100)
forge index                build code memory of your project
forge recall "question"    find the code that matches
forge rag "question"       answer using your own code
forge team "goal"          Architect + Coder + Tester + Referee build it
forge duel | duel check    you vs the AI on hidden tests
forge ci                   set up the free GitHub cloud test robot"""

if __name__ == "__main__":
    a = sys.argv[1:]
    cmd, rest = (a[0], a[1:]) if a else ("help", [])
    if cmd == "selftest":
        sys.exit(0 if selftest() else 1)
    elif cmd == "explain" and rest:
        explain(rest[0], rest[1] if len(rest) > 1 else "beginner")
    elif cmd == "mutate" and rest:
        mutate(rest[0])
    elif cmd == "index":
        index()
    elif cmd == "recall" and rest:
        for h in recall(" ".join(rest)):
            print(f"--- {h['file']} :: {h['name']}\n{h['text'][:600]}\n")
    elif cmd == "rag" and rest:
        rag(" ".join(rest))
    elif cmd == "team" and rest:
        team(" ".join(rest))
    elif cmd == "duel":
        duel_check() if rest[:1] == ["check"] else duel_new()
    elif cmd == "ci":
        ci()
    else:
        print(HELP)
FORGE3EOF
if [ ! -f ~/googolforge/plugins/hello.py ]; then
cat > ~/googolforge/plugins/hello.py <<'PLUGEOF'
# Example plugin: greets you and counts your project files (copy me to make your own)
import pathlib
work = pathlib.Path.home() / "googolforge" / "workspace"
files = list(work.glob("*.py")) if work.exists() else []
print(f"Hello from your first GoogolForge plugin! You have {len(files)} project file(s).")
PLUGEOF
fi
python ~/googolforge/forge3.py ci
python ~/googolforge/gf.py version
echo "######## STEP J2: real forge and gf commands on PATH ########"
BIN="${PREFIX:-/data/data/com.termux/files/usr}/bin"
if [ -d "$BIN" ] && [ -w "$BIN" ]; then
  printf '#!/data/data/com.termux/files/usr/bin/bash\nexec python "$HOME/googolforge/gf.py" "$@"\n' > "$BIN/forge"
  printf '#!/data/data/com.termux/files/usr/bin/bash\nexec python "$HOME/googolforge/gf.py" chat "$@"\n' > "$BIN/gf"
  chmod +x "$BIN/forge" "$BIN/gf"
  echo "forge and gf installed in $BIN"
fi
echo "######## STEP K: final checks ########"
git config --global user.name >/dev/null 2>&1 || git config --global user.name "Alex"
git config --global user.email >/dev/null 2>&1 || git config --global user.email "alex@googolforge.local"
PASS=0
python ~/googolforge/forge.py selftest >/dev/null 2>&1 && { echo "OK  Forge engine"; PASS=$((PASS+1)); } || echo "FAIL Forge engine"
python ~/googolforge/academy.py selftest >/dev/null 2>&1 && { echo "OK  Academy"; PASS=$((PASS+1)); } || echo "FAIL Academy"
python ~/googolforge/assistant.py selftest >/dev/null 2>&1 && { echo "OK  Assistant"; PASS=$((PASS+1)); } || echo "FAIL Assistant"
python ~/googolforge/web.py selftest >/dev/null 2>&1 && { echo "OK  Dashboard"; PASS=$((PASS+1)); } || echo "FAIL Dashboard"
python ~/googolforge/bench.py selftest >/dev/null 2>&1 && { echo "OK  Benchmark Arena"; PASS=$((PASS+1)); } || echo "FAIL Benchmark Arena"
python ~/googolforge/gf.py version >/dev/null 2>&1 && { echo "OK  v3.0 launcher"; PASS=$((PASS+1)); } || echo "FAIL v3.0 launcher"
python ~/googolforge/repairmem.py selftest >/dev/null 2>&1 && grep -q GF-REPAIRMEM ~/googolforge/forge.py && { echo "OK  Self-Repair Memory"; PASS=$((PASS+1)); } || echo "FAIL Self-Repair Memory"
python ~/googolforge/templates.py selftest >/dev/null 2>&1 && { echo "OK  Project templates"; PASS=$((PASS+1)); } || echo "FAIL Project templates"
python ~/googolforge/path.py selftest >/dev/null 2>&1 && { echo "OK  Season 2 path"; PASS=$((PASS+1)); } || echo "FAIL Season 2 path"
bash -n ~/googolforge/voice.sh && [ -x ~/.shortcuts/GF-Chat ] && { echo "OK  Voice + home buttons"; PASS=$((PASS+1)); } || echo "FAIL Voice + home buttons"
python ~/googolforge/forge3.py selftest >/dev/null 2>&1 && { echo "OK  Pro tools (team, mutate, code memory, duel)"; PASS=$((PASS+1)); } || echo "FAIL Pro tools"
[ -f ~/googolforge/.github/workflows/forge-test.yml ] && [ -f ~/googolforge/plugins/hello.py ] && grep -q manifest.json ~/googolforge/web.py && { echo "OK  Cloud tests + plugins + app install"; PASS=$((PASS+1)); } || echo "FAIL Cloud tests + plugins + app install"
bash -n ~/googolforge/autopublish.sh && grep -q "chat_memory.json" ~/googolforge/publish.sh && { echo "OK  Auto-publish + privacy"; PASS=$((PASS+1)); } || echo "FAIL Auto-publish"
curl -s http://127.0.0.1:11434/api/tags >/dev/null 2>&1 && { echo "OK  AI server running"; PASS=$((PASS+1)); } || echo "FAIL AI server (run forge-start)"
termux-wake-unlock 2>/dev/null || true
echo ""
echo "== GoogolForge setup: $PASS/14 checks passed =="
echo "Optional, for your free website: gh auth login, then forge autopublish on"
echo "Now open a NEW Termux session and type:  forge   (menu)  |  gf  (chat)  |  forge path  |  forge team \"a stopwatch\""
