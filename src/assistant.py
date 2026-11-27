#!/usr/bin/env python3
"""GoogolForge Assistant v1.6 - talk to GoogolForge in plain English.
Two-layer router: fast rules first, then the AI. Every AI choice is checked
against a fixed command list before anything runs. Risky actions ask first."""
import json, os, pathlib, re, subprocess, sys, urllib.request
sys.dont_write_bytecode = True

HOME = pathlib.Path(os.environ.get("GF_HOME", str(pathlib.Path.home() / "googolforge")))
WORK = HOME / "workspace"
MEM = HOME / "chat_memory.json"
CONF = HOME / "config.json"
FORGE = HOME / "forge.py"
ACADEMY = HOME / "academy.py"
GF = HOME / "gf.py"
NOPROXY = urllib.request.build_opener(urllib.request.ProxyHandler({}))

# command: (program, needs, risky, description)
#   needs: none | text (a goal/topic/question) | file | number
CATALOG = {
    "pipeline": ("forge", "text", False, "build a whole project from a goal"),
    "plan":     ("forge", "text", False, "plan a project without building"),
    "run":      ("forge", "none", False, "build the planned tasks"),
    "status":   ("forge", "none", False, "show project progress"),
    "retry":    ("forge", "none", False, "reset failed tasks so they can run again"),
    "debug":    ("forge", "file", False, "find and fix bugs in a file"),
    "review":   ("forge", "file", False, "score a file with the judge AI"),
    "lint":     ("forge", "none", False, "check all code for errors"),
    "report":   ("forge", "none", False, "full project scorecard"),
    "export":   ("forge", "none", False, "zip the project to your phone"),
    "doctor":   ("forge", "none", False, "check the AI and models are ready"),
    "publish":  ("forge", "none", True,  "push to GitHub and your free website"),
    "ask":      ("forge", "text", False, "answer a coding question"),
    "daily":    ("academy", "none", False, "lesson + quiz + drill"),
    "lesson":   ("academy", "text?", False, "teach a Python topic"),
    "quiz":     ("academy", "text?", False, "quiz on a topic"),
    "drill":    ("academy", "text?", False, "coding exercise"),
    "check":    ("academy", "number?", False, "test your drill answer"),
    "solution": ("academy", "number?", True, "reveal a drill answer (no XP)"),
    "progress": ("academy", "none", False, "rank, XP and streak"),
    "bench":    ("gf", "none", False, "score the AI on hidden coding tests (quick)"),
    "shootout": ("gf", "none", True,  "rank every installed AI model (slow)"),
    "new":      ("gf", "template", False, "start a project from a template: game, cli, api, bot, data"),
    "path":     ("gf", "pathstep", False, "Season 2: today's mission (go = start, done = finish)"),
    "lessons":  ("gf", "none", False, "what the debugger has learned"),
    "health":   ("gf", "none", False, "self-test every GoogolForge system"),
    "mutate":   ("gf", "file", False, "plant bugs to see if your tests catch them"),
    "explain":  ("gf", "file", False, "explain a file line by line"),
    "index":    ("gf", "none", False, "build code memory of your project"),
    "rag":      ("gf", "text", False, "answer a question using your own code"),
    "team":     ("gf", "text", False, "Architect, Coder and Tester AIs build it together"),
    "duel":     ("gf", "duelstep", False, "you vs the AI on hidden tests (check = score it)"),
    "ci":       ("gf", "none", False, "set up the free GitHub cloud test robot"),
    "genius":   ("gf", "none", True,  "Genius mode exam: 4 drafts, spec tests, strong-model escalation (slow)"),
    "losses":   ("gf", "none", False, "show what the last exam got wrong"),
    "heplus":   ("gf", "none", False, "HumanEval+ quick exam (8 public tasks)"),
    "holdout":  ("gf", "none", True,  "holdout exam: 6 never-tuned tasks, the honest test (slow)"),
}
GF_ARGS = {"bench": ["bench", "--quick"], "shootout": ["shootout"], "lessons": ["lessons"], "health": ["test"],
           "genius": ["bench", "--genius", "--hard"], "losses": ["bench", "losses"],
           "heplus": ["bench", "--heplus", "--quick"], "holdout": ["bench", "--holdout"]}
KINDS = {"game": "game", "cli": "cli", "todo": "cli", "to-do": "cli", "api": "api", "server": "api",
         "bot": "bot", "chatbot": "bot", "data": "data", "csv": "data", "stats": "data"}

RULES = [  # (regex, command, how to get the argument)
    (r"\bholdout\b", "holdout", None),
    (r"\b(what did (it|the ai) get wrong|losses|wrong answers)\b", "losses", None),
    (r"\bhuman.?eval\b", "heplus", None),
    (r"\bgenius\b", "genius", None),
    (r"\b(mutat\w*|test my tests|how good are my tests)\b", "mutate", "file"),
    (r"\bexplain\b.*\.py\b|\bexplain (my|the|this)\b.*\b(code|file|program)\b|\bwalk me through\b", "explain", "file"),
    (r"\b(re)?index\b", "index", None),
    (r"\b(in|search|from) my (own )?(code|project)\b|\bwhere in my code\b", "rag", "goal"),
    (r"\b(ai )?team (build|make|create|code)\b|\bteam mode\b", "team", "teamgoal"),
    (r"\bduel\b", "duel", "duelstep"),
    (r"\b(cloud test\w*|test robot|github actions|ci)\b", "ci", None),
    (r"\b(what (have|did) (you|the debugger|it) learn\w*|repair memory|lessons learned|fix memory)\b", "lessons", None),
    (r"\b(test everything|check (all|everything)|all systems|system check|self.?test)\b", "health", None),
    (r"\b(shoot.?out|compare (the |all )?(ai )?models|best (ai )?model|which model)\b", "shootout", None),
    (r"\b(benchmark|bench|score the ai|how (good|smart) is the ai)\b", "bench", None),
    (r"\b(season ?2|season two|my path|30.?day|mission)\b", "path", "pathstep"),
    (r"\b(template|starter)\b|\bnew (game|cli|api|bot|chatbot|data|todo|to-do) (project|app|template)\b", "new", "template"),
    (r"\b(fix|debug|repair|broken|bug|error in|crash\w*|not working|doesn.?t work)\b", "debug", "file"),
    (r"\b(review|grade|score|rate)\b.*\b(code|file|\.py)\b", "review", "file"),
    (r"\b(publish|deploy|put .* online|go live|website live)\b", "publish", None),
    (r"\b(daily|today'?s (training|lesson|session)|train me)\b", "daily", None),
    (r"\b(my )?(progress|rank|xp|streak|level)\b", "progress", None),
    (r"\b(check|test) (my )?(drill|answer|solution)\b", "check", "number"),
    (r"\b(show|reveal|give)( me)? (the )?(answer|solution)\b", "solution", "number"),
    (r"\b(quiz|test me)\b", "quiz", "topic"),
    (r"\b(drill|exercise|practice|challenge)\b", "drill", "topic"),
    (r"\b(teach|lesson|explain how|learn about)\b", "lesson", "topic"),
    (r"\b(status|where am i|how far)\b", "status", None),
    (r"\b(report|scorecard|results)\b", "report", None),
    (r"\b(retry|try again|redo failed)\b", "retry", None),
    (r"\b(export|zip|backup|back up|save to (my )?phone)\b", "export", None),
    (r"\b(doctor|health check|is (the )?ai (ready|running))\b", "doctor", None),
    (r"\blint\b", "lint", None),
    (r"\b(continue|keep building|resume)\b", "run", None),
    (r"\b(build|make|create|write|code) (me )?(a|an|the|my)\b", "pipeline", "goal"),
    (r"^\s*(what|why|how|when|which|can|does|is|are)\b|\?\s*$", "ask", "goal"),
]


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


def ai(prompt, fmt=None, model=None):
    body = {"model": model or C["judge"], "prompt": prompt, "stream": False,
            "options": {"temperature": 0.1, "num_predict": 1536, "repeat_penalty": 1.1, "num_thread": int(C.get("threads", 5))}}
    if fmt:
        body["format"] = fmt
    req = urllib.request.Request(C["ollama"] + "/api/generate", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        with NOPROXY.open(req, timeout=300) as r:
            return json.loads(r.read())["response"]
    except Exception:
        return None


def parse_json(text):
    try:
        return json.loads(text)
    except Exception:
        m = re.search(r"\{.*\}", text or "", re.S)
        try:
            return json.loads(m.group(0)) if m else {}
        except Exception:
            return {}


# ---------- memory ----------
def mem_load():
    if MEM.exists():
        try:
            return json.loads(MEM.read_text())
        except Exception:
            pass
    return {"history": [], "last_file": "", "last_topic": ""}


def mem_save(m):
    m["history"] = m["history"][-20:]
    HOME.mkdir(parents=True, exist_ok=True)
    MEM.write_text(json.dumps(m, indent=2))


# ---------- argument helpers ----------
def find_file(text, m):
    hit = re.search(r"([\w\-/]+\.py)\b", text)
    if hit:
        name = pathlib.Path(hit.group(1)).name
        if (WORK / name).exists():
            return name
    files = sorted(WORK.glob("*.py"), key=lambda p: p.stat().st_mtime) if WORK.exists() else []
    if files:
        for f in files:  # a file named in plain words, e.g. "the calculator"
            if f.stem.lower() in text.lower():
                return f.name
    if m.get("last_file") and (WORK / m["last_file"]).exists():
        return m["last_file"]
    return files[-1].name if files else ""


def find_number(text):
    hit = re.search(r"\b(\d{1,3})\b", text)
    return hit.group(1) if hit else ""


FILLER = r"^(please |can you |could you |hey |ok |okay )*(build|make|create|write|code|teach|quiz|drill|give)( me)?( on| about)?( an| a| the)?\b\s*"


def find_topic(text):
    after = re.search(r"\b(?:on|about|for|with)\s+(.+)$", text, flags=re.I)
    if after:
        text = after.group(1)
    t = re.sub(r"\b(quiz|test me|drill|exercise|practice|challenge|lesson|teach me|teach|learn about|explain how)\b", " ", text, flags=re.I)
    t = re.sub(r"\b(please|me|a|an|on|about|in|some|give|python|to|do)\b", " ", t, flags=re.I)
    t = re.sub(r"[^\w\s]", " ", t)
    return re.sub(r"\s+", " ", t).strip()


def find_template(text):
    low = text.lower()
    kind = next((v for k, v in KINDS.items() if re.search(r"\b" + re.escape(k) + r"\b", low)), "game")
    named = re.search(r"\b(?:called|named)\s+([a-z][\w\-]*)", low)
    name = re.sub(r"[^a-z0-9_]", "_", named.group(1)) if named else "my_" + kind
    return f"{kind} {name}"


def find_pathstep(text):
    low = text.lower()
    if re.search(r"\b(done|finished|complete[d]?|mark)\b", low):
        return "done"
    if re.search(r"\b(start|begin|go|let'?s)\b", low):
        return "go"
    return ""


def clean_goal(text):
    return re.sub(FILLER, "", text.strip(), flags=re.I).strip() or text.strip()


# ---------- routing ----------
def by_rules(text, m):
    low = text.lower()
    for pat, cmd, kind in RULES:
        if re.search(pat, low):
            arg = ""
            if kind == "file":
                arg = find_file(text, m)
            elif kind == "number":
                arg = find_number(text)
            elif kind == "topic":
                arg = find_topic(text)
            elif kind == "template":
                arg = find_template(text)
            elif kind == "pathstep":
                arg = find_pathstep(text)
            elif kind == "duelstep":
                arg = "check" if re.search(r"\b(check|score|done|finished|judge)\b", low) else ""
            elif kind == "teamgoal":
                arg = re.sub(r"^.*?\bteam (mode )?(build|make|create|code)?( me)?( an?| the)?\s*", "", text, flags=re.I).strip() or text.strip()
            elif kind == "goal":
                arg = clean_goal(text) if cmd == "pipeline" else text.strip()
            return {"command": cmd, "arg": arg, "via": "rules"}
    return None


def by_ai(text, m):
    menu = "\n".join(f"- {k}: {v[3]} (argument: {v[1]})" for k, v in CATALOG.items())
    recent = "\n".join(f"{h['you']} -> {h['cmd']}" for h in m["history"][-4:])
    files = ", ".join(p.name for p in sorted(WORK.glob("*.py"))[:15]) if WORK.exists() else ""
    out = ai("You route requests for a coding app. Pick exactly ONE command from this menu:\n" + menu +
             f"\nProject files: {files or 'none'}\nRecent:\n{recent or 'none'}\n"
             "Reply ONLY with JSON: {\"command\":\"name\",\"arg\":\"argument or empty\"}\n"
             "If unsure, use ask with the user's words as arg.\nRequest: " + text, fmt="json")
    d = parse_json(out)
    if not d:
        return None
    return {"command": str(d.get("command", "")).strip().lower(), "arg": str(d.get("arg", "")).strip(), "via": "ai"}


def validate(choice, text, m):
    """Layer two: the rule checker. Nothing outside the menu ever runs."""
    if not choice or choice["command"] not in CATALOG:
        return {"command": "ask", "arg": text.strip(), "via": "fallback"}
    need = CATALOG[choice["command"]][1]
    arg = re.sub(r"[\x00-\x1f]", " ", choice.get("arg", ""))[:300]
    if need == "file":
        name = pathlib.Path(arg).name if arg else ""
        if not name.endswith(".py") or not (WORK / name).exists():
            name = find_file(text, m)
        if not name:
            return {"command": "status", "arg": "", "via": choice["via"],
                    "note": "No code files yet. Build something first."}
        arg = name
    elif need.startswith("number"):
        arg = arg if arg.isdigit() else find_number(text)
    elif need == "template":
        parts = arg.lower().split()
        kind = KINDS.get(parts[0], "") if parts else ""
        name = re.sub(r"[^a-z0-9_]", "_", parts[1])[:40] if len(parts) > 1 else ""
        arg = f"{kind} {name or 'my_' + kind}" if kind else find_template(text)
    elif need == "duelstep":
        arg = "check" if arg.lower() == "check" else ""
    elif need == "pathstep":
        arg = arg.lower() if arg.lower() in ("go", "done") else find_pathstep(text)
    elif need == "text" and not arg:
        arg = text.strip()
    elif need == "none":
        arg = ""
    choice["arg"] = arg
    return choice


def route(text, m, use_ai=True):
    c = by_rules(text, m)
    if not c and use_ai:
        c = by_ai(text, m)
    return validate(c, text, m)


def command_line(c):
    prog, need, _, _ = CATALOG[c["command"]]
    if prog == "gf":
        base = [sys.executable, str(GF)]
        if c["command"] in GF_ARGS:
            return base + GF_ARGS[c["command"]]
        return base + [c["command"]] + (c["arg"].split() if c["arg"] else [])
    script = FORGE if prog == "forge" else ACADEMY
    args = [sys.executable, str(script), c["command"]]
    if c["arg"]:
        args += c["arg"].split() if need in ("text?",) else [c["arg"]]
    return args


def shown(c):
    prog = CATALOG[c["command"]][0]
    a = c["arg"]
    if a and " " in a:
        a = f'"{a}"'
    return f"{prog} {c['command']} {a}".strip()


def execute(c, m, text, dry=False):
    if c.get("note"):
        print(c["note"])
    print(f"-> {shown(c)}", flush=True)
    if CATALOG[c["command"]][2]:
        try:
            ok = input("This one's a big step. Run it? (y/n): ").strip().lower().startswith("y")
        except EOFError:
            ok = False
        if not ok:
            print("Skipped.")
            return
    m["history"].append({"you": text, "cmd": shown(c)})
    if CATALOG[c["command"]][1] == "file":
        m["last_file"] = c["arg"]
    mem_save(m)
    if dry:
        return
    try:
        subprocess.run(command_line(c))  # list form: no shell, no injection
    except KeyboardInterrupt:
        print("\nStopped.")


HELP = """Talk normally. Examples:
  build me a tip calculator          fix my calculator
  how's my project going?            review calculator.py
  quiz me on loops                   check my drill
  give me today's training           publish it
Type 'menu' for all commands, 'history' for recent ones, 'exit' to leave."""


def chat(dry=False):
    m = mem_load()
    print("GoogolForge Assistant. Tell me what you want in plain English.\n" + HELP)
    while True:
        try:
            text = input("\nyou> ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nSee you next session.")
            break
        if not text:
            continue
        low = text.lower()
        if low in ("exit", "quit", "bye", "q"):
            print("See you next session.")
            break
        if low in ("help", "?"):
            print(HELP)
            continue
        if low == "menu":
            for k, v in CATALOG.items():
                print(f"  {v[0]} {k:<9} {v[3]}")
            continue
        if low == "history":
            for h in m["history"][-10:]:
                print(f"  {h['you']}  ->  {h['cmd']}")
            continue
        execute(route(text, m), m, text, dry)


def selftest():
    import tempfile
    global WORK, MEM
    fails = 0

    def chk(name, cond):
        nonlocal fails
        print(("PASS " if cond else "FAIL ") + name)
        fails += not cond

    with tempfile.TemporaryDirectory() as d:
        WORK, MEM = pathlib.Path(d) / "workspace", pathlib.Path(d) / "mem.json"
        WORK.mkdir()
        (WORK / "calculator.py").write_text("x=1\n")
        (WORK / "game.py").write_text("y=2\n")
        m = mem_load()
        cases = [
            ("build me a tip calculator app", "pipeline", "tip calculator app"),
            ("fix my calculator", "debug", "calculator.py"),
            ("there's a bug in game.py", "debug", "game.py"),
            ("review calculator.py code", "review", "calculator.py"),
            ("how far along is my project", "status", ""),
            ("quiz me on loops", "quiz", "loops"),
            ("give me a drill on dictionaries", "drill", "dictionaries"),
            ("check my drill 3", "check", "3"),
            ("teach me recursion", "lesson", "recursion"),
            ("give me today's training", "daily", ""),
            ("what's my rank", "progress", ""),
            ("publish it", "publish", ""),
            ("back up my project", "export", ""),
            ("what is a list comprehension?", "ask", "what is a list comprehension?"),
            ("show me the solution", "solution", ""),
            ("my calculator keeps crashing", "debug", "calculator.py"),
            ("make an inventory tracker for my store", "pipeline", "inventory tracker for my store"),
            ("ready for practice on string methods", "drill", "string methods"),
            ("benchmark the ai", "bench", ""),
            ("which model is best?", "shootout", ""),
            ("give me a chatbot starter called helper", "new", "bot helper"),
            ("new todo app template", "new", "cli my_cli"),
            ("what's my season 2 mission", "path", ""),
            ("I finished today's mission", "path", "done"),
            ("let's start my 30-day path", "path", "go"),
            ("what have you learned from my bugs", "lessons", ""),
            ("check everything", "health", ""),
            ("how good are my tests in calculator.py", "mutate", "calculator.py"),
            ("explain my calculator code", "explain", "calculator.py"),
            ("index my project", "index", ""),
            ("in my code, where is the score saved?", "rag", "in my code, where is the score saved?"),
            ("team build a stopwatch app", "team", "stopwatch app"),
            ("start a duel", "duel", ""),
            ("check my duel", "duel", "check"),
            ("set up the cloud tests", "ci", ""),
        ]
        for text, cmd, arg in cases:
            r = route(text, m, use_ai=False)
            chk(f"'{text}' -> {cmd} {arg}".rstrip(), r["command"] == cmd and r["arg"] == arg)
        bad = validate({"command": "rm -rf", "arg": "/", "via": "ai"}, "delete everything", m)
        chk("unknown AI command falls back to ask", bad["command"] == "ask")
        inj = validate({"command": "debug", "arg": "../../etc/passwd; rm -rf ~", "via": "ai"}, "fix it", m)
        chk("bad file argument is replaced with a real project file", inj["arg"] in ("calculator.py", "game.py"))
        chk("risky commands are flagged", CATALOG["publish"][2] and CATALOG["solution"][2] and CATALOG["shootout"][2])
        t = validate({"command": "new", "arg": "rocket; rm -rf ~", "via": "ai"}, "make a game starter", m)
        chk("bad template argument is cleaned", t["arg"] == "game my_game")
        t = validate({"command": "new", "arg": "bot ../../evil", "via": "ai"}, "x", m)
        chk("template name can't escape the folder", t["arg"] == "bot ______evil")
        chk("duel step only allows check", validate({"command": "duel", "arg": "; rm", "via": "ai"}, "duel", m)["arg"] == "")
        chk("path step only allows go/done", validate({"command": "path", "arg": "rm", "via": "ai"}, "path", m)["arg"] == "")
        chk("gf commands build the right line", command_line({"command": "new", "arg": "game guess"})[-3:] == ["new", "game", "guess"]
            and command_line({"command": "bench", "arg": ""})[-2:] == ["bench", "--quick"])
        chk("commands run without a shell", isinstance(command_line({"command": "status", "arg": ""}), list))
        mem_save({"history": [{"you": "x", "cmd": "y"}] * 30, "last_file": "game.py", "last_topic": ""})
        chk("memory keeps the last 20 turns", len(mem_load()["history"]) == 20)
        chk("'fix it' remembers the last file", route("fix it", mem_load(), use_ai=False)["arg"] == "game.py")
    print(f"\nSELFTEST: {'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
    return fails == 0


def main():
    a = sys.argv[1:]
    if a and a[0] == "selftest":
        sys.exit(0 if selftest() else 1)
    if a and a[0] == "--dry":
        chat(dry=True)
    elif a:  # one-shot: forge chat "build me a game"
        m = mem_load()
        text = " ".join(a)
        execute(route(text, m), m, text)
    else:
        chat()


if __name__ == "__main__":
    main()
