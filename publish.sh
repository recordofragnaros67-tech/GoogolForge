#!/data/data/com.termux/files/usr/bin/bash
# GoogolForge Objective 4: publish to GitHub + free website (GitHub Pages)
set -e
cd ~/googolforge || { echo "Run the v1.2 installer first."; exit 1; }
command -v gh >/dev/null && command -v git >/dev/null || pkg install -y gh git python curl
# 1. Sign in to GitHub (opens a one-time code flow the first time; auto mode never prompts)
if ! gh auth status >/dev/null 2>&1; then
  [ -n "$GF_AUTO" ] && { echo "Not signed in to GitHub. Run: gh auth login"; exit 3; }
  gh auth login -h github.com -p https -w
fi
LOGIN=$(gh api user -q .login)
UID_GH=$(gh api user -q .id)
git config user.name "$LOGIN"
git config user.email "${UID_GH}+${LOGIN}@users.noreply.github.com"
# 2. Keep private and bulky files out of the public repo
cat > .gitignore <<'GI'
ollama.log
progress.log
autopublish.log
chat_memory.json
config.json
academy/
*.bak
*.zip
.last_publish
.publish_out
.publock/
*.pyc
__pycache__/
web_token
code_index.json
*.pre-repairmem
GI
# Cloud test robot (GitHub Actions) - free for public repos
[ -f .github/workflows/forge-test.yml ] || python forge3.py ci >/dev/null 2>&1 || true
# Untrack private files that an older version may have pushed
git rm -r -q --cached --ignore-unmatch chat_memory.json config.json academy autopublish.log progress.log ollama.log web_token code_index.json >/dev/null 2>&1 || true
export GF_LOGIN="$LOGIN"
# 3. AI writes the tagline (local model, free); falls back if Ollama is off
mkdir -p docs
python - <<'PY'
import json, urllib.request, html, pathlib
tag = "Elite open-source AI, built move by move."
try:
    op = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    body = {"model": "llama3.2:1b", "stream": False, "options": {"temperature": 0.7},
            "prompt": "Write one bold tagline, under 12 words, no quotes, for GoogolForge AI Technologies, "
                      "a free open-source AI engine that plans, codes, tests and judges software."}
    req = urllib.request.Request("http://127.0.0.1:11434/api/generate", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    out = json.loads(op.open(req, timeout=120).read())["response"].strip().strip('"').splitlines()[0]
    if 3 < len(out) < 120:
        tag = out
except Exception:
    pass
divs = ["GoogolForge Master Foundation", "DragonForge AI", "Theban Arcana", "TeaForge AI",
        "GoogolForge Quantum", "GoogolForge Linux", "GoogolForge Academy",
        "GoogolForge Research Institute", "GoogolForge Security", "GoogolForge Cloud",
        "GoogolForge Commerce"]
cards = "".join(f"<li>{html.escape(d)}</li>" for d in divs)
import datetime, os
LOGIN = os.environ.get("GF_LOGIN", "")
ws = pathlib.Path("workspace")
builds = sorted(ws.glob("*.py"), key=lambda f: -f.stat().st_mtime)[:12] if ws.exists() else []
blist = "".join(f'<li><a href="https://github.com/{LOGIN}/googolforge/blob/main/workspace/{html.escape(f.name)}">{html.escape(f.name)}</a></li>' for f in builds) or "<li>First builds coming soon.</li>"
stamp = datetime.datetime.now().strftime("%B %d, %Y")
page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>GoogolForge AI Technologies</title>
<style>
body{{margin:0;font-family:system-ui,sans-serif;background:#0b0f1a;color:#e8ecf5;line-height:1.6}}
header{{padding:72px 24px 40px;text-align:center;background:radial-gradient(circle at top,#26324f,#0b0f1a)}}
h1{{font-size:2.4rem;margin:0}} .tag{{color:#f5b942;font-size:1.2rem}}
main{{max-width:760px;margin:auto;padding:24px}}
ul{{list-style:none;padding:0;display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:12px}}
li{{background:#151c2e;border:1px solid #2a3550;border-radius:10px;padding:14px}}
code{{background:#151c2e;padding:2px 6px;border-radius:4px}}
footer{{text-align:center;color:#7d8aa8;padding:32px;font-size:.9rem}}
</style></head><body>
<header><h1>GoogolForge AI Technologies</h1><p class="tag">{html.escape(tag)}</p></header>
<main>
<h2>Master Foundation v1.5: Elite Intelligence Engine</h2>
<p>Plans a goal, writes each piece with a local open-source AI, tests it, and has an independent AI judge sign off before it counts. Free, private, and runs on a phone. Includes GoogolForge Academy, a plain-English Assistant, and a browser Dashboard.</p>
<p>Try: <code>forge chat "build me a tip calculator"</code></p>
<h2>Latest builds</h2><ul>{blist}</ul>
<h2>The GoogolForge ecosystem</h2><ul>{cards}</ul>
</main><footer>&copy; GoogolForge AI Technologies &middot; updated {stamp}</footer></body></html>"""
pathlib.Path("docs/index.html").write_text(page)
pathlib.Path("README.md").write_text(
    "# GoogolForge Master Foundation v1.5\n\n" + tag + "\n\nFree, open-source AI engine: plan, code, test, judge.\n\n"
    "```\nforge plan \"your goal\"\nforge run\nforge status\n```\n")
print("Tagline:", tag)
PY
# 4. Commit and push
git branch -M main
git add -A
git commit -qm "GoogolForge: publish site and engine" || echo "Nothing new to commit"
if gh repo view "$LOGIN/googolforge" >/dev/null 2>&1; then
  git remote get-url origin >/dev/null 2>&1 || git remote add origin "https://github.com/$LOGIN/googolforge.git"
  git push -u origin main
else
  gh repo create googolforge --public --source=. --remote=origin --push \
    --description "GoogolForge AI Technologies - free open-source Elite Intelligence Engine"
fi
# 5. Turn on free hosting (GitHub Pages from /docs)
gh api -X POST "repos/$LOGIN/googolforge/pages" -f "source[branch]=main" -f "source[path]=/docs" >/dev/null 2>&1 \
  || echo "Pages already on (or will be in a minute)."
echo "== Live in 1 to 2 minutes: https://$LOGIN.github.io/googolforge/ =="
echo "== Code: https://github.com/$LOGIN/googolforge =="
