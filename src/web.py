#!/usr/bin/env python3
"""GoogolForge Dashboard v1.7 - control GoogolForge from Chrome on your phone.
Private: listens only on 127.0.0.1 and every request needs a secret token.
Requests go through the Assistant's router and validator, so only menu commands run."""
import json, os, pathlib, secrets, subprocess, sys, threading, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
sys.dont_write_bytecode = True

HOME = pathlib.Path(os.environ.get("GF_HOME", str(pathlib.Path.home() / "googolforge")))
sys.path.insert(0, str(HOME))
import assistant as A  # noqa: E402

PORT = int(os.environ.get("GF_PORT", "8080"))
def saved_token():
    """One private token that survives restarts, so the home-screen app keeps working."""
    f = HOME / "web_token"
    try:
        t = f.read_text().strip()
        if len(t) >= 16:
            return t
    except Exception:
        pass
    t = secrets.token_urlsafe(16)
    try:
        HOME.mkdir(parents=True, exist_ok=True)
        f.write_text(t)
        os.chmod(f, 0o600)
    except Exception:
        pass
    return t


TOKEN = os.environ.get("GF_TOKEN") or saved_token()
ICON = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96"><rect width="96" height="96" rx="20" fill="#0d1117"/>'
        '<text x="48" y="62" font-size="44" text-anchor="middle" fill="#e3b341" font-family="sans-serif" '
        'font-weight="bold">GF</text></svg>')
SW = "self.addEventListener('fetch', e => {});"


def manifest():
    return {"name": "GoogolForge", "short_name": "GoogolForge", "display": "standalone",
            "background_color": "#0d1117", "theme_color": "#0d1117",
            "start_url": f"/?t={TOKEN}", "scope": "/",
            "icons": [{"src": f"/icon.svg?t={TOKEN}", "sizes": "any", "type": "image/svg+xml", "purpose": "any"}]}
JOBS, QUIZZES, LOCK = {}, {}, threading.Lock()
WEB_ONLY_TERMINAL = {"quiz"}          # handled by the page's own quiz screen
AUTO = {"run", "debug"}               # risky code still needs approval -> safely declined


def build_args(c):
    args = A.command_line(c)
    if c["command"] in AUTO:
        args.append("--auto")
    return args


def start_job(c, text):
    jid = secrets.token_hex(4)
    job = {"id": jid, "cmd": A.shown(c), "out": "", "done": False, "code": None, "started": time.time()}
    with LOCK:
        JOBS[jid] = job
        for old in sorted(JOBS.values(), key=lambda j: j["started"])[:-20]:
            JOBS.pop(old["id"], None)
    m = A.mem_load()
    m["history"].append({"you": text, "cmd": A.shown(c)})
    if A.CATALOG[c["command"]][1] == "file":
        m["last_file"] = c["arg"]
    A.mem_save(m)

    def work():
        env = dict(os.environ, PYTHONUNBUFFERED="1")
        try:
            p = subprocess.Popen(build_args(c), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 stdin=subprocess.DEVNULL, text=True, env=env)
            for line in p.stdout:
                with LOCK:
                    job["out"] = (job["out"] + line)[-60000:]
            job["code"] = p.wait()
        except Exception as e:
            job["out"] += f"\nCould not run: {e}"
            job["code"] = 1
        job["done"] = True

    threading.Thread(target=work, daemon=True).start()
    return job


def handle_request(body):
    """Core logic, separate from HTTP so it can be tested."""
    text = (body.get("text") or "").strip()[:500]
    if body.get("command"):
        c = A.validate({"command": str(body["command"]), "arg": str(body.get("arg", "")), "via": "button"},
                       text or str(body.get("arg", "")), A.mem_load())
    elif text:
        c = A.route(text, A.mem_load())
    else:
        return {"error": "Say what you want, or tap a button."}
    if c["command"] in WEB_ONLY_TERMINAL:
        return {"quiz": c["arg"] or "", "cmd": A.shown(c)}
    if A.CATALOG[c["command"]][2] and not body.get("confirm"):
        return {"confirm": True, "cmd": A.shown(c), "command": c["command"], "arg": c["arg"], "note": c.get("note", "")}
    job = start_job(c, text or A.shown(c))
    return {"job": job["id"], "cmd": job["cmd"], "note": c.get("note", "")}


def overview():
    o = {"goal": "", "done": 0, "total": 0, "files": [], "rank": "Pawn", "xp": 0, "streak": 0, "ai": False}
    try:
        st = json.loads((HOME / "tasks.json").read_text())
        o["goal"] = st.get("goal", "")
        o["total"] = len(st.get("tasks", []))
        o["done"] = sum(t.get("status") == "done" for t in st.get("tasks", []))
    except Exception:
        pass
    try:
        p = json.loads((HOME / "academy" / "progress.json").read_text())
        o["xp"], o["streak"] = p.get("xp", 0), p.get("streak", 0)
        for need, name in [(0, "Pawn"), (100, "Knight"), (300, "Bishop"), (600, "Rook"),
                           (1000, "Queen"), (1600, "King"), (2500, "Grandmaster")]:
            if o["xp"] >= need:
                o["rank"] = name
    except Exception:
        pass
    work = A.WORK
    if work.exists():
        o["files"] = [f.name for f in sorted(work.glob("*.py"), key=lambda f: -f.stat().st_mtime)][:12]
    try:
        with A.NOPROXY.open(A.C["ollama"] + "/api/tags", timeout=2):
            o["ai"] = True
    except Exception:
        pass
    return o


SCORES = HOME / "bench_history.json"


def scores():
    """Genius Lab (v3.9): this phone's own exam history, newest first. Only real local runs."""
    try:
        h = json.loads(SCORES.read_text())
    except Exception:
        return []
    out = []
    for r in reversed(h[-12:]):
        suite = r.get("suite", "arena")
        kind = suite if suite != "arena" else ("hard" if r.get("hard") else ("quick" if r.get("quick") else "arena"))
        out.append({"date": str(r.get("date", ""))[:16], "model": str(r.get("model", "")), "set": kind,
                    "style": str(r.get("style", "plain")), "score": int(r.get("score", 0)),
                    "solved": f"{r.get('solved', 0)}/{r.get('tasks', 0)}", "seconds": int(r.get("seconds", 0))})
    return out


def make_quiz(topic):
    sys.path.insert(0, str(HOME))
    import academy as AC
    topic = topic or AC.topic_or_next([])
    for _ in range(3):
        qs = AC.valid_quiz(AC.parse_json(AC.ask(
            "Write a 5-question multiple choice quiz on this Python topic for a beginner. "
            "Reply ONLY with JSON: {\"questions\":[{\"q\":\"question\",\"options\":"
            "[\"a\",\"b\",\"c\",\"d\"],\"answer\":0,\"why\":\"one-line explanation\"}]} "
            "where answer is the index 0-3 of the correct option.\nTopic: " + topic, fmt="json")))
        if qs:
            qid = secrets.token_hex(4)
            QUIZZES[qid] = {"topic": topic, "questions": qs}
            for old in list(QUIZZES)[:-10]:
                QUIZZES.pop(old, None)
            return {"id": qid, "topic": topic, "questions": qs}
    return {"error": "The AI couldn't build a clean quiz. Tap again."}


def grade_quiz(body):
    """Grading happens on the server, so XP can't be faked from the page."""
    import academy as AC
    quiz = QUIZZES.pop(str(body.get("id", "")), None)
    if not quiz:
        return {"error": "Quiz expired. Start a new one."}
    qs, topic = quiz["questions"], quiz["topic"]
    picks = body.get("answers") or []
    score = sum(1 for q, a in zip(qs, picks) if str(a) == str(int(q["answer"])))
    if not qs:
        return {"error": "No quiz to grade."}
    pct = int(100 * score / len(qs))
    p = AC.load()
    p["quizzes"] += 1
    t = p["topics"].setdefault(topic, {"xp": 0, "best_quiz": 0, "drills": 0})
    t["best_quiz"] = max(t["best_quiz"], pct)
    AC.award(p, score * 5 + (15 if pct == 100 else 0), topic, "the quiz")
    return {"score": score, "total": len(qs), "pct": pct}


PAGE = r"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>GoogolForge</title><meta name="theme-color" content="#0d1117">
<link rel="manifest" id="mf"><link rel="icon" id="ic"><style>
:root{--bg:#0d1117;--card:#161b22;--line:#30363d;--txt:#e6edf3;--dim:#8b949e;--gold:#e3b341;--ok:#3fb950;--bad:#f85149}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--txt);font:16px system-ui,sans-serif}
header{padding:16px;border-bottom:1px solid var(--line)}h1{margin:0;font-size:20px;color:var(--gold)}
.sub{color:var(--dim);font-size:13px}main{padding:12px;max-width:720px;margin:auto}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px;margin-bottom:12px}
.stats{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;text-align:center}
.stats b{display:block;font-size:20px}.bar{height:8px;background:var(--line);border-radius:4px;overflow:hidden;margin-top:8px}
.bar i{display:block;height:100%;background:var(--gold)}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}
button{background:#21262d;color:var(--txt);border:1px solid var(--line);border-radius:10px;padding:12px 6px;font-size:14px}
button:active{background:#30363d}button.go{background:var(--gold);color:#000;border:0;font-weight:600}
.row{display:flex;gap:8px}input,select{flex:1;background:#0d1117;color:var(--txt);border:1px solid var(--line);border-radius:10px;padding:12px;font-size:16px}
pre{white-space:pre-wrap;word-break:break-word;background:#010409;border-radius:8px;padding:10px;font-size:13px;max-height:55vh;overflow:auto;margin:8px 0 0}
.dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px}.cmd{color:var(--gold);font-family:monospace;font-size:13px}
.q{margin:12px 0}.q label{display:block;padding:8px;border:1px solid var(--line);border-radius:8px;margin:6px 0}
.lab{border-color:var(--gold)}.lab h2{color:var(--gold)}
table{width:100%;border-collapse:collapse;font-size:13px;margin-top:10px}td,th{padding:6px 4px;border-bottom:1px solid var(--line);text-align:left}
th{color:var(--dim);font-weight:500}.sb{height:6px;background:var(--line);border-radius:3px;min-width:50px}.sb i{display:block;height:100%;border-radius:3px}
.right{border-color:var(--ok)!important}.wrong{border-color:var(--bad)!important}h2{font-size:15px;margin:0 0 10px;color:var(--dim)}
</style></head><body>
<header><h1>GoogolForge</h1><div class="sub"><span id="ai" class="dot"></span><span id="ais">checking AI...</span></div></header>
<main>
<div class="card"><div id="goal" class="sub">No project yet</div><div class="bar"><i id="pbar" style="width:0"></i></div>
<div class="stats" style="margin-top:12px"><div><b id="prog">0/0</b><span class="sub">tasks</span></div>
<div><b id="rank">Pawn</b><span class="sub">rank</span></div><div><b id="xp">0</b><span class="sub">XP, streak <span id="streak">0</span></span></div></div></div>

<div class="card"><h2>Tell GoogolForge what you want</h2>
<div class="row"><input id="say" placeholder="build me a tip calculator" enterkeyhint="go"><button class="go" onclick="say()">Go</button></div></div>

<div class="card"><h2>Build</h2><div class="grid">
<button onclick="cmd('status')">Status</button><button onclick="cmd('run')">Keep building</button><button onclick="cmd('retry')">Retry failed</button>
<button onclick="cmd('report')">Report</button><button onclick="cmd('lint')">Check code</button><button onclick="cmd('doctor')">Health</button>
<button onclick="cmd('export')">Export zip</button><button onclick="cmd('publish')">Publish</button><button onclick="hist()">History</button></div>
<div class="row" style="margin-top:10px"><select id="file"><option value="">(no files yet)</option></select>
<button onclick="fcmd('debug')">Fix</button><button onclick="fcmd('review')">Review</button></div></div>

<div class="card"><h2>Learn</h2><div class="grid">
<button onclick="cmd('daily')">Daily lesson</button><button onclick="quiz('')">Quiz</button><button onclick="cmd('drill')">Drill</button>
<button onclick="cmd('check')">Check drill</button><button onclick="cmd('progress')">Progress</button><button onclick="cmd('lesson')">Lesson</button></div></div>
<div class="card"><h2>Level up</h2><div class="grid">
<button onclick="cmd('path')">Season 2</button><button onclick="cmd('path','done')">Mission done</button><button onclick="cmd('new','game my_game')">New game</button>
<button onclick="cmd('bench')">Benchmark</button><button onclick="cmd('shootout')">Shootout</button><button onclick="cmd('lessons')">Fix memory</button>
<button onclick="cmd('health')">Test all</button></div></div>
<div class="card"><h2>Pro tools</h2><div class="grid">
<button onclick="fcmd('mutate')">Test my tests</button><button onclick="fcmd('explain')">Explain file</button><button onclick="cmd('index')">Index my code</button>
<button onclick="cmd('duel')">Start duel</button><button onclick="cmd('duel','check')">Check duel</button><button onclick="cmd('ci')">Cloud tests</button></div>
<div class="sub">Team build: type "team build a stopwatch" above. Ask about your code: "in my code, where is the score saved?"</div></div>

<div class="card lab"><h2>Genius Lab</h2><div class="grid">
<button class="go" onclick="cmd('genius')">Genius exam</button><button onclick="cmd('losses')">What went wrong</button><button onclick="cmd('bench')">Quick exam</button>
<button onclick="cmd('heplus')">HumanEval+</button><button onclick="cmd('holdout')">Holdout</button><button onclick="cmd('shootout')">Shootout</button></div>
<div class="sub" style="margin-top:8px">Scores below are this phone's own runs. The holdout is the honest test: never tune on it.</div>
<div id="scores" class="sub" style="margin-top:6px">No exams yet. Tap Quick exam to start.</div></div>

<div class="card" id="outcard" style="display:none"><div class="cmd" id="outcmd"></div><pre id="out"></pre></div>
<div class="card" id="quizcard" style="display:none"></div>
</main><script>
const T=new URLSearchParams(location.search).get('t');let poll=null;
document.getElementById('mf').href='/manifest.json?t='+T;document.getElementById('ic').href='/icon.svg?t='+T;
if('serviceWorker' in navigator){navigator.serviceWorker.register('/sw.js?t='+T).catch(()=>{})}
async function api(path,body){const r=await fetch(path+(path.includes('?')?'&':'?')+'t='+T,body?{method:'POST',headers:{'Content-Type':'application/json','X-Token':T},body:JSON.stringify(body)}:{});return r.json()}
function show(c,txt){document.getElementById('outcard').style.display='';document.getElementById('outcmd').textContent=c;document.getElementById('out').textContent=txt;document.getElementById('outcard').scrollIntoView({behavior:'smooth'})}
async function send(b){const r=await api('/api/do',b);
 if(r.error)return show('',r.error);
 if(r.quiz!==undefined)return quiz(r.quiz);
 if(r.confirm){if(!confirm('This is a big step:\n'+r.cmd+'\nRun it?'))return show(r.cmd,'Skipped.');return send({command:r.command,arg:r.arg,confirm:true})}
 show('-> '+r.cmd,(r.note?r.note+'\n':'')+'Working...');watch(r.job,r.cmd)}
function watch(id,c){clearInterval(poll);poll=setInterval(async()=>{const j=await api('/api/job/'+id);
 show('-> '+c+(j.done?'  (finished)':'  (running)'),j.out||'Working...');const p=document.getElementById('out');p.scrollTop=p.scrollHeight;
 if(j.done){clearInterval(poll);refresh()}},1500)}
function say(){const v=document.getElementById('say').value.trim();if(v){send({text:v});document.getElementById('say').value=''}}
document.getElementById('say').addEventListener('keydown',e=>{if(e.key==='Enter')say()});
function cmd(c,a){send({command:c,arg:a||''})}
function fcmd(c){const f=document.getElementById('file').value;if(!f)return show('','Build something first.');send({command:c,arg:f})}
async function hist(){const h=await api('/api/history');show('history',h.map(x=>x.you+'  ->  '+x.cmd).join('\n')||'Nothing yet.')}
async function quiz(topic){const q=document.getElementById('quizcard');q.style.display='';q.innerHTML='<div class="sub">Building your quiz...</div>';q.scrollIntoView({behavior:'smooth'});
 const d=await api('/api/quiz',{topic});if(d.error){q.innerHTML='<div class="sub">'+d.error+'</div>';return}
 q.innerHTML='<h2>Quiz: '+esc(d.topic)+'</h2>'+d.questions.map((x,i)=>'<div class="q"><b>'+(i+1)+'. '+esc(x.q)+'</b>'+x.options.map((o,j)=>'<label id="l'+i+'_'+j+'"><input type="radio" name="q'+i+'" value="'+j+'"> '+esc(o)+'</label>').join('')+'<div class="sub" id="w'+i+'"></div></div>').join('')+'<button class="go" id="sub">Submit</button>';
 document.getElementById('sub').onclick=async()=>{const ans=d.questions.map((x,i)=>{const c=document.querySelector('input[name=q'+i+']:checked');return c?c.value:''});
  const g=await api('/api/grade',{id:d.id,answers:ans});if(g.error){q.insertAdjacentHTML('beforeend','<div class="sub">'+g.error+'</div>');return}
  d.questions.forEach((x,i)=>{document.getElementById('l'+i+'_'+x.answer).classList.add('right');if(ans[i]!==''&&ans[i]!=String(x.answer))document.getElementById('l'+i+'_'+ans[i]).classList.add('wrong');document.getElementById('w'+i).textContent=x.why||''});
  document.getElementById('sub').outerHTML='<div class="cmd">Score '+g.score+'/'+g.total+' ('+g.pct+'%)</div>';refresh()}}
function esc(s){return String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
async function refresh(){const o=await api('/api/overview');
 document.getElementById('ai').style.background=o.ai?'var(--ok)':'var(--bad)';document.getElementById('ais').textContent=o.ai?'AI ready':'AI off: run forge-start in Termux';
 document.getElementById('goal').textContent=o.goal?'Project: '+o.goal:'No project yet';document.getElementById('prog').textContent=o.done+'/'+o.total;
 document.getElementById('pbar').style.width=(o.total?100*o.done/o.total:0)+'%';document.getElementById('rank').textContent=o.rank;
 document.getElementById('xp').textContent=o.xp;document.getElementById('streak').textContent=o.streak;
 const s=document.getElementById('file'),cur=s.value;s.innerHTML=o.files.length?o.files.map(f=>'<option>'+esc(f)+'</option>').join(''):'<option value="">(no files yet)</option>';if(cur)s.value=cur}
async function lab(){const s=await api('/api/scores');if(!s.length)return;
 const col=v=>v>=80?'var(--ok)':v>=50?'var(--gold)':'var(--bad)';
 document.getElementById('scores').innerHTML='<table><tr><th>When</th><th>Exam</th><th>Score</th><th>Solved</th><th>Time</th></tr>'+s.map(r=>'<tr><td>'+esc(r.date.replace('T',' '))+'</td><td>'+esc(r.set+' '+r.style)+'<div class="sub">'+esc(r.model)+'</div></td><td><b>'+r.score+'</b><div class="sb"><i style="width:'+r.score+'%;background:'+col(r.score)+'"></i></div></td><td>'+esc(r.solved)+'</td><td>'+Math.round(r.seconds/60)+'m</td></tr>').join('')+'</table>'}
async function refreshAll(){await refresh();lab()}
refreshAll();setInterval(refreshAll,15000);
</script></body></html>"""


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def ok(self, data, ctype="application/json", code=200):
        b = data if isinstance(data, bytes) else (json.dumps(data) if ctype == "application/json" else data).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Frame-Options", "DENY")
        self.end_headers()
        self.wfile.write(b)

    def authed(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        given = self.headers.get("X-Token") or (q.get("t") or [""])[0]
        return secrets.compare_digest(given, TOKEN)

    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path
        if not self.authed():
            return self.ok("<h3>Locked. Open the link that <code>forge web</code> printed in Termux.</h3>", "text/html", 403)
        if path == "/":
            return self.ok(PAGE, "text/html")
        if path == "/manifest.json":
            return self.ok(json.dumps(manifest()), "application/manifest+json")
        if path == "/icon.svg":
            return self.ok(ICON, "image/svg+xml")
        if path == "/sw.js":
            return self.ok(SW, "text/javascript")
        if path == "/api/overview":
            return self.ok(overview())
        if path == "/api/scores":
            return self.ok(scores())
        if path == "/api/history":
            return self.ok(A.mem_load()["history"][-15:])
        if path.startswith("/api/job/"):
            j = JOBS.get(path.rsplit("/", 1)[-1])
            return self.ok({"out": j["out"], "done": j["done"]} if j else {"out": "Job not found.", "done": True})
        self.ok({"error": "not found"}, code=404)

    def do_POST(self):
        if not self.headers.get("X-Token") or not secrets.compare_digest(self.headers.get("X-Token", ""), TOKEN):
            return self.ok({"error": "locked"}, code=403)
        try:
            body = json.loads(self.rfile.read(min(int(self.headers.get("Content-Length", 0)), 200000)) or b"{}")
        except Exception:
            return self.ok({"error": "bad request"}, code=400)
        path = urllib.parse.urlparse(self.path).path
        if path == "/api/do":
            return self.ok(handle_request(body))
        if path == "/api/quiz":
            return self.ok(make_quiz(str(body.get("topic", ""))[:80]))
        if path == "/api/grade":
            return self.ok(grade_quiz(body))
        self.ok({"error": "not found"}, code=404)


def serve():
    url = f"http://127.0.0.1:{PORT}/?t={TOKEN}"
    print("GoogolForge Dashboard is running (private to this phone).")
    print("Open this in Chrome (long-press it to copy):\n\n  " + url + "\n")
    print("Keep this Termux session open. Press Volume Down + C to stop.")
    try:
        subprocess.Popen(["termux-open-url", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()


def selftest():
    import tempfile, urllib.request, shutil
    global TOKEN, PORT
    fails = 0

    def chk(n, c):
        nonlocal fails
        print(("PASS " if c else "FAIL ") + n)
        fails += not c

    d = pathlib.Path(tempfile.mkdtemp())
    (d / "workspace").mkdir()
    (d / "workspace" / "calc.py").write_text("x=1\n")
    A.WORK, A.MEM = d / "workspace", d / "mem.json"
    TOKEN, PORT = "testtoken", 18080 + os.getpid() % 1000
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    op = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    base = f"http://127.0.0.1:{PORT}"

    def get(p, tok=True):
        try:
            with op.open(base + p + (("&" if "?" in p else "?") + "t=testtoken" if tok else "")) as r:
                return r.status, r.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, ""

    def post(p, b, tok="testtoken"):
        req = urllib.request.Request(base + p, data=json.dumps(b).encode(),
                                     headers={"Content-Type": "application/json", "X-Token": tok})
        try:
            with op.open(req) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, {}

    chk("page locked without token", get("/", tok=False)[0] == 403)
    s, body = get("/")
    chk("page opens with token", s == 200 and "GoogolForge" in body)
    chk("POST rejected with wrong token", post("/api/do", {"text": "status"}, tok="nope")[0] == 403)
    chk("overview works", json.loads(get("/api/overview")[1]).get("files") == ["calc.py"])
    r = post("/api/do", {"text": "publish it"})[1]
    chk("publish asks to confirm first", r.get("confirm") is True and "job" not in r)
    r = post("/api/do", {"command": "rm -rf", "arg": "/"})[1]
    chk("unknown command falls back to safe ask", r.get("cmd", "").startswith("forge ask"))
    r = post("/api/do", {"text": "quiz me on loops"})[1]
    chk("quiz goes to the web quiz screen", r.get("quiz") == "loops")
    r = post("/api/do", {"command": "debug", "arg": "../../etc/passwd"})[1]
    chk("file argument locked to project files", r.get("cmd") == "forge debug calc.py")
    chk("run and debug get --auto (risky code still declined)",
        build_args({"command": "debug", "arg": "calc.py"})[-1] == "--auto")
    job = start_job({"command": "status", "arg": ""}, "status")
    job["done"] = False
    chk("jobs are tracked", job["id"] in JOBS)
    chk("history saved", any(h["cmd"] == "forge status" for h in A.mem_load()["history"]))
    chk("text is HTML-escaped on the page", "function esc(" in PAGE and "innerHTML='<h2>Quiz: '+esc(" in PAGE)
    QUIZZES["q1"] = {"topic": "t", "questions": [{"q": "x", "options": ["a", "b", "c", "d"], "answer": 2}] * 3}
    import academy as AC
    AC.PROG = d / "prog.json"
    g = post("/api/grade", {"id": "q1", "answers": ["2", "2", "0"]})[1]
    chk("quiz graded on the server", g.get("score") == 2 and g.get("total") == 3)
    chk("a quiz can't be graded twice", "error" in post("/api/grade", {"id": "q1", "answers": ["2"] * 3})[1])
    global SCORES
    SCORES = d / "bench_history.json"
    chk("Genius Lab empty without runs", json.loads(get("/api/scores")[1]) == [])
    SCORES.write_text(json.dumps([{"date": "2026-11-27T11:00", "model": "m", "tasks": 6, "solved": 5, "score": 83,
                                   "seconds": 600, "hard": True, "style": "genius", "suite": "arena"}]))
    sc = json.loads(get("/api/scores")[1])
    chk("Genius Lab shows real local runs", sc and sc[0]["score"] == 83 and sc[0]["set"] == "hard")
    chk("Genius Lab locked without token", get("/api/scores", tok=False)[0] == 403)
    chk("genius button runs the Genius exam", build_args({"command": "genius", "arg": ""})[-3:] == ["bench", "--genius", "--hard"])
    chk("slow exams ask first", A.CATALOG["genius"][2] and A.CATALOG["holdout"][2])
    chk("Genius Lab on the page", "Genius Lab" in PAGE and "/api/scores" in PAGE)
    srv.shutdown()
    shutil.rmtree(d, ignore_errors=True)
    print(f"\nSELFTEST: {'ALL PASSED' if not fails else str(fails) + ' FAILED'}")
    return fails == 0


if __name__ == "__main__":
    if sys.argv[1:2] == ["selftest"]:
        sys.exit(0 if selftest() else 1)
    serve()
