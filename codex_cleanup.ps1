# codex_cleanup.ps1 - 清理 Codex 数据库
param([switch]$Aggressive)

$CODEX = "$env:USERPROFILE\.codex"
$running = Get-Process -Name "Codex","codex" -ErrorAction SilentlyContinue

# === WAL checkpoint（运行中也能做） ===
$dbs = @("state_5.sqlite", "logs_2.sqlite", "goals_1.sqlite", "memories_1.sqlite")
foreach ($db in $dbs) {
    $path = Join-Path $CODEX $db
    $walPath = "$path-wal"
    if ((Test-Path $path) -and (Test-Path $walPath)) {
        $walKB = [math]::Round((Get-Item $walPath).Length / 1KB, 0)
        if ($walKB -gt 50) {
            python -c "import sqlite3; c=sqlite3.connect(r'$path'); c.execute('PRAGMA wal_checkpoint(TRUNCATE)'); c.close()" 2>&1 | Out-Null
        }
    }
}

# === 深度清理（仅 Codex 未运行时） ===
if (-not $running) {
    $logdb = Join-Path $CODEX "logs_2.sqlite"
    if (Test-Path $logdb) {
        python -c "import sqlite3; c=sqlite3.connect(r'$logdb', isolation_level=None); c.execute(\"DELETE FROM logs WHERE level IN ('TRACE','DEBUG')\"); c.execute('VACUUM'); c.close()" 2>&1 | Out-Null
    }
    Get-Item "$CODEX\.codex-global-state.json.tmp-*" -ErrorAction SilentlyContinue | Remove-Item -Force
}
