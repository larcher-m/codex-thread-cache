# read_history.ps1 - 秒出对话记录
param([string]$Arg)

$CACHE = "$env:USERPROFILE\.codex\thread_cache.json"
$DB = "$env:USERPROFILE\.codex\state_5.sqlite"
$BUILD_SCRIPT = "$PSScriptRoot\build_cache.py"

function Build-Cache {
    Write-Host "(rebuilding cache...)" -ForegroundColor DarkGray
    python $BUILD_SCRIPT 2>&1 | Out-Null
}

# Check if cache needs rebuild
$needRebuild = $false
if (-not (Test-Path $CACHE)) {
    $needRebuild = $true
} else {
    try {
        $dbConn = New-Object -ComObject ADODB.Connection 2>$null
        if ($dbConn) {
            # ADO approach not available, use file-based check
        }
    } catch {}
    # Simple check: if cache older than DB modification time
    $cacheTime = (Get-Item $CACHE).LastWriteTime
    $dbTime = (Get-Item $DB).LastWriteTime
    if ($dbTime -gt $cacheTime) {
        $needRebuild = $true
    }
}

if ($Arg -eq "--rebuild") {
    $needRebuild = $true
}

if ($needRebuild) {
    Build-Cache
}

# Read cache
$cache = Get-Content $CACHE -Raw -Encoding UTF8 | ConvertFrom-Json

if ($Arg -and $Arg -ne "--rebuild") {
    # Detail view
    $match = $null
    foreach ($tid in $cache.threads.PSObject.Properties.Name) {
        if ($tid -like "$Arg*") {
            $match = $cache.threads.$tid
            break
        }
    }
    if (-not $match) {
        Write-Host "Not found: $Arg"
        return
    }
    Write-Host "`nTitle: $($match.title)" -ForegroundColor Cyan
    Write-Host "Time: $($match.time) | Model: $($match.model) | $($match.msg_count) msgs"
    Write-Host "CWD: $($match.cwd)`n"
    $i = 1
    foreach ($msg in $match.messages) {
        $content = if ($msg.content.Length -gt 200) { $msg.content.Substring(0,200) } else { $msg.content }
        Write-Host "  [$i] [$($msg.role)] $content"
        $i++
    }
    Write-Host ""
} else {
    # List view
    $updated = [DateTimeOffset]::FromUnixTimeSeconds($cache.updated).LocalDateTime.ToString("MM-dd HH:mm")
    Write-Host "`n$($cache.count) threads (updated $updated)`n" -ForegroundColor Cyan
    foreach ($tid in $cache.threads.PSObject.Properties.Name) {
        $t = $cache.threads.$tid
        $s = if ($t.archived) { "[A]" } else { "[ ]" }
        $title = if ($t.title) { $t.title } else { $t.first }
        $line = "$s $($t.time) | $($t.model.PadRight(20)) | $($t.msg_count.ToString().PadLeft(4))msg | $($tid.Substring(0,8)) | $($title.Substring(0, [Math]::Min(60, $title.Length)))"
        Write-Host $line
        if ($t.prompts) {
            foreach ($p in $t.prompts[0..([Math]::Min(2, $t.prompts.Count-1))]) {
                $pp = if ($p.Length -gt 80) { $p.Substring(0,80) } else { $p }
                Write-Host "     * $pp" -ForegroundColor DarkGray
            }
        }
    }
    Write-Host "`nUsage: rh <id_prefix>`n"
}
