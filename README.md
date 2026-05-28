# 解决 DeepSeek 接入 Codex 后对话记录严重卡顿的问题

> 从 6 秒到 88 毫秒：用本地缓存 + PowerShell 原生解析替代 Python 冷启动

## 问题

将 Codex CLI 的模型切换为 DeepSeek 后，每次查看历史对话记录都需要等待 **6～7 秒**，切一个线程等一次，体验极差。

## 排查

Codex 的对话数据存储在：

- **SQLite 数据库** `~/.codex/state_5.sqlite` — 存线程元数据（标题、时间、模型等）
- **JSONL 日志文件** `~/.codex/sessions/2026/05/28/rollout-*.jsonl` — 存完整对话内容

最初用 `python -c` 内联脚本查询：

```bash
python -c "import sqlite3; db=sqlite3.connect(...); ..."
```

每次执行都要：启动 Python 解释器 → 加载 sqlite3 模块 → 连接数据库 → 解析 JSONL → 输出。单次 **6～7 秒**。

## 根因

不是数据库大（实际只有 11 个线程、4.5MB 数据），而是 **Python 冷启动开销**在每次查询时都会发生。

## 解决方案

### 架构

```
┌─────────────┐      ┌──────────────────┐      ┌──────────────┐
│ state_5.sqlite│ ──▶ │ build_cache.py  │ ──▶ │thread_cache.json│
│ rollout/*.jsonl│     │ (仅缓存过期时运行) │      │  (静态缓存)    │
└─────────────┘      └──────────────────┘      └──────┬───────┘
                                                      │
┌─────────────┐      ┌──────────────────┐              │
│   用户敲 rh  │ ──▶ │ read_history.ps1 │ ◀────────────┘
└─────────────┘      │ (PowerShell 原生)  │
                     │ 88ms 秒出          │
                     └──────────────────┘
```

### 核心思路

1. **一次性批量构建缓存**：Python 脚本一次性读取全部 SQLite 和 JSONL 数据，生成 `thread_cache.json`
2. **PowerShell 原生读取**：日常查询用 PowerShell 的 `ConvertFrom-Json` 直接解析缓存，零启动开销
3. **自动过期检测**：比较缓存文件与数据库的修改时间，过期时自动触发重建

### 关键代码

**`build_cache.py`**（仅在缓存过期时运行）：

```python
import sqlite3, json, os

db = sqlite3.connect(os.path.expanduser("~/.codex/state_5.sqlite"))
db.row_factory = sqlite3.Row
rows = db.execute("SELECT * FROM threads ORDER BY created_at DESC").fetchall()

threads = {}
for r in rows:
    # 读取 rollout JSONL 文件
    messages = []
    if r["rollout_path"] and os.path.exists(r["rollout_path"]):
        with open(r["rollout_path"], encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    msg = json.loads(line)
                    messages.append({
                        "role": msg.get("role", "?"),
                        "content": extract_content(msg)
                    })
    threads[r["id"]] = { ... }

with open(CACHE, "w", encoding="utf-8") as f:
    json.dump({"count": len(threads), "threads": threads}, f, ensure_ascii=False)
```

**`read_history.ps1`**（PowerShell 原生，88ms）：

```powershell
# 自动检测缓存是否过期
$cacheTime = (Get-Item $CACHE).LastWriteTime
$dbTime = (Get-Item $DB).LastWriteTime
if ($dbTime -gt $cacheTime) {
    python build_cache.py  # 仅在过期时触发
}

# PowerShell 原生读取 JSON（零启动开销）
$cache = Get-Content $CACHE -Raw -Encoding UTF8 | ConvertFrom-Json

foreach ($tid in $cache.threads.PSObject.Properties.Name) {
    $t = $cache.threads.$tid
    Write-Host "$($t.time) | $($t.model) | $($t.msg_count)msg | $($t.title)"
}
```

### 别名设置

在 PowerShell Profile 中添加：

```powershell
function Read-History { & "path/to/read_history.ps1" @args }
Set-Alias -Name rh -Value Read-History
```

### 使用

```powershell
rh                # 列出所有对话线程
rh 019e64be       # 查看指定线程的完整对话
rh --rebuild      # 强制刷新缓存
```

## 效果对比

| 场景 | 优化前 | 优化后 | 提升 |
|---|---|---|---|
| 列出线程列表 | ~6000ms | **88ms** | **68×** |
| 查看单个线程 | ~6000ms | **135ms** | **44×** |
| 缓存重建（过期时） | 6s × N 次 | **400ms**（一次性） | **15×** |

## 适用范围

任何使用 SQLite + JSONL 存储、且通过 Python 内联脚本查询的场景，都可以用同样的「预建缓存 + 原生解析」思路优化。不仅限于 Codex。

## 文件结构

```
.
├── build_cache.py      # Python 缓存构建脚本
├── read_history.ps1    # PowerShell 查询入口
└── README.md
```
