param(
    [Parameter(Mandatory)] [string]$NazmInstaller,
    [Parameter(Mandatory)] [string]$BaaInstaller,
    [Parameter(Mandatory)] [string]$TakweenInstaller,
    [Parameter(Mandatory)] [string]$QalamInstaller,
    [string]$ReleaseVersion = "0.6.0",
    [string]$NazmVersion = "0.4.0",
    [string]$BaaVersion = "0.6.0",
    [string]$TakweenVersion = "0.1.0",
    [string]$QalamVersion = "3.7.0",
    [string]$BaaLspVersion = "0.1.0",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $root "dist\eco-installer-manifest-v1.json"
}

function New-Component {
    param(
        [string]$Id,
        [string]$DisplayName,
        [string]$Version,
        [int]$Order,
        [string]$Installer,
        [string]$Program,
        [string[]]$Arguments
    )

    $resolved = (Resolve-Path -LiteralPath $Installer).Path
    $expectedName = "$Id-setup-$Version-x64.exe"
    if ([IO.Path]::GetFileName($resolved) -cne $expectedName) {
        throw "Installer name must be '$expectedName': $resolved"
    }

    [ordered]@{
        id = $Id
        display_name = $DisplayName
        version = $Version
        install_order = $Order
        installer = [IO.Path]::GetFileName($resolved)
        sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolved).Hash.ToLowerInvariant()
        silent_arguments = @(
            "/VERYSILENT",
            "/SUPPRESSMSGBOXES",
            "/NORESTART",
            "/SP-",
            "/ALLUSERS"
        )
        health_check = [ordered]@{
            program = $Program
            arguments = $Arguments
            expected_exit_code = 0
        }
    }
}

$nazmName = -join [char[]](0x0646, 0x0638, 0x0645)
$baaName = -join [char[]](0x0628, 0x0627, 0x0621)
$takweenName = -join [char[]](0x062A, 0x0643, 0x0648, 0x064A, 0x0646)
$qalamName = -join [char[]](0x0642, 0x0644, 0x0645)
$arabicVersion = "--" +
    (-join [char[]](0x0625, 0x0635, 0x062F, 0x0627, 0x0631))

$components = @(
    New-Component "nazm" $nazmName $NazmVersion 10 $NazmInstaller `
        ("bin\" + $nazmName + ".exe") @($arabicVersion)
    New-Component "baa" $baaName $BaaVersion 20 $BaaInstaller `
        "baa.exe" @("--version")
    New-Component "takween" $takweenName $TakweenVersion 30 $TakweenInstaller `
        ("bin\" + $takweenName + ".exe") @($arabicVersion)
    New-Component "qalam" $qalamName $QalamVersion 40 $QalamInstaller `
        "baa-lsp\baa-lsp.exe" @("--version")
)

$bundledPrograms = @(
    [ordered]@{
        id = "baa-lsp"
        display_name = "خادم لغة باء"
        version = $BaaLspVersion
        owner_component = "qalam"
        program = "baa-lsp\baa-lsp.exe"
        health_check = [ordered]@{
            arguments = @("--version")
            expected_exit_code = 0
        }
    }
)

$manifest = [ordered]@{
    schema_version = "eco-installer-manifest-v1"
    release_version = $ReleaseVersion
    target = "x86_64-windows"
    generated_at_utc = [DateTime]::UtcNow.ToString("o")
    components = $components
    bundled_programs = $bundledPrograms
}

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$json = $manifest | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($OutputPath, $json + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))
Write-Output $OutputPath
