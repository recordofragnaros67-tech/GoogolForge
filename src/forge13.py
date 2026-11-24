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
