#requires -Version 5.1
<#
.SYNOPSIS
  fuck-windows - Windows 流氓软件 / 弹窗广告 一键清理工具

.DESCRIPTION
  扫描并清除流氓软件在系统中的全部持久化入口：
  进程 / 服务 / 内核驱动 / 计划任务 / 自启动项 / 卸载注册表 / 安装目录 / Temp 残留。
  清理前自动备份注册表到 backup 目录，可运行 restore.ps1 恢复。

.PARAMETER ScanOnly
  只扫描并输出报告，不做任何系统更改。

.PARAMETER Auto
  无人值守模式，跳过确认提示（仍只清理 High 置信项）。

.PARAMETER Aggressive
  连同 Medium 置信项（启发式命中）一起清理，请确认报告内容后使用。

.PARAMETER TameAutostart
  顺手禁用常见国产软件的开机自启（腾讯视频/百度网盘/夸克网盘等，可恢复，不卸载）。

.PARAMETER Harden
  开启 Windows Defender PUA 防护并触发快速扫描。

.EXAMPLE
  .\fuck-windows.ps1 -ScanOnly
  .\fuck-windows.ps1
  .\fuck-windows.ps1 -Auto -Aggressive -TameAutostart -Harden
#>
param(
    [switch]$ScanOnly,
    [switch]$Auto,
    [switch]$Aggressive,
    [switch]$TameAutostart,
    [switch]$Harden
)

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$Root = $PSScriptRoot
if (-not $Root) { $Root = Split-Path -Parent $MyInvocation.MyCommand.Path }

foreach ($m in 'Common', 'Scanner', 'Terminator', 'Purger', 'Hardener') {
    $modulePath = Join-Path $Root "lib\$m.psm1"
    if (-not (Test-Path -LiteralPath $modulePath)) {
        Write-Host ("缺少模块文件: {0}" -f $modulePath) -ForegroundColor Red
        exit 1
    }
    try {
        Import-Module $modulePath -Force -DisableNameChecking -ErrorAction Stop
    } catch {
        Write-Host ("导入模块失败: {0} - {1}" -f $modulePath, $_.Exception.Message) -ForegroundColor Red
        exit 1
    }
}

# ---------- 自提权（ScanOnly 纯读操作可免提权运行） ----------
if (-not (Test-FWAdmin)) {
    if ($ScanOnly) {
        Write-Host '提示: 当前非管理员权限，部分位置可能读取不全；清理操作仍需提权。' -ForegroundColor DarkYellow
    } else {
        Write-Host '需要管理员权限，正在请求 UAC 提权...' -ForegroundColor Yellow
        try {
            Invoke-FWSelfElevation -Params $PSBoundParameters -ScriptPath $PSCommandPath -KeepWindow:(-not $Auto)
        } catch {
            Write-Host ("提权失败或被取消: {0}" -f $_.Exception.Message) -ForegroundColor Red
            exit 1
        }
        exit
    }
}

Initialize-FWEnvironment $Root
try {
    $db = Import-PowerShellDataFile (Join-Path $Root 'signatures.psd1')
} catch {
    Write-Host ("读取特征库失败: {0}" -f $_.Exception.Message) -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host '  ███████╗██╗   ██╗██╗  ██╗    ██████╗ ██╗███████╗' -ForegroundColor Cyan
Write-Host '  ██╔════╝╚██╗ ██╔╝██║  ██║    ██╔══██╗██║██╔════╝' -ForegroundColor Cyan
Write-Host '  █████╗   ╚████╔╝ ███████║    ██║  ██║██║███████╗' -ForegroundColor Cyan
Write-Host '  ██╔══╝    ╚██╔╝ ██╔══██║    ██║  ██║██║╚════██║' -ForegroundColor Cyan
Write-Host '  ██║        ██║  ██║  ██║    ██████╔╝██║███████║' -ForegroundColor Cyan
Write-Host '  ╚═╝        ╚═╝  ╚═╝  ╚═╝    ╚═════╝ ╚═╝╚══════╝' -ForegroundColor Cyan
Write-Host '  Windows 流氓软件 / 弹窗广告 清理工具 v1.0' -ForegroundColor Cyan
Write-Host ''

# ---------- 扫描 ----------
Write-Log '========== 第 1 步：全面扫描 ==========' 'STEP'
$findings = @(Get-FWScanResult -SigDb $db)
$high = @($findings | Where-Object Confidence -eq 'High')
$medium = @($findings | Where-Object Confidence -eq 'Medium')

if ($findings.Count -gt 0) {
    Write-Host ''
    Write-Host '================ 扫描报告 ================' -ForegroundColor Yellow
    $findings |
        Sort-Object @{E = { if ($_.Confidence -eq 'High') { 0 } else { 1 } }}, Category, Name |
        Format-Table @{L = '类别'; E = { $_.Category }},
                    @{L = '名称'; E = { if ($_.Name.Length -gt 50) { $_.Name.Substring(0, 50) + '...' } else { $_.Name } }},
                    @{L = '置信'; E = { $_.Confidence }},
                    @{L = '原因'; E = { if ($_.Reason.Length -gt 40) { $_.Reason.Substring(0, 40) + '...' } else { $_.Reason } }} `
        -AutoSize | Out-String -Width 200 | Write-Host
}
Write-Log ("扫描完成: High {0} 项, Medium {1} 项" -f $high.Count, $medium.Count) 'INFO'
$logAll = $findings | ForEach-Object { "[{0}] {1} | {2} | {3} | {4}" -f $_.Confidence, $_.Category, $_.Name, $_.Path, $_.Reason }
$logPath = Get-FWLogPath
if ($logPath) { $logAll | Add-Content -LiteralPath $logPath -Encoding UTF8 }

if ($findings.Count -eq 0) {
    Write-Log '未发现流氓软件，系统很干净！' 'OK'
    if (-not $Auto) { Read-Host '按回车退出' | Out-Null }
    exit 0
}

if ($ScanOnly) {
    Write-Log 'ScanOnly 模式，未做任何更改。去掉 -ScanOnly 参数执行清理。' 'INFO'
    if (-not $Auto) { Read-Host '按回车退出' | Out-Null }
    exit 0
}

# ---------- 确认 ----------
$cleanSet = @()
if ($Auto) {
    $cleanSet = @($high)
    if ($Aggressive) { $cleanSet += $medium }
    Write-Log ("Auto 模式: 将清理 {0} 项{1}" -f $cleanSet.Count, $(if ($Aggressive) { '(含可疑项)' } else { '' }))
} else {
    Write-Host ''
    Write-Host "确认清理 $($high.Count) 项高危(High)条目?" -ForegroundColor Yellow
    Write-Host '  Y = 清理高危项    A = 高危+可疑项全部清理    N = 取消' -ForegroundColor Yellow
    $ans = Read-Host '请选择 (Y/A/N)'
    switch (([string]$ans).Trim().ToUpper()) {
        'Y' { $cleanSet = @($high) }
        'A' { $cleanSet = @($high) + @($medium) }
        default {
            Write-Log '用户取消，未做任何更改。'
            Read-Host '按回车退出' | Out-Null
            exit 0
        }
    }
}
if ($cleanSet.Count -eq 0) {
    Write-Log '没有需要清理的条目。' 'INFO'
    if (-not $Auto) { Read-Host '按回车退出' | Out-Null }
    exit 0
}

Write-Log ("本次将清理 {0} 项。注册表将备份到 {1}" -f $cleanSet.Count, (Get-FWBackupDir)) 'INFO'
New-FWRestoreScript

# ---------- 清理 ----------
Write-Log '========== 第 2 步：停止服务与内核驱动 ==========' 'STEP'
$svcTargets = @($cleanSet | Where-Object { $_.Category -in '服务', '驱动' } | ForEach-Object { $_.Target })
Remove-FWRogueServices $svcTargets

Write-Log '========== 第 3 步：终止进程(两轮防复活) ==========' 'STEP'
$procTargets = @($cleanSet | Where-Object Category -eq '进程' | ForEach-Object { $_.Target })
Stop-FWRogueProcesses $procTargets

Write-Log '========== 第 4 步：删除计划任务 ==========' 'STEP'
$taskTargets = @($cleanSet | Where-Object Category -eq '计划任务' | ForEach-Object { $_.Target })
Remove-FWTasks $taskTargets

Write-Log '========== 第 5 步：删除自启动项 ==========' 'STEP'
$startupTargets = @($cleanSet | Where-Object { $_.Category -eq '自启动' } | ForEach-Object { $_.Target })
foreach ($kp in @($startupTargets | ForEach-Object { $_.KeyPath } | Select-Object -Unique)) {
    Backup-FWRegistryKey $kp | Out-Null
}
Remove-FWStartupValues $startupTargets
Remove-FWStartupShortcuts @($cleanSet | Where-Object Category -eq '启动文件夹' | ForEach-Object { $_.Target })

Write-Log '========== 第 6 步：清除卸载注册表 ==========' 'STEP'
$uninstTargets = @($cleanSet | Where-Object Category -eq '已安装软件' | ForEach-Object { $_.Target })
Remove-FWUninstallKeys $uninstTargets

Write-Log '========== 第 7 步：删除安装目录 ==========' 'STEP'
$dirTargets = @($cleanSet | Where-Object { $_.Category -in '目录', 'Temp残留' } | ForEach-Object { $_.Target })
# 已安装软件条目带 InstallLocation 且通过安全检查的也一并删除
$dirTargets += @($cleanSet | Where-Object { $_.Category -eq '已安装软件' -and $_.Path } | ForEach-Object { $_.Path })
$locked = Remove-FWDirectories $dirTargets $db

Write-Log '========== 第 8 步：处理锁定文件 ==========' 'STEP'
$rebootNeeded = Add-FWRebootDelete $locked

# 终结补刀：目录删除后再杀一轮可能复活的进程
Stop-FWRogueProcesses $procTargets

# ---------- 可选动作 ----------
if ($TameAutostart) {
    Write-Log '========== 附加：禁用国产软件开机自启 ==========' 'STEP'
    Disable-FWUserAutostart $db
}
if ($Harden) {
    Write-Log '========== 附加：系统加固 ==========' 'STEP'
    Enable-FWPUAProtection
    Start-FWQuickScan
}

# ---------- 验证 ----------
Write-Log '========== 第 9 步：清理后验证 ==========' 'STEP'
$remain = @(Get-FWScanResult -SigDb $db | Where-Object Confidence -eq 'High')
if ($rebootNeeded) {
    $lockedSet = @($locked)
    $remain = @($remain | Where-Object { $lockedSet -notcontains $_.Name -and $lockedSet -notcontains $_.Path })
}
Write-Log ("验证结果: 残留高危项 {0} 个{1}" -f $remain.Count, $(if ($rebootNeeded) { '(锁定文件将在重启后自动删除)' } else { '' })) $(if ($remain.Count -eq 0) { 'OK' } else { 'WARN' })
foreach ($r in $remain) { Write-Log ("  残留: [{0}] {1} ({2})" -f $r.Category, $r.Name, $r.Reason) 'WARN' }

Write-Host ''
Write-Host '================ 清理完成 ================' -ForegroundColor Green
$logPath = Get-FWLogPath
Write-Log ("日志: {0}" -f $(if ($logPath) { $logPath } else { '未启用' })) 'INFO'
$backupDir = Get-FWBackupDir
if ($backupDir) {
    Write-Log ("备份/恢复: {0}" -f (Join-Path $backupDir 'restore.ps1')) 'INFO'
} else {
    Write-Log '备份目录不可用，本次未生成注册表备份' 'WARN'
}
if ($rebootNeeded) {
    Write-Host ''
    Write-Host '  ※ 检测到被内核驱动锁定的文件，请重启电脑完成最终删除 ※' -ForegroundColor Yellow
}
if (-not $Auto) { Read-Host '按回车退出' | Out-Null }
