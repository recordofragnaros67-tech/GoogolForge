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
