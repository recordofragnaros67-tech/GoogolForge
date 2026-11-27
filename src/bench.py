#!/usr/bin/env python3
"""GoogolForge Benchmark Arena v1.6 (HumanEval+ slice and full 164, MBPP+ slice, original holdout set, Genius style with Smart Router, Elite style, sealed hidden tests, Shootout, Hard mode, Team style) - turn "quality" into a number.
Ten fixed coding tasks with hidden tests. The coder model gets two tries per task
(the second sees the error, like the real engine). Scores are saved so every
model, prompt or version change is measured against the last one."""
import ast, datetime, gzip, json, os, pathlib, re, subprocess, sys, tempfile, time, urllib.request
sys.dont_write_bytecode = True

HOME = pathlib.Path(os.environ.get("GF_HOME", str(pathlib.Path.home() / "googolforge")))
HIST = HOME / "bench_history.json"
LOSSES = HOME / "losses"
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


PREFIX = {"code": "", "slow": False}  # dataset tasks: the task's own signature, imports and helpers go first


def check(code, tests):
    with tempfile.TemporaryDirectory() as d:
        f = pathlib.Path(d) / "t.py"
        f.write_text(PREFIX["code"] + "\n" + code + "\n" + tests + "\nprint('BENCH_OK')\n")
        try:
            r = subprocess.run([sys.executable, "-B", str(f)], capture_output=True, text=True,
                               timeout=30 if PREFIX["code"] or PREFIX["slow"] else 15, stdin=subprocess.DEVNULL, cwd=d)
        except subprocess.TimeoutExpired:
            return False, "timed out"
        return "BENCH_OK" in r.stdout, (r.stderr or r.stdout)[-600:]


RULES = ("Standard library only, no input(), no prints, no example usage. "
         "Reply in one ```python block.\n")
STYLES = {
    "plain":  "Write ONLY the Python code for this. " + RULES,
    "expert": ("You are a senior Python engineer. Handle edge cases (empty input, single item, "
               "duplicates, boundaries). Write ONLY the code. " + RULES),
    "lawyer": ("Read the task like a lawyer: obey every exact rule and worked example word for word. "
               "Write ONLY the code. " + RULES),
    "steps":  ("First list the edge cases in at most 3 short # comments, then write the code. " + RULES),
    "elite":  ("Write ONLY the Python code for this. " + RULES),
    "algo":   ("First name the classic algorithm or data structure that solves this in one # comment, "
               "then implement it carefully. " + RULES),
    "team":   ("You are the Coder on a team. Write ONLY the code and handle every edge case the Tester listed. " + RULES),
}
CANDIDATES = ["qwen2.5-coder:1.5b", "qwen2.5-coder:3b", "llama3.2:1b", "llama3.2:3b", "deepseek-coder:1.3b"]


LAST = {}  # the final answer and error of the last task, kept for the loss log (never shown to the model)
PITFALLS = ("Python pitfalls to check: // floors toward minus infinity (use int(a / b) to truncate toward zero); "
            "a token like '-7' is a negative number, not an operator; counts and numbers can have several digits; "
            "empty input must return an empty result; a single item is a valid input; to read a count with "
            "several digits, collect consecutive digits (for example re.findall(r'(\\d+)(\\D)', s)). ")


def pitfalls(spec):
    """Only the Python pitfalls that matter for THIS task (v3.6.4). Generic advice for every task
    made models invent rules, like rejecting negative numbers in a dependency graph."""
    low, out = spec.lower(), []
    if "truncat" in low or "division" in low:
        out.append("// floors toward minus infinity; use int(a / b) to truncate toward zero")
    if ("integer" in low or "number" in low) and re.search(r"'[^']*\d [^']*'", spec):
        out.append("a token like '-7' is a negative number, not an operator")
    if "more than 9" in low or "several digits" in low or ("count" in low and "encod" in low):
        out.append("counts can have several digits: collect consecutive digits, e.g. re.findall(r'(\\d+)(\\D)', s)")
    if re.search(r"'\s*<?->", spec):
        out.append("the worked example in the task must hold exactly")
    return ("Pitfalls for this task: " + "; ".join(out) + ". ") if out else ""


def lint_fix(spec, code):
    """Rule Lawyer autofix (v3.6.1): the task text says 'truncating toward zero' but the code uses //,
    which floors. Rewrite a // b as int(a / b). Only fires when the task itself states that rule."""
    if "truncat" not in spec.lower() or "//" not in code:
        return code
    return re.sub(r"([\w\]\)]+)\s*//\s*([\w\[\(]+)", r"int(\1 / \2)", code)


def solve(spec, tests, model, asker=ask, style="plain"):
    prompt = STYLES.get(style, STYLES["plain"]) + spec
    if style == "team":  # a second model acts as Tester and lists edge cases first
        cases = asker("You are the Tester. List the 3 trickiest edge cases for this task, one short line each, "
                      "no code.\n" + spec, C.get("judge", model))
        prompt += "\nTester's edge cases:\n" + (cases or "")[:600]
    if style in ("elite", "genius"):
        code = (elite_code if style == "elite" else genius_code)(spec, model, asker)
        ok, err = check(code, tests)
        LAST.update(code=code, err=err)
        return 1 if ok else 0
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
                "rules. " + pitfalls(spec) + "If the task has two functions that undo each other, add round-trip asserts like "
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


def probes(spec):
    """Stress Probe (v3.6): property checks built ONLY from the task text, with no answer key.
    1) The task says integers/numbers: the task's own example with its first number made negative
       must not crash. 2) Two functions that undo each other: g(f(x)) == x on the task's letter
       examples, also stretched past 9 repeats. Like property-based testing."""
    sigs = re.findall(r"def (\w+)\(([^)]*)\)", spec)
    if not sigs:
        return []
    low, out = spec.lower(), []
    lits = re.findall(r"'([^'\n]{1,40})'", spec)
    one_arg = [n for n, a in sigs if a.strip() and "," not in a]
    if len(sigs) == 1 and one_arg and ("integer" in low or "number" in low):
        for x in lits:
            if re.search(r"\d", x) and " " in x:
                y = re.sub(r"(?<![\w-])(\d+)", r"-\1", x, count=1)
                out.append(f"assert ({one_arg[0]}({y!r}), True)[1]")
    lit = r"('[^'\n]{0,40}'|-?\d+|True|False|None)"
    if len(one_arg) == 1:  # the task's own worked example: e.g. 'x' -> y
        for a, b in re.findall(r"('[^'\n]{1,40}')\s*->\s*" + lit, spec):
            out.insert(0, f"assert {one_arg[0]}({a})=={b}")
    if len(one_arg) >= 2:  # a pair example: 'x' <-> 'y' means f(x)==y and g(y)==x
        for a, b in re.findall(r"('[^'\n]{1,40}')\s*<->\s*('[^'\n]{1,40}')", spec):
            out[:0] = [f"assert {one_arg[0]}({a})=={b}", f"assert {one_arg[1]}({b})=={a}"]
    if len(one_arg) >= 2 and any(w in low for w in ("reverse", "<->", "undo", "inverse", "round trip")):
        f, g = one_arg[0], one_arg[1]
        for x in lits:
            if x.isalpha():
                for v in (x, x[0] * 12 + x):
                    out.append(f"assert {g}({f}({v!r}))=={v!r}")
    return out[:6]


def sane(asserts, drafts):
    """Drop a broken test: one that EVERY draft fails with NameError (wrong function name)."""
    keep = []
    for a in asserts:
        errs = [check(c, a) for c in drafts]
        if all((not ok) and "NameError" in (e or "") for ok, e in errs):
            continue
        keep.append(a)
    return keep


def fingerprint(code, asserts):
    """What a draft actually returns on the inputs of the AI's own tests (no expected values used)."""
    calls = []
    for a in asserts:
        try:
            t = ast.parse(a).body[0].test
        except (SyntaxError, IndexError, AttributeError):
            continue
        if isinstance(t, ast.Compare):
            calls.append(ast.get_source_segment(a, t.left))
    if not calls:
        return None
    body = "".join(f"try:\n    _o.append(repr({c}))\nexcept Exception as _e:\n    _o.append(type(_e).__name__)\n" for c in calls)
    with tempfile.TemporaryDirectory() as d:
        f = pathlib.Path(d) / "fp.py"
        f.write_text(code + "\n_o = []\n" + body + "print('FP' + repr(_o))\n")
        try:
            r = subprocess.run([sys.executable, "-B", str(f)], capture_output=True, text=True,
                               timeout=15, stdin=subprocess.DEVNULL, cwd=d)
        except subprocess.TimeoutExpired:
            return "timeout"
    out = [ln for ln in r.stdout.splitlines() if ln.startswith("FP")]
    return out[-1] if out else "crash"


def agreed(drafts, mine, best):
    """Second opinion (v3.6.2): before trusting an early win, at least two drafts that pass every
    self-test must behave identically. A lone passer may only agree with a weak test."""
    passers = [c for c in drafts if all(check(c, a)[0] for a in mine)]
    fb = fingerprint(best, mine)
    return fb is not None and sum(fingerprint(c, mine) == fb for c in passers) >= 2


def genius_code(spec, model, asker, lister=None):
    """Genius style (v3.6, Edge-Case Hunter + Rule Lawyer + Stress Probe): Fischer-style preparation.
    1) 4 different opening drafts from the fast model (plain, expert, steps, algo).
    2) Spec tests written by the strongest model available (never sees hidden tests).
    3) CodeT choice: most self-tests passed, ties broken by agreement between drafts.
    4) Smart Router: if the best draft still fails its own tests, escalate to the strong model
       for 2 fresh drafts plus up to 2 sealed self-repairs."""
    strong = strong_model(model, lister)
    judge = strong or model
    drafts = [lint_fix(spec, extract(asker(STYLES[s] + spec, model))) for s in ("plain", "expert", "steps", "algo")]
    drafts.append(lint_fix(spec, extract(asker(STYLES["lawyer"] + pitfalls(spec) + spec, model))))
    edges, mine = hunt_tests(spec, judge, asker)
    mine = sane(mine, drafts) + probes(spec)
    hint = ("\nEdge cases to handle:\n" + edges + "\n") if edges else ""
    best, n = pick(drafts, mine)
    if mine and n == len(mine) and agreed(drafts, mine, best):
        return best
    coder = strong or model
    if strong:
        drafts += [lint_fix(spec, extract(asker(STYLES[s] + spec + hint, strong))) for s in ("expert", "algo")]
        drafts.append(lint_fix(spec, extract(asker(STYLES["lawyer"] + pitfalls(spec) + spec + hint, strong))))
        best, n = pick(drafts, mine)
    for _ in range(2):
        if not mine or n == len(mine):
            break
        fail = self_score(best, mine)[1]
        fixed = lint_fix(spec, extract(asker(STYLES["plain"] + spec + hint + "\n" + pitfalls(spec) + f"\nThis attempt fails this check:\n{fail}\n"
                              "If the check itself contradicts the task, keep the code correct for the task.\n"
                              f"Attempt:\n{best}", coder)))
        m = self_score(fixed, mine)[0]
        if m >= n:
            best, n = fixed, m
    return best


# ---- Dataset suites (v3.7 HumanEval+ slice; v3.8 full HumanEval+, MBPP+ slice, holdout) -----------
# heplus:     40 fixed tasks from EvalPlus HumanEval+ v0.1.10 (Apache-2.0, github.com/evalplus/humanevalplus_release):
#             every 4th task, up to 120 hidden inputs each. Built by tools/build_heplus.py.
# heplusfull: all 164 HumanEval+ tasks, up to 80 hidden inputs each, gzip. tools/build_heplus.py --full.
# mbppplus:   40 fixed tasks from EvalPlus MBPP+ v0.2.0 (Apache-2.0, github.com/evalplus/mbppplus_release),
#             up to 100 hidden inputs each. Built by tools/build_mbppplus.py.
# holdout:    6 ORIGINAL hard tasks written for GoogolForge, in no public benchmark. HOLDOUT: never use its
#             results, losses or hidden inputs to tune prompts, pitfalls, lint fixes, probes or routing.
#             Built by tools/build_holdout.py (every reference is checked against brute force there).
# Expected outputs come from the canonical/reference solutions. The model sees only the task prompt.
DATA_URL = "https://raw.githubusercontent.com/recordofragnaros67-tech/GoogolForge/main/data/"
HEP_URL = DATA_URL + "heplus40.json"
DATASETS = {  # suite: (file, what it is, download size, model instruction)
    "heplus": ("heplus40.json", "the HumanEval+ slice", "400 KB", "Complete this Python function. Keep the exact name and signature:\n"),
    "heplusfull": ("heplus164.json.gz", "full HumanEval+", "250 KB", "Complete this Python function. Keep the exact name and signature:\n"),
    "mbppplus": ("mbppplus40.json", "the MBPP+ slice", "340 KB", "Write a Python function for this task. Use the exact function name from the example:\n"),
    "holdout": ("holdout6.json", "the holdout set", "40 KB", "Complete this Python function. Keep the exact name and signature:\n"),
}
SHORT = {"heplus": "he_", "heplusfull": "he_", "mbppplus": "mbpp_", "holdout": "ho_"}


def he_data(suite="heplus"):
    name = DATASETS[suite][0]
    here = pathlib.Path(__file__).resolve().parent.parent / "data" / name
    mine = HOME / "data" / name
    if here.exists():
        raw = here.read_bytes()
    else:
        if not mine.exists():
            print(f"Downloading {DATASETS[suite][1]} (about {DATASETS[suite][2]})...")
            mine.parent.mkdir(parents=True, exist_ok=True)
            with urllib.request.urlopen(DATA_URL + name, timeout=60) as r:
                mine.write_bytes(r.read())
        raw = mine.read_bytes()
    return json.loads(gzip.decompress(raw) if name.endswith(".gz") else raw)


def he_tests(t):
    """Sealed hidden tests for one dataset task. A failure says only which case number failed."""
    cases = ",\n".join(f"({i}, {o})" for i, o in t["cases"])
    atol = t.get("atol") or 0
    root = t["entry"] == "find_zero"  # any real root counts, as in EvalPlus
    return (f"import copy as _cp, math as _m\n_CASES = [\n{cases}\n]\n"
            f"def _same(a, b):\n"
            f"    if isinstance(a, float) or isinstance(b, float):\n"
            f"        try:\n            return _m.isclose(a, b, rel_tol=1e-6, abs_tol={max(atol, 1e-9)!r}) or (a != a and b != b)\n"
            f"        except TypeError:\n            return False\n"
            f"    if isinstance(a, (list, tuple)) and isinstance(b, (list, tuple)):\n"
            f"        return type(a) == type(b) and len(a) == len(b) and all(_same(x, y) for x, y in zip(a, b))\n"
            f"    return a == b\n"
            f"for _n, (_i, _o) in enumerate(_CASES):\n"
            f"    _r = {t['entry']}(*_cp.deepcopy(_i))\n"
            + ("    assert abs(poly(_i[0], _r)) < 1e-4, f'wrong answer on hidden case {_n}'\n" if root else
               "    assert _same(_r, _o), f'wrong answer on hidden case {_n}'\n"))


def he_prefix(t):
    """Code that goes before the model's answer: HumanEval+ needs its prompt (imports, helpers)."""
    return t.get("prefix", t["prompt"])


def he_tasks(suite="heplus"):
    d, intro = he_data(suite), DATASETS[suite][3]
    return [(SHORT[suite] + t["id"].split("/")[-1] + "_" + t["entry"], 3, intro + t["prompt"],
             he_tests(t), he_prefix(t)) for t in d["tasks"]]


def ref_failures(suite):
    """Ids of tasks whose own reference/canonical solution fails its hidden tests (should be none)."""
    bad = []
    for t in he_data(suite)["tasks"]:
        PREFIX.update(code=he_prefix(t), slow=True)
        if not check(he_prefix(t) + t["ref"], he_tests(t))[0]:
            bad.append(t["id"])
    PREFIX.update(code="", slow=False)
    return bad


def run(model=None, quick=False, asker=ask, style="plain", quiet=False, hard=False, suite="arena"):
    model = model or C["coder"]
    if suite in DATASETS:
        tasks = he_tasks(suite)[:8] if quick else he_tasks(suite)
    else:
        tasks = HARD if hard else (TASKS[:4] if quick else TASKS)
    say = (lambda *a, **k: None) if quiet else print
    say(f"BENCHMARK ARENA  model={model}  style={style}  tasks={len(tasks)}\n")
    if suite == "holdout":
        say("HOLDOUT set: a check on real progress. Never tune prompts or heuristics on it; its losses are not saved.\n")
    first = second = 0
    t0 = time.time()
    rows = []
    for name, lvl, spec, tests, *pre in tasks:
        s = time.time()
        PREFIX.update(code=pre[0] if pre else "", slow=bool(pre))
        try:
            res = solve(spec, tests, model, asker, style)
        except Exception as e:
            say(f"AI call failed ({e}). Start it with: forge-start")
            return None
        finally:
            PREFIX.update(code="", slow=False)
        first += res == 1
        second += res in (1, 2)
        mark = {1: "WIN  (1st try)", 2: "WIN  (after fix)", 0: "LOSS"}[res]
        say(f"  L{lvl} {name:<16} {mark:<17} {time.time() - s:5.1f}s")
        rows.append({"task": name, "result": res})
        if res == 0 and LAST and suite != "holdout":
            LOSSES.mkdir(parents=True, exist_ok=True)
            (LOSSES / f"{name}.txt").write_text(f"# TASK\n# {spec}\n\n{LAST.get('code', '')}\n\n# ERROR\n"
                                                + "\n".join("# " + x for x in LAST.get("err", "").splitlines()[-12:]))
        LAST.clear()
    n = len(tasks)
    score = round(100 * (first + 0.5 * (second - first)) / n)
    result = {"date": datetime.datetime.now().isoformat(timespec="minutes"), "model": model,
              "tasks": n, "first_try": first, "solved": second, "score": score,
              "seconds": round(time.time() - t0), "quick": quick, "hard": hard, "style": style, "suite": suite, "rows": rows}
    hist = json.loads(HIST.read_text()) if HIST.exists() else []
    same = [h for h in hist if h["tasks"] == n and h["model"] == model and h.get("hard", False) == hard
            and h.get("suite", "arena") == suite]
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
    LAST.update(code="x=1", err="")
    chk("Rule Lawyer gets the truncation pitfall only on a task that needs it",
        "int(a / b)" in pitfalls(HARD[0][2]) and "negative" not in pitfalls(HARD[4][2]))
    def fake_hunt(prompt, model):
        if "tough exam setter" in prompt:
            return "assert reverse_words('a b')=='b a'"
        return "```python\ndef reverse_words(s):\n    return s\n```"
    LAST.clear()
    solve(TASKS[0][2], TASKS[0][3], "m", fake_hunt, "genius")
    chk("loss log keeps the final wrong answer and its error", "return s" in LAST.get("code", "") and LAST.get("err"))
    chk("Stress Probe: negative-number probe from the task's own example",
        "assert (rpn('-3 4 + 2 *'), True)[1]" in probes(HARD[0][2]))
    chk("Stress Probe: the task's worked examples become checks",
        "assert rpn('3 4 + 2 *')==14" in probes(HARD[0][2])
        and "assert encode('aaab')=='3a1b'" in probes(HARD[2][2]) and "assert decode('3a1b')=='aaab'" in probes(HARD[2][2]))
    rl = probes(HARD[2][2])
    chk("Stress Probe: round trip plus a run longer than 9",
        "assert decode(encode('aaab'))=='aaab'" in rl and any("a" * 13 in x for x in rl))
    chk("Stress Probe: correct reference answers pass every probe",
        all(check(REF[t[0]], "\n".join(probes(t[2])))[0] for t in TASKS + HARD))
    rev = extract(answers["reverse"])
    chk("second opinion: two identical passers agree, a lone passer does not",
        agreed([rev, rev], ["assert reverse_words('a b')=='b a'"], rev)
        and not agreed([rev, "def reverse_words(s):\n    return s\n"], ["assert reverse_words('a b')=='b a'"], rev))
    chk("lint_fix turns // into int(a / b) only when the task says truncate",
        "int(a / b)" in lint_fix(HARD[0][2], "x = a // b") and lint_fix(TASKS[0][2], "x = a // b") == "x = a // b")
    chk("Stress Probe: no probes for two-argument functions", probes(TASKS[9][2]) == [])
    hd = he_data()["tasks"]
    chk("HumanEval+ slice: 40 tasks, each with hidden cases", len(hd) == 40 and all(len(t["cases"]) >= 4 for t in hd))
    okref = True
    for t in hd:  # every canonical solution passes its own hidden tests (proves the tests are fair)
        PREFIX["code"] = t["prompt"]
        okref = okref and check(t["prompt"] + t["ref"], he_tests(t))[0]
    bad = hd[0]
    PREFIX["code"] = bad["prompt"]
    wrong = check(f"def {bad['entry']}(*a):\n    return False\n", he_tests(bad))
    PREFIX["code"] = ""
    chk("HumanEval+ slice: all 40 reference solutions pass", okref)
    chk("HumanEval+ sealed judge: a wrong answer fails and names only the case number",
        not wrong[0] and "hidden case" in wrong[1] and "[" not in wrong[1].split("hidden case")[-1])
    chk("HumanEval+ prompt never contains the reference or the cases",
        all(t["ref"].strip() not in he_tasks()[k][2] and he_tasks()[k][3] not in he_tasks()[k][2] for k, t in enumerate(hd[:5])))
    for suite, n, least in (("heplusfull", 164, 10), ("mbppplus", 40, 10), ("holdout", 6, 20)):
        ts = he_data(suite)["tasks"]
        chk(f"{suite}: {n} tasks, each with at least {least} hidden cases",
            len(ts) == n and all(len(t["cases"]) >= least for t in ts) and len({t["id"] for t in ts}) == n)
        bad = ref_failures(suite)
        chk(f"{suite}: every reference solution passes its hidden tests" + (f" (failed: {bad[:5]})" if bad else ""), not bad)
        tk = he_tasks(suite)
        chk(f"{suite}: prompts never contain the reference or the cases",
            all(t["ref"].strip() not in tk[k][2] and t["cases"][-1][0] not in tk[k][2] for k, t in enumerate(ts)))
        t0 = ts[0]
        PREFIX.update(code=he_prefix(t0), slow=True)
        w = check(f"def {t0['entry']}(*a):\n    return None\n", he_tests(t0))
        PREFIX.update(code="", slow=False)
        chk(f"{suite}: sealed judge fails a wrong answer and names only the case number",
            not w[0] and "hidden case" in w[1])
    chk("holdout is marked as a holdout", "HOLDOUT" in he_data("holdout")["source"])
    LAST.clear()
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
    elif a[:1] == ["losses"]:  # show the last wrong answers so you can see the exact bug
        fs = sorted(LOSSES.glob("*.txt")) if LOSSES.exists() else []
        print("\n\n".join(f"===== {f.stem} =====\n{f.read_text()}" for f in fs) or "No losses saved. Run: forge bench --genius --hard")
    else:
        for x in a:
            if x.startswith("--strong="):
                C["strong"] = x.split("=", 1)[1]
        if LOSSES.exists():
            for f in LOSSES.glob("*.txt"):
                f.unlink()
        rest = [x for x in a if not x.startswith("--")]
        style = "genius" if "--genius" in a else "elite" if "--elite" in a else "team" if "--team" in a else "plain"
        run(rest[0] if rest else None, "--quick" in a, style=style, hard="--hard" in a,
            suite=next((k for f, k in (("--heplus-full", "heplusfull"), ("--heplus", "heplus"), ("--mbppplus", "mbppplus"),
                                      ("--holdout", "holdout")) if f in a), "arena"))
