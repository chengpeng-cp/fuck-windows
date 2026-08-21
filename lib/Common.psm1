#requires -Version 5.1
Set-StrictMode -Off

$script:FWRoot = $null
$script:FWLogPath = $null
$script:FWBackupDir = $null

function Initialize-FWEnvironment {
    param([Parameter(Mandatory)][string]$RootDir)
    $script:FWRoot = $RootDir
    $logDir = Join-Path $RootDir 'logs'
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:FWBackupDir = Join-Path (Join-Path $RootDir 'backup') $stamp
    try {
        New-Item -ItemType Directory -Path $logDir, $script:FWBackupDir -Force | Out-Null
    } catch {
        $script:FWBackupDir = Join-Path $env:TEMP ("fw-backup-$stamp")
        New-Item -ItemType Directory -Path $script:FWBackupDir -Force | Out-Null
    }
    $script:FWLogPath = Join-Path $logDir ("clean_$stamp.log")
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERR', 'STEP')][string]$Level = 'INFO'
    )
    $line = "[{0}] [{1,-4}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    Write-Host $line
    if ($script:FWLogPath) {
        try { $line | Out-File -FilePath $script:FWLogPath -Append -Encoding UTF8 } catch {}
    }
}

function Get-FWBackupDir { return $script:FWBackupDir }

function Test-FWAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-FWSelfElevation {
    param([hashtable]$Params, [Parameter(Mandatory)][string]$ScriptPath, [switch]$KeepWindow)
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass')
    if ($KeepWindow) { $argList += '-NoExit' }
    $argList += @('-File', "`"$ScriptPath`"")
    foreach ($k in $Params.Keys) {
        $v = $Params[$k]
        if ($v -is [switch] -or $v -is [bool]) { if ($v) { $argList += "-$k" } }
        else { $argList += "-$k"; $argList += "`"$v`"" }
    }
    Start-Process powershell -Verb RunAs -ArgumentList ($argList -join ' ')
}

function Get-FWPatternRegex {
    param([string[]]$Patterns)
    if (-not $Patterns -or $Patterns.Count -eq 0) { return $null }
    return [regex]::New('(?:' + ($Patterns -join '|') + ')', 'IgnoreCase')
}

function Backup-FWRegistryKey {
    param([Parameter(Mandatory)][string]$KeyPath)
    if (-not $script:FWBackupDir) { return $null }
    $regPath = ($KeyPath -replace 'Microsoft\.PowerShell\.Core\\Registry::', '') -replace '^(HKEY[^:\\]+):', '$1'
    $safeName = ($regPath -replace '[\\/:*?"<>| ]', '_')
    if ($safeName.Length -gt 100) { $safeName = $safeName.Substring(0, 100) }
    $file = Join-Path $script:FWBackupDir ("reg_$safeName.reg")
    & reg.exe export "$regPath" "$file" /y 2>&1 | Out-Null
    if (Test-Path $file) { return $file }
    return $null
}

Export-ModuleMember -Function '*'
