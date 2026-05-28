# 从 6 秒到 88 毫秒：我是怎么解决 Codex + DeepSeek 对话记录卡顿的

## 起因

最近把 Codex CLI 的默认模型从 GPT 换成了 DeepSeek，用着挺爽——直到我发现一个致命问题：

**每次切对话记录都要等 6 秒。**

不是什么偶发卡顿，是每一次。翻 5 个历史对话就要干坐半分钟。作为一个一天切几十次对话的人，这简直没法用。

## 第一反应：数据库太大了？

Codex 的对话数据存在两个地方：

- `~/.codex/state_5.sqlite` — 存线程元数据
- `~/.codex/sessions/2026/05/*.jsonl` — 存完整对话内容

我心想肯定是数据太多了。一扫：

```
11 个线程
4.5 MB JSONL 数据
```

就这？4.5MB 要 6 秒？不可能是数据量的问题。

## 真正的原因：Python 冷启动

Codex 内部查询对话用的是 `python -c` 内联脚本，大概长这样：

```bash
python -c "import sqlite3; import json; db=sqlite3.connect(...); ..."
```

每次执行都要走完完整流程：

```
启动 Python 解释器      ~2s
加载 sqlite3 模块       ~0.5s
连接数据库 + 查询       ~0.5s
读取 JSONL 文件         ~1s
格式化输出             ~0.5s
────────────────────────────
总计                    ~5-7s
```

Python 启动本身就要 2 秒。11 个线程，11 次查询，每次都是冷启动。

**根因不是数据多，是每次都在重复启动一个重量级运行时。**

## 第一版方案：一次读完存 JSON

思路很简单——写一个 Python 脚本，一次性把 SQLite + 所有 JSONL 读完，存成一个 `thread_cache.json`。以后读缓存就行了。

写了个 `build_thread_cache.py`，跑了一下：

```
Cache built: 11 threads, 2515 total messages
Time: 0.4s
```

不错，建缓存只要 0.4 秒。然后写了个 `read_history.py` 读缓存：

```bash
python read_history.py
# 0.4s
```

从 6 秒降到 0.4 秒，15 倍提升。我挺满意，发了个别名 `rh`，觉得问题解决了。

## 问题没完：重启后又是 3 秒

第二天打开电脑，敲 `rh`——又是 3 秒。

不是读取慢，是 Python 冷启动慢。缓存文件在那躺着，但 **启动 Python 解释器本身就要 2-3 秒**。

我意识到：缓存思路没错，但用 Python 做日常读取本身就是错的。

## 终局方案：PowerShell 原生解析

PowerShell 是 Windows 终端自带的，没有启动开销。而我们的缓存就是一个 JSON 文件，PowerShell 原生就能解析。

```powershell
$cache = Get-Content thread_cache.json -Raw | ConvertFrom-Json
# 88ms
```

88 毫秒。不是秒，是毫秒。

最终架构变成了两层：

```
layer 1: build_cache.py    (Python, 仅在缓存过期时运行, 0.4s)
layer 2: read_history.ps1  (PowerShell 原生, 日常读取, 88ms)
```

关键逻辑：**自动过期检测**

```powershell
$cacheTime = (Get-Item $CACHE).LastWriteTime
$dbTime = (Get-Item $DB).LastWriteTime
if ($dbTime -gt $cacheTime) {
    python build_cache.py  # 缓存过期，自动重建
}
# 否则直接用 PowerShell 秒读
```

用户完全无感——缓存新鲜时 88ms，过期时自动重建也是 0.4s，没有手动操作。

## 效果

| 操作 | 优化前 | 优化后 | 
|---|---|---|
| 列出对话列表 | ~6000ms | **88ms** |
| 查看指定对话 | ~6000ms | **135ms** |
| 缓存重建 | 6s × N 次查询 | 0.4s（自动触发） |

## 思路总结

这个方案的精髓不是「写了更好的查询」，而是**换了一个不需要启动开销的运行时来做日常读取**。

具体来说三条原则：

1. **预计算 > 实时查询**：把一次性工作提前做完，存成静态文件
2. **用对的工具做对的事**：Python 适合数据清洗和批量处理，不适合高频轻量读取
3. **让用户无感**：自动检测过期 + 自动重建，用户只需要敲一个命令

## 代码仓库

GitHub: [链接]

完整代码两个文件：`build_cache.py` + `read_history.ps1`，配置好别名就能用。

---

*如果你也遇到类似的「明明数据不多但就是慢」的问题，可以先看看是不是每次都在冷启动一个重运行时——这个坑比数据量本身更常见。*
