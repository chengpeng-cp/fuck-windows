#requires -Version 5.1
Set-StrictMode -Off

function New-FWFinding {
    param($Category, $Name, $Path, $Reason, $Confidence, $Target, $PID2 = $null)
    return [PSCustomObject][ordered]@{
        Category   = $Category
        Name       = $Name
        Path       = $Path
        Reason     = $Reason
        Confidence = $Confidence
        Target     = $Target
        Pid        = $PID2
    }
}

function Find-FWRogueProcesses {
    param([Parameter(Mandatory)]$SigDb)
    $nameRx = Get-FWPatternRegex $SigDb.RogueProcesses
    $pathRx = Get-FWPatternRegex $SigDb.RoguePaths
    $popRx = [regex]::New('_[a-z]*pop(\.exe)?$', 'IgnoreCase')
    $out = @()
    foreach ($p in (Get-Process -ErrorAction SilentlyContinue)) {
        $path = $null
        try { $path = $p.Path } catch {}
        $hit = $null; $conf = $null
        if ($nameRx -and $nameRx.IsMatch($p.Name)) { $hit = '进程名匹配特征库'; $conf = 'High' }
        elseif ($path -and (Test-FWPathPattern -Text $path -Regex $pathRx)) { $hit = '进程路径匹配特征库'; $conf = 'High' }
        elseif ($popRx.IsMatch($p.Name)) { $hit = '疑似弹窗进程(*_pop 命名)'; $conf = 'Medium' }
        if (-not $hit) { continue }
        if (-not $path) {
            try { $path = (Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction SilentlyContinue).ExecutablePath } catch {}
        }
        $out += New-FWFinding '进程' $p.Name $path $hit $conf $p.Name $p.Id
    }
    return $out
}

function Find-FWRogueServices {
    param([Parameter(Mandatory)]$SigDb)
    $nameRx = Get-FWPatternRegex $SigDb.RogueProcesses
    $pathRx = Get-FWPatternRegex $SigDb.RoguePaths
    $out = @()

    $svchostGroups = $null
    try { $svchostGroups = (Get-Item 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Svchost' -ErrorAction SilentlyContinue).Property } catch {}

    foreach ($svc in (Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) {
        $pn = [string]$svc.PathName
        $hit = $null; $conf = $null
        if ($pn -and (Test-FWPathPattern -Text $pn -Regex $pathRx)) { $hit = '服务路径匹配特征库'; $conf = 'High' }
        elseif ($nameRx -and $nameRx.IsMatch([string]$svc.Name)) { $hit = '服务名匹配特征库'; $conf = 'High' }
        if (-not $hit -and $pn -match '(?i)svchost\.exe\s+-k\s+([A-Za-z0-9_]+)') {
            $grp = $Matches[1]
            if ($svchostGroups -and ($svchostGroups -notcontains $grp)) {
                $hit = "svchost 伪装(未注册服务组 $grp)"; $conf = 'Medium'
            }
        }
        if ($hit) { $out += New-FWFinding '服务' $svc.Name $pn $hit $conf $svc.Name $svc.ProcessId }
    }

    # 内核驱动：Type=1，无论运行与否都检查注册表
    foreach ($key in (Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction SilentlyContinue)) {
        $p = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if ($p.Type -ne 1 -or -not $p.ImagePath) { continue }
        $img = [string]$p.ImagePath
        if (Test-FWPathPattern -Text $img -Regex $pathRx) { $hit = '流氓内核驱动(特征库匹配)'; $conf = 'High' }
        elseif ($img -match '(?i)\\Users\\|\\ProgramData\\' -and $img -notmatch '(?i)\\ProgramData\\Microsoft\\') { $hit = '内核驱动位于用户可写目录'; $conf = 'High' }
        elseif ($img -match '(?i)\\\?\?\\[A-Za-z]:\\(?!Windows\\)') { $hit = '内核驱动位于系统目录外'; $conf = 'Medium' }
        else { continue }
        $out += New-FWFinding '驱动' $key.PSChildName $img $hit $conf $key.PSChildName
    }
    return $out
}

function Find-FWRogueTasks {
    param([Parameter(Mandatory)]$SigDb)
    $pathRx = Get-FWPatternRegex $SigDb.RoguePaths
    $out = @()
    foreach ($t in (Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        foreach ($a in @($t.Actions)) {
            if (-not $a.Execute) { continue }
            $cmd = ('{0} {1}' -f $a.Execute, $a.Arguments)
            $exe = [string]$a.Execute
            $hit = $null; $conf = $null
            if (Test-FWPathPattern -Text $cmd -Regex $pathRx) { $hit = '任务动作匹配特征库'; $conf = 'High' }
            elseif ($t.TaskPath -like '\Microsoft\*' -and $exe -match '(?i)\\Users\\|\\ProgramData\\' -and $exe -notmatch '(?i)\\Microsoft\\') { $hit = '任务伪装在 \Microsoft 目录且指向用户可写位置'; $conf = 'High' }
            elseif ($exe -match '(?i)\\Users\\[^\\]+\\AppData\\Local\\Temp\\') { $hit = '任务从 Temp 目录执行程序'; $conf = 'High' }
            elseif ($exe -match '(?i)\\Users\\') { $hit = '任务从用户目录执行(需人工判断)'; $conf = 'Medium' }
            else { continue }
            $out += New-FWFinding '计划任务' ($t.TaskPath + $t.TaskName) $cmd $hit $conf @{ Name = $t.TaskName; TaskPath = $t.TaskPath }
            break
        }
    }
    return $out
}

function Find-FWRogueUninstall {
    param([Parameter(Mandatory)]$SigDb)
    $dnRx = Get-FWPatternRegex $SigDb.RogueDisplayNames
    $pubRx = Get-FWPatternRegex $SigDb.RoguePublishers
    $suspDnRx = Get-FWPatternRegex $SigDb.SuspiciousDisplayNames
    $roots = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $out = @()
    foreach ($r in $roots) {
        foreach ($k in (Get-ChildItem -LiteralPath $r -ErrorAction SilentlyContinue)) {
            $p = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
            if (-not $p.DisplayName) { continue }
            $hit = $null; $conf = $null
            if ($pubRx -and $p.Publisher -and $pubRx.IsMatch([string]$p.Publisher)) { $hit = "发布者匹配特征库($($p.Publisher))"; $conf = 'High' }
            elseif ($dnRx -and $dnRx.IsMatch([string]$p.DisplayName)) { $hit = '软件名匹配特征库'; $conf = 'High' }
            elseif ($suspDnRx -and $suspDnRx.IsMatch([string]$p.DisplayName)) { $hit = '匹配常见捆绑软件清单'; $conf = 'Medium' }
            elseif ($p.InstallLocation -and ([string]$p.InstallLocation) -match '(?i)\\Users\\[^\\]+\\AppData\\Roaming\\') { $hit = '安装于 AppData\Roaming(流氓软件典型位置)'; $conf = 'Medium' }
            else { continue }
            $out += New-FWFinding '已安装软件' $p.DisplayName ([string]$p.InstallLocation) $hit $conf $k.PSPath
        }
    }
    return $out
}

function Find-FWRogueStartup {
    param([Parameter(Mandatory)]$SigDb)
    $pathRx = Get-FWPatternRegex $SigDb.RoguePaths
    $runKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )
    $out = @()
    $psProps = @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')
    foreach ($rk in $runKeys) {
        $props = Get-ItemProperty -LiteralPath $rk -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($prop in @($props.PSObject.Properties)) {
            if ($psProps -contains $prop.Name) { continue }
            $v = [string]$prop.Value
            $hit = $null; $conf = $null
            if ($pathRx -and $pathRx.IsMatch($v)) { $hit = '自启动项指向流氓路径'; $conf = 'High' }
            elseif ($v -match '(?i)\\AppData\\Local\\Temp\\') { $hit = '自启动项从 Temp 执行'; $conf = 'High' }
            else { continue }
            $out += New-FWFinding '自启动' $prop.Name $v $hit $conf @{ KeyPath = $rk; ValueName = $prop.Name }
        }
    }

    $sh = New-Object -ComObject WScript.Shell
    $startupDirs = @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'),
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\StartUp')
    )
    foreach ($dir in $startupDirs) {
        foreach ($lnk in (Get-ChildItem -LiteralPath $dir -Filter *.lnk -ErrorAction SilentlyContinue)) {
            try {
                $l = $sh.CreateShortcut($lnk.FullName)
                $t = "$($l.TargetPath) $($l.Arguments)"
                if ((Test-FWPathPattern -Text $t -Regex $pathRx) -or
                    (Test-FWPathPattern -Text $lnk.FullName -Regex $pathRx)) {
                    $out += New-FWFinding '启动文件夹' $lnk.Name $t '启动快捷方式指向流氓目标' 'High' $lnk.FullName
                }
            } catch {}
        }
    }
    return $out
}

function Find-FWRogueDirectories {
    param([Parameter(Mandatory)]$SigDb)
    $out = @()
    $placeholders = @{
        '{Roaming}'        = $env:APPDATA
        '{Local}'          = $env:LOCALAPPDATA
        '{ProgramFilesX86}' = ${env:ProgramFiles(x86)}
        '{ProgramData}'    = $env:ProgramData
    }
    foreach ($d in $SigDb.RogueDirectories) {
        if ([string]::IsNullOrWhiteSpace($d)) { continue }
        $resolved = [string]$d
        foreach ($k in $placeholders.Keys) {
            if ($null -ne $placeholders[$k]) { $resolved = $resolved.Replace($k, [string]$placeholders[$k]) }
        }
        if (Test-Path -LiteralPath $resolved -PathType Container) {
            $out += New-FWFinding '目录' $resolved $resolved '特征库已知流氓目录' 'High' $resolved
        }
    }
    return $out
}

function Find-FWTempResidue {
    param([Parameter(Mandatory)]$SigDb)
    $tempRx = Get-FWExactPatternRegex -Patterns $SigDb.TempResiduePatterns
    $out = @()
    if (-not $tempRx) { return $out }
    foreach ($d in (Get-ChildItem -LiteralPath $env:TEMP -Directory -ErrorAction SilentlyContinue)) {
        if (Test-FWExactPattern -Value $d.Name -Regex $tempRx) {
            $out += New-FWFinding 'Temp残留' $d.Name $d.FullName 'Temp 目录中的流氓残留' 'High' $d.FullName
        }
    }
    return $out
}

function Get-FWScanResult {
    param([Parameter(Mandatory)]$SigDb)
    $all = @()
    $all += Find-FWRogueProcesses $SigDb
    $all += Find-FWRogueServices $SigDb
    $all += Find-FWRogueTasks $SigDb
    $all += Find-FWRogueUninstall $SigDb
    $all += Find-FWRogueStartup $SigDb
    $all += Find-FWRogueDirectories $SigDb
    $all += Find-FWTempResidue $SigDb
    $seen = @{}
    $dedup = @()
    foreach ($f in $all) {
        $key = "$($f.Category)|$($f.Name)|$($f.Path)"
        if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; $dedup += $f }
    }
    return $dedup
}

Export-ModuleMember -Function '*'
