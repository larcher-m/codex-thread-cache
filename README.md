# codex-thread-cache

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Python](https://img.shields.io/badge/Python-3.8%2B-blue.svg)](https://www.python.org/)

> 解决 Codex 接入 DeepSeek 后历史对话卡顿 & 卡死的完整方案。

## 两个问题，一个仓库

| 问题 | 症状 | 根因 | 方案 | 文章 |
|---|---|---|---|---|
| **卡顿** | 切对话 6 秒 | Python 冷启动 | 预建缓存 + PowerShell 原生读取 (88ms) | [掘金·上篇](https://juejin.cn/post/7644745124401397802) |
| **卡死** | 点击对话假死 | SQLite WAL 膨胀 (4MB) + 日志 70MB | 自动 checkpoint + 定时清理 | [掘金·后续](https://juejin.cn/post/7645141802761568299) |

## 架构

```
┌──────────────────────────────────────────────────┐
│                   终端层（日常）                    │
│  rh          → 列表 / 搜索 / 详情 (88ms)           │
│  rh 关键词    → 搜索标题                            │
│  rh id前缀    → 查看对话                            │
└──────────────────────────────────────────────────┘
                          │
┌──────────────────────────────────────────────────┐
│                   维护层（自动化）                   │
│  codex_launcher → 清理 WAL → 启动应用（一键）       │
│  定时任务       → 每 3 小时自动 checkpoint          │
└──────────────────────────────────────────────────┘
                          │
┌──────────────────────────────────────────────────┐
│                   构建层（偶尔）                     │
│  build_cache.py → SQLite + JSONL → JSON 缓存       │
│  codex_cleanup.ps1 → WAL 清理 + 日志瘦身           │
└──────────────────────────────────────────────────┘
```

## 快速开始

```powershell
# 1. 克隆仓库
git clone https://github.com/larcher-m/codex-thread-cache.git
cd codex-thread-cache

# 2. 构建缓存
python build_cache.py

# 3. 安装 rh 命令（任选一种）
## 方式 A：复制到 PATH（cmd 和 PowerShell 都能用）
copy rh.bat C:\Users\%USERNAME%\AppData\Local\Programs\Python\Python314\Scripts\rh.bat

## 方式 B：PowerShell 别名
Add-Content $PROFILE "`nfunction rh { & '$PWD\rh.ps1' @args }"

# 4. 使用
rh              # 秒出列表
rh DeepSeek     # 搜索
rh 019e6a94     # 查看详情

# 5. 设置自动维护（可选但推荐）
## 创建桌面快捷方式：指向 codex_launcher.bat，固定到任务栏
## 设置定时任务：
schtasks /Create /TN "Codex DB Auto Cleanup" /SC DAILY /RI 180 /DU 24:00 /IT /F `
  /TR "powershell -WindowStyle Hidden -File %CD%\codex_cleanup.ps1"
```

## 文件说明

| 文件 | 说明 |
|---|---|
| `build_cache.py` | Python 脚本，一次性读取 SQLite + JSONL，生成 `thread_cache.json` |
| `rh.ps1` | PowerShell 脚本，原生解析 JSON 缓存，支持列表/搜索/详情 |
| `rh.bat` | cmd 包装器，复制到 PATH 后可在任何终端使用 `rh` |
| `codex_cleanup.ps1` | WAL checkpoint + TRACE/DEBUG 日志清理 + VACUUM |
| `codex_launcher.ps1` | 清理 + 启动 Codex 桌面应用 |
| `codex_launcher.bat` | 启动器 bat 包装器，双击即用 |

## 性能数据

| 场景 | 原始 | 上篇方案 | 本篇补充 |
|---|---|---|---|
| 终端列表 | 6000ms | 88ms (68×) | 88ms |
| 终端详情 | 6000ms | 135ms (44×) | 135ms |
| 应用侧边栏 | 6s + 偶尔假死 | 需手动操作 | **零维护** |
| 缓存重建 | 6s × N | 0.4s 自动 | 0.4s 自动 |

## 相关文章

- 📝 [掘金·上篇：Python 冷启动排查与两层缓存方案](https://juejin.cn/post/7644745124401397802)
- 📝 掘金·后续：SQLite WAL 膨胀与自动维护方案
- 📰 [B 站专栏](https://www.bilibili.com/opus/1207468413903962150)

## License

MIT
