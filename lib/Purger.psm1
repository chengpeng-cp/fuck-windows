#requires -Version 5.1
Set-StrictMode -Off

function Test-FWSafeRoguePath {
    param([string]$Path, [Parameter(Mandatory)]$SigDb)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $p = $Path.Trim().Trim('"').Trim()
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    # 只接受本地盘符绝对路径，拒绝 UNC、设备路径、相对路径
    if ($p -notmatch '^[A-Za-z]:\\') { return $false }
    # 拒绝路径穿越，防止被篡改的 InstallLocation 把删除目标指向其他目录
    if ($p -match '(^|[\\/])\.\.([\\/]|$)') { return $false }
    # 拒绝 NTFS 数据流等盘符后出现的冒号
    if ($p.IndexOf(':', 2) -ge 0) { return $false }
    $p = $p.TrimEnd('\')
    if ($p -match '(?i)^[A-Za-z]:\\?$') { return $false }
    if ($p -match '(?i)^[A-Za-z]:\\Windows(\\|$)') { return $false }
    if ($p -match '(?i)\\Windows\\|\\System32\\|\\SysWOW64\\') { return $false }
    if ($p.Length -lt 12) { return $false }
    $rx = Get-FWPatternRegex $SigDb.RoguePaths
    if ($rx -and ($rx.IsMatch($p) -or $rx.IsMatch($p + '\'))) { return $true }
    # Temp 残留：只允许 Temp 目录的直接子目录，且目录名命中特征库
    $tempRoot = $env:TEMP
    if ($tempRoot) {
        $tempRoot = [System.IO.Path]::GetFullPath($tempRoot).TrimEnd('\')
        $parent = [System.IO.Path]::GetDirectoryName($p)
        $tempRx = Get-FWPatternRegex $SigDb.TempResiduePatterns
        if ($tempRx -and $parent -and $parent.TrimEnd('\') -eq $tempRoot -and $tempRx.IsMatch([System.IO.Path]::GetFileName($p))) {
            return $true
        }
    }
    return $false
}

function Remove-FWTasks {
    param([object[]]$Targets)
    $systemRoot = $env:SystemRoot
    if (-not $systemRoot) { $systemRoot = 'C:\Windows' }
    $tasksRoot = (Join-Path $systemRoot 'System32\Tasks').TrimEnd('\')
    foreach ($t in $Targets) {
        if (-not $t -or [string]::IsNullOrWhiteSpace([string]$t.Name)) { continue }
        try {
            Unregister-ScheduledTask -TaskName $t.Name -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop
            Write-Log "删除计划任务: $($t.TaskPath)$($t.Name)" 'OK'
            continue
        } catch {}
        # 回退：直接删除任务的 XML 文件
        try {
            $rel = ((('' + $t.TaskPath).Trim('\')) + '\' + $t.Name).TrimStart('\')
            $xml = [System.IO.Path]::GetFullPath((Join-Path $tasksRoot $rel))
            if (-not $xml.StartsWith($tasksRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                Write-Log "计划任务路径异常，已跳过: $($t.TaskPath)$($t.Name)" 'WARN'
                continue
            }
            if (Test-Path -LiteralPath $xml) {
                Remove-Item -LiteralPath $xml -Force -ErrorAction SilentlyContinue
            }
            $stillThere = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -eq $t.Name -and $_.TaskPath -eq $t.TaskPath })
            if ($stillThere.Count -eq 0) {
                Write-Log "删除计划任务(文件方式): $($t.TaskPath)$($t.Name)" 'OK'
            } else {
                Write-Log "计划任务删除失败: $($t.TaskPath)$($t.Name)" 'WARN'
            }
        } catch {
            Write-Log ("计划任务删除异常: {0} - {1}" -f ($t.TaskPath + $t.Name), $_.Exception.Message) 'WARN'
        }
    }
}

function Remove-FWStartupValues {
    param([object[]]$Targets)
    foreach ($t in $Targets) {
        try {
            # -Name 支持通配符，注册表值名可能包含 * ? [ ]，这里按字面量转义
            $valueName = [System.Management.Automation.WildcardPattern]::Escape([string]$t.ValueName)
            Remove-ItemProperty -Path $t.KeyPath -Name $valueName -ErrorAction Stop
            Write-Log "删除自启动项: $($t.KeyPath)\$($t.ValueName)" 'OK'
        } catch {
            Write-Log "自启动项删除失败: $($t.KeyPath)\$($t.ValueName)" 'WARN'
        }
    }
}

function Remove-FWStartupShortcuts {
    param([string[]]$Paths)
    foreach ($p in $Paths) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        $target = ([string]$p).Trim().Trim('"').Trim()
        if (-not (Test-Path -LiteralPath $target)) { continue }
        Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $target)) {
            Write-Log "删除启动快捷方式: $target" 'OK'
        } else {
            Write-Log "启动快捷方式删除失败: $target" 'WARN'
        }
    }
}

function Remove-FWUninstallKeys {
    param([string[]]$RegistryPaths)
    foreach ($rk in $RegistryPaths) {
        if ([string]::IsNullOrWhiteSpace($rk)) { continue }
        if (-not (Test-Path -LiteralPath $rk)) { continue }
        Backup-FWRegistryKey $rk | Out-Null
        try {
            Remove-Item -LiteralPath $rk -Recurse -Force -ErrorAction Stop
            Write-Log "删除卸载注册表项: $rk" 'OK'
        } catch {
            Write-Log "注册表项删除失败: $rk" 'WARN'
        }
    }
}

function Test-FWTreeHasReparsePoint {
    # 用 .NET 逐层枚举，避免 Get-ChildItem -Recurse 跟随目录联接进入目标目录
    param([Parameter(Mandatory)][string]$Path)
    $stack = New-Object System.Collections.Stack
    $stack.Push($Path)
    while ($stack.Count -gt 0) {
        $current = [string]$stack.Pop()
        try {
            $di = New-Object System.IO.DirectoryInfo -ArgumentList $current
            foreach ($entry in $di.GetFileSystemInfos()) {
                if (($entry.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
                if ($entry -is [System.IO.DirectoryInfo]) { $stack.Push($entry.FullName) }
            }
        } catch {
            # 无法枚举时按“不安全”处理，宁可不删
            return $true
        }
    }
    return $false
}

function Remove-FWDirectories {
    # 返回仍然被锁定(需重启删除)的路径列表
    param([string[]]$Paths, [Parameter(Mandatory)]$SigDb)
    $locked = @()
    foreach ($raw in $Paths) {
        if ([string]::IsNullOrWhiteSpace($raw)) { continue }
        $d = ([string]$raw).Trim().Trim('"').Trim()
        if ([string]::IsNullOrWhiteSpace($d)) { continue }
        if (-not (Test-Path -LiteralPath $d -PathType Container)) { continue }
        if (-not (Test-FWSafeRoguePath $d $SigDb)) {
            Write-Log "跳过(安全检查未通过): $d" 'WARN'
            continue
        }
        # 不跟随符号链接/目录联接，避免把目标目录误删
        try {
            $item = Get-Item -LiteralPath $d -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq [System.IO.FileAttributes]::ReparsePoint) {
                Write-Log "跳过(目录是符号链接/联接点): $d" 'WARN'
                continue
            }
        } catch {
            Write-Log "跳过(无法读取目录属性): $d" 'WARN'
            continue
        }
        if (Test-FWTreeHasReparsePoint $d) {
            Write-Log "跳过(目录内包含符号链接/联接点，避免误删目标): $d" 'WARN'
            continue
        }
        Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $d)) {
            Write-Log "删除目录: $d" 'OK'
            continue
        }
        # 内核驱动锁定的文件：夺取所有权后重试
        & takeown.exe /F "$d" /R /D Y 2>&1 | Out-Null
        & icacls.exe "$d" /grant "*S-1-5-32-544:(OI)(CI)F" /T /C /Q 2>&1 | Out-Null
        Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $d)) {
            Write-Log "删除目录(夺取所有权后): $d" 'OK'
        } else {
            Write-Log "目录被锁定，已标记重启删除: $d" 'WARN'
            $locked += $d
        }
    }
    return $locked
}

function Add-FWRebootDelete {
    param([string[]]$Paths)
    $paths = @($Paths | Where-Object { $_ } | Select-Object -Unique)
    if ($paths.Count -eq 0) { return $false }
    $files = @()
    foreach ($d in $paths) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        if (Test-FWTreeHasReparsePoint $d) {
            Write-Log "跳过重启删除(目录内包含符号链接/联接点): $d" 'WARN'
            continue
        }
        # 先删普通子项，剩下的硬骨头逐个标记
        $children = @(Get-ChildItem -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue)
        foreach ($child in ($children | Sort-Object { $_.FullName.Length } -Descending)) {
            Remove-Item -LiteralPath $child.FullName -Force -Recurse -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $child.FullName) { $files += $child.FullName }
        }
        if (Test-Path -LiteralPath $d) { $files += $d }
    }
    $files = @($files | Select-Object -Unique)
    if ($files.Count -eq 0) { return $false }
    $sm = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    $existing = (Get-ItemProperty -LiteralPath $sm -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
    $ops = @()
    foreach ($f in $files) { $ops += "\??\$f"; $ops += '' }
    $final = @()
    if ($null -ne $existing) { $final = @($existing) }
    $final += $ops
    $final = [string[]]$final
    try {
        # 直接用 .NET 写入 REG_MULTI_SZ，避免不同 PowerShell 版本的动态参数差异
        $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager', $true)
        if (-not $key) { throw '无法打开 Session Manager 注册表键' }
        try {
            $key.SetValue('PendingFileRenameOperations', $final, [Microsoft.Win32.RegistryValueKind]::MultiString)
        } finally {
            $key.Close()
        }
        Write-Log ("已标记 {0} 个文件/目录重启时自动删除" -f $files.Count) 'OK'
        return $true
    } catch {
        Write-Log ("写入重启删除队列失败: {0}" -f $_.Exception.Message) 'ERR'
        return $false
    }
}

function Disable-FWUserAutostart {
    param([Parameter(Mandatory)]$SigDb)
    $rx = Get-FWPatternRegex $SigDb.UserAutostartPatterns
    if (-not $rx) { return }
    $runKeys = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )
    $psProps = @('PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider')
    $removed = @()
    foreach ($rk in $runKeys) {
        $props = Get-ItemProperty -LiteralPath $rk -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($prop in @($props.PSObject.Properties)) {
            if ($psProps -contains $prop.Name) { continue }
            if ($rx.IsMatch([string]$prop.Value)) {
                $removed += [PSCustomObject]@{ KeyPath = $rk; Name = $prop.Name; Value = [string]$prop.Value }
            }
        }
    }
    if ($removed.Count -eq 0) { Write-Log '未发现需要禁用的软件自启项'; return }
    foreach ($kp in @($removed | ForEach-Object { $_.KeyPath } | Select-Object -Unique)) {
        Backup-FWRegistryKey $kp | Out-Null
    }
    $restoreLines = foreach ($r in $removed) {
        $valueName = [System.Management.Automation.WildcardPattern]::Escape([string]$r.Name)
        Remove-ItemProperty -Path $r.KeyPath -Name $valueName -ErrorAction SilentlyContinue
        $stillThere = $null -ne (Get-ItemProperty -LiteralPath $r.KeyPath -Name $valueName -ErrorAction SilentlyContinue)
        if ($stillThere) {
            Write-Log ("禁用自启动失败: {0} = {1}" -f $r.Name, $r.Value) 'WARN'
        } else {
            Write-Log ("禁用自启动(可恢复): {0} = {1}" -f $r.Name, $r.Value) 'OK'
        }
        $safeName = ([string]$r.Name).Replace("'", "''")
        $safeValue = ([string]$r.Value).Replace("'", "''")
        "New-ItemProperty -Path '{0}' -Name '{1}' -Value '{2}' -PropertyType String -Force | Out-Null" -f $r.KeyPath, $safeName, $safeValue
    }
    $dir = Get-FWBackupDir
    if (-not $dir) {
        Write-Log '备份目录不可用，已跳过生成自启动恢复脚本' 'WARN'
        return
    }
    $restoreFile = Join-Path $dir 'restore_autostart.ps1'
    $header = "# 恢复被禁用的软件自启动项`n# 由 fuck-windows 于 $(Get-Date) 生成`n# 请以管理员身份运行本脚本（恢复 HKLM 自启动项需要管理员权限）`n"
    Set-Content -LiteralPath $restoreFile -Value ($header + ($restoreLines -join "`n")) -Encoding UTF8
}

function New-FWRestoreScript {
    $dir = Get-FWBackupDir
    if (-not $dir) { return }
    $lines = @(
        '# fuck-windows 恢复脚本'
        '# 恢复清理前导出的注册表项（自启动、卸载信息、服务/驱动注册等）'
        '# 注意：被删除的文件和目录无法通过本脚本恢复'
        '# 请以管理员身份运行本脚本（导入 HKLM 注册表项需要管理员权限）'
        ('# 生成时间: ' + (Get-Date))
        ''
        '$here = Split-Path -Parent $MyInvocation.MyCommand.Path'
        'Get-ChildItem -LiteralPath $here -Filter "reg_*.reg" | ForEach-Object {'
        '    Write-Host "导入 $($_.Name)"'
        '    reg.exe import $_.FullName'
        '}'
    )
    Set-Content -LiteralPath (Join-Path $dir 'restore.ps1') -Value ($lines -join "`r`n") -Encoding UTF8
}

Export-ModuleMember -Function '*'
