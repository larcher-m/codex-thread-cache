# codex-thread-cache

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Python](https://img.shields.io/badge/Python-3.8%2B-blue.svg)](https://www.python.org/)

> 解决 Codex CLI 接入 DeepSeek 后查看历史对话严重卡顿的问题 —— 从 6 秒降到 88 毫秒。

## 问题

Codex 切换模型为 DeepSeek 后，每次查看历史对话记录需要等待 **6～7 秒**，因为底层用 `python -c` 内联脚本查询，每次都要冷启动 Python 解释器。

## 方案

**两层架构**：Python 一次性预建 JSON 缓存 + PowerShell 原生零启动读取。

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

| 场景 | 优化前 | 优化后 | 提升 |
|---|---|---|---|
| 列出对话列表 | ~6000ms | **88ms** | 68× |
| 查看单个对话 | ~6000ms | **135ms** | 44× |
| 缓存重建 | 6s × N 次 | 0.4s（自动） | — |

## 快速开始

### 前置要求

- Windows 10+ / Windows Server 2016+
- PowerShell 5.1+
- Python 3.8+（仅缓存构建时需要）

### 安装

```powershell
# 1. 克隆
git clone https://github.com/larcher-m/codex-thread-cache.git
cd codex-thread-cache

# 2. 首次构建缓存（后续自动）
python build_cache.py

# 3. 添加别名到 PowerShell Profile
Add-Content $PROFILE @"

# Codex history quick access
function Read-History { & "$PWD\read_history.ps1" @args }
Set-Alias -Name rh -Value Read-History
"@

# 4. 重新加载 Profile 或重开终端
. $PROFILE
```

### 使用

```powershell
rh                 # 列出所有对话线程
rh 019e64be        # 查看指定线程的完整对话内容
rh --rebuild       # 强制刷新缓存
```

### 自动缓存维护

`read_history.ps1` 每次运行时会自动比较数据库和缓存的修改时间：

- 缓存新鲜 → PowerShell 原生读取，**88ms**
- 缓存过期 → 自动调用 `build_cache.py` 重建，**~0.4s**
- 用户完全无感，只需敲 `rh`

## 文件说明

| 文件 | 说明 |
|---|---|
| `build_cache.py` | Python 脚本，一次性读取 SQLite + JSONL，生成 `thread_cache.json` |
| `read_history.ps1` | PowerShell 脚本，原生解析 JSON 缓存并展示，自动检测过期 |
| `article-juejin.md` | 掘金技术文章（完整排查过程 + 设计思路） |
| `architecture.mermaid` | 系统架构 Mermaid 图 |
| `perf-comparison.mermaid` | 性能对比甘特图 |

## 设计思路

### 为什么不是"优化查询"？

11 个线程、4.5MB 数据——任何 SQL 查询都不应该慢。真正的瓶颈是 **Python 冷启动**：

```
python -c "import sqlite3; ..."
         ↑ 每次都要走这套流程
```

每次 `python -c` 都要启动解释器 → 加载模块 → 连接数据库 → 解析 JSONL → 退出进程。不是查询慢，是启动慢。

### 为什么选 PowerShell 做日常读取？

PowerShell 是 Windows 自带的，`Get-Content | ConvertFrom-Json` 没有进程启动开销。对于一个高频操作（每天几十次），零启动成本比任何查询优化都重要。

### 核心原则

1. **预计算 > 实时查询** — SQL + JSONL → JSON 缓存，一次性完成
2. **用对的工具做对的事** — Python 做批量数据清洗，Shell 做高频轻量读取
3. **自动化过期检测** — 用户只需一个命令，不操心缓存状态

## 适用范围

任何使用「SQLite + JSONL」存储、且通过 Python 内联脚本查询的场景，都可以用同样的「预建缓存 + 原生解析」思路优化。

## 相关文章

- 📝 [掘金](https://juejin.cn/post/7644745124401397802)
- 📰 [B 站专栏](https://www.bilibili.com/opus/1207468413903962150)

- [掘金：Codex + DeepSeek 对话记录卡顿排查与优化](https://juejin.cn/post/7644745124401397802)

## License

MIT
