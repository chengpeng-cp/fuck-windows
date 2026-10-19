#requires -Version 5.1
Set-StrictMode -Off

$script:FWRoot = $null
$script:FWLogPath = $null
$script:FWBackupDir = $null
$script:FWRegistryBackupCache = @{}

function Initialize-FWEnvironment {
    param([Parameter(Mandatory)][string]$RootDir)
    $script:FWRoot = $RootDir
    $script:FWRegistryBackupCache = @{}
    $logDir = Join-Path $RootDir 'logs'
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:FWBackupDir = Join-Path (Join-Path $RootDir 'backup') $stamp
    $script:FWLogPath = Join-Path $logDir ("clean_$stamp.log")
    try {
        New-Item -ItemType Directory -Path $logDir -Force -ErrorAction Stop | Out-Null
    } catch {
        # 程序目录不可写时回退到系统临时目录，避免日志功能静默失效
        $script:FWBackupDir = Join-Path $env:TEMP ("fw-backup-$stamp")
        $script:FWLogPath = Join-Path $env:TEMP ("fw-clean_$stamp.log")
    }
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERR', 'STEP')][string]$Level = 'INFO'
    )
    $line = "[{0}] [{1,-4}] {2}" -f (Get-Date -Format 'HH:mm:ss'), $Level, $Message
    Write-Host $line
    if ($script:FWLogPath) {
        try { $line | Add-Content -LiteralPath $script:FWLogPath -Encoding UTF8 } catch {}
    }
}

function Ensure-FWBackupDir {
    if (-not $script:FWBackupDir) { return $null }
    if (Test-Path -LiteralPath $script:FWBackupDir -PathType Container) { return $script:FWBackupDir }
    try {
        New-Item -ItemType Directory -Path $script:FWBackupDir -Force -ErrorAction Stop | Out-Null
        return $script:FWBackupDir
    } catch {
        $fallback = Join-Path $env:TEMP ("fw-backup-" + (Get-Date -Format 'yyyyMMdd_HHmmss'))
        try {
            New-Item -ItemType Directory -Path $fallback -Force -ErrorAction Stop | Out-Null
            $script:FWBackupDir = $fallback
            return $fallback
        } catch {
            $script:FWBackupDir = $null
            return $null
        }
    }
}

function Get-FWBackupDir { return (Ensure-FWBackupDir) }

function Get-FWLogPath { return $script:FWLogPath }

function Test-FWAdmin {
    return ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-FWSelfElevation {
    param([System.Collections.IDictionary]$Params, [Parameter(Mandatory)][string]$ScriptPath, [switch]$KeepWindow)
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

function Test-FWExactPattern {
    param([AllowNull()][string]$Value, [string[]]$Patterns, [regex]$Regex)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $rx = $Regex
    if (-not $rx) { $rx = Get-FWExactPatternRegex -Patterns $Patterns }
    return ($rx -and $rx.IsMatch($Value))
}

function Get-FWExactPatternRegex {
    param([string[]]$Patterns)
    if (-not $Patterns -or $Patterns.Count -eq 0) { return $null }
    return [regex]::New('\A(?:' + ($Patterns -join '|') + ')\z', 'IgnoreCase')
}

function Test-FWPathPattern {
    param([AllowNull()][string]$Text, [string[]]$Patterns, [regex]$Regex)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $false }
    $rx = $Regex
    if (-not $rx) { $rx = Get-FWPatternRegex -Patterns $Patterns }
    if (-not $rx) { return $false }

    foreach ($match in $rx.Matches($Text)) {
        # RoguePaths identifies a complete directory component or executable name,
        # never an arbitrary substring such as "gamebox" in "gameboxPlus".
        if ($match.Value.EndsWith('\') -or $match.Value.EndsWith('/')) { return $true }
        $tail = $Text.Substring($match.Index + $match.Length)
        if ($tail.Length -eq 0) { return $true }
        $next = $tail[0]
        if ([char]::IsWhiteSpace($next) -or $next -eq '\' -or $next -eq '/' -or $next -eq '"' -or $next -eq "'") {
            return $true
        }
        if ($next -eq '.') {
            $extension = [regex]::Match($tail, '^\.(?:exe|sys|dll|com|bat|cmd|scr|ps1|vbs|js)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            if ($extension.Success) {
                $afterExtension = $tail.Substring($extension.Length)
                if ($afterExtension.Length -eq 0) { return $true }
                $after = $afterExtension[0]
                if ([char]::IsWhiteSpace($after) -or $after -eq '\' -or $after -eq '/' -or $after -eq '"' -or $after -eq "'") {
                    return $true
                }
            }
        }
    }
    return $false
}

function Backup-FWRegistryKey {
    param([Parameter(Mandatory)][string]$KeyPath)
    $dir = Ensure-FWBackupDir
    if (-not $dir) { return $null }

    $regPath = ConvertTo-FWRegistryExportPath -KeyPath $KeyPath
    if ([string]::IsNullOrWhiteSpace($regPath)) { return $null }
    $cacheKey = $regPath.ToUpperInvariant()
    if ($script:FWRegistryBackupCache.ContainsKey($cacheKey)) {
        $cachedFile = $script:FWRegistryBackupCache[$cacheKey]
        $cachedItem = Get-Item -LiteralPath $cachedFile -ErrorAction SilentlyContinue
        if ($cachedItem -and $cachedItem.Length -gt 0) { return $cachedFile }
        $script:FWRegistryBackupCache.Remove($cacheKey)
    }

    if (-not (Test-Path -LiteralPath $KeyPath)) { return $null }
    $safeName = ($regPath -replace '[\\/:*?"<>| ]', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safeName)) { $safeName = 'root' }
    if ($safeName.Length -gt 100) { $safeName = $safeName.Substring(0, 100) }
    $file = Join-Path $dir ("reg_$safeName.reg")
    $i = 1
    while (Test-Path -LiteralPath $file) {
        $file = Join-Path $dir ("reg_{0}_{1}.reg" -f $safeName, $i)
        $i++
    }
    & reg.exe export "$regPath" "$file" /y 2>&1 | Out-Null
    $exported = Get-Item -LiteralPath $file -ErrorAction SilentlyContinue
    if ($exported -and $exported.Length -gt 0) {
        $script:FWRegistryBackupCache[$cacheKey] = $file
        return $file
    }
    Write-Log ("注册表备份失败: {0}" -f $KeyPath) 'WARN'
    return $null
}

function ConvertTo-FWRegistryExportPath {
    param([Parameter(Mandatory)][string]$KeyPath)
    $regPath = $KeyPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
    $regPath = $regPath -replace '^Registry::', ''
    # PowerShell 注册表路径是 HKCU:/HKLM: 形式，reg.exe 只接受 HKCU\ 或 HKEY_* 全名
    $hiveMap = @{
        'HKCU' = 'HKEY_CURRENT_USER'
        'HKLM' = 'HKEY_LOCAL_MACHINE'
        'HKCR' = 'HKEY_CLASSES_ROOT'
        'HKU'  = 'HKEY_USERS'
        'HKCC' = 'HKEY_CURRENT_CONFIG'
    }
    if ($regPath -match '^(HKEY_[A-Z_]+|HKCU|HKLM|HKCR|HKU|HKCC):?(?=\\|$)') {
        $hive = $Matches[1]
        if ($hiveMap.ContainsKey($hive)) { $hive = $hiveMap[$hive] }
        $regPath = $hive + $regPath.Substring($Matches[1].Length).TrimStart(':')
    }
    $regPath = $regPath.TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($regPath)) { return $null }
    return $regPath
}

Export-ModuleMember -Function '*'
