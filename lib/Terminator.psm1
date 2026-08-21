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
            foreach ($p in (Get-Process -Name $n -ErrorAction SilentlyContinue)) {
                & taskkill.exe /F /T /PID $p.Id 2>&1 | Out-Null
                Write-Log ("终止进程 {0} (PID {1})" -f $n, $p.Id) 'OK'
                $killed++
            }
        }
        if ($killed -eq 0) { break }
        Start-Sleep -Seconds 2
    }
}

function Remove-FWRogueServices {
    param([string[]]$Names)
    foreach ($n in (@($Names | Where-Object { $_ }) | Select-Object -Unique)) {
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
