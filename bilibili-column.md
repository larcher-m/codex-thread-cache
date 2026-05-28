# Codex + DeepSeek 用户请进：你的对话记录是不是也卡到想砸键盘？

> 配套视频已发，搜索「Codex 卡顿」或点我主页查看。本文是文字版，方便复制代码和慢慢看。

---

## 你有这个问题吗？

把 Codex CLI 的模型从 GPT 换成 DeepSeek 之后，每次翻看历史对话——

点一下。
等。
等。
等。
**6 秒。**

翻五个对话，半分钟没了。

如果你也遇到了，恭喜，不是你的电脑问题，不是 DeepSeek 的问题，是 Codex 内部一个非常蠢的设计。

---

## 不是数据库大，是 Python 在摸鱼

我第一时间打开 Codex 的数据目录看了一眼：

```
~/.codex/
├── state_5.sqlite    ← SQLite 数据库
└── sessions/
    └── 2026/05/
        ├── rollout-xxx.jsonl
        ├── rollout-yyy.jsonl
        └── ...
```

总共 **11 个线程，4.5MB 数据**。就这？

那为什么这么慢？因为 Codex 内部是这样查对话的：

```bash
python -c "import sqlite3; import json; db=sqlite3.connect(...); SELECT ...; 读 JSONL ..."
```

每一次查询，你的电脑实际上在干这些事：

```
启动 Python 解释器      ████████████ 2 秒
加载 sqlite3 模块       ███         0.5 秒
连接数据库 + SQL 查询    ███         0.5 秒
逐行解析 JSONL 文件     ██████      1 秒
格式化输出 + 退出进程    ████        1 秒
─────────────────────────────────────────
合计                               5-7 秒
```

11 个线程 = 11 次查询 = 11 轮完整的 Python 冷启动。

**不是 SQL 慢，不是 JSONL 大，是每次都在重新请 Python 起床。**

---

## 修复思路：让 Python 只醒一次

既然问题在启动开销，那就换个思路：

> **Python 干一次重活，把结果存成静态文件；日常读取用不需要启动开销的工具。**

```
┌─────────────┐      ┌──────────────────┐      ┌──────────────────┐
│ state_5.sqlite│ ──▶ │ build_cache.py  │ ──▶ │thread_cache.json │
│ rollout/*.jsonl│     │ (只跑一次)        │      │   (静态缓存)      │
└─────────────┘      └──────────────────┘      └────────┬─────────┘
                                                        │
┌─────────────┐      ┌──────────────────┐               │
│   你敲 rh    │ ──▶ │ read_history.ps1 │ ◀─────────────┘
└─────────────┘      │ (PowerShell 原生) │
                     │ 88ms 秒出         │
                     └──────────────────┘
```

### 第一步：build_cache.py（一次性构建）

这是一个 Python 脚本，功能就一件事——把 SQLite 和所有 JSONL 的数据全读出来，写成一个 `thread_cache.json`：

```python
import sqlite3, json, os

db = sqlite3.connect(os.path.expanduser("~/.codex/state_5.sqlite"))
db.row_factory = sqlite3.Row
rows = db.execute("SELECT * FROM threads ORDER BY created_at DESC").fetchall()

threads = {}
for r in rows:
    # 读取这个线程对应的 JSONL 文件
    messages = []
    if r["rollout_path"] and os.path.exists(r["rollout_path"]):
        with open(r["rollout_path"], encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    msg = json.loads(line)
                    messages.append({
                        "role": msg.get("role", "?"),
                        "content": msg.get("content", "")
                    })
    
    threads[r["id"]] = {
        "title": r["title"],
        "model": r["model"],
        "msg_count": len(messages),
        "messages": messages,
        # ... 其他字段
    }

with open(CACHE, "w", encoding="utf-8") as f:
    json.dump({"count": len(threads), "threads": threads}, f)
```

跑一次：

```
Cache built: 11 threads, 2515 total messages
Time: 0.4s
```

**这个脚本平时不需要手动跑。** 只有对话记录更新后，它才会自动触发。

### 第二步：read_history.ps1（日常秒读）

这是 PowerShell 脚本，纯原生，没有启动开销。核心就几行：

```powershell
# 读缓存文件
$cache = Get-Content thread_cache.json -Raw -Encoding UTF8 | ConvertFrom-Json

# 自动检测过期
$cacheTime = (Get-Item $CACHE).LastWriteTime
$dbTime = (Get-Item $DB).LastWriteTime
if ($dbTime -gt $cacheTime) {
    # 缓存过期了，自动重建
    python build_cache.py
}

# 遍历输出
foreach ($tid in $cache.threads.PSObject.Properties.Name) {
    $t = $cache.threads.$tid
    Write-Host "$($t.time) | $($t.model) | $($t.msg_count)msg | $($t.title)"
}
```

### 第三步：加个别名

在 PowerShell Profile 里加两行：

```powershell
function Read-History { & "path\to\read_history.ps1" @args }
Set-Alias -Name rh -Value Read-History
```

以后任何终端里敲 `rh` 就行了。

---

## 效果

| 操作 | 优化前 | 优化后 |
|---|---|---|
| 列出对话列表 | ~6000ms | **88ms** |
| 查看指定对话 | ~6000ms | **135ms** |
| 缓存更新 | 6s × N 次查询 | 0.4s（自动触发） |

从 **6 秒** 到 **88 毫秒**，**68 倍提升**。

我特意跑了三遍确认——不是缓存命中，是真的每次都是原生解析。冷启动没了，自然就快了。

---

## 安装（三分钟）

```powershell
# 1. 克隆仓库
git clone https://github.com/larcher-m/codex-thread-cache.git
cd codex-thread-cache

# 2. 首次构建缓存
python build_cache.py

# 3. 添加别名
Add-Content $PROFILE @"

function Read-History { & "$PWD\read_history.ps1" @args }
Set-Alias -Name rh -Value Read-History
"@

# 4. 重载配置
. $PROFILE

# 5. 开用
rh
```

搞定。以后敲 `rh` 就能秒看所有对话，敲 `rh 线程ID前缀` 看具体内容。

---

## 核心思想

这方案说白了就一条：

> **把一次性重活交给 Python，把高频轻活交给原生 Shell。**

不是什么高深的技术，就是「别用牛刀杀鸡」。但大多数时候，性能问题的答案就在这种选择里。

下次你遇到「明明数据不多但就是慢」的情况，先别优化查询——看看是不是每次都在冷启动一个重量级运行时。这个坑，比数据量本身常见多了。

---

## 链接

- 📦 **GitHub**：[larcher-m/codex-thread-cache](https://github.com/larcher-m/codex-thread-cache)
- 🎬 **B 站视频**：（录制中）
- ✍️ **掘金**：https://juejin.cn/post/7644745124401397802

有问题评论区见，好用的话点个赞让更多人看到 ✌️
