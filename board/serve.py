#!/usr/bin/env python3
"""Gates: the local, read-only board for sdlc-pipeline.

Reads docs/features/*/state.json, review-log.md, qa-report.md, tasks.md, docs/pipeline/agent-runs.log and
docs/pipeline/RULE-CANDIDATES.md from the repos you list, and serves one page plus /api/state. Standard library only.

  python3 board/serve.py                 # http://localhost:7777
  python3 board/serve.py --port 8000
  python3 board/serve.py --config path/to/board.local.json
  python3 board/serve.py --json          # print the state once and exit (what the tests use)

Config (board/board.local.json, gitignored; see board.local.example.json):
  { "repos": ["~/src/repo-a"], "roots": ["~/Development"], "port": 7777, "stale_minutes": 120 }
  repos: clones to show. roots: directories scanned two levels deep for repos that contain docs/pipeline/VERSION.

The board writes one file, its own board.local.json (add or remove a repo), and can run the pipeline's install.sh
into a repo you choose. It never writes a feature's files; authority stays in the pipeline's files and in CI
(docs/pipeline/ENFORCEMENT.md). The server listens on 127.0.0.1 only and write calls need the X-Gates header.
"""
import argparse, calendar, glob, json, os, pathlib, re, subprocess, sys, time
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlparse

HERE = pathlib.Path(__file__).resolve().parent
STAGES = {
    "lite": ["spec", "implement", "review", "qa", "pr"],
    "standard": ["prd", "handoff", "implement", "review", "qa", "pr"],
    "full": ["grill", "prd", "handoff", "implement", "review", "qa", "pr"],
}
GATE_STAGE = {"prd": "prd", "handoff": "handoff", "implement": "implement", "review": "review", "qa": "qa", "pr": "pr"}
RESUME = {"grill": "/grill", "prd": "/prd", "handoff": "/handoff", "implement": "/implement", "review": "/review", "qa": "/qa", "pr": None, "spec": "/feature"}


def load_config(path):
    cfg = {"repos": [], "roots": [], "port": 7777, "stale_minutes": 120}
    p = pathlib.Path(path).expanduser()
    if p.exists():
        cfg.update(json.loads(p.read_text()))
    return cfg


def discover(cfg):
    seen, out = set(), []
    for r in cfg.get("repos", []):              # listed repos always show, installed or not
        p = pathlib.Path(r).expanduser()
        if not p.is_dir(): continue
        p = p.resolve()
        if str(p) not in seen:
            seen.add(str(p)); out.append(p)
    for root in cfg.get("roots", []):
        rp = pathlib.Path(root).expanduser()
        if not rp.is_dir():
            continue
        for pat in ("*/docs/pipeline/VERSION", "*/*/docs/pipeline/VERSION"):
            for v in sorted(rp.glob(pat)):
                p = v.parents[2].resolve()
                if str(p) not in seen:
                    seen.add(str(p)); out.append(p)
    return out


def candidates(cfg, known):
    """Git repos under the roots that do not have the pipeline yet, for the Add list."""
    out = []
    for root in cfg.get("roots", []):
        rp = pathlib.Path(root).expanduser()
        if not rp.is_dir():
            continue
        for pat in ("*/.git", "*/*/.git"):
            for g in sorted(rp.glob(pat)):
                p = g.parent.resolve()
                if str(p) in known or (p / "docs/pipeline/VERSION").exists():
                    continue
                out.append({"name": p.name, "path": str(p)})
    return out[:50]


def pipeline_version():
    return read(HERE.parent / "VERSION").strip() or None


def save_config(cfg):
    path = pathlib.Path(cfg["_path"]).expanduser()
    data = {k: v for k, v in cfg.items() if not k.startswith("_")}
    path.write_text(json.dumps(data, indent=2) + "\n")


def safe_repo_path(raw):
    """Expand and validate a user-supplied path: must exist, be a directory, and contain .git."""
    if not raw or not isinstance(raw, str):
        return None, "path is required"
    p = pathlib.Path(raw).expanduser()
    try:
        p = p.resolve(strict=True)
    except (OSError, RuntimeError):
        return None, f"{raw} does not exist"
    if not p.is_dir():
        return None, f"{p} is not a directory"
    if not (p / ".git").exists():
        return None, f"{p} is not a git repository (no .git); run git init there first"
    return p, None


def install_pipeline(repo, mode):
    """Run this checkout's install.sh into repo. mode: full | minimal | guards-only."""
    flags = {"full": [], "minimal": ["--minimal"], "guards-only": ["--guards-only"]}
    if mode not in flags:
        return False, f"unknown mode {mode}"
    script = HERE.parent / "install.sh"
    if not script.exists():
        return False, "install.sh not found next to board/"
    try:
        r = subprocess.run(["bash", str(script), str(repo)] + flags[mode], capture_output=True, text=True, timeout=120)
    except subprocess.SubprocessError as e:
        return False, str(e)
    return r.returncode == 0, (r.stdout + r.stderr).strip()[-4000:]


def browse(raw):
    """Subdirectories of a path, for the folder picker. Hidden dirs and the usual noise are left out."""
    p = pathlib.Path(raw or "~").expanduser()
    try:
        p = p.resolve(strict=True)
    except (OSError, RuntimeError):
        return {"path": raw, "parent": None, "dirs": [], "error": "not found"}
    skip = {"node_modules", "dist", "build", "target", "__pycache__", "Library", "Applications"}
    dirs = []
    try:
        for c in sorted(p.iterdir(), key=lambda x: x.name.lower()):
            if c.is_dir() and not c.name.startswith(".") and c.name not in skip:
                dirs.append({"name": c.name, "path": str(c), "git": (c / ".git").exists(), "pipeline": (c / "docs/pipeline/VERSION").exists()})
    except OSError:
        pass
    return {"path": str(p), "parent": str(p.parent) if p.parent != p else None, "dirs": dirs[:200]}


def read(p):
    try:
        return pathlib.Path(p).read_text(errors="replace")
    except OSError:
        return ""


def jload(p, default):
    try:
        return json.loads(pathlib.Path(p).read_text())
    except (OSError, ValueError):
        return default


_tree_cache = {}
def tree_hash(repo):
    """Current tree hash via the pipeline's own script, cached 15s per repo. None when the script is missing or fails."""
    now = time.time()
    hit = _tree_cache.get(str(repo))
    if hit and now - hit[0] < 15:
        return hit[1]
    script = repo / "docs/pipeline/enforcement/tree-hash.sh"
    val = None
    if script.exists():
        try:
            val = subprocess.run(["bash", str(script)], cwd=repo, capture_output=True, text=True, timeout=20).stdout.strip() or None
        except (subprocess.SubprocessError, OSError):
            val = None
    _tree_cache[str(repo)] = (now, val)
    return val


def last_section(text, heading_re):
    """Text of the last markdown section whose heading matches heading_re."""
    idx = [m.start() for m in re.finditer(heading_re, text, re.M)]
    return text[idx[-1]:] if idx else ""


def parse_review(fdir):
    t = read(fdir / "review-log.md")
    verdicts = re.findall(r"^VERDICT: (APPROVE|CHANGES_REQUESTED|BLOCKED)", t, re.M)
    trees = re.findall(r"^Tree: ([0-9a-f]{40})", t, re.M)
    rnd = last_section(t, r"^## Review round \d+")
    counts = {"blocker": 0, "major": 0, "minor": 0, "nit": 0}
    in_findings = False
    for line in rnd.splitlines():
        if line.startswith("### Findings"): in_findings = True; continue
        if line.startswith("### ") or line.startswith("## "): in_findings = False
        if in_findings and line.startswith("|"):
            cells = [c.strip().lower() for c in line.strip("|").split("|")]
            if len(cells) > 1 and cells[1] in counts:
                counts[cells[1]] += 1
    stop = re.search(r"^Stopping criterion for next round: (.*)$", rnd, re.M)
    return {"last_verdict": verdicts[-1] if verdicts else None, "rounds": len(verdicts), "reviewed_tree": trees[-1] if trees else None,
            "findings": counts, "stopping_criterion": stop.group(1).strip() if stop else None}


def parse_qa(fdir):
    t = read(fdir / "qa-report.md")
    m = re.search(r"^QA: (PASS|FAIL|BLOCKED|NOT READY)", t, re.M)
    tr = re.findall(r"^Tree: ([0-9a-f]{40})", t, re.M)
    return {"qa": m.group(1) if m else None, "qa_tree": tr[-1] if tr else None}


def parse_tasks(fdir):
    t = read(fdir / "tasks.md")
    done = len(re.findall(r"^- \[x\] T\d+", t, re.M | re.I)); open_ = len(re.findall(r"^- \[ \] T\d+", t, re.M))
    disputes = last_section(t, r"^## Test disputes").strip().splitlines()[1:] if "## Test disputes" in t else []
    return {"done": done, "total": done + open_, "disputes": [d for d in disputes if d.strip()]}


def parse_candidates(repo):
    t = read(repo / "docs/pipeline/RULE-CANDIDATES.md")
    out = []
    for line in t.splitlines():
        if line.startswith("- "):
            m = re.match(r"- (\S+) (\S+) ([^:]+): (.*?)(?: → candidate: (.*))?$", line)
            if m:
                out.append({"date": m.group(1), "slug": m.group(2), "ref": m.group(3), "what": m.group(4), "candidate": m.group(5) or ""})
            else:
                out.append({"date": "", "slug": "", "ref": "", "what": line[2:], "candidate": ""})
    return out


def parse_runs(repo, stale_minutes):
    """Start lines without a matching stop are running. Lines look like:
       2026-10-29T20:01:02Z event=start agent=implementer session=abc ...   (event= is absent on older logs: treat as stop)"""
    t = read(repo / "docs/pipeline/agent-runs.log")
    open_runs, finished = {}, []
    for line in t.splitlines()[-500:]:
        m = re.match(r"(\S+) (.*)", line)
        if not m: continue
        ts, rest = m.groups()
        kv = dict(re.findall(r"(\w+)=(\S*)", rest))
        ev = kv.get("event", "stop"); key = (kv.get("agent", "unknown"), kv.get("session", ""))
        if ev == "start":
            open_runs[key] = ts
        else:
            started = open_runs.pop(key, None)
            finished.append({"agent": key[0], "session": key[1], "started": started, "stopped": ts})
    now = time.time()
    running = []
    for (agent, session), ts in open_runs.items():
        try:
            age = now - calendar.timegm(time.strptime(ts, "%Y-%m-%dT%H:%M:%SZ"))
        except ValueError:
            age = 0
        if age < stale_minutes * 60:
            running.append({"agent": agent, "session": session, "started": ts, "age_s": int(age)})
    return running, finished[-10:]


def feature_state(repo, fdir, running):
    st = jload(fdir / "state.json", {})
    slug = st.get("slug") or fdir.name
    mode = st.get("mode") or "standard"
    stages = STAGES.get(mode, STAGES["standard"])
    stage = st.get("stage") or ""
    rv = parse_review(fdir); qa = parse_qa(fdir); tasks = parse_tasks(fdir)
    hist = st.get("history") or []
    last_hist_stage = next((h.get("stage") for h in reversed(hist) if h.get("stage") in stages), None)

    # where on the track, and in what state
    waiting_gate = None
    if stage.startswith("awaiting-"):
        waiting_gate = stage.split("-", 1)[1]
    handoffs = st.get("handoffs") or []
    if handoffs and not waiting_gate:
        waiting_gate = handoffs[-1].get("gate")
    if stage == "needs-human":
        current, cur_state = (last_hist_stage or "review"), "stopped"
    elif waiting_gate:
        current, cur_state = GATE_STAGE.get(waiting_gate, waiting_gate), "waiting"
    elif stage in stages:
        current, cur_state = stage, "current"
    elif stage == "grill" and mode != "full":
        current, cur_state = stages[0], "current"
    else:
        current, cur_state = (last_hist_stage or stages[0]), "current"
    if current not in stages:
        current = stages[0]
    ci = stages.index(current)
    track = []
    for i, s in enumerate(stages):
        state = "done" if i < ci else (cur_state if i == ci else "ahead")
        if s == "pr" and i == ci and qa["qa"] == "PASS" and rv["last_verdict"] == "APPROVE":
            state = "waiting"  # merge is the human's
        track.append({"stage": s, "state": state})

    # waiting-on-you entries
    waiting = []
    for h in handoffs:
        waiting.append({"gate": h.get("gate"), "question": h.get("question"), "to_role": h.get("to_role"),
                        "resume": f"{RESUME.get(GATE_STAGE.get(h.get('gate'), ''), '/start')} {slug}".strip()})
    if stage == "needs-human":
        why = rv["stopping_criterion"] or (hist[-1].get("result") if hist else None) or "see review-log.md or tasks.md"
        waiting.append({"gate": current, "question": f"Stopped: {why}", "to_role": None, "resume": f"{RESUME.get(current, '/start')} {slug}"})
    if tasks["disputes"]:
        waiting.append({"gate": "implement", "question": "Test dispute: " + tasks["disputes"][0].strip("- ").strip(), "to_role": "engineer", "resume": f"/implement {slug}"})

    cur_tree = tree_hash(repo)
    tree = None
    if rv["reviewed_tree"]:
        tree = {"reviewed": rv["reviewed_tree"], "current": cur_tree, "match": (cur_tree == rv["reviewed_tree"]) if cur_tree else None}

    # a running role is attributed to the most recently touched feature in the repo (inference, flagged as such)
    live = None
    try:
        mtime = (fdir / "state.json").stat().st_mtime
    except OSError:
        mtime = 0
    return {
        "slug": slug, "mode": mode, "stage": stage, "track": track, "current": current, "current_state": cur_state,
        "review_round": st.get("review_round", 0), "max_review_rounds": st.get("max_review_rounds", 3),
        "last_verdict": rv["last_verdict"], "findings": rv["findings"], "stopping_criterion": rv["stopping_criterion"],
        "qa": qa["qa"], "blast_radius": st.get("blast_radius"), "cost_usd": st.get("cost_usd", 0),
        "feature_branch": st.get("feature_branch"), "ticket": st.get("ticket"), "tasks": tasks, "tree": tree,
        "waived": len(st.get("waived_findings") or []), "waiting": waiting, "updated": mtime, "live": live,
        "history": hist[-6:], "path": str(fdir),
    }


def repo_state(repo, cfg):
    docs_dir = (jload(repo / "docs/pipeline/pipeline.json", {}) or {}).get("docs_dir", "docs/features")
    running, finished = parse_runs(repo, cfg.get("stale_minutes", 120))
    feats = []
    for sj in sorted(glob.glob(str(repo / docs_dir / "*" / "state.json"))):
        feats.append(feature_state(repo, pathlib.Path(sj).parent, running))
    if feats and running:
        newest = max(feats, key=lambda f: f["updated"])
        newest["live"] = {"agent": running[0]["agent"], "age_s": running[0]["age_s"], "inferred": True}
    feats.sort(key=lambda f: (0 if f["waiting"] else 1, 0 if f["live"] else 1, -f["updated"]))
    return {
        "name": repo.name, "path": str(repo), "version": read(repo / "docs/pipeline/VERSION").strip() or None,
        "features": feats, "running": running, "recent_runs": finished, "candidates": parse_candidates(repo),
    }


def build_state(cfg):
    repos = [repo_state(r, cfg) for r in discover(cfg)]
    waiting = [{"repo": r["name"], "slug": f["slug"], **w} for r in repos for f in r["features"] for w in f["waiting"]]
    known = {r["path"] for r in repos}
    return {"api": 2, "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "repos": repos, "waiting": waiting,
            "running": [{"repo": r["name"], **x} for r in repos for x in r["running"]],
            "candidates": [{"repo": r["name"], **c} for r in repos for c in r["candidates"]],
            "config_path": cfg.get("_path"), "config": {"repos": cfg.get("repos", []), "roots": cfg.get("roots", [])},
            "pipeline_version": pipeline_version(), "repo_candidates": candidates(cfg, known)}


class Handler(SimpleHTTPRequestHandler):
    cfg = {}
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=str(HERE), **kw)
    def log_message(self, fmt, *args):  # quiet
        pass
    def send_json(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def same_origin(self):
        """Writes need the custom header (a cross-site form cannot set it) and a local Origin when one is sent."""
        if self.headers.get("X-Gates") != "1":
            return False
        origin = self.headers.get("Origin")
        return origin is None or urlparse(origin).hostname in ("localhost", "127.0.0.1")
    def body_json(self):
        n = int(self.headers.get("Content-Length") or 0)
        try:
            return json.loads(self.rfile.read(n) or b"{}")
        except ValueError:
            return {}
    def do_POST(self):
        path = urlparse(self.path).path
        if not self.same_origin():
            return self.send_json({"error": "forbidden"}, 403)
        data = self.body_json()
        if path == "/api/repos":                      # add a repo (and optionally install the pipeline)
            repo, err = safe_repo_path(data.get("path"))
            if err: return self.send_json({"error": err}, 400)
            repos = list(self.cfg.get("repos", []))
            if str(repo) not in [str(pathlib.Path(r).expanduser().resolve()) for r in repos if pathlib.Path(r).expanduser().exists()]:
                repos.append(str(repo)); self.cfg["repos"] = repos; save_config(self.cfg)
            out = {"added": str(repo)}
            if data.get("install"):
                ok, log = install_pipeline(repo, data.get("mode", "minimal"))
                out.update({"installed": ok, "log": log})
                if not ok: return self.send_json(out, 500)
            return self.send_json(out)
        if path == "/api/repos/install":              # install or upgrade in a repo already on the board
            repo, err = safe_repo_path(data.get("path"))
            if err: return self.send_json({"error": err}, 400)
            ok, log = install_pipeline(repo, data.get("mode", "minimal"))
            return self.send_json({"installed": ok, "log": log}, 200 if ok else 500)
        if path == "/api/repos/remove":               # remove from the board; files in the repo are left alone
            raw = data.get("path") or ""
            target = str(pathlib.Path(raw).expanduser().resolve()) if raw else ""
            keep = [r for r in self.cfg.get("repos", []) if str(pathlib.Path(r).expanduser().resolve()) != target]
            self.cfg["repos"] = keep; save_config(self.cfg)
            return self.send_json({"removed": target, "note": "removed from the board only; the repo's files are unchanged"})
        if path == "/api/roots":                      # add or remove a scan root
            root = data.get("path") or ""; rp = pathlib.Path(root).expanduser()
            roots = list(self.cfg.get("roots", []))
            if data.get("remove"):
                roots = [r for r in roots if r != root]
            else:
                if not rp.is_dir(): return self.send_json({"error": f"{root} is not a directory"}, 400)
                if root not in roots: roots.append(root)
            self.cfg["roots"] = roots; save_config(self.cfg)
            return self.send_json({"roots": roots})
        return self.send_json({"error": "not found"}, 404)
    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/state":
            return self.send_json(build_state(self.cfg))
        if path == "/api/browse":
            from urllib.parse import parse_qs
            q = parse_qs(urlparse(self.path).query)
            return self.send_json(browse((q.get("path") or ["~"])[0]))
        if path in ("/", "/index.html") or path.startswith("/#"):
            self.path = "/index.html"
        elif not (path.startswith("/design/") or path == "/favicon.svg"):
            self.send_error(404); return
        return super().do_GET()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default=str(HERE / "board.local.json"))
    ap.add_argument("--port", type=int)
    ap.add_argument("--json", action="store_true", help="print /api/state once and exit")
    ap.add_argument("--repo", action="append", default=[], help="add a repo path (repeatable; adds to the config)")
    a = ap.parse_args()
    cfg = load_config(a.config); cfg["_path"] = a.config
    cfg["repos"] = list(cfg.get("repos", [])) + a.repo
    if a.json:
        print(json.dumps(build_state(cfg), indent=2)); return
    port = a.port or cfg.get("port", 7777)
    Handler.cfg = cfg
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    n = len(discover(cfg))
    print(f"Gates on http://localhost:{port}  ({n} repo{'s' if n != 1 else ''}; config {a.config})")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
