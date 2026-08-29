[CmdletBinding()]
param(
    [string]$Manifest = "https://raw.githubusercontent.com/vertex-ai-llc/pubto-downloads/main/manifest.json",
    [switch]$Yes,
    [switch]$DryRun,
    [switch]$Check
)

$ErrorActionPreference = "Stop"

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw "This installer supports Windows. Use install-desktop.sh on macOS."
}
$processArchitecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
if ($processArchitecture -notin @("AMD64", "x86_64")) {
    throw "Pubto Desktop currently supports Windows x64."
}

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("pubto-install-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $workDir | Out-Null
$rollbackArmed = $false
$rollbackDone = $false
$previousInstallRoot = $null
$installedInstallRoot = $null
$backupInstallRoot = Join-Path $workDir "previous-install"
$backupConfigRoot = Join-Path $workDir "pubto-config"
$backupTauriDataRoot = Join-Path $workDir "tauri-data"
$configRoot = Join-Path $env:APPDATA "pubto"
$tauriDataRoot = Join-Path $env:APPDATA "dev.pubto.desktop"
$installPhase = "manifest"
$releaseVersion = ""
$installerLogPath = Join-Path $workDir "msi-install.log"

function Write-InstallerDiagnostic {
    $definitions = @{
        manifest = @("windows_manifest_failed", "Windows installation could not load the release manifest")
        download = @("windows_download_failed", "Windows installation could not download the selected package")
        checksum = @("windows_checksum_failed", "Windows installation rejected the package checksum")
        backup = @("windows_backup_failed", "Windows installation could not back up the previous installation")
        package = @("windows_package_failed", "The Windows installer package returned an error")
        launch = @("windows_app_launch_failed", "Windows installation completed but Desktop could not be started")
        agent_health = @("windows_agent_health_failed", "Windows installation completed but the local Agent did not become ready")
    }
    $definition = $definitions[$installPhase]
    if (-not $definition) { $definition = $definitions["package"] }
    New-Item -ItemType Directory -Path $configRoot -Force | Out-Null
    @{
        code = $definition[0]
        occurredAt = (Get-Date).ToUniversalTime().ToString("o")
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $configRoot "installer-diagnostic.json") -Encoding UTF8
    if (Test-Path -LiteralPath $installerLogPath -PathType Leaf) {
        $logRoot = Join-Path $configRoot "installer-logs"
        New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
        Copy-Item -LiteralPath $installerLogPath -Destination (Join-Path $logRoot "latest-msi.log") -Force
    }
}

function Find-PubtoInstall {
    param([string]$PreferredRoot = "")
    $candidates = @()
    if ($PreferredRoot) { $candidates += $PreferredRoot }
    $candidates += @(
        (Join-Path $env:LOCALAPPDATA "Programs\Pubto"),
        (Join-Path $env:ProgramFiles "Pubto"),
        (Join-Path $env:LOCALAPPDATA "Pubto")
    )
    return $candidates | Select-Object -Unique | Where-Object {
        Test-Path -LiteralPath (Join-Path $_ "Pubto.exe") -PathType Leaf
    } | Select-Object -First 1
}

function Stop-PubtoProcesses {
    Get-Process -Name "Pubto", "pubto-agent" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    foreach ($attempt in 1..20) {
        $running = Get-Process -Name "Pubto", "pubto-agent" -ErrorAction SilentlyContinue
        if (-not $running) { return }
        Start-Sleep -Milliseconds 250
    }
    Get-Process -Name "Pubto", "pubto-agent" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Copy-Directory {
    param([string]$Source, [string]$Destination)
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | Copy-Item -Destination $Destination -Recurse -Force
}

function Restore-Previous {
    if (-not $rollbackArmed -or $rollbackDone) { return }
    $rollbackDone = $true
    Stop-PubtoProcesses
    $failedInstallRoot = Find-PubtoInstall $installedInstallRoot
    if ($failedInstallRoot -and (Test-Path -LiteralPath $failedInstallRoot)) {
        Remove-Item -LiteralPath $failedInstallRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($previousInstallRoot -and (Test-Path -LiteralPath $backupInstallRoot)) {
        New-Item -ItemType Directory -Path (Split-Path -Parent $previousInstallRoot) -Force | Out-Null
        Copy-Directory $backupInstallRoot $previousInstallRoot
    }
    if (Test-Path -LiteralPath $configRoot) { Remove-Item -LiteralPath $configRoot -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $backupConfigRoot) { Copy-Directory $backupConfigRoot $configRoot }
    if (Test-Path -LiteralPath $tauriDataRoot) { Remove-Item -LiteralPath $tauriDataRoot -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $backupTauriDataRoot) { Copy-Directory $backupTauriDataRoot $tauriDataRoot }
    $restoredApp = Find-PubtoInstall $previousInstallRoot
    if ($restoredApp) { Start-Process -FilePath (Join-Path $restoredApp "Pubto.exe") }
    Write-Warning "Pubto Desktop installation failed; the previous app and local data were restored."
}

try {
    $manifestPath = Join-Path $workDir "manifest.json"
    if (Test-Path -LiteralPath $Manifest -PathType Leaf) {
        Copy-Item -LiteralPath $Manifest -Destination $manifestPath
    } else {
        $manifestUri = [Uri]$Manifest
        if ($manifestUri.Scheme -ne "https") {
            throw "The release manifest URL must use HTTPS."
        }
        Invoke-WebRequest -UseBasicParsing -Uri $manifestUri -OutFile $manifestPath
    }

    $release = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($release.schemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace([string]$release.version) -or [string]$release.version -notmatch "^[0-9A-Za-z][0-9A-Za-z.+_-]{0,63}$") {
        throw "Invalid release manifest."
    }
    $releaseVersion = [string]$release.version
    $artifact = @($release.artifacts) | Where-Object {
        $_.component -eq "desktop" -and $_.os -eq "windows" -and $_.arch -eq "amd64"
    } | Select-Object -First 1
    if ($null -eq $artifact) {
        throw "No compatible Pubto Desktop artifact is present in the release manifest."
    }
    $artifactUri = [Uri]$artifact.url
    if ($artifactUri.Scheme -ne "https" -or $artifact.sha256 -notmatch "^[0-9a-fA-F]{64}$" -or $artifact.packageType -notin @("nsis", "msi")) {
        throw "The selected Desktop artifact has invalid URL, checksum, or installer metadata."
    }

    Write-Host "Pubto Desktop: Windows x64"
    Write-Host "Package: $($artifact.url)"
    if ($Check) {
        $discovery = Join-Path $configRoot "agent-discovery.json"
        if (Test-Path -LiteralPath $discovery -PathType Leaf) {
            try {
                $agent = Get-Content -LiteralPath $discovery -Raw | ConvertFrom-Json
                $agentUri = [Uri]$agent.url
                if ($agentUri.Scheme -eq "http" -and $agentUri.Port -gt 0 -and $agentUri.Host -in @("127.0.0.1", "localhost", "::1")) {
                    $health = Invoke-RestMethod -Method Get -Uri ($agentUri.AbsoluteUri.TrimEnd("/") + "/v1/health")
                    if ($health.status -eq "ok" -and $health.component -eq "pubto-agent") {
                        if ([string]$health.version -eq $releaseVersion) { Write-Host "Pubto Desktop is up to date ($releaseVersion)." }
                        else { Write-Host "Pubto Desktop update available: $releaseVersion (installed $($health.version))." }
                        return
                    }
                }
            } catch { }
        }
        Write-Host "Pubto Desktop is not installed or its local Agent is not running."
        return
    }
    if ($DryRun) {
        Write-Host "Dry run complete; no package was downloaded or installed."
        return
    }

    if (-not $Yes) {
        $answer = Read-Host "Install or upgrade Pubto Desktop for this user? [y/N]"
        if ($answer -notin @("y", "Y")) { return }
    }

    $installPhase = "download"
    $extension = if ($artifact.packageType -eq "msi") { ".msi" } else { ".exe" }
    $packagePath = Join-Path $workDir ("Pubto-Setup" + $extension)
    Invoke-WebRequest -UseBasicParsing -Uri $artifactUri -OutFile $packagePath
    $installPhase = "checksum"
    $actualSha = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha -ne $artifact.sha256.ToLowerInvariant()) {
        throw "Pubto Desktop checksum verification failed."
    }

    $installPhase = "backup"
    Stop-PubtoProcesses
    $previousInstallRoot = Find-PubtoInstall
    if ($previousInstallRoot) {
        Copy-Directory $previousInstallRoot $backupInstallRoot
    }
    if (Test-Path -LiteralPath $configRoot -PathType Container) {
        Copy-Directory $configRoot $backupConfigRoot
    }
    if (Test-Path -LiteralPath $tauriDataRoot -PathType Container) {
        Copy-Directory $tauriDataRoot $backupTauriDataRoot
    }
    $rollbackArmed = $true

    $installPhase = "package"
    if ($artifact.packageType -eq "msi") {
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList @("/i", $packagePath, "/qn", "/norestart", "/l*v", $installerLogPath) -Wait -PassThru
    } else {
        $process = Start-Process -FilePath $packagePath -ArgumentList @("/S") -Wait -PassThru
    }
    if ($process.ExitCode -ne 0) {
        throw "Pubto Desktop installer exited with code $($process.ExitCode)."
    }

    $installPhase = "launch"
    $installedInstallRoot = Find-PubtoInstall
    if (-not $installedInstallRoot) { throw "Pubto.exe was not found in a supported installation directory." }
    $desktopApp = Join-Path $installedInstallRoot "Pubto.exe"
    Start-Process -FilePath $desktopApp

    $installPhase = "agent_health"
    $discovery = Join-Path $configRoot "agent-discovery.json"
    foreach ($attempt in 1..60) {
        if (Test-Path -LiteralPath $discovery -PathType Leaf) {
            try {
                $agent = Get-Content -LiteralPath $discovery -Raw | ConvertFrom-Json
                $agentUri = [Uri]$agent.url
                if ($agentUri.Scheme -eq "http" -and $agentUri.Port -gt 0 -and $agentUri.Host -in @("127.0.0.1", "localhost", "::1")) {
                    $health = Invoke-RestMethod -Method Get -Uri ($agentUri.AbsoluteUri.TrimEnd("/") + "/v1/health")
                    if ($health.status -eq "ok" -and $health.component -eq "pubto-agent" -and $health.version -eq $releaseVersion) {
                        $rollbackArmed = $false
                        Write-Host "Pubto Desktop is installed and its local Agent is ready."
                        return
                    }
                }
            } catch {
                # Retry while Desktop starts and rewrites discovery atomically.
            }
        }
        Start-Sleep -Seconds 1
    }
    throw "Pubto Desktop was installed, but the local Agent did not become ready within 60 seconds."
} catch {
    $failure = $_
    if ($rollbackArmed) {
        Restore-Previous
    }
    try { Write-InstallerDiagnostic } catch { Write-Warning "Could not preserve the installer diagnostic marker." }
    throw $failure
} finally {
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
}
