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
