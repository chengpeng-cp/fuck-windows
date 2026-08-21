#requires -Version 5.1
Set-StrictMode -Off

function Test-FWSafeRoguePath {
    param([string]$Path, [Parameter(Mandatory)]$SigDb)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $p = $Path.TrimEnd('\')
    if ($p -match '(?i)^[A-Za-z]:\\?$') { return $false }
    if ($p -match '(?i)\\Windows\\|\\System32\\|\\SysWOW64\\') { return $false }
    if ($p.Length -lt 12) { return $false }
    $rx = Get-FWPatternRegex $SigDb.RoguePaths
    return ($rx -and $rx.IsMatch($p))
}

function Remove-FWTasks {
    param([object[]]$Targets)
    foreach ($t in $Targets) {
        try {
            Unregister-ScheduledTask -TaskName $t.Name -TaskPath $t.TaskPath -Confirm:$false -ErrorAction Stop
            Write-Log "删除计划任务: $($t.TaskPath)$($t.Name)" 'OK'
        } catch {
            $xml = Join-Path 'C:\Windows\System32\Tasks' (($t.TaskPath -replace '^\\|\\$', '') + '\' + $t.Name)
            if (Test-Path $xml) { Remove-Item $xml -Force -ErrorAction SilentlyContinue }
            if (-not (Get-ScheduledTask -TaskName $t.Name -TaskPath $t.TaskPath -ErrorAction SilentlyContinue)) {
                Write-Log "删除计划任务(文件方式): $($t.TaskPath)$($t.Name)" 'OK'
            } else {
                Write-Log "计划任务删除失败: $($t.TaskPath)$($t.Name)" 'WARN'
            }
        }
    }
}

function Remove-FWStartupValues {
    param([object[]]$Targets)
    foreach ($t in $Targets) {
        try {
            Remove-ItemProperty -Path $t.KeyPath -Name $t.ValueName -ErrorAction Stop
            Write-Log "删除自启动项: $($t.KeyPath)\$($t.ValueName)" 'OK'
        } catch {
            Write-Log "自启动项删除失败: $($t.KeyPath)\$($t.ValueName)" 'WARN'
        }
    }
}

function Remove-FWStartupShortcuts {
    param([string[]]$Paths)
    foreach ($p in $Paths) {
        if (Test-Path $p) {
            Remove-Item $p -Force -ErrorAction SilentlyContinue
            Write-Log "删除启动快捷方式: $p" 'OK'
        }
    }
}

function Remove-FWUninstallKeys {
    param([string[]]$RegistryPaths)
    foreach ($rk in $RegistryPaths) {
        if (-not (Test-Path $rk)) { continue }
        Backup-FWRegistryKey $rk | Out-Null
        try {
            Remove-Item $rk -Recurse -Force -ErrorAction Stop
            Write-Log "删除卸载注册表项: $rk" 'OK'
        } catch {
            Write-Log "注册表项删除失败: $rk" 'WARN'
        }
    }
}

function Remove-FWDirectories {
    # 返回仍然被锁定(需重启删除)的路径列表
    param([string[]]$Paths, [Parameter(Mandatory)]$SigDb)
    $locked = @()
    foreach ($d in $Paths) {
        if (-not (Test-Path $d)) { continue }
        if (-not (Test-FWSafeRoguePath $d $SigDb)) {
            Write-Log "跳过(安全检查未通过): $d" 'WARN'
            continue
        }
        Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $d)) {
            Write-Log "删除目录: $d" 'OK'
            continue
        }
        # 内核驱动锁定的文件：夺取所有权后重试
        & takeown.exe /F "$d" /R /D Y 2>&1 | Out-Null
        & icacls.exe "$d" /grant "*S-1-5-32-544:(OI)(CI)F" /T /C /Q 2>&1 | Out-Null
        Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path $d)) {
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
    $paths = @($Paths | Where-Object { $_ })
    if ($paths.Count -eq 0) { return $false }
    $files = @()
    foreach ($d in $paths) {
        if (Test-Path $d) {
            # 先删普通子项，剩下的硬骨头逐个标记
            Get-ChildItem $d -Recurse -Force -ErrorAction SilentlyContinue |
                Sort-Object { $_.FullName.Length } -Descending |
                ForEach-Object {
                    Remove-Item $_.FullName -Force -Recurse -ErrorAction SilentlyContinue
                    if (Test-Path $_.FullName) { $files += $_.FullName }
                }
            if (Test-Path $d) { $files += $d }
        }
    }
    $files = @($files | Sort-Object { $_.Length } -Descending | Select-Object -Unique)
    if ($files.Count -eq 0) { return $false }
    $sm = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    $existing = (Get-ItemProperty $sm -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
    $ops = @()
    foreach ($f in $files) { $ops += "\??\$f"; $ops += '' }
    $final = @()
    if ($existing) { $final = @($existing) }
    $final += $ops
    Set-ItemProperty $sm -Name PendingFileRenameOperations -Value ([string[]]$final) -Type MultiString
    Write-Log ("已标记 {0} 个文件/目录重启时自动删除" -f $files.Count) 'OK'
    return $true
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
    $removed = @()
    foreach ($rk in $runKeys) {
        $props = Get-ItemProperty $rk -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($prop in @($props.PSObject.Properties)) {
            if ($prop.Name -match '^PS') { continue }
            if ($rx.IsMatch([string]$prop.Value)) {
                $removed += [PSCustomObject]@{ KeyPath = $rk; Name = $prop.Name; Value = [string]$prop.Value }
            }
        }
    }
    if ($removed.Count -eq 0) { Write-Log '未发现需要禁用的软件自启项'; return }
    Backup-FWRegistryKey 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' | Out-Null
    $restoreLines = foreach ($r in $removed) {
        Remove-ItemProperty -Path $r.KeyPath -Name $r.Name -ErrorAction SilentlyContinue
        Write-Log ("禁用自启动(可恢复): {0} = {1}" -f $r.Name, $r.Value) 'OK'
        "New-ItemProperty -Path '{0}' -Name '{1}' -Value '{2}' -PropertyType String -Force | Out-Null" -f $r.KeyPath, $r.Name, $r.Value.Replace("'", "''")
    }
    $restoreFile = Join-Path (Get-FWBackupDir) 'restore_autostart.ps1'
    $header = "# 恢复被禁用的软件自启动项`n# 由 fuck-windows 于 $(Get-Date) 生成`n"
    ($header + ($restoreLines -join "`n")) | Out-File $restoreFile -Encoding UTF8
}

function New-FWRestoreScript {
    $dir = Get-FWBackupDir
    if (-not $dir) { return }
    $lines = @(
        '# fuck-windows 恢复脚本'
        '# 恢复清理前导出的注册表项（自启动/卸载信息等）'
        '# 注意：被删除的文件和目录无法通过本脚本恢复'
        ('# 生成时间: ' + (Get-Date))
        ''
        '$here = Split-Path -Parent $MyInvocation.MyCommand.Path'
        'Get-ChildItem -Path $here -Filter "reg_*.reg" | ForEach-Object {'
        '    Write-Host "导入 $($_.Name)"'
        '    reg.exe import $_.FullName'
        '}'
    )
    $lines -join "`r`n" | Out-File (Join-Path $dir 'restore.ps1') -Encoding UTF8
}

Export-ModuleMember -Function '*'
