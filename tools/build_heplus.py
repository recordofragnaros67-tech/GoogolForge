#!/usr/bin/env python3
"""Build data/heplus40.json: a fixed 40-task slice of EvalPlus HumanEval+ (v0.1.10, Apache-2.0).
Slice = every 4th task (HumanEval/0, /4, /8 ... /156). Expected outputs come from each task's
canonical solution, run here once. Only inputs whose repr round-trips exactly are kept."""
import copy, gzip, json, math, signal, sys, urllib.request
URL = "https://github.com/evalplus/humanevalplus_release/releases/download/v0.1.10/HumanEvalPlus.jsonl.gz"
src = sys.argv[1] if len(sys.argv) > 1 else None
raw = gzip.open(src) if src else gzip.GzipFile(fileobj=urllib.request.urlopen(URL))
rows = [json.loads(l) for l in raw]
MAX_CASES = 120  # keeps each check fast on a phone; base inputs always kept

class Slow(Exception): pass
def alarm(*_): raise Slow()
signal.signal(signal.SIGALRM, alarm)

def same(a, b):
    return a == b or (isinstance(a, float) and isinstance(b, float) and math.isnan(a) and math.isnan(b))

out = []
for r in rows[0::4][:40]:
    ns = {}
    exec(r["prompt"] + r["canonical_solution"], ns)
    fn = ns[r["entry_point"]]
    base, plus = r["base_input"], r["plus_input"]
    step = max(1, len(plus) // max(1, MAX_CASES - len(base)))
    cases = []
    for inp in base + plus[::step]:
        try:
            signal.alarm(2)
            res = fn(*copy.deepcopy(inp))
            signal.alarm(0)
        except Exception:
            signal.alarm(0)
            continue
        ri, ro = repr(inp), repr(res)
        try:
            if eval(ri) != inp or not same(eval(ro), res):
                continue
        except Exception:
            continue
        if len(ri) + len(ro) > 4000:
            continue
        cases.append([ri, ro])
        if len(cases) >= MAX_CASES:
            break
    hdr = "".join(l + "\n" for l in r["prompt"].splitlines() if l.startswith(("import ", "from ")))
    out.append({"id": r["task_id"], "entry": r["entry_point"], "prompt": r["prompt"], "imports": hdr,
                "atol": r.get("atol", 0) or 0, "cases": cases, "ref": r["canonical_solution"]})
    print(r["task_id"], r["entry_point"], len(base), len(plus), "->", len(cases))
json.dump({"source": "EvalPlus HumanEval+ v0.1.10 (Apache-2.0), every 4th task", "tasks": out},
          open("data/heplus40.json", "w"), separators=(",", ":"))
