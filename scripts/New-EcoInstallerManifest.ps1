param(
    [Parameter(Mandatory)] [string]$NazmInstaller,
    [Parameter(Mandatory)] [string]$BaaInstaller,
    [Parameter(Mandatory)] [string]$TakweenInstaller,
    [Parameter(Mandatory)] [string]$QalamInstaller,
    [string]$ReleaseVersion = "0.1.0",
    [string]$NazmVersion = "0.4.0",
    [string]$BaaVersion = "0.6.0",
    [string]$TakweenVersion = "0.1.0",
    [string]$QalamVersion = "3.3.0",
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

$components = @(
    New-Component "nazm" "نظم" $NazmVersion 10 $NazmInstaller "نظم.exe" @("--إصدار")
    New-Component "baa" "باء" $BaaVersion 20 $BaaInstaller "baa.exe" @("--version")
    New-Component "takween" "تكوين" $TakweenVersion 30 $TakweenInstaller "تكوين.exe" @("--إصدار")
    New-Component "qalam" "قلم" $QalamVersion 40 $QalamInstaller "Qalam.exe" @("--verify-tools=json")
)

$manifest = [ordered]@{
    schema_version = "eco-installer-manifest-v1"
    release_version = $ReleaseVersion
    target = "x86_64-windows"
    generated_at_utc = [DateTime]::UtcNow.ToString("o")
    components = $components
}

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
$json = $manifest | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText($OutputPath, $json + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false))
Write-Output $OutputPath
