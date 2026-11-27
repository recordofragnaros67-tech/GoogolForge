#!/usr/bin/env python3
"""Build data/mbppplus40.json: a fixed 40-task slice of EvalPlus MBPP+ (v0.2.0, Apache-2.0,
github.com/evalplus/mbppplus_release).
  python tools/build_mbppplus.py [MbppPlus.jsonl.gz]
Only tasks a plain equality check can judge fairly are eligible:
  - the prompt's worked example is a plain `assert f(args) == expected`,
  - its arguments equal the first stored base input exactly (so JSON did not turn tuples into lists),
  - the canonical solution reproduces that expected value,
  - not one of EvalPlus's set-order or not-None special cases, and no `set(` in the prompt.
From the eligible tasks, 40 are taken evenly spaced (fixed, no randomness). Expected outputs
come from the canonical solutions, up to 100 inputs per task (base inputs first)."""
import ast, json, math, sys
from build_heplus import load, make_cases

URL = "https://github.com/evalplus/mbppplus_release/releases/download/v0.2.0/MbppPlus.jsonl.gz"
SPECIAL = {"similar_elements", "find_char_long", "common_in_nested_lists", "extract_singly", "larg_nnum",
           "intersection_array", "find_dissimilar", "Diff", "check_str", "text_match_three", "text_starta_endb"}
N, MAX_CASES = 40, 100


def close(a, b):
    if isinstance(a, float) or isinstance(b, float):
        try:
            return math.isclose(a, b, rel_tol=1e-6, abs_tol=1e-9)
        except TypeError:
            return False
    return type(a) == type(b) and a == b


def example(r):
    """(args, expected) from the prompt's `assert entry(args) == expected`, else None."""
    lines = [ln.strip() for ln in r["prompt"].splitlines() if ln.strip().startswith("assert ")]
    if len(lines) != 1 or "set(" in r["prompt"]:
        return None
    try:
        t = ast.parse(lines[0]).body[0].test
    except (SyntaxError, IndexError, AttributeError):
        return None
    if not (isinstance(t, ast.Compare) and len(t.ops) == 1 and isinstance(t.ops[0], ast.Eq)
            and isinstance(t.left, ast.Call) and isinstance(t.left.func, ast.Name)
            and t.left.func.id == r["entry_point"] and not t.left.keywords):
        return None
    try:
        return [ast.literal_eval(a) for a in t.left.args], ast.literal_eval(t.comparators[0])
    except (ValueError, SyntaxError, TypeError):
        return None


def main(argv):
    rows = load(argv[0] if argv else None, URL)
    ok = []
    for r in rows:
        ex = example(r)
        if r["entry_point"] in SPECIAL or ex is None or not r["base_input"] or ex[0] != r["base_input"][0]:
            continue
        ns = {}
        try:
            exec(r["canonical_solution"], ns)
            if not close(ns[r["entry_point"]](*ex[0]), ex[1]):
                continue
        except Exception:
            continue
        ok.append(r)
    pick = [ok[i * len(ok) // N] for i in range(N)]
    out = []
    for r in pick:
        ns = {}
        exec(r["canonical_solution"], ns)
        cases = make_cases(ns[r["entry_point"]], r["base_input"], r["plus_input"], MAX_CASES)
        out.append({"id": r["task_id"], "entry": r["entry_point"], "prompt": r["prompt"], "prefix": "",
                    "atol": r.get("atol", 0) or 0, "cases": cases, "ref": r["canonical_solution"]})
        print(r["task_id"], r["entry_point"], len(r["base_input"]), len(r["plus_input"]), "->", len(cases))
    print(f"{len(ok)} of {len(rows)} tasks eligible, {len(out)} picked")
    json.dump({"source": f"EvalPlus MBPP+ v0.2.0 (Apache-2.0), {N} evenly spaced eligible tasks", "tasks": out},
              open("data/mbppplus40.json", "w"), separators=(",", ":"))


if __name__ == "__main__":
    main(sys.argv[1:])
