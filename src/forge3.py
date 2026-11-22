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
    body = {"model": model or C["coder"], "prompt": prompt, "stream": False, "options": {"temperature": 0.2, "num_predict": 1536, "repeat_penalty": 1.1}}
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
