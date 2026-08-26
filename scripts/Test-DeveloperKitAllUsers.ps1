param(
    [string]$ReleaseVersion = '0.3.0',
    [string]$Installer = ''
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($Installer)) {
    $Installer = Join-Path $root (
        "dist\installer\baa-developer-kit-setup-$ReleaseVersion-x64.exe")
}
$Installer = (Resolve-Path -LiteralPath $Installer).Path
$checksumPath = $Installer + '.sha256'
if (!(Test-Path -LiteralPath $checksumPath -PathType Leaf)) {
    throw "Developer Kit checksum is missing: $checksumPath"
}
$checksumLine = [IO.File]::ReadAllText(
    $checksumPath, [Text.Encoding]::ASCII).Trim()
if ($checksumLine -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$' -or
    $Matches[2] -cne [IO.Path]::GetFileName($Installer)) {
    throw 'Developer Kit checksum file is invalid.'
}
if ($Matches[1] -ine
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Installer).Hash) {
    throw 'Developer Kit SHA-256 verification failed.'
}

$uninstallKeys = [ordered]@{
    nazm = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{8D3D57AE-41CF-4B8A-95E9-270E4564E2A1}_is1'
    baa = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{E4B6D77C-6C22-4E2D-8F9D-61D34A26B0D1}_is1'
    takween = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{9D321DC1-69B3-44F0-A52A-86DB6A6E0C97}_is1'
    qalam = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{1A6F6714-2C14-4DBD-BACB-B26CBABE36EE}_is1'
}
$componentDirectories = [ordered]@{
    nazm = Join-Path $env:ProgramFiles 'Nazm'
    baa = Join-Path $env:ProgramFiles 'Baa'
    takween = Join-Path $env:ProgramFiles 'Takween'
    qalam = Join-Path $env:ProgramFiles 'Qalam'
}
foreach ($entry in $uninstallKeys.GetEnumerator()) {
    if (Test-Path -LiteralPath $entry.Value) {
        throw "Refusing to replace an existing all-users $($entry.Key) installation."
    }
}
foreach ($entry in $componentDirectories.GetEnumerator()) {
    if (Test-Path -LiteralPath $entry.Value) {
        throw "Refusing to replace an existing all-users $($entry.Key) directory: $($entry.Value)"
    }
}

$userPathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')
$machinePathBefore = [Environment]::GetEnvironmentVariable('Path', 'Machine')
$environmentBefore = @{}
foreach ($name in @('BAA_HOME', 'BAA_STDLIB', 'TAKWEEN_HOME')) {
    $environmentBefore[$name] =
        [Environment]::GetEnvironmentVariable($name, 'Machine')
}
$processPathBefore = $env:PATH
$processBaaHomeBefore = $env:BAA_HOME
$processBaaStdlibBefore = $env:BAA_STDLIB
$hadProcessBaaNazm = Test-Path Env:BAA_NAZM
$processBaaNazmBefore = $env:BAA_NAZM
$programDirectory = Join-Path ([IO.Path]::GetTempPath()) (
    'Baa all-users installer - ' + [Guid]::NewGuid().ToString('N'))
$setupLog = Join-Path ([IO.Path]::GetTempPath()) (
    'baa-developer-kit-all-users-' + [Guid]::NewGuid().ToString('N') + '.log')
$installed = $false

$nazmName = -join [char[]](0x0646, 0x0638, 0x0645)
$takweenName = -join [char[]](0x062A, 0x0643, 0x0648, 0x064A, 0x0646)
$qalamName = -join [char[]](0x0642, 0x0644, 0x0645)
$qalamShortcut = Join-Path $env:ProgramData (
    'Microsoft\Windows\Start Menu\Programs\' + $qalamName + '\' +
    $qalamName + '.lnk')
$versionArgument = '--' +
    (-join [char[]](0x0625, 0x0635, 0x062F, 0x0627, 0x0631))

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
    $process = Start-Process -FilePath $Installer -ArgumentList @(
        '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-',
        '/ALLUSERS', "/LOG=`"$setupLog`""
    ) -WindowStyle Hidden -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "All-users Developer Kit failed with exit code $($process.ExitCode). Log: $setupLog"
    }
}

function Uninstall-Components {
    foreach ($id in @('qalam', 'takween', 'baa', 'nazm')) {
        $uninstaller = Join-Path $componentDirectories[$id] 'unins000.exe'
        if (Test-Path -LiteralPath $uninstaller -PathType Leaf) {
            $process = Start-Process -FilePath $uninstaller -ArgumentList @(
                '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'
            ) -WindowStyle Hidden -Wait -PassThru
            if ($process.ExitCode -ne 0) {
                throw "$id all-users uninstall failed with exit code $($process.ExitCode)."
            }
        }
    }
    Wait-State 'all-users component uninstall cleanup' {
        -not ($uninstallKeys.Values | Where-Object {
            Test-Path -LiteralPath $_
        })
    }
}

try {
    Invoke-DeveloperKit
    $installed = $true
    Invoke-DeveloperKit

    foreach ($entry in $uninstallKeys.GetEnumerator()) {
        if (!(Test-Path -LiteralPath $entry.Value)) {
            throw "Missing all-users registration: $($entry.Key)"
        }
    }
    $nazmBin = Join-Path $componentDirectories.nazm 'bin'
    $baaDirectory = $componentDirectories.baa
    $takweenBin = Join-Path $componentDirectories.takween 'bin'
    $machinePathAfter = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    foreach ($expected in @($nazmBin, $baaDirectory, $takweenBin)) {
        if ((Get-PathEntryCount $machinePathAfter $expected) -ne 1) {
            throw "Machine PATH does not contain exactly one owned entry: $expected"
        }
    }
    if ((Get-PathEntryCount $machinePathAfter (
            Join-Path $baaDirectory 'gcc\bin')) -ne 0) {
        throw 'Baa private GCC leaked into machine PATH.'
    }
    if ([Environment]::GetEnvironmentVariable('Path', 'User') -ne
        $userPathBefore) {
        throw 'All-users installation changed user PATH.'
    }
    if ([Environment]::GetEnvironmentVariable('BAA_HOME', 'Machine') -ine
        $baaDirectory -or
        [Environment]::GetEnvironmentVariable('BAA_STDLIB', 'Machine') -ine
        (Join-Path $baaDirectory 'stdlib') -or
        [Environment]::GetEnvironmentVariable('TAKWEEN_HOME', 'Machine') -ine
        $componentDirectories.takween) {
        throw 'All-users installation wrote incorrect machine environment values.'
    }
    if (!(Test-Path -LiteralPath $qalamShortcut -PathType Leaf)) {
        throw 'All-users Qalam Start Menu shortcut is missing.'
    }

    $nazmExecutable = Join-Path $nazmBin ($nazmName + '.exe')
    $baaExecutable = Join-Path $baaDirectory 'baa.exe'
    $takweenExecutable = Join-Path $takweenBin ($takweenName + '.exe')
    $env:PATH = "$machinePathAfter;$userPathBefore"
    $env:BAA_HOME = $baaDirectory
    $env:BAA_STDLIB = Join-Path $baaDirectory 'stdlib'
    Remove-Item Env:BAA_NAZM -ErrorAction SilentlyContinue
    & $nazmExecutable $versionArgument
    if ($LASTEXITCODE -ne 0) { throw 'All-users Nazm probe failed.' }
    & $baaExecutable --version
    if ($LASTEXITCODE -ne 0) { throw 'All-users Baa probe failed.' }
    & $takweenExecutable $versionArgument
    if ($LASTEXITCODE -ne 0) { throw 'All-users Takween probe failed.' }

    [IO.Directory]::CreateDirectory($programDirectory) | Out-Null
    $integerKeyword = -join [char[]](0x0635, 0x062D, 0x064A, 0x062D)
    $entryPoint = -join [char[]](
        0x0627, 0x0644, 0x0631, 0x0626, 0x064A, 0x0633, 0x064A, 0x0629)
    $returnKeyword = -join [char[]](0x0625, 0x0631, 0x062C, 0x0639)
    $baaExtension = -join [char[]](0x0628, 0x0627, 0x0621)
    $source = Join-Path $programDirectory ('all-users.' + $baaExtension)
    $program = Join-Path $programDirectory 'all-users.exe'
    [IO.File]::WriteAllText(
        $source,
        "$integerKeyword $entryPoint() {`n    $returnKeyword $([char]0x0660).`n}`n",
        [Text.UTF8Encoding]::new($false))
    & $baaExecutable $source -o $program
    if ($LASTEXITCODE -ne 0 -or
        !(Test-Path -LiteralPath $program -PathType Leaf)) {
        throw 'All-users Baa/Nazm/private-linker pipeline failed.'
    }
    & $program
    if ($LASTEXITCODE -ne 0) {
        throw 'All-users compiled program failed to run.'
    }

    Uninstall-Components
    $installed = $false
}
finally {
    $env:PATH = $processPathBefore
    $env:BAA_HOME = $processBaaHomeBefore
    $env:BAA_STDLIB = $processBaaStdlibBefore
    if ($hadProcessBaaNazm) { $env:BAA_NAZM = $processBaaNazmBefore }
    else { Remove-Item Env:BAA_NAZM -ErrorAction SilentlyContinue }
    if ($installed) { Uninstall-Components }
    if (Test-Path -LiteralPath $programDirectory) {
        $resolvedProgram = [IO.Path]::GetFullPath($programDirectory)
        $resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if (!$resolvedProgram.StartsWith(
                $resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to remove test files outside Temp: $resolvedProgram"
        }
        Remove-Item -LiteralPath $resolvedProgram -Recurse -Force
    }
}

if ([Environment]::GetEnvironmentVariable('Path', 'Machine') -ne
    $machinePathBefore -or
    [Environment]::GetEnvironmentVariable('Path', 'User') -ne
    $userPathBefore) {
    throw 'All-users uninstall did not restore PATH.'
}
foreach ($name in $environmentBefore.Keys) {
    if ([Environment]::GetEnvironmentVariable($name, 'Machine') -ne
        $environmentBefore[$name]) {
        throw "All-users uninstall did not restore $name."
    }
}
foreach ($directory in $componentDirectories.Values) {
    if (Test-Path -LiteralPath $directory) {
        throw "All-users uninstall left component files: $directory"
    }
}
if (Test-Path -LiteralPath $qalamShortcut) {
    throw 'All-users uninstall left the Qalam Start Menu shortcut.'
}

Write-Output 'Baa Developer Kit all-users installer contract passed.'
