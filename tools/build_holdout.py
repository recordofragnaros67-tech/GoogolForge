#!/usr/bin/env python3
"""Build data/holdout6.json: the GoogolForge HOLDOUT set (v3.8).

HOLDOUT RULES - read before touching this file
  * Six original hard tasks written for GoogolForge. They are not from any public benchmark.
  * They exist to catch overfitting. Never use holdout results, losses or hidden inputs to tune
    prompts, pitfalls, lint fixes, probes or routing. Tune on hard/heplus/mbppplus only, then
    run --holdout to see whether the gain is real.
  * Each task has a reference solution and 30+ hidden inputs. Every reference is checked here
    against an independent brute-force solution before anything is written.
  python tools/build_holdout.py
Inputs come from a fixed seed, so the file is reproducible."""
import json, random, re, sys

TASKS = []


def task(entry, prompt):
    def wrap(fn):
        TASKS.append({"entry": entry, "prompt": prompt, "fn": fn})
        return fn
    return wrap


# 1 ------------------------------------------------------------------------------------------
P_COVER = '''def covered_k(intervals: list, k: int) -> int:
    """Each interval is [a, b] with integers a < b and means the half-open range a <= x < b.
    Return the total length of the number line covered by AT LEAST k of the intervals (k >= 1).
    Intervals may overlap, repeat or come in any order; an empty list gives 0.
    >>> covered_k([[0, 5], [3, 8]], 2)
    2
    >>> covered_k([[0, 5], [3, 8]], 1)
    8
    """
'''
REF_COVER = '''def covered_k(intervals: list, k: int) -> int:
    ev = []
    for a, b in intervals:
        ev.append((a, 1))
        ev.append((b, -1))
    ev.sort()
    total, depth, prev = 0, 0, None
    for x, d in ev:
        if prev is not None and depth >= k:
            total += x - prev
        depth += d
        prev = x
    return total
'''


def brute_cover(intervals, k):
    if not intervals:
        return 0
    lo, hi = min(a for a, _ in intervals), max(b for _, b in intervals)
    return sum(1 for x in range(lo, hi) if sum(a <= x < b for a, b in intervals) >= k)


def gen_cover(rng):
    out = [([], 1), ([[2, 3]], 1), ([[2, 3]], 2), ([[0, 5], [5, 9]], 2), ([[0, 5], [0, 5], [0, 5]], 3),
           ([[-4, -1], [-3, 2]], 2)]
    while len(out) < 34:
        n = rng.randint(1, 9)
        iv = []
        for _ in range(n):
            a = rng.randint(-30, 30)
            iv.append([a, a + rng.randint(1, 20)])
        out.append((iv, rng.randint(1, 4)))
    return out


# 2 ------------------------------------------------------------------------------------------
P_EXPAND = '''def expand(pattern: str) -> list:
    """pattern uses lowercase letters, '(' ')' for grouping and '|' for "or". '|' can appear at the
    top level or inside any group, groups can nest, and an alternative can be empty.
    Return every distinct string the pattern can produce, sorted.
    >>> expand('a(b|cd)e')
    ['abe', 'acde']
    >>> expand('x|y(|z)')
    ['x', 'y', 'yz']
    """
'''
REF_EXPAND = '''def expand(pattern: str) -> list:
    pos = 0

    def alt():
        nonlocal pos
        out = set(seq())
        while pos < len(pattern) and pattern[pos] == '|':
            pos += 1
            out |= set(seq())
        return out

    def seq():
        nonlocal pos
        cur = {''}
        while pos < len(pattern) and pattern[pos] not in '|)':
            if pattern[pos] == '(':
                pos += 1
                inner = alt()
                pos += 1
            else:
                inner = {pattern[pos]}
                pos += 1
            cur = {a + b for a in cur for b in inner}
        return cur

    return sorted(alt())
'''


def brute_expand(pattern):
    """Independent check: bottom-up, innermost group first, then a regex filter as a second check."""
    s = pattern
    groups = {}
    while "(" in s:
        m = re.search(r"\(([^()]*)\)", s)
        key = chr(0x4E00 + len(groups))
        groups[key] = m.group(1)
        s = s[:m.start()] + key + s[m.end():]

    def words(text):
        res = set()
        for part in text.split("|"):
            acc = {""}
            for ch in part:
                acc = {a + b for a in acc for b in (words(groups[ch]) if ch in groups else {ch})}
            res |= acc
        return res
    got = sorted(words(s))
    rx = re.compile("(?:" + pattern + ")")
    assert all(rx.fullmatch(w) for w in got)
    return got


def gen_expand(rng):
    def node(d):
        if d > 2 or rng.random() < 0.3:
            return "".join(rng.choice("abc") for _ in range(rng.randint(0, 2)))
        parts = []
        for _ in range(rng.randint(1, 3)):
            parts.append("".join(rng.choice("abcd") for _ in range(rng.randint(0, 1))))
            if rng.random() < 0.6:
                parts[-1] += "(" + "|".join(node(d + 1) for _ in range(rng.randint(1, 3))) + ")"
        return "".join(parts)
    out = [("",), ("abc",), ("a|b|a",), ("(a|b)(c|d)",), ("((a))",), ("a(|b)(|c)",), ("(|)",), ("ab|",)]
    while len(out) < 34:
        p = node(0) if rng.random() < 0.5 else "|".join(node(1) for _ in range(rng.randint(2, 3)))
        if (p,) not in out:
            out.append((p,))
    return out


# 3 ------------------------------------------------------------------------------------------
P_COINS = '''def fewest_coins(amount: int, coins: list, limit: int) -> int:
    """coins holds distinct positive denominations. You may use each denomination AT MOST limit
    times. Return the fewest coins whose values add up to exactly amount, or -1 if that is
    impossible. amount 0 needs 0 coins.
    >>> fewest_coins(13, [5, 1], 2)
    -1
    >>> fewest_coins(10, [6, 4, 1], 1)
    2
    """
'''
REF_COINS = '''def fewest_coins(amount: int, coins: list, limit: int) -> int:
    INF = float('inf')
    best = [0] + [INF] * amount
    for c in coins:
        nxt = best[:]
        for total in range(amount + 1):
            if best[total] == INF:
                continue
            for n in range(1, limit + 1):
                t = total + n * c
                if t > amount:
                    break
                if best[total] + n < nxt[t]:
                    nxt[t] = best[total] + n
        best = nxt
    return -1 if best[amount] == INF else best[amount]
'''


def brute_coins(amount, coins, limit):
    from itertools import product
    best = None
    for counts in product(range(limit + 1), repeat=len(coins)):
        if sum(n * c for n, c in zip(counts, coins)) == amount:
            best = sum(counts) if best is None else min(best, sum(counts))
    return -1 if best is None else best


def gen_coins(rng):
    out = [(0, [1, 2], 1), (0, [], 3), (7, [], 2), (3, [2], 5), (12, [5, 1], 2), (24, [7, 5, 3], 2),
           (6, [4, 3, 1], 3), (100, [50, 25, 10, 1], 1), (63, [25, 21, 10, 1], 3)]
    while len(out) < 36:
        coins = rng.sample(range(1, 30), rng.randint(1, 5))
        limit = rng.randint(1, 4)
        out.append((rng.randint(0, sum(coins) * limit + 3), coins, limit))
    return out


# 4 ------------------------------------------------------------------------------------------
P_SLOT = '''def first_slot(busy: list, day_start: str, day_end: str, minutes: int):
    """busy has one list per person; each list holds that person's busy times as 'HH:MM-HH:MM'
    strings (24-hour clock, start before end, same day), possibly overlapping and in any order.
    Return the earliest start time 'HH:MM' of a meeting lasting `minutes` that lies fully inside
    day_start..day_end and overlaps nobody's busy time, or None if there is no such time.
    A meeting may start exactly when a busy time ends and may end exactly when one starts.
    >>> first_slot([['09:00-10:00'], ['09:30-10:30']], '09:00', '12:00', 30)
    '10:30'
    >>> first_slot([['09:00-11:50']], '09:00', '12:00', 15)
    None
    """
'''
REF_SLOT = '''def first_slot(busy: list, day_start: str, day_end: str, minutes: int):
    def m(t):
        h, mm = t.split(':')
        return int(h) * 60 + int(mm)
    spans = sorted((m(a), m(b)) for person in busy for s in person for a, b in [s.split('-')])
    t, end = m(day_start), m(day_end)
    for a, b in spans:
        if a >= t + minutes:
            break
        if b > t:
            t = b
    if t + minutes <= end:
        return '%02d:%02d' % divmod(t, 60)
    return None
'''


def brute_slot(busy, day_start, day_end, minutes):
    def m(t):
        return int(t[:2]) * 60 + int(t[3:])
    spans = [(m(s[:5]), m(s[6:])) for p in busy for s in p]
    for t in range(m(day_start), m(day_end) - minutes + 1):
        if all(t + minutes <= a or t >= b for a, b in spans):
            return "%02d:%02d" % divmod(t, 60)
    return None


def gen_slot(rng):
    def hm(x):
        return "%02d:%02d" % divmod(x, 60)
    out = [([], "09:00", "10:00", 60), ([], "09:00", "10:00", 61), ([[]], "08:00", "08:30", 15),
           ([["09:00-10:00"], ["10:00-11:00"]], "09:00", "12:00", 60),
           ([["08:00-09:30"]], "09:00", "17:00", 30), ([["12:00-13:00"]], "09:00", "17:00", 180),
           ([["09:05-09:10", "09:00-09:20"]], "09:00", "09:40", 20)]
    while len(out) < 36:
        start = rng.randrange(6 * 60, 11 * 60, 5)
        end = start + rng.randrange(60, 8 * 60, 5)
        busy = []
        for _ in range(rng.randint(1, 4)):
            p = []
            for _ in range(rng.randint(0, 4)):
                a = rng.randrange(start - 60, end + 30, 5)
                p.append(f"{hm(a)}-{hm(a + rng.randrange(5, 150, 5))}")
            busy.append(p)
        out.append((busy, hm(start), hm(end), rng.choice([15, 30, 45, 60, 90, 120])))
    return out


# 5 ------------------------------------------------------------------------------------------
P_TRUTH = '''def truth(expr: str, env: dict) -> bool:
    """Evaluate a logic formula. Tokens: variable names (lowercase letters and digits, never a keyword),
    the constants true and false, not, and, or, -> and parentheses. Tokens are separated by spaces,
    except that parentheses may touch other tokens. Precedence from tightest to loosest:
    not, and, or, ->. 'and' and 'or' group left to right; '->' (implication: false only when
    the left side is true and the right side is false) groups RIGHT to left, so a -> b -> c
    means a -> (b -> c). env maps every variable to True or False.
    >>> truth('a -> b -> c', {'a': True, 'b': False, 'c': False})
    True
    >>> truth('not a or b and c', {'a': True, 'b': True, 'c': False})
    False
    """
'''
REF_TRUTH = '''def truth(expr: str, env: dict) -> bool:
    toks = expr.replace('(', ' ( ').replace(')', ' ) ').split()
    pos = 0

    def peek():
        return toks[pos] if pos < len(toks) else None

    def take():
        nonlocal pos
        pos += 1
        return toks[pos - 1]

    def imp():
        left = disj()
        if peek() == '->':
            take()
            right = imp()
            return (not left) or right
        return left

    def disj():
        v = conj()
        while peek() == 'or':
            take()
            r = conj()
            v = v or r
        return v

    def conj():
        v = neg()
        while peek() == 'and':
            take()
            r = neg()
            v = v and r
        return v

    def neg():
        if peek() == 'not':
            take()
            return not neg()
        t = take()
        if t == '(':
            v = imp()
            take()
            return v
        if t == 'true':
            return True
        if t == 'false':
            return False
        return bool(env[t])

    return imp()
'''

PREC = {"->": 0, "or": 1, "and": 2, "not": 3, "atom": 4}


def render(node, rng):
    """Render an AST with only the parentheses precedence needs (plus some random extra ones)."""
    kind = node[0]
    if kind == "atom":
        return node[1]
    if kind == "not":
        inner = render(node[1], rng)
        if PREC[node[1][0]] < 3:
            inner = "(" + inner + ")"
        return ("not " + inner) if not inner.startswith("(") else rng.choice(["not ", "not"]) + inner
    op, a, b = kind, node[1], node[2]
    p = PREC[op]
    la, rb = render(a, rng), render(b, rng)
    left_assoc = op in ("and", "or")
    need_l = PREC[a[0]] < p or (not left_assoc and PREC[a[0]] == p)
    need_r = PREC[b[0]] < p or (left_assoc and PREC[b[0]] == p)
    if need_l or rng.random() < 0.1:
        la = "(" + la + ")"
    if need_r or rng.random() < 0.1:
        rb = "(" + rb + ")"
    return f"{la} {op} {rb}"


def value(node, env):
    k = node[0]
    if k == "atom":
        return {"true": True, "false": False}.get(node[1], env.get(node[1]))
    if k == "not":
        return not value(node[1], env)
    a, b = value(node[1], env), value(node[2], env)
    return {"and": a and b, "or": a or b, "->": (not a) or b}[k]


def gen_truth(rng):
    names = ["p", "q", "rain", "wet", "x1"]

    def tree(d):
        if d > 3 or rng.random() < 0.25:
            return ("atom", rng.choice(names + ["true", "false"]))
        k = rng.choice(["not", "and", "or", "->", "->"])
        return (k, tree(d + 1)) if k == "not" else (k, tree(d + 1), tree(d + 1))
    out, BR = [], {}  # BR: expected values computed from the tree, independent of the reference parser
    fixed = {"p": "p", "true": "True", "not false": "not False", "p -> q": "(not p) or q",
             "p -> q -> rain": "(not p) or ((not q) or rain)", "(p -> q) -> rain": "(not ((not p) or q)) or rain",
             "not p or q and rain": "(not p) or (q and rain)", "not(p and q)": "not (p and q)",
             "p and not not q": "p and (not (not q))", "false -> p and q": "True",
             "p or q -> rain and wet": "(not (p or q)) or (rain and wet)"}
    for s, py in fixed.items():
        for _ in range(2):
            env = {n: rng.random() < 0.5 for n in names}
            BR[(s, tuple(sorted(env.items())))] = bool(eval(py, {}, dict(env)))
            out.append((s, env))
    while len(out) < 50:
        t = tree(0)
        env = {n: rng.random() < 0.5 for n in names}
        s = render(t, rng)
        BR[(s, tuple(sorted(env.items())))] = value(t, env)
        out.append((s, env))
    return out, BR


# 6 ------------------------------------------------------------------------------------------
P_AREA = '''def union_area(rects: list) -> int:
    """Each rectangle is [x1, y1, x2, y2] with integers x1 < x2 and y1 < y2 (any size, may be
    negative). Return the total area covered by the union of all rectangles: overlapping parts
    count once. An empty list gives 0.
    >>> union_area([[0, 0, 2, 2], [1, 1, 3, 3]])
    7
    """
'''
REF_AREA = '''def union_area(rects: list) -> int:
    xs = sorted({r[0] for r in rects} | {r[2] for r in rects})
    total = 0
    for i in range(len(xs) - 1):
        a, b = xs[i], xs[i + 1]
        spans = sorted((r[1], r[3]) for r in rects if r[0] <= a and r[2] >= b)
        covered, end = 0, None
        for y1, y2 in spans:
            if end is None or y1 > end:
                covered += y2 - y1
                end = y2
            elif y2 > end:
                covered += y2 - end
                end = y2
        total += covered * (b - a)
    return total
'''


def brute_area(rects):
    cells = set()
    for x1, y1, x2, y2 in rects:
        for x in range(x1, x2):
            for y in range(y1, y2):
                cells.add((x, y))
    return len(cells)


def gen_area(rng):
    out = [([],), ([[0, 0, 1, 1]],), ([[0, 0, 2, 2], [0, 0, 2, 2]],), ([[0, 0, 2, 2], [2, 0, 4, 2]],),
           ([[-3, -3, 3, 3], [-1, -1, 1, 1]],), ([[0, 0, 10, 1], [0, 0, 1, 10]],)]
    while len(out) < 34:
        rs = []
        for _ in range(rng.randint(1, 7)):
            x, y = rng.randint(-15, 15), rng.randint(-15, 15)
            rs.append([x, y, x + rng.randint(1, 12), y + rng.randint(1, 12)])
        out.append((rs,))
    return out


SPECS = [("holdout/1", P_COVER, REF_COVER, "covered_k", brute_cover, gen_cover),
         ("holdout/2", P_EXPAND, REF_EXPAND, "expand", brute_expand, gen_expand),
         ("holdout/3", P_COINS, REF_COINS, "fewest_coins", brute_coins, gen_coins),
         ("holdout/4", P_SLOT, REF_SLOT, "first_slot", brute_slot, gen_slot),
         ("holdout/5", P_TRUTH, REF_TRUTH, "truth", None, gen_truth),
         ("holdout/6", P_AREA, REF_AREA, "union_area", brute_area, gen_area)]
BIG = {  # large inputs only the reference handles (brute force would be too slow); still verified by hand below
    "covered_k": [([[0, 10**9], [5, 10**9 + 5]], 2), ([[-10**12, 10**12]], 1), ([[1, 2]] * 50 + [[0, 3]], 51)],
    "union_area": [([[0, 0, 10**6, 10**6], [5 * 10**5, 5 * 10**5, 2 * 10**6, 2 * 10**6]],)],
}
BIG_EXPECT = {"covered_k": [10**9 - 5, 2 * 10**12, 1], "union_area": [3 * 10**12]}


def main():
    rng = random.Random(20261126)
    out = []
    for tid, prompt, ref, entry, brute, gen in SPECS:
        ns = {}
        exec(ref, ns)
        fn = ns[entry]
        made = gen(rng)
        inputs, br = made if isinstance(made, tuple) else (made, None)
        cases = []
        for args in inputs:
            got = fn(*json.loads(json.dumps(args)))
            if entry == "truth":
                key = (args[0], tuple(sorted(args[1].items())))
                want = br[key]
            else:
                want = brute(*json.loads(json.dumps(args)))
            assert got == want, (tid, args, got, want)
            cases.append([repr(list(args)), repr(got)])
        for args, want in zip(BIG.get(entry, []), BIG_EXPECT.get(entry, [])):
            got = fn(*args)
            assert got == want, (tid, args, got, want)
            cases.append([repr(list(args)), repr(got)])
        for line in [ln for ln in prompt.splitlines() if ln.strip().startswith(">>>")]:  # docstring examples hold
            call = line.strip()[4:]
            exp = prompt.splitlines()[prompt.splitlines().index(line) + 1].strip()
            assert repr(eval(call, dict(ns))) == exp, (tid, call, exp)
        assert len(cases) >= 20
        out.append({"id": tid, "entry": entry, "prompt": prompt, "atol": 0, "cases": cases, "ref": ref})
        print(tid, entry, len(cases), "cases")
    doc = {"source": "GoogolForge original holdout set (v3.8). HOLDOUT: never tune prompts or "
                     "heuristics on these tasks; use them only to check that a gain is real.",
           "tasks": out}
    json.dump(doc, open("data/holdout6.json", "w"), separators=(",", ":"))


if __name__ == "__main__":
    sys.exit(main())
