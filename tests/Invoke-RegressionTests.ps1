#requires -Version 5.1
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'lib\Common.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'lib\Scanner.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $root 'lib\Purger.psm1') -Force -DisableNameChecking
$db = Import-PowerShellDataFile (Join-Path $root 'signatures.psd1')

$script:passed = 0
$script:failed = 0

function Assert-Equal {
    param([string]$Name, $Actual, $Expected)
    if ($Actual -eq $Expected) {
        $script:passed++
        Write-Output "PASS $Name"
    } else {
        $script:failed++
        Write-Output "FAIL $Name (expected: $Expected; actual: $Actual)"
    }
}

foreach ($section in @('RogueProcesses', 'RoguePaths', 'RogueDisplayNames', 'RoguePublishers', 'SuspiciousDisplayNames', 'TempResiduePatterns', 'UserAutostartPatterns')) {
    foreach ($pattern in $db[$section]) {
        try {
            [regex]::new($pattern) | Out-Null
            $script:passed++
        } catch {
            $script:failed++
            Write-Output "FAIL invalid regex in $section`: $pattern"
        }
    }
}
Write-Output "Checked $($script:passed) assertions/signatures before regression cases."

Assert-Equal -Name 'HKLM provider path converts for reg.exe' -Actual (ConvertTo-FWRegistryExportPath -KeyPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Demo') -Expected 'HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Demo'
Assert-Equal -Name 'HKCU provider path converts for reg.exe' -Actual (ConvertTo-FWRegistryExportPath -KeyPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run') -Expected 'HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run'
Assert-Equal -Name 'Registry provider-qualified path converts for reg.exe' -Actual (ConvertTo-FWRegistryExportPath -KeyPath 'Microsoft.PowerShell.Core\Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Demo') -Expected 'HKEY_LOCAL_MACHINE\SOFTWARE\Demo'

$pathCases = @(
    @{ Name = 'known install directory'; Path = 'C:\Program Files (x86)\AISmartClean'; Expected = $true },
    @{ Name = 'known directory component'; Path = 'C:\Users\u\AppData\Roaming\gamebox\helper.exe'; Expected = $true },
    @{ Name = 'known executable name with arguments'; Path = '"C:\Tools\gamebox.exe" -service'; Expected = $true },
    @{ Name = 'prefix lookalike directory'; Path = 'C:\Program Files\SomeLegit\gameboxPlus'; Expected = $false },
    @{ Name = 'embedded lookalike directory'; Path = 'C:\Program Files\SomeLegit\mygamebox\app.exe'; Expected = $false },
    @{ Name = 'executable name with extra suffix'; Path = 'C:\Program Files\SomeLegit\gamebox.exe.backup'; Expected = $false }
)
foreach ($case in $pathCases) {
    Assert-Equal -Name $case.Name -Actual (Test-FWPathPattern -Text $case.Path -Patterns $db.RoguePaths) -Expected $case.Expected
}

$tempCases = @(
    @{ Name = 'exact Temp signature'; Value = 'pdzip'; Expected = $true },
    @{ Name = 'case-insensitive exact Temp signature'; Value = 'PUDDINGDESKTOP'; Expected = $true },
    @{ Name = 'Temp name with signature prefix'; Value = 'mypdzipX'; Expected = $false },
    @{ Name = 'Temp name with signature substring'; Value = 'old_datalock_cache'; Expected = $false },
    @{ Name = 'Temp backup-like name'; Value = 'pdzip-backup'; Expected = $false }
)
foreach ($case in $tempCases) {
    Assert-Equal -Name $case.Name -Actual (Test-FWExactPattern -Value $case.Value -Patterns $db.TempResiduePatterns) -Expected $case.Expected
}

$originalTemp = $env:TEMP
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('fw-regression-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    foreach ($name in @('pdzip', 'PUDDINGDESKTOP', 'mypdzipX', 'old_datalock_cache')) {
        New-Item -ItemType Directory -Path (Join-Path $fixtureRoot $name) | Out-Null
    }
    $env:TEMP = $fixtureRoot
    $tempFindings = @(Find-FWTempResidue -SigDb $db)
    Assert-Equal -Name 'Temp scanner returns only exact-name hits' -Actual $tempFindings.Count -Expected 2
    Assert-Equal -Name 'Temp scanner excludes substring lookalikes' -Actual (@($tempFindings.Name | Where-Object { $_ -in @('mypdzipX', 'old_datalock_cache') }).Count) -Expected 0
} finally {
    if ($null -eq $originalTemp) { Remove-Item Env:TEMP -ErrorAction SilentlyContinue }
    else { $env:TEMP = $originalTemp }
    Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$safePathCases = @(
    @{ Name = 'safe known rogue path'; Path = 'C:\Program Files (x86)\AISmartClean'; Expected = $true },
    @{ Name = 'safe exact rogue component'; Path = 'C:\Users\u\AppData\Roaming\gamebox'; Expected = $true },
    @{ Name = 'unsafe lookalike component'; Path = 'C:\Program Files\SomeLegit\gameboxPlus'; Expected = $false },
    @{ Name = 'Windows system directory'; Path = 'C:\Windows\System32\evil'; Expected = $false },
    @{ Name = 'drive root'; Path = 'C:\'; Expected = $false },
    @{ Name = 'path traversal'; Path = 'C:\Users\u\DataLock\..\Windows'; Expected = $false },
    @{ Name = 'device path'; Path = '\\?\C:\Tools\DataLock'; Expected = $false },
    @{ Name = 'NTFS alternate stream'; Path = 'C:\Users\u\DataLock:payload'; Expected = $false }
)
foreach ($case in $safePathCases) {
    Assert-Equal -Name $case.Name -Actual (Test-FWSafeRoguePath -Path $case.Path -SigDb $db) -Expected $case.Expected
}

$processRx = Get-FWPatternRegex -Patterns $db.RogueProcesses
Assert-Equal -Name 'exact DataLock process match' -Actual $processRx.IsMatch('DataLock') -Expected $true
Assert-Equal -Name 'DataLock service-name lookalike rejected' -Actual $processRx.IsMatch('DataLockSvc') -Expected $false

Write-Output "Regression results: $script:passed passed, $script:failed failed."
if ($script:failed -gt 0) { exit 1 }
exit 0
