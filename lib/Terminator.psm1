#requires -Version 5.1
Set-StrictMode -Off

function Stop-FWRogueProcesses {
    param([string[]]$Names)
    $unique = @($Names | Where-Object { $_ } | Select-Object -Unique)
    if ($unique.Count -eq 0) { return }
    # 两轮强杀：流氓软件守护进程会互相拉起，第一轮杀完等 2 秒再补一轮
    foreach ($round in 1..2) {
        $killed = 0
        foreach ($n in $unique) {
            # 不用 Get-Process -Name，避免进程名中的通配符误伤其他进程
            foreach ($p in @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $n })) {
                & taskkill.exe /F /T /PID $p.Id 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Log ("终止进程 {0} (PID {1})" -f $n, $p.Id) 'OK'
                    $killed++
                } else {
                    Write-Log ("终止进程失败 {0} (PID {1})" -f $n, $p.Id) 'WARN'
                }
            }
        }
        if ($killed -eq 0) { break }
        Start-Sleep -Seconds 2
    }
}

function Remove-FWRogueServices {
    param([string[]]$Names)
    foreach ($n in (@($Names | Where-Object { $_ }) | Select-Object -Unique)) {
        # 先备份服务/驱动注册表项，便于 restore.ps1 恢复注册信息
        Backup-FWRegistryKey "HKLM:\SYSTEM\CurrentControlSet\Services\$n" | Out-Null
        & sc.exe stop $n 2>&1 | Out-Null
        & sc.exe delete $n 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Log "删除服务/驱动: $n" 'OK'
        } else {
            Write-Log "服务删除失败(可能需重启后消失): $n" 'WARN'
        }
    }
}

Export-ModuleMember -Function '*'
