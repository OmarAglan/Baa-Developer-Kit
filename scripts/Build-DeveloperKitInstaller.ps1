param(
    [string]$ReleaseVersion = '0.6.0',
    [string]$NazmInstaller = '..\Nazm\dist\installer\nazm-setup-0.4.0-x64.exe',
    [string]$BaaInstaller = '..\Baa\dist\installer\baa-setup-0.6.0-x64.exe',
    [string]$TakweenInstaller = '..\Takween\dist\installer\takween-setup-0.1.0-x64.exe',
    [string]$QalamInstaller = '..\Qalam-IDE\dist\installer\qalam-setup-3.7.0-x64.exe',
    [string]$IsccPath = '',
    [string]$SignToolName = '',
    [string]$SignToolCommand = ''
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Resolve-Installer {
    param([string]$Path, [string]$ExpectedName)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    if ([IO.Path]::GetFileName($resolved) -cne $ExpectedName) {
        throw "Expected installer '$ExpectedName': $resolved"
    }
    $sidecar = $resolved + '.sha256'
    if (!(Test-Path -LiteralPath $sidecar -PathType Leaf)) {
        throw "Installer checksum is missing: $sidecar"
    }
    $line = [IO.File]::ReadAllText($sidecar, [Text.Encoding]::ASCII).Trim()
    if ($line -notmatch '^([0-9A-Fa-f]{64}) \*(.+)$') {
        throw "Invalid installer checksum file: $sidecar"
    }
    if ($Matches[2] -cne $ExpectedName) {
        throw "Installer checksum names the wrong file: $sidecar"
    }
    $actual = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash
    if ($Matches[1] -ine $actual) {
        throw "Installer checksum mismatch: $resolved"
    }
    return $resolved
}

$NazmInstaller = Resolve-Installer $NazmInstaller 'nazm-setup-0.4.0-x64.exe'
$BaaInstaller = Resolve-Installer $BaaInstaller 'baa-setup-0.6.0-x64.exe'
$TakweenInstaller = Resolve-Installer $TakweenInstaller 'takween-setup-0.1.0-x64.exe'
$QalamInstaller = Resolve-Installer $QalamInstaller 'qalam-setup-3.7.0-x64.exe'

$manifestPath = Join-Path $root 'dist\eco-installer-manifest-v1.json'
& (Join-Path $PSScriptRoot 'New-EcoInstallerManifest.ps1') `
    -NazmInstaller $NazmInstaller `
    -BaaInstaller $BaaInstaller `
    -TakweenInstaller $TakweenInstaller `
    -QalamInstaller $QalamInstaller `
    -ReleaseVersion $ReleaseVersion `
    -QalamVersion '3.7.0' `
    -OutputPath $manifestPath

$manifest = Get-Content -LiteralPath $manifestPath -Raw |
    ConvertFrom-Json
$bundledPrograms = @($manifest.bundled_programs)
if ($bundledPrograms.Count -ne 1 -or
    $bundledPrograms[0].id -cne 'baa-lsp' -or
    $bundledPrograms[0].owner_component -cne 'qalam' -or
    $bundledPrograms[0].program -cne 'baa-lsp\baa-lsp.exe') {
    throw 'Installer manifest must record Baa-LSP as a Qalam-owned program.'
}
$hashes = @{}
foreach ($component in $manifest.components) {
    $hashes[$component.id] = $component.sha256
}

if ([string]::IsNullOrWhiteSpace($IsccPath)) {
    $command = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($command) { $IsccPath = $command.Source }
}
if ([string]::IsNullOrWhiteSpace($IsccPath)) {
    $IsccPath = @(
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe'
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
}
if ([string]::IsNullOrWhiteSpace($IsccPath) -or
    !(Test-Path -LiteralPath $IsccPath -PathType Leaf)) {
    throw 'Inno Setup 6 compiler was not found. Pass -IsccPath explicitly.'
}

$definitions = @(
    "/DMyAppVersion=$ReleaseVersion",
    "/DNazmInstallerPath=$NazmInstaller",
    "/DBaaInstallerPath=$BaaInstaller",
    "/DTakweenInstallerPath=$TakweenInstaller",
    "/DQalamInstallerPath=$QalamInstaller",
    "/DInstallerManifestPath=$manifestPath",
    "/DNazmSha256=$($hashes.nazm)",
    "/DBaaSha256=$($hashes.baa)",
    "/DTakweenSha256=$($hashes.takween)",
    "/DQalamSha256=$($hashes.qalam)"
)
if ([string]::IsNullOrWhiteSpace($SignToolName) -ne
    [string]::IsNullOrWhiteSpace($SignToolCommand)) {
    throw 'Pass both -SignToolName and -SignToolCommand, or neither.'
}
if (![string]::IsNullOrWhiteSpace($SignToolName)) {
    if ($SignToolName -notmatch '^[A-Za-z0-9_-]+$') {
        throw 'SignToolName may contain only letters, digits, underscore, and hyphen.'
    }
    $definitions += "/DInstallerSignTool=$SignToolName"
    $definitions += "/S$SignToolName=$SignToolCommand"
}
$definitions += 'setup.iss'
Push-Location $root
try {
    & $IsccPath @definitions
    if ($LASTEXITCODE -ne 0) {
        throw "ISCC failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

$installer = Join-Path $root (
    "dist\installer\baa-developer-kit-setup-$ReleaseVersion-x64.exe")
if (!(Test-Path -LiteralPath $installer -PathType Leaf)) {
    throw "Developer Kit installer was not produced: $installer"
}
$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
$checksum = "$installer.sha256"
[IO.File]::WriteAllText(
    $checksum,
    "$hash *$([IO.Path]::GetFileName($installer))`n",
    [Text.Encoding]::ASCII)
$archive = [IO.Path]::ChangeExtension($installer, '.zip')
if (Test-Path -LiteralPath $archive) {
    Remove-Item -LiteralPath $archive -Force
}
Compress-Archive -LiteralPath @($installer, $checksum, $manifestPath) `
    -DestinationPath $archive -CompressionLevel Optimal
$archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
$archiveChecksum = "$archive.sha256"
[IO.File]::WriteAllText(
    $archiveChecksum,
    "$archiveHash *$([IO.Path]::GetFileName($archive))`n",
    [Text.Encoding]::ASCII)
Write-Output $installer
Write-Output $checksum
Write-Output $archive
Write-Output $archiveChecksum
