---
highlight: vs2015
theme: smartblue
---

> 🏷️ **标签**：性能优化 · SQLite · PowerShell · Codex · DeepSeek · 故障排查
> 📦 **GitHub**：[larcher-m/codex-thread-cache](https://github.com/larcher-m/codex-thread-cache)
> 📝 **前篇**：[Codex + DeepSeek 用户请进：你的对话记录是不是也卡到想砸键盘？](https://juejin.cn/post/7644745124401397802)

# 后续：上次的优化又崩了？这次是 SQLite WAL 把 Codex 直接卡死了

## TL;DR

上篇用「预建缓存 + PowerShell 原生读取」把对话记录从 6 秒降到 88ms。**但两周后 Codex 桌面应用直接卡死——点击任何历史对话就假死。**

新根因有两个：

1. **SQLite WAL 日志膨胀**：`state_5.sqlite` 的 WAL 文件从 0 涨到 **4MB**（数据库本身才 300KB），每次读取要扫 870 页未合并日志
2. **日志数据库失控**：`logs_2.sqlite` 胀到 **70MB**，其中 52% 是 TRACE 级别日志

解决方案：一键启动器（启动即清理）+ Windows 定时任务（每 3 小时自动维护）+ 增强版 `rh`。

---

## 又出问题了

上篇文章发完后，`rh` 命令一直很好用——88ms 秒出，毫无卡顿。我甚至把桌面应用侧边栏的"加载中…"都忘了。

**直到某天，Codex 桌面应用突然彻底卡死。** 不是慢——是点击任何历史对话就假死，任务管理器里显示"无响应"。

终端里的 `rh` 仍然秒出。说明不是数据损坏，是**应用本身出了问题**。

## 排查：三个 SQLite 文件的秘密

Codex 的数据目录 `~/.codex` 里有三个 SQLite 数据库：

```
state_5.sqlite      300KB   ← 对话元数据（线程、标题、模型）
logs_2.sqlite        70MB   ← 运行日志
goals_1.sqlite       24KB   ← 目标任务
```

看大小都正常，直到我注意到同名的 `.sqlite-wal` 文件：

```
state_5.sqlite       300KB   ← 数据库本体
state_5.sqlite-wal    4.1MB  ← WAL 日志！！！ 
state_5.sqlite-shm    32KB   

logs_2.sqlite         70MB
logs_2.sqlite-wal     4.2MB  ← 又是 4MB WAL
```

**WAL 文件比数据库大了 13 倍。** 这才是真凶。

## 什么是 WAL，为什么它会胀成这样？

SQLite 默认使用 WAL（Write-Ahead Log）模式。简单说：

- 写操作不直接改数据库，先写到 WAL 文件
- 读操作需要同时查数据库 + WAL，合并最新结果
- 当 WAL 积累到一定大小，触发 checkpoint 合并回主数据库

正常情况下这个过程对用户透明。**但 Codex 桌面应用在运行期间持续高频写入**（记录日志、更新状态），而 checkpoint 频率跟不上写入速度，导致 WAL 像滚雪球一样越来越大。

```
正常 WAL:     ▏ 几 KB，随时合并
Codex 的 WAL: ████████████████ 4MB，870 页待合并
```

每次切换对话，应用读取 `state_5.sqlite` 时，SQLite 需要在 870 页 WAL 中逐页查找最新数据。870 次磁盘 IO，每次几百毫秒——**UI 线程直接卡死。**

## 解决方案

### 1. 手动 checkpoint：把 WAL 合并回数据库

```python
import sqlite3
conn = sqlite3.connect("state_5.sqlite")
conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
conn.close()
```

效果立竿见影：

```
state_5.sqlite-wal:  4,140KB → 0KB
logs_2.sqlite-wal:   4,273KB → 0KB
```

**但这只是临时的。Codex 继续跑，WAL 几小时后又涨回来。**

### 2. 日志数据库大扫除

`logs_2.sqlite` 为什么 70MB？看下日志级别分布：

```
TRACE: 17,578 条 (52.1%)  ← 全是 HTTP 连接、文件监控、SSE 流的冗余日志
INFO:   7,508 条
DEBUG:  7,328 条
WARN:   1,302 条
ERROR:     33 条
```

超过一半是 TRACE 日志，每次 HTTP 请求、每个文件变动都记一条。删掉 TRACE/DEBUG 后：

```
logs_2.sqlite: 70MB → ~15MB
```

### 3. 一键启动器：从此不用手动操作

手动跑 checkpoint 太蠢了。写了个启动器 `codex_launcher.ps1`，每次双击它就会：

1. 检查 Codex 是否已在运行
2. 对三个数据库做 WAL checkpoint
3. 日志超过 30MB 时自动清理 TRACE/DEBUG
4. 清理临时文件
5. 启动 Codex 桌面应用

放在桌面当快捷方式，从此启动即清爽。

### 4. Windows 定时任务：无人值守维护

绕不开的问题：Codex 运行时数据库被锁定，无法清理。所以设了一个 Windows 定时任务，**每 3 小时自动跑一次**——如果 Codex 刚好关了，自动清理；如果开着，等下一次。

```powershell
schtasks /Create /TN "Codex DB Auto Cleanup" /SC DAILY /RI 180 /DU 24:00 /IT /F `
  /TR "powershell -WindowStyle Hidden -File codex_cleanup.ps1"
```

### 5. 增强版 `rh`：搜索 + 详情 

原来的 `rh` 只能列表和看详情。增强版加了**关键词搜索**：

```powershell
rh                 # 列表（88ms）
rh 赛博朋克         # 搜索标题含"赛博朋克"的对话
rh 019e6a94        # 查看指定对话详情
rh --rebuild       # 强制刷新缓存
```

而且现在 `rh` 可以被 cmd 和 PowerShell 同时识别，复制到了 PATH 目录。

## 完整文件清单

| 文件 | 用途 | 新增 |
|---|---|---|
| `build_cache.py` | SQLite + JSONL → JSON 缓存 | 原有 |
| `rh.ps1` | 列表 / 搜索 / 详情（PowerShell 原生） | **增强** |
| `codex_cleanup.ps1` | WAL checkpoint + 日志清理 + VACUUM | **新增** |
| `codex_launcher.ps1` | 清理 → 启动 Codex（一键） | **新增** |
| `codex_launcher.bat` | bat 包装器，双击即用 | **新增** |

## 教训

这次追查让我对 SQLite WAL 有了切身体会：

> WAL 不是为了让你无限写的——它是缓冲区，不是垃圾场。高频写入场景下，checkpoint 频率必须跟得上写入速度。

Codex 的问题在于把大量 TRACE 日志和状态更新写入 WAL，却不及时 checkpoint。应用开发者应该要么降低日志级别，要么定期主动 checkpoint。

对用户来说，**上篇解决的是「慢」，这篇解决的是「死」**。两者配合才是一个完整的方案：

```
终端浏览（快）    ← rh → 88ms → 上篇
应用不卡（稳）    ← cleanup + launcher → 本篇
自动维护（省心）  ← 定时任务 → 本篇
```

---

*如果你也遇到「以为修好了结果又崩了」的情况，别急着怀疑之前的方案——先看看 SQLite 的 WAL 文件和日志数据库，这个坑比 Python 冷启动藏得更深。*

*完整代码和脚本见 GitHub：[larcher-m/codex-thread-cache](https://github.com/larcher-m/codex-thread-cache)*
