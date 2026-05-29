# rh.ps1 - 秒出对话记录（增强版）
# 用法: rh              -> 列表
#       rh <关键词>      -> 搜索标题
#       rh <id前缀>      -> 查看详情
#       rh --rebuild     -> 强制重建缓存

param([string]$Arg)

$CACHE = "$env:USERPROFILE\.codex\thread_cache.json"
$DB = "$env:USERPROFILE\.codex\state_5.sqlite"
$BUILD = "$PSScriptRoot\build_cache.py"

function Build-Cache {
    Write-Host "(building cache...)" -ForegroundColor DarkGray
    python $BUILD 2>&1 | Out-Null
}

$needRebuild = $false
if (-not (Test-Path $CACHE)) { $needRebuild = $true }
else {
    $cacheTime = (Get-Item $CACHE).LastWriteTime
    $dbTime = (Get-Item $DB).LastWriteTime
    if ($dbTime -gt $cacheTime) { $needRebuild = $true }
}
if ($Arg -eq "--rebuild") { $needRebuild = $true }
if ($needRebuild) { Build-Cache }

$cache = Get-Content $CACHE -Raw -Encoding UTF8 | ConvertFrom-Json

# ---- 搜索模式 ----
if ($Arg -and $Arg -ne "--rebuild") {
    $matches = @()
    foreach ($tid in $cache.threads.PSObject.Properties.Name) {
        $t = $cache.threads.$tid
        $title = if ($t.title) { $t.title } else { $t.first }
        if ($tid -like "$Arg*" -or $title -like "*$Arg*") {
            $matches += @{ tid=$tid; thread=$t }
        }
    }

    if ($matches.Count -eq 0) {
        Write-Host "`nNo match: $Arg`n" -ForegroundColor Red
        return
    }

    if ($matches.Count -eq 1 -and $matches[0].tid -like "$Arg*") {
        # 精确匹配，显示详情
        $t = $matches[0].thread
        $title = if ($t.title) { $t.title } else { $t.first }
        Write-Host "`n$title" -ForegroundColor Cyan
        Write-Host "Time: $($t.time) | Model: $($t.model) | $($t.msg_count) msgs" -ForegroundColor DarkGray
        Write-Host "CWD: $($t.cwd)`n" -ForegroundColor DarkGray
        $i = 1
        foreach ($msg in $t.messages) {
            $roleColor = if ($msg.role -eq "user") { "Yellow" } 
                         elseif ($msg.role -eq "assistant") { "Green" }
                         else { "DarkGray" }
            $prefix = "[$i] [$($msg.role)]"
            $content = $msg.content
            if ($content.Length -gt 300) { $content = $content.Substring(0, 300) + "..." }
            Write-Host "  $prefix " -NoNewline -ForegroundColor $roleColor
            Write-Host $content -ForegroundColor Gray
            $i++
        }
        Write-Host ""
    } else {
        # 多个匹配，显示列表
        $updated = [DateTimeOffset]::FromUnixTimeSeconds($cache.updated).LocalDateTime.ToString("MM-dd HH:mm")
        Write-Host "`n$($matches.Count) matches (updated $updated)`n" -ForegroundColor Cyan
        foreach ($m in $matches) {
            $t = $m.thread
            $title = if ($t.title) { $t.title } else { $t.first }
            $tidShort = $m.tid.Substring(0, 8)
            Write-Host "  $($t.time) | $($t.model.PadRight(20)) | $($t.msg_count)msg | $tidShort | $title" -ForegroundColor Gray
        }
        Write-Host "`nUse: rh <id_prefix>`n"
    }
    return
}

# ---- 列表模式 ----
$updated = [DateTimeOffset]::FromUnixTimeSeconds($cache.updated).LocalDateTime.ToString("MM-dd HH:mm")
Write-Host "`n$($cache.count) threads (updated $updated)`n" -ForegroundColor Cyan
foreach ($tid in $cache.threads.PSObject.Properties.Name) {
    $t = $cache.threads.$tid
    $s = if ($t.archived) { "[A]" } else { "[ ]" }
    $title = if ($t.title) { $t.title } else { $t.first }
    $tidShort = $tid.Substring(0, 8)
    $line = "$s $($t.time) | $($t.model.PadRight(20)) | $($t.msg_count.ToString().PadLeft(4))msg | $tidShort | $($title.Substring(0, [Math]::Min(60, $title.Length)))"
    Write-Host $line
}
Write-Host "`nUsage: rh <keyword|id_prefix>`n"
