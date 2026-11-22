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
            "options": {"temperature": temp, "num_predict": 1536, "repeat_penalty": 1.1}}
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
