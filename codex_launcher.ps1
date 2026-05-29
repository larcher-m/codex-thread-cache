# codex_launcher.ps1 - 一键清理并启动 Codex 桌面应用
$CODEX = "$env:USERPROFILE\.codex"

$running = Get-Process -Name "Codex","codex" -ErrorAction SilentlyContinue
if ($running) {
    exit 0
}

# 快速 WAL checkpoint
$dbs = @("state_5.sqlite", "logs_2.sqlite", "goals_1.sqlite")
foreach ($db in $dbs) {
    $path = Join-Path $CODEX $db
    if (Test-Path $path) {
        $script = @"
import sqlite3
conn = sqlite3.connect(r'$path')
conn.execute('PRAGMA wal_checkpoint(TRUNCATE)')
conn.close()
"@
        $script | python 2>&1 | Out-Null
    }
}

# 日志 > 30MB 时清理 TRACE/DEBUG
$logdb = Join-Path $CODEX "logs_2.sqlite"
if ((Test-Path $logdb) -and ((Get-Item $logdb).Length -gt 30MB)) {
    $script = @"
import sqlite3
conn = sqlite3.connect(r'$logdb')
conn.execute("DELETE FROM logs WHERE level IN ('TRACE','DEBUG')")
conn.commit()
conn.close()
conn2 = sqlite3.connect(r'$logdb', isolation_level=None)
conn2.execute('VACUUM')
conn2.close()
"@
    $script | python 2>&1 | Out-Null
}

# 清理临时文件
Get-Item "$CODEX\.codex-global-state.json.tmp-*" -ErrorAction SilentlyContinue | Remove-Item -Force

# 启动 Codex 桌面应用 (Windows Store)
Start-Process "shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App"
