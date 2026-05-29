# codex_cleanup.ps1 - 清理 Codex 数据库，解决启动慢/加载慢
param([switch]$Aggressive)

$CODEX = "$env:USERPROFILE\.codex"

# 检查 Codex 是否在运行
$running = Get-Process -Name "Codex","codex" -ErrorAction SilentlyContinue
if ($running) {
    Write-Host "Codex is still running. Please quit Codex first!" -ForegroundColor Red
    Write-Host "  Right-click the Codex tray icon -> Quit" -ForegroundColor Yellow
    exit 1
}

Write-Host "=== Codex DB Cleanup ===" -ForegroundColor Cyan

# 1. Checkpoint + truncate all WALs
$dbs = @("state_5.sqlite", "logs_2.sqlite", "goals_1.sqlite")
foreach ($db in $dbs) {
    $path = Join-Path $CODEX $db
    if (Test-Path $path) {
        $walSize = if (Test-Path "$path-wal") { (Get-Item "$path-wal").Length } else { 0 }
        
        $script = @"
import sqlite3
conn = sqlite3.connect(r'$path')
conn.execute('PRAGMA wal_checkpoint(TRUNCATE)')
conn.close()
"@
        $script | python 2>&1 | Out-Null
        
        Write-Host "  $db : WAL was $([math]::Round($walSize/1KB,0))KB -> truncated" -ForegroundColor Gray
    }
}

# 2. Clean logs DB - delete TRACE/DEBUG and old entries
$logdb = Join-Path $CODEX "logs_2.sqlite"
if (Test-Path $logdb) {
    $oldSize = [math]::Round((Get-Item $logdb).Length / 1MB, 1)
    $days = if ($Aggressive) { 1 } else { 3 }
    
    $script = @"
import sqlite3, time
conn = sqlite3.connect(r'$logdb')
cutoff = int(time.time()) - $days * 86400
old = conn.execute('DELETE FROM logs WHERE ts < ?', (cutoff,)).rowcount
trace = conn.execute("DELETE FROM logs WHERE level IN ('TRACE','DEBUG')").rowcount
conn.commit()
conn.close()
conn2 = sqlite3.connect(r'$logdb', isolation_level=None)
conn2.execute('VACUUM')
conn2.close()
print(f'{old} old, {trace} TRACE/DEBUG')
"@
    $result = $script | python
    $newSize = [math]::Round((Get-Item $logdb).Length / 1MB, 1)
    Write-Host "  logs_2.sqlite: ${oldSize}MB -> ${newSize}MB (removed $result)" -ForegroundColor Green
}

# 3. Remove stale temp files
Get-Item "$CODEX\.codex-global-state.json.tmp-*" -ErrorAction SilentlyContinue | Remove-Item -Force

# 4. Clear thread cache
$cache = Join-Path $CODEX "thread_cache.json"
if (Test-Path $cache) { Remove-Item $cache -Force }

Write-Host ""
Write-Host "Done! You can now restart Codex." -ForegroundColor Green
Write-Host "Tip: Run 'rh' in terminal for instant chat history." -ForegroundColor Cyan
