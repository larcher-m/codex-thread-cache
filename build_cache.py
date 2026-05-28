import sqlite3, json, os
from datetime import datetime, timezone, timedelta

DB = os.path.expanduser(r"~\.codex\state_5.sqlite")
CACHE = os.path.expanduser(r"~\.codex\thread_cache.json")
GS = os.path.expanduser(r"~\.codex\.codex-global-state.json")
TZ = timezone(timedelta(hours=8))

prompt_history = {}
if os.path.exists(GS):
    try:
        with open(GS, encoding="utf-8") as f:
            ph = json.load(f).get("electron-persisted-atom-state", {}).get("prompt-history", {})
        prompt_history = ph or {}
    except: pass

db = sqlite3.connect(DB)
db.row_factory = sqlite3.Row
rows = db.execute("SELECT * FROM threads ORDER BY created_at DESC").fetchall()
db.close()

threads = {}
for r in rows:
    tid = r["id"]; rp = r["rollout_path"]
    messages = []
    if rp and os.path.exists(rp):
        with open(rp, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        obj = json.loads(line)
                        role = obj.get("role","?")
                        content = ""
                        if isinstance(obj.get("content"), str):
                            content = obj["content"]
                        elif isinstance(obj.get("content"), list):
                            parts = []
                            for part in obj["content"]:
                                if isinstance(part, dict):
                                    if part.get("type")=="text": parts.append(part.get("text",""))
                                    elif part.get("type")=="tool_call": parts.append(f"[tool:{part.get('name','?')}]")
                            content = " ".join(parts)
                        messages.append({"role":role,"content":content})
                    except: pass
    ts = datetime.fromtimestamp(r["created_at"] or 0, TZ).strftime("%Y-%m-%d %H:%M") if r["created_at"] else "?"
    threads[tid] = {
        "id":tid,"title":r["title"] or "","first":(r["first_user_message"] or "")[:120],
        "time":ts,"model":r["model"] or "?","archived":bool(r["archived"]),
        "tokens":r["tokens_used"] or 0,"cwd":r["cwd"] or "",
        "msg_count":len(messages),"prompts":prompt_history.get(tid,[]),"messages":messages
    }

cache = {"count":len(threads),"threads":threads,"updated":int(datetime.now(TZ).timestamp())}
with open(CACHE,"w",encoding="utf-8") as f:
    json.dump(cache, f, ensure_ascii=False)
print(f"OK {len(threads)} threads")
