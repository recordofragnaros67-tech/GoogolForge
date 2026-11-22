#!/usr/bin/env python3
"""GoogolForge Self-Repair Memory v1.0 - the debugger learns from every fix.
Each successful fix is saved as a lesson: the error's fingerprint plus the lines that changed.
When a similar error shows up later, the best past lessons go into the AI's prompt."""
import difflib, json, os, pathlib, re, sys
sys.dont_write_bytecode = True

HOME = pathlib.Path(os.environ.get("GF_HOME", str(pathlib.Path.home() / "googolforge")))
MEM = HOME / "repair_memory.json"
MAX = 200


def load():
    try:
        return json.loads(MEM.read_text())
    except Exception:
        return []


def save(items):
    HOME.mkdir(parents=True, exist_ok=True)
    MEM.write_text(json.dumps(items[-MAX:], indent=1))


def fingerprint(err):
    """Turn raw error output into (type, normalized words)."""
    lines = [l.strip() for l in (err or "").strip().splitlines() if l.strip()]
    last = ""
    for l in reversed(lines):
        if re.match(r"^[A-Za-z_][\w.]*(Error|Exception|Exit)\b", l) or l.startswith("AssertionError"):
            last = l
            break
    if not last:
        last = lines[-1] if lines else ""
    etype = re.match(r"^([\w.]+)", last).group(1) if re.match(r"^([\w.]+)", last) else "Unknown"
    msg = last[len(etype):]
    msg = re.sub(r"'[^']*'|\"[^\"]*\"", " Q ", msg)      # names and strings
    msg = re.sub(r"\d+", " N ", msg)                     # numbers
    words = sorted(set(w for w in re.findall(r"[a-zA-Z]+", msg.lower()) if len(w) > 1))
    return etype, words


def change_summary(before, after, limit=12):
    diff = [l for l in difflib.unified_diff((before or "").splitlines(), (after or "").splitlines(), lineterm="", n=0)
            if (l.startswith("+") or l.startswith("-")) and not l.startswith(("+++", "---"))]
    return "\n".join(diff[:limit])


def record(err, fname, before, after):
    etype, words = fingerprint(err)
    change = change_summary(before, after)
    if not change:
        return None
    items = load()
    items = [i for i in items if not (i["type"] == etype and i["words"] == words and i["change"] == change)]
    item = {"type": etype, "words": words, "file": fname, "change": change, "uses": 0}
    items.append(item)
    save(items)
    return item


def similar(err, k=3):
    etype, words = fingerprint(err)
    scored = []
    for i in load():
        if i["type"] != etype:
            continue
        a, b = set(words), set(i["words"])
        sim = len(a & b) / len(a | b) if (a | b) else 1.0
        if sim >= 0.3:
            scored.append((sim, i.get("uses", 0), i))
    scored.sort(key=lambda t: (-t[0], -t[1]))
    return [t[2] for t in scored[:k]]


def hints(err):
    found = similar(err)
    if not found:
        return ""
    items = load()
    for f in found:  # count how often each lesson is reused
        for i in items:
            if i == f:
                i["uses"] = i.get("uses", 0) + 1
    save(items)
    out = "\nPast fixes for similar errors in this project (use them if they apply):\n"
    for n, f in enumerate(found, 1):
        out += f"Fix {n} ({f['type']} in {f['file']}):\n{f['change']}\n"
    return out


def show():
    items = load()
    if not items:
        print("No repair lessons yet. They're saved automatically when forge debug or forge run fixes something.")
        return
    print(f"SELF-REPAIR MEMORY: {len(items)} lesson(s)\n")
    for i in items[-15:]:
        print(f"  {i['type']:<20} {i['file']:<18} used {i.get('uses', 0)}x   words: {' '.join(i['words'][:6])}")


def selftest():
    global MEM
    import tempfile
    fails = 0

    def chk(n, c):
        nonlocal fails
        print(("PASS " if c else "FAIL ") + n)
        fails += not c

    with tempfile.TemporaryDirectory() as d:
        MEM = pathlib.Path(d) / "m.json"
        e1 = 'Traceback...\n  File "a.py", line 3\nNameError: name \'totl\' is not defined'
        e2 = 'Traceback...\n  File "b.py", line 9\nNameError: name \'cnt\' is not defined'
        e3 = "TypeError: unsupported operand type(s) for +: 'int' and 'str'"
        chk("fingerprint ignores names and numbers", fingerprint(e1) == fingerprint(e2))
        chk("different errors differ", fingerprint(e1) != fingerprint(e3))
        chk("record saves the change", record(e1, "a.py", "x = totl + 1", "x = total + 1") is not None)
        chk("no change, no lesson", record(e1, "a.py", "same", "same") is None)
        chk("similar error finds the lesson", len(similar(e2)) == 1)
        chk("unrelated error finds nothing", similar(e3) == [])
        h = hints(e2)
        chk("hint contains the fix", "+x = total + 1" in h and "-x = totl + 1" in h)
        chk("reuse is counted", load()[0]["uses"] == 1)
        record(e1, "a.py", "x = totl + 1", "x = total + 1")
        chk("duplicates are not stored twice", len(load()) == 1)
        chk("assertion errors fingerprint", fingerprint("Traceback\nAssertionError")[0] == "AssertionError")
    print(f"\nSELFTEST: {'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
    return fails == 0


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["selftest"]:
        sys.exit(0 if selftest() else 1)
    elif a[:1] == ["clear"]:
        save([])
        print("Repair memory cleared.")
    else:
        show()
