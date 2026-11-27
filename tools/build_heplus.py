#!/usr/bin/env python3
"""Build the HumanEval+ data files from EvalPlus HumanEval+ (v0.1.10, Apache-2.0).
  python tools/build_heplus.py [HumanEvalPlus.jsonl.gz]         -> data/heplus40.json
      fixed 40-task slice: every 4th task (HumanEval/0, /4, /8 ... /156), up to 120 inputs each
  python tools/build_heplus.py --full [HumanEvalPlus.jsonl.gz]  -> data/heplus164.json.gz
      all 164 tasks, up to 80 inputs each (base inputs first), gzip-compressed to stay small
Expected outputs come from each task's canonical solution, run here once. Only inputs whose
repr round-trips exactly are kept. tools/build_mbppplus.py reuses make_cases()."""
import copy, gzip, json, math, signal, sys, urllib.request
URL = "https://github.com/evalplus/humanevalplus_release/releases/download/v0.1.10/HumanEvalPlus.jsonl.gz"


class Slow(Exception):
    pass


def alarm(*_):
    raise Slow()


def same(a, b):
    return a == b or (isinstance(a, float) and isinstance(b, float) and math.isnan(a) and math.isnan(b))


def make_cases(fn, base, plus, max_cases, max_len=4000):
    """Run the canonical solution on base inputs, then an even spread of plus inputs."""
    signal.signal(signal.SIGALRM, alarm)
    step = max(1, len(plus) // max(1, max_cases - len(base)))
    cases = []
    for inp in base + plus[::step]:
        try:
            signal.alarm(2)
            res = fn(*copy.deepcopy(inp))
            signal.alarm(0)
        except BaseException:
            signal.alarm(0)
            continue
        try:
            ri, ro = repr(inp), repr(res)
            if eval(ri) != inp or not same(eval(ro), res):
                continue
        except BaseException:
            continue
        if len(ri) + len(ro) > max_len:
            continue
        cases.append([ri, ro])
        if len(cases) >= max_cases:
            break
    return cases


def load(src, url):
    raw = gzip.open(src) if src else gzip.GzipFile(fileobj=urllib.request.urlopen(url))
    return [json.loads(line) for line in raw]


def main(argv):
    full = "--full" in argv
    rest = [a for a in argv if not a.startswith("--")]
    rows = load(rest[0] if rest else None, URL)
    pick, max_cases = (rows, 80) if full else (rows[0::4][:40], 120)  # base inputs always kept
    out = []
    for r in pick:
        ns = {}
        exec(r["prompt"] + r["canonical_solution"], ns)
        fn = ns[r["entry_point"]]
        base, plus = r["base_input"], r["plus_input"]
        cases = make_cases(fn, base, plus, max_cases, 2500 if full else 4000)
        hdr = "".join(ln + "\n" for ln in r["prompt"].splitlines() if ln.startswith(("import ", "from ")))
        out.append({"id": r["task_id"], "entry": r["entry_point"], "prompt": r["prompt"], "imports": hdr,
                    "atol": r.get("atol", 0) or 0, "cases": cases, "ref": r["canonical_solution"]})
        print(r["task_id"], r["entry_point"], len(base), len(plus), "->", len(cases))
    if full:
        doc = {"source": "EvalPlus HumanEval+ v0.1.10 (Apache-2.0), all 164 tasks, up to 80 inputs each",
               "tasks": out}
        with gzip.GzipFile("data/heplus164.json.gz", "wb", mtime=0) as f:
            f.write(json.dumps(doc, separators=(",", ":")).encode())
    else:
        json.dump({"source": "EvalPlus HumanEval+ v0.1.10 (Apache-2.0), every 4th task", "tasks": out},
                  open("data/heplus40.json", "w"), separators=(",", ":"))


if __name__ == "__main__":
    main(sys.argv[1:])
