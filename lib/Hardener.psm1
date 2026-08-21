#requires -Version 5.1
Set-StrictMode -Off

function Enable-FWPUAProtection {
    try {
        Set-MpPreference -PUAProtection 1 -ErrorAction Stop
        Write-Log '已开启 Windows Defender PUA 防护(拦截流氓/捆绑软件安装)' 'OK'
    } catch {
        Write-Log ("PUA 防护开启失败: {0}" -f $_.Exception.Message) 'WARN'
    }
    try {
        Set-MpPreference -DisableRealtimeMonitoring $false -ErrorAction Stop
        Write-Log '已确认实时防护处于开启状态' 'OK'
    } catch {
        Write-Log '实时防护状态设置失败(可能被组策略管控)' 'WARN'
    }
}

function Start-FWQuickScan {
    Start-Process powershell -ArgumentList '-NoProfile','-WindowStyle','Hidden','-Command','Start-MpScan -ScanType QuickScan' -WindowStyle Hidden
    Write-Log '已在后台启动 Defender 快速扫描' 'OK'
}

Export-ModuleMember -Function '*'
