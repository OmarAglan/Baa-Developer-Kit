param(
    [string]$ReleaseVersion = '0.6.0',
    [string]$Installer = '',
    [string]$PreviousInstaller = ''
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($Installer)) {
    $Installer = Join-Path $root (
        "dist\installer\baa-developer-kit-setup-$ReleaseVersion-x64.exe")
}
$Installer = (Resolve-Path -LiteralPath $Installer).Path

function Assert-InstallerChecksum {
    param([string]$Path)
    $checksumPath = $Path + '.sha256'
    if (!(Test-Path -LiteralPath $checksumPath -PathType Leaf)) {
        throw "Developer Kit checksum is missing: $checksumPath"
    }
    $checksumLine = [IO.File]::ReadAllText(
        $checksumPath, [Text.Encoding]::ASCII).Trim()
    if ($checksumLine -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$') {
        throw 'Developer Kit checksum file has an invalid format.'
    }
    if ($Matches[2] -cne [IO.Path]::GetFileName($Path)) {
        throw 'Developer Kit checksum names the wrong file.'
    }
    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($Matches[1] -ine $actualHash) {
        throw 'Developer Kit SHA-256 verification failed.'
    }
}
Assert-InstallerChecksum $Installer
if (![string]::IsNullOrWhiteSpace($PreviousInstaller)) {
    $PreviousInstaller = (Resolve-Path -LiteralPath $PreviousInstaller).Path
    Assert-InstallerChecksum $PreviousInstaller
}

$uninstallKeys = [ordered]@{
    nazm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{8D3D57AE-41CF-4B8A-95E9-270E4564E2A1}_is1'
    baa = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{E4B6D77C-6C22-4E2D-8F9D-61D34A26B0D1}_is1'
    takween = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{9D321DC1-69B3-44F0-A52A-86DB6A6E0C97}_is1'
    qalam = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{1A6F6714-2C14-4DBD-BACB-B26CBABE36EE}_is1'
}
foreach ($entry in $uninstallKeys.GetEnumerator()) {
    if (Test-Path -LiteralPath $entry.Value) {
        throw "Refusing to replace an existing current-user $($entry.Key) installation."
    }
}

$userPathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')
$machinePathBefore = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$environmentBefore = @{}
foreach ($name in @('BAA_HOME', 'BAA_STDLIB', 'TAKWEEN_HOME')) {
    $environmentBefore[$name] =
        [Environment]::GetEnvironmentVariable($name, 'User')
}

$kitName = -join [char[]](
    0x0639, 0x062F, 0x0629, 0x0020, 0x062A, 0x0637, 0x0648,
    0x064A, 0x0631, 0x0020, 0x0628, 0x0627, 0x0621)
$longSuffix = -join ('x' * 72)
$componentRoot = Join-Path ([IO.Path]::GetTempPath()) (
    "$kitName - long path $longSuffix-$([Guid]::NewGuid().ToString('N'))")
$setupLog = Join-Path ([IO.Path]::GetTempPath()) (
    'baa-developer-kit-' + [Guid]::NewGuid().ToString('N') + '.log')
$receiptDirectory = Join-Path $env:LOCALAPPDATA 'BaaEcosystem\InstallerLogs'
$testStarted = [DateTime]::Now.AddSeconds(-2)
$installed = $false
$qalamProcess = $null

$nazmName = -join [char[]](0x0646, 0x0638, 0x0645)
$takweenName = -join [char[]](0x062A, 0x0643, 0x0648, 0x064A, 0x0646)
$versionArgument = '--' +
    (-join [char[]](0x0625, 0x0635, 0x062F, 0x0627, 0x0631))
$componentDirectories = [ordered]@{
    nazm = Join-Path $componentRoot 'nazm'
    baa = Join-Path $componentRoot 'baa'
    takween = Join-Path $componentRoot 'takween'
    qalam = Join-Path $componentRoot 'qalam'
}

function Normalize-PathEntry {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return $Value.Trim().Trim('"').Replace('/', '\').TrimEnd('\').ToLowerInvariant()
}

function Get-PathEntryCount {
    param([string]$PathValue, [string]$Expected)
    $wanted = Normalize-PathEntry $Expected
    return @($PathValue -split ';' | Where-Object {
        (Normalize-PathEntry $_) -eq $wanted
    }).Count
}

function Wait-State {
    param([string]$Description, [scriptblock]$Condition)
    for ($attempt = 0; $attempt -lt 300; $attempt++) {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 200
    }
    throw "Timed out waiting for $Description."
}

function Invoke-DeveloperKit {
    param([string]$Executable = '')
    if ([string]::IsNullOrWhiteSpace($Executable)) {
        $Executable = $Installer
    }
    $arguments = @(
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-',
        '/CURRENTUSER',
        "/COMPONENTROOT=`"$componentRoot`"",
        "/LOG=`"$setupLog`""
    )
    $process = Start-Process -FilePath $Executable -ArgumentList $arguments `
        -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Developer Kit failed with exit code $($process.ExitCode). Log: $setupLog"
    }
}

function Invoke-VersionProbe {
    param([string]$Program, [string[]]$Arguments)
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Health probe failed with exit code ${LASTEXITCODE}: $Program"
    }
}

function Stop-Qalam {
    if ($script:qalamProcess -and !$script:qalamProcess.HasExited) {
        $script:qalamProcess.Kill()
        $script:qalamProcess.WaitForExit()
    }
}

function Test-QalamWindow {
    param([string]$Executable)
    if (-not ('DeveloperKitWindowProbe' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DeveloperKitWindowProbe
{
    [StructLayout(LayoutKind.Sequential)]
    public struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr window, out Rect rectangle);
}
'@
    }
    $runtimeTemp = Join-Path $componentRoot 'qalam-runtime-temp'
    [IO.Directory]::CreateDirectory($runtimeTemp) | Out-Null
    $previousTemp = $env:TEMP
    $previousTmp = $env:TMP
    try {
        $env:TEMP = $runtimeTemp
        $env:TMP = $runtimeTemp
        $script:qalamProcess = Start-Process -FilePath $Executable `
            -WindowStyle Hidden -PassThru
    }
    finally {
        $env:TEMP = $previousTemp
        $env:TMP = $previousTmp
    }
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 100
        $script:qalamProcess.Refresh()
    } while (!$script:qalamProcess.HasExited -and
             $script:qalamProcess.MainWindowHandle -eq [IntPtr]::Zero -and
             [DateTime]::UtcNow -lt $deadline)
    if ($script:qalamProcess.HasExited) {
        throw "Installed Qalam exited with code $($script:qalamProcess.ExitCode)."
    }
    if ($script:qalamProcess.MainWindowHandle -eq [IntPtr]::Zero) {
        throw 'Installed Qalam created no native window.'
    }
    $rect = New-Object DeveloperKitWindowProbe+Rect
    if (![DeveloperKitWindowProbe]::GetWindowRect(
            $script:qalamProcess.MainWindowHandle, [ref]$rect)) {
        throw 'Installed Qalam window geometry could not be read.'
    }
    if (($rect.Right - $rect.Left) -lt 640 -or
        ($rect.Bottom - $rect.Top) -lt 480) {
        throw 'Installed Qalam window geometry is unusable.'
    }
    Stop-Qalam
}

function Uninstall-Components {
    foreach ($id in @('qalam', 'takween', 'baa', 'nazm')) {
        $directory = $componentDirectories[$id]
        $uninstaller = Join-Path $directory 'unins000.exe'
        if (Test-Path -LiteralPath $uninstaller -PathType Leaf) {
            $process = Start-Process -FilePath $uninstaller -ArgumentList @(
                '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'
            ) -WindowStyle Hidden -Wait -PassThru
            if ($process.ExitCode -ne 0) {
                throw "$id uninstall failed with exit code $($process.ExitCode)."
            }
        }
    }
    Wait-State 'component uninstall cleanup' {
        -not ($uninstallKeys.Values | Where-Object {
            Test-Path -LiteralPath $_
        })
    }
}

try {
    $previousProgramHashes = @{}
    if (![string]::IsNullOrWhiteSpace($PreviousInstaller)) {
        Invoke-DeveloperKit $PreviousInstaller
        $installed = $true
        $upgradePrograms = [ordered]@{
            baa = Join-Path $componentDirectories.baa 'baa.exe'
            qalam = Join-Path $componentDirectories.qalam 'Qalam.exe'
        }
        foreach ($entry in $upgradePrograms.GetEnumerator()) {
            if (!(Test-Path -LiteralPath $entry.Value -PathType Leaf)) {
                throw "Previous installation is missing $($entry.Key): $($entry.Value)"
            }
            $previousProgramHashes[$entry.Key] =
                (Get-FileHash -LiteralPath $entry.Value -Algorithm SHA256).Hash
        }
    }
    Invoke-DeveloperKit
    foreach ($entry in $previousProgramHashes.GetEnumerator()) {
        $program = $upgradePrograms[$entry.Key]
        $currentHash =
            (Get-FileHash -LiteralPath $program -Algorithm SHA256).Hash
        if ($currentHash -ieq $entry.Value) {
            throw "Upgrade did not replace $($entry.Key): $program"
        }
    }
    $installed = $true
    Invoke-DeveloperKit

    foreach ($entry in $uninstallKeys.GetEnumerator()) {
        if (!(Test-Path -LiteralPath $entry.Value)) {
            throw "Missing installed-component registration: $($entry.Key)"
        }
    }

    $nazmBin = Join-Path $componentDirectories.nazm 'bin'
    $baaDirectory = $componentDirectories.baa
    $takweenBin = Join-Path $componentDirectories.takween 'bin'
    $qalamDirectory = $componentDirectories.qalam
    $userPathAfter = [Environment]::GetEnvironmentVariable('Path', 'User')
    foreach ($expected in @($nazmBin, $baaDirectory, $takweenBin)) {
        $entryCount = Get-PathEntryCount $userPathAfter $expected
        if ($entryCount -ne 1) {
            throw "Installer PATH entry count was $entryCount, expected 1: $expected; PATH=$userPathAfter"
        }
    }
    if ((Get-PathEntryCount $userPathAfter (
            Join-Path $baaDirectory 'gcc\bin')) -ne 0) {
        throw 'Baa private GCC leaked into PATH.'
    }
    if ([Environment]::GetEnvironmentVariable('Path', 'Machine') -ne
        $machinePathBefore) {
        throw 'Current-user Developer Kit changed machine PATH.'
    }

    $nazmExecutable = Join-Path $nazmBin ($nazmName + '.exe')
    $baaExecutable = Join-Path $baaDirectory 'baa.exe'
    $takweenExecutable = Join-Path $takweenBin ($takweenName + '.exe')
    $qalamExecutable = Join-Path $qalamDirectory 'Qalam.exe'
    $lspExecutable = Join-Path $qalamDirectory 'baa-lsp\baa-lsp.exe'
    Invoke-VersionProbe $nazmExecutable @($versionArgument)
    Invoke-VersionProbe (Join-Path $nazmBin 'nazm.exe') @($versionArgument)
    Invoke-VersionProbe $baaExecutable @('--version')
    Invoke-VersionProbe $takweenExecutable @($versionArgument)
    Invoke-VersionProbe (Join-Path $takweenBin 'takween.exe') @('--version')
    Invoke-VersionProbe $lspExecutable @('--version')

    $previousPath = $env:PATH
    $previousBaaHome = $env:BAA_HOME
    $previousBaaStdlib = $env:BAA_STDLIB
    try {
        $env:PATH = "$nazmBin;$baaDirectory;$takweenBin;$env:SystemRoot\System32;$env:SystemRoot"
        $env:BAA_HOME = $baaDirectory
        $env:BAA_STDLIB = Join-Path $baaDirectory 'stdlib'
        foreach ($externalTool in @('gcc.exe', 'ld.exe', 'cmake.exe',
                                    'python.exe')) {
            if (Get-Command $externalTool -CommandType Application `
                    -ErrorAction SilentlyContinue) {
                throw "External developer tool remained visible: $externalTool"
            }
        }
        $sourceDirectory = Join-Path $componentRoot ($kitName + ' source')
        [IO.Directory]::CreateDirectory($sourceDirectory) | Out-Null
        $integerKeyword = -join [char[]](0x0635, 0x062D, 0x064A, 0x062D)
        $entryPoint = -join [char[]](
            0x0627, 0x0644, 0x0631, 0x0626, 0x064A, 0x0633, 0x064A, 0x0629)
        $returnKeyword = -join [char[]](0x0625, 0x0631, 0x062C, 0x0639)
        $baaExtension = -join [char[]](0x0628, 0x0627, 0x0621)
        $source = Join-Path $sourceDirectory (
            ($kitName -replace ' ', '-') + '.' + $baaExtension)
        $program = Join-Path $sourceDirectory (($kitName -replace ' ', '-') + '.exe')
        [IO.File]::WriteAllText(
            $source,
            "$integerKeyword $entryPoint() {`n    $returnKeyword $([char]0x0660).`n}`n",
            [Text.UTF8Encoding]::new($false))
        & $baaExecutable $source -o $program
        if ($LASTEXITCODE -ne 0 -or
            !(Test-Path -LiteralPath $program -PathType Leaf)) {
            throw 'Installed Baa/Nazm/private-linker pipeline failed.'
        }
        & $program
        if ($LASTEXITCODE -ne 0) {
            throw 'Program built by the installed ecosystem failed to run.'
        }

        $nazmSource = Join-Path $sourceDirectory (
            $nazmName + '.' + $nazmName)
        $nazmObject = Join-Path $sourceDirectory ($nazmName + '.obj')
        $nazmProgram = Join-Path $sourceDirectory ($nazmName + '.exe')
        $textSection = '.' + (-join [char[]](0x0646, 0x0635))
        $globalDirective = '.' +
            (-join [char[]](0x0639, 0x0627, 0x0645))
        $mainSymbol = -join [char[]](
            0x0627, 0x0644, 0x0631, 0x0626, 0x064A, 0x0633, 0x064A,
            0x0629)
        $moveInstruction = -join [char[]](
            0x0627, 0x0646, 0x0642, 0x0644)
        $returnInstruction = -join [char[]](
            0x0627, 0x0631, 0x062C, 0x0639)
        $accumulator32 = -join [char[]](
            0x0633, 0x062C, 0x0644, 0x005F, 0x0627, 0x0644, 0x0645,
            0x0631, 0x0643, 0x0645, 0x005F, 0x0663, 0x0662)
        $arabicComma = [char]0x060C
        $nazmText = "$textSection`n$globalDirective $mainSymbol`n" +
            "${mainSymbol}:`n" +
            "    $moveInstruction $accumulator32$arabicComma $([char]0x0660)`n" +
            "    $returnInstruction`n"
        [IO.File]::WriteAllText(
            $nazmSource, $nazmText, [Text.UTF8Encoding]::new($false))
        $outputOption = '--' +
            (-join [char[]](0x062E, 0x0631, 0x062C))
        $formatOption = '--' +
            (-join [char[]](0x0635, 0x064A, 0x063A, 0x0629))
        $coffFormat = -join [char[]](0x0643, 0x0648, 0x0641)
        & $nazmExecutable $nazmSource $outputOption $nazmObject `
            $formatOption $coffFormat
        if ($LASTEXITCODE -ne 0 -or
            !(Test-Path -LiteralPath $nazmObject -PathType Leaf)) {
            throw 'Installed Nazm direct assembly workflow failed.'
        }
        & $baaExecutable $nazmSource "--nazm-path=$nazmExecutable" `
            -o $nazmProgram
        if ($LASTEXITCODE -ne 0 -or
            !(Test-Path -LiteralPath $nazmProgram -PathType Leaf)) {
            throw 'Installed Baa direct Nazm executable workflow failed.'
        }
        & $nazmProgram
        if ($LASTEXITCODE -ne 0) {
            throw 'Executable built from the direct Nazm source failed to run.'
        }

        $mixedProject = Join-Path $sourceDirectory 'mixed-takween'
        $mixedSource = Join-Path $mixedProject 'src'
        [IO.Directory]::CreateDirectory($mixedSource) | Out-Null
        $projectManifestName = (-join [char[]](
            0x0645, 0x0634, 0x0631, 0x0648, 0x0639)) + '.' +
            (-join [char[]](0x062A, 0x0643, 0x0648, 0x064A, 0x0646))
        $mixedFiles = [ordered]@{
            (Join-Path $mixedProject $projectManifestName) =
                'W9in2YTZhdi02LHZiNi5XQrYp9mE2KfYs9mFID0gItmF2K7YqtmE2Ldf2YbYuNmFIgrYp9mE2KXYtdiv2KfYsSA9ICIxLjAuMCIK2KXYtdiv2KfYsV/YqNin2KEgPSAiPj0wLjYuMCA8MC43LjAiCgpb2KfZhNij2YfYr9in2YEu2KjYsdmG2KfZhdisX9mG2LjZhV0K2KfZhNmG2YjYuSA9ICLYqtmG2YHZitiw2YoiCtin2YTZhdiv2K7ZhCA9ICJzcmMvbWFpbi7YqNin2KEiCtin2YTZhdi12KfYr9ixID0gWyJzcmMvaGVscGVyLtmG2LjZhSJdCgpb2KfZhNio2YbYp9ihXQrYp9mE2YXYrtix2KwgPSAiYnVpbGQiCtin2YTZhtmF2LcgPSAi2KrYt9mI2YrYsSIK2KfZhNmF2KzZhdi5ID0gItmG2LjZhSIKClvYp9mE2KPZhtmF2KfYty7Yqti32YjZitixXQrYp9mE2KrYrdiz2YrZhiA9IDEK2KfZhNiq2K3ZgtmCID0g2K7Yt9ijCg=='
            (Join-Path $mixedSource ('main.' + $baaExtension)) =
                '2K7Yp9ix2KzZiiDYtdit2YrYrSDZgtmK2YXYqV/Zhti42YUoKS4KCti12K3ZititINin2YTYsdim2YrYs9mK2KkoKSB7CiAgICDYpdix2KzYuSDZgtmK2YXYqV/Zhti42YUoKSAtINmnLgp9Cg=='
            (Join-Path $mixedSource ('helper.' + $nazmName)) =
                'LtmG2LUKLti52KfZhSDZgtmK2YXYqV/Zhti42YUK2YLZitmF2Klf2YbYuNmFOgogICAg2KfZhtmC2YQg2LPYrNmEX9in2YTZhdix2YPZhV/Zo9mi2Iwg2acKICAgINin2LHYrNi5Cg=='
        }
        foreach ($mixedFile in $mixedFiles.GetEnumerator()) {
            [IO.File]::WriteAllBytes(
                $mixedFile.Key, [Convert]::FromBase64String($mixedFile.Value))
        }
        Push-Location $mixedProject
        try {
            & $takweenExecutable build
            if ($LASTEXITCODE -ne 0) {
                throw 'Installed Takween mixed Baa/Nazm build failed.'
            }
            & $takweenExecutable run
            if ($LASTEXITCODE -ne 0) {
                throw 'Installed Takween mixed Baa/Nazm run failed.'
            }
            & $takweenExecutable clean
            if ($LASTEXITCODE -ne 0 -or
                (Test-Path -LiteralPath (Join-Path $mixedProject 'build'))) {
                throw 'Installed Takween mixed-project cleanup failed.'
            }
        }
        finally {
            Pop-Location
        }
        Test-QalamWindow $qalamExecutable
    }
    finally {
        Stop-Qalam
        $env:PATH = $previousPath
        $env:BAA_HOME = $previousBaaHome
        $env:BAA_STDLIB = $previousBaaStdlib
    }

    $newReceipts = @(Get-ChildItem -LiteralPath $receiptDirectory -File |
        Where-Object { $_.LastWriteTime -ge $testStarted })
    foreach ($suffix in @('-nazm.log', '-baa.log', '-takween.log',
                           '-qalam.log', '-manifest.json')) {
        if (!($newReceipts | Where-Object { $_.Name.EndsWith($suffix) })) {
            throw "Developer Kit did not preserve its $suffix receipt."
        }
    }

    Uninstall-Components
    $installed = $false
}
finally {
    Stop-Qalam
    if ($installed) { Uninstall-Components }
    if (Test-Path -LiteralPath $componentRoot) {
        $resolvedRoot = [IO.Path]::GetFullPath($componentRoot)
        $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (!$resolvedRoot.StartsWith(
                $resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove test files outside Temp: $resolvedRoot"
        }
        Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
    }
}

if ([Environment]::GetEnvironmentVariable('Path', 'User') -ne $userPathBefore) {
    throw 'Developer Kit uninstall did not restore user PATH.'
}
if ([Environment]::GetEnvironmentVariable('Path', 'Machine') -ne
    $machinePathBefore) {
    throw 'Developer Kit uninstall changed machine PATH.'
}
foreach ($name in $environmentBefore.Keys) {
    if ([Environment]::GetEnvironmentVariable($name, 'User') -ne
        $environmentBefore[$name]) {
        throw "Developer Kit uninstall did not restore $name."
    }
}
Write-Output 'Baa Developer Kit installer contract passed.'
