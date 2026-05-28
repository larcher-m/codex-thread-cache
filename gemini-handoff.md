# Gemini 视频制作交接文档

## 项目概述

这是一个技术排障 + 解决方案分享项目。Codex CLI 接入 DeepSeek 后查看历史对话严重卡顿（每次 6 秒），我们排查出根因是 Python 冷启动开销，通过"预建 JSON 缓存 + PowerShell 原生解析"两层架构，从 6000ms 优化到 88ms。

## 已发布内容

- 掘金文章：https://juejin.cn/post/7644745124401397802
- B站专栏：https://www.bilibili.com/opus/1207468413903962150
- GitHub 仓库：https://github.com/larcher-m/codex-thread-cache

## Gemini 需要产出的

根据下面的脚本，制作一个 **4 分 30 秒**的技术讲解视频。需要：
- 生成画面/动画（不需要真人出镜）
- 生成配音/口播
- 展示终端操作、架构图、性能对比
- BGM：轻电子/chillhop
- 整体风格：技术向，简洁，有节奏感

---

## 完整视频脚本

**标题**：Codex + DeepSeek 用户请进：你的对话记录是不是也卡到想砸键盘？

### 分镜表

| 时间段 | 画面 | 口播 |
|---|---|---|
| 0:00-0:15 | 片头：黑底白字标题「Codex + DeepSeek 用户请进」，底下小字「你的对话记录是不是也卡到想砸键盘？」 | BGM渐进，可加键盘敲击音效 |
| 0:15-0:45 | 终端画面，切到历史对话，计时器显示 6.2s | 如果你也把 Codex 的模型从 GPT 换成了 DeepSeek，那你大概率遇到过这个——每次翻看历史对话，点一下……等 6 秒。再点一个……又 6 秒。你敢翻 5 个对话，半分钟就没了。我忍了一周，终于受不了，动手把它修好了。 |
| 0:45-1:15 | 打开 ~/.codex/ 目录，高亮 state_5.sqlite 和 sessions/，显示统计数据：11 线程、4.5MB | 第一时间我想：肯定是数据库太大了吧？打开一看——11 个线程，总共 4.5MB 数据。就这？4.5MB 的 SQLite 怎么可能要 6 秒？ |
| 1:15-1:45 | 展示 python -c 命令，逐行标注耗时分解：Python启动 2s → sqlite3 0.5s → 查询 0.5s → JSONL 1s → 输出 1s | 真实原因藏在这里。Codex 内部查对话用的是 python -c 内联脚本。每次执行，你的电脑都要——启动 Python 解释器 2 秒、加载 sqlite3 0.5 秒、连接数据库 0.5 秒、再解析 JSONL 文件 1 秒。不是数据大，是每次都在重新启动一个重量级运行时。 |
| 1:45-2:15 | Mermaid架构图动画：SQLite+JSONL → build_cache.py → thread_cache.json → read_history.ps1 → 用户 | 解决方案——既然 Python 启动慢，那就让它只启动一次。两层架构：底层用 Python 一次性读完所有数据生成静态 JSON 缓存，上层日常读取用 PowerShell 原生解析。 |
| 2:15-2:45 | 终端实操：python build_cache.py → 0.4s 完成 | 缓存构建脚本，一次性读取全部数据，0.4 秒搞定。平时不用跑，对话更新时自动触发。 |
| 2:45-3:30 | 终端实操：敲 rh → 88ms 出列表；敲 rh 019e64be → 135ms 出 305 条消息 | 日常查询用 PowerShell 脚本，别名 rh。看好了——88 毫秒出列表，135 毫秒出完整对话。6 秒到 88 毫秒，68 倍提升。 |
| 3:30-4:00 | 性能对比表：红→黄→绿三栏（6s → 3s → 88ms） | 三个阶段：原生 6 秒、第一版缓存 3 秒、终版 88 毫秒。不是优化了查询，是换了一个没有启动开销的运行时。 |
| 4:00-4:20 | GitHub 仓库页面截图 + README | 完整代码开源在 GitHub，两个文件加一行别名，三分钟搞定。 |
| 4:20-4:30 | 片尾：黑底白字「被卡过？点个赞」+ GitHub链接 | 如果你也被折磨过，点个赞让更多人看到。下期见。 |

---

## 关键画面素材说明

### 终端演示命令（需要模拟展示）

```bash
# 旧方案（展示慢）
python -c "import sqlite3, json, os; db=sqlite3.connect(os.path.expanduser('~/.codex/state_5.sqlite')); rows=db.execute('SELECT COUNT(*) FROM threads').fetchone(); print(rows)"

# 新方案 - 构建缓存
python build_cache.py
# 输出: Cache built: 11 threads, 2515 total messages  (0.4s)

# 新方案 - 查询
rh
# 输出: 11 个对话线程列表  (88ms)

rh 019e64be
# 输出: 305 条完整消息  (135ms)
```

### 架构图

```
┌─────────────┐      ┌──────────────────┐      ┌──────────────────┐
│ state_5.sqlite│ ──▶ │ build_cache.py  │ ──▶ │thread_cache.json │
│ rollout/*.jsonl│     │ (仅过期时运行)    │      │   (静态缓存)      │
└─────────────┘      └──────────────────┘      └────────┬─────────┘
                                                        │
┌─────────────┐      ┌──────────────────┐               │
│   用户敲 rh  │ ──▶ │ read_history.ps1 │ ◀─────────────┘
└─────────────┘      │ (PowerShell 原生) │
                     │ 88ms 秒出         │
                     └──────────────────┘
```

请将此 ASCII 图美化为动画风格的架构图，带颜色和动效。

### 性能对比表

| 场景 | 优化前 | 第一版 | 终版 |
|---|---|---|---|
| 列出对话 | 6000ms | 3000ms | **88ms** |
| 查看单线程 | 6000ms | 3000ms | **135ms** |

建议做成三栏对比动画：红色 → 黄色 → 绿色，数字跳动，88ms 处放大高亮。

### 代码展示（可选，放画面一侧滚动）

build_cache.py 核心逻辑：
```python
db = sqlite3.connect("~/.codex/state_5.sqlite")
rows = db.execute("SELECT * FROM threads").fetchall()
for r in rows:
    with open(r["rollout_path"]) as f:
        messages = [json.loads(line) for line in f]
    threads[r["id"]] = {...}
json.dump(threads, open("thread_cache.json", "w"))
```

read_history.ps1 核心逻辑：
```powershell
$cache = Get-Content thread_cache.json | ConvertFrom-Json
if ($dbTime -gt $cacheTime) { python build_cache.py }
foreach ($t in $cache.threads) { Write-Host $t.title }
```

---

## 技术细节（供 Gemini 理解背景）

### 问题根因
Codex 用 `python -c` 内联脚本查 SQLite + JSONL，每次冷启动 Python 2 秒 + 加载模块 + 查询，累积 6-7 秒。11 个线程就是 11 轮冷启动。

### 解决方案
- `build_cache.py`：一次性批量读 SQLite + 全部 JSONL → 生成 thread_cache.json（0.4s）
- `read_history.ps1`：PowerShell 原生读 JSON（无启动开销），88ms
- 自动过期检测：比较数据库和缓存的修改时间，过期时自动重建
- 别名：`rh` 一键查询

### 效果
从 6000ms 到 88ms，68 倍提升。

---

## 风格要求

- 画风：简约技术风，深色背景 + 青色/绿色高亮
- 字体：等宽字体用于代码，无衬线用于标题
- 节奏：前半段偏慢（铺垫问题），2:45 起加速（展示解决方案）
- BGM：chillhop / lofi，2:45 后可稍快
- 关键数字（88ms、68x）要大、要突出

---

## 最终交付

生成完整视频文件（MP4，1080p+），可直接上传 B 站。视频发布后链接回填到：
- B 站专栏底部（替换"录制中"）
- 掘金文章  
- GitHub README
