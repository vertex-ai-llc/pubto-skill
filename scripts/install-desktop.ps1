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
        process_stop = @("windows_process_stop_failed", "Windows installation could not close the previous Pubto processes")
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
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($programFilesX86) { $candidates += Join-Path $programFilesX86 "Pubto" }
    if ($env:USERPROFILE) { $candidates += Join-Path $env:USERPROFILE "bin" }
    return $candidates | Select-Object -Unique | Where-Object {
        (Test-Path -LiteralPath (Join-Path $_ "pubto-desktop.exe") -PathType Leaf) -or
            (Test-Path -LiteralPath (Join-Path $_ "Pubto.exe") -PathType Leaf)
    } | Select-Object -First 1
}

function Get-PubtoDesktopExecutable {
    param([string]$InstallRoot)
    foreach ($name in @("pubto-desktop.exe", "Pubto.exe")) {
        $candidate = Join-Path $InstallRoot $name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Add-PubtoUserPath {
    param([string]$Directory)
    $fullDirectory = [IO.Path]::GetFullPath($Directory).TrimEnd([char[]]@('\', '/'))
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $parts = @($current -split ';' | Where-Object { $_ -and $_.Trim() })
    $present = @($parts | Where-Object { $_.Trim().TrimEnd([char[]]@('\', '/')) -ieq $fullDirectory })
    if ($present.Count -eq 0) {
        [Environment]::SetEnvironmentVariable('Path', (($parts + $fullDirectory) -join ';'), 'User')
    }
    $updated = [Environment]::GetEnvironmentVariable('Path', 'User')
    $verifiedEntries = @($updated -split ';' | Where-Object { $_.Trim().TrimEnd([char[]]@('\', '/')) -ieq $fullDirectory })
    if ($verifiedEntries.Count -eq 0) {
        throw "Could not add the Pubto command folder to your user PATH."
    }
    $processEntries = @($env:Path -split ';' | Where-Object { $_.Trim().TrimEnd([char[]]@('\', '/')) -ieq $fullDirectory })
    if ($processEntries.Count -eq 0) {
        $env:Path = "$fullDirectory;$env:Path"
    }
    try {
        if (-not ('PubtoEnvironmentBroadcast' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class PubtoEnvironmentBroadcast {
  [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
  public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);
}
'@
        }
        $result = [UIntPtr]::Zero
        [void][PubtoEnvironmentBroadcast]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
    } catch { }
}

function Get-PubtoProcesses {
    $running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $name = [string]$_.Name
        $caption = [string]$_.Caption
        $description = [string]$_.Description
        $executablePath = [string]$_.ExecutablePath
        $commandLine = [string]$_.CommandLine
        $name -match '(?i)^pubto\.exe$' -or
            $name -match '(?i)^pubto-desktop(?:-[^.]+)?\.exe$' -or
            $name -match '(?i)^pubto-agent(?:-[^.]+)?\.exe$' -or
            $caption -eq 'Pubto Agent' -or
            $description -eq 'Pubto Agent' -or
            $executablePath -match '(?i)(?:\\|/)pubto-agent(?:-[^\\/\s"]+)?\.exe' -or
            $commandLine -match '(?i)(?:\\|/)pubto-agent(?:-[^\\/\s"]+)?\.exe'
    })
    $running += @(Get-Process -Name "Pubto", "pubto-desktop", "pubto-agent" -ErrorAction SilentlyContinue)
    # Get-Process/CIM can hide an elevated process from a current-user
    # installer. tasklist is a system utility and still reports its image/PID.
    $tasklist = Join-Path $env:SystemRoot "System32\tasklist.exe"
    if (Test-Path -LiteralPath $tasklist -PathType Leaf) {
        $rows = @(& $tasklist /FO CSV /NH 2>$null)
        foreach ($row in $rows) {
            if ($row -match '"([^"\r\n]*pubto-agent[^"\r\n]*)"\s*,\s*"(\d+)"') {
                $running += [pscustomobject]@{ Name = $Matches[1]; ProcessId = [int]$Matches[2] }
            }
        }
    }
    return @($running | Sort-Object -Property Id, ProcessId -Unique)
}

# taskkill returns a non-zero status when a process is already gone. That is a
# normal upgrade state, not an installer failure. Keep native command output
# and exit status out of PowerShell's terminating error pipeline.
function Invoke-PubtoTaskKill {
    param(
        [string[]]$TaskkillArguments
    )
    $previousErrorPreference = $ErrorActionPreference
    $previousNativePreference = $null
    $hasNativePreference = $false
    $previousLastExitCode = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    $hadLastExitCode = $null -ne $previousLastExitCode
    $savedLastExitCode = if ($hadLastExitCode) { $previousLastExitCode.Value } else { $null }
    $taskkillExitCode = -1
    try {
        $ErrorActionPreference = 'SilentlyContinue'
        $preference = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
        if ($preference) {
            $hasNativePreference = $true
            $previousNativePreference = $preference.Value
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false -Scope Local
        }
        $taskkill = Join-Path $env:SystemRoot "System32\taskkill.exe"
        if (-not (Test-Path -LiteralPath $taskkill -PathType Leaf)) { $taskkill = "taskkill.exe" }
        & $taskkill @TaskkillArguments *> $null
        $taskkillExitCode = $LASTEXITCODE
    } catch {
        # A missing/already-exited process is expected during cleanup.
    } finally {
        if ($hasNativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $previousNativePreference -Scope Local
        }
        if ($hadLastExitCode) {
            Set-Variable -Name LASTEXITCODE -Value $savedLastExitCode -Scope Global
        } else {
            Remove-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
        }
        $ErrorActionPreference = $previousErrorPreference
    }
    return $taskkillExitCode
}

# Image-name termination is not sufficient when Windows has a renamed sidecar
# or another process holds the executable open. Restart Manager is the Windows
# API used by installers to close the owners of a specific executable image.
function Invoke-PubtoRestartManager {
    if (-not $IsWindows -and $env:OS -ne 'Windows_NT') { return }
    try {
        if (-not ('PubtoRestartManager' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class PubtoRestartManager {
  [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
  public static extern int RmStartSession(out uint handle, int flags, string key);

  [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
  public static extern int RmRegisterResources(
    uint handle, uint fileCount, string[] files, uint appCount, IntPtr apps,
    uint serviceCount, string[] services);

  [DllImport("rstrtmgr.dll")]
  public static extern int RmShutdown(uint handle, int flags, IntPtr status);

  [DllImport("rstrtmgr.dll")]
  public static extern int RmEndSession(uint handle);
}
'@
        }
        $files = @(
            Get-PubtoProcesses | ForEach-Object {
                if ($_.ExecutablePath) { [string]$_.ExecutablePath }
            } | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }
        ) | Sort-Object -Unique
        $roots = @(
            (Join-Path $env:LOCALAPPDATA "Programs\Pubto"),
            (Join-Path $env:LOCALAPPDATA "Pubto\bin"),
            (Join-Path $env:ProgramFiles "Pubto"),
            (Join-Path $env:USERPROFILE "bin")
        )
        $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
        if ($programFilesX86) { $roots += Join-Path $programFilesX86 "Pubto" }
        foreach ($root in @($roots | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) })) {
            $files += @(Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '(?i)^pubto(?:-desktop|-agent)?(?:-[^.]+)?\.exe$' } |
                ForEach-Object { $_.FullName })
        }
        $files = @($files | Sort-Object -Unique)
        if ($files.Count -eq 0) { return }
        $session = [uint32]0
        $started = [PubtoRestartManager]::RmStartSession(
            [ref]$session, 0, [guid]::NewGuid().ToString()
        )
        if ($started -ne 0) { return }
        try {
            $registered = [PubtoRestartManager]::RmRegisterResources(
                $session, [uint32]$files.Count, [string[]]$files, 0,
                [IntPtr]::Zero, 0, [string[]]@()
            )
            if ($registered -eq 0) {
                # RmForceShutdown = 1. Only registered Pubto images are
                # eligible for termination.
                [void][PubtoRestartManager]::RmShutdown($session, 1, [IntPtr]::Zero)
            }
        } finally {
            [void][PubtoRestartManager]::RmEndSession($session)
        }
    } catch {
        # Best effort; the bounded taskkill loop remains the final fallback.
    }
}

function Invoke-PubtoImageKill {
    Invoke-PubtoRestartManager
    foreach ($name in @(
        "pubto.exe",
        "pubto-desktop.exe",
        "pubto-desktop*.exe",
        "pubto-desktop-x86_64-pc-windows-msvc.exe",
        "pubto-desktop-aarch64-pc-windows-msvc.exe"
    )) {
        Invoke-PubtoTaskKill -TaskkillArguments @('/IM', $name, '/T', '/F') | Out-Null
    }
    Start-Sleep -Milliseconds 150
    foreach ($name in @(
        "pubto-agent.exe",
        "pubto-agent*.exe",
        "pubto-agent-x86_64-pc-windows-msvc.exe",
        "pubto-agent-aarch64-pc-windows-msvc.exe"
    )) {
        Invoke-PubtoTaskKill -TaskkillArguments @('/IM', $name, '/T', '/F') | Out-Null
    }
    Get-Process -Name "pubto-agent" -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    foreach ($process in @(Get-PubtoProcesses)) {
        $processId = if ($process.ProcessId) { $process.ProcessId } else { $process.Id }
        if ([int]$processId -gt 0) {
            Invoke-PubtoTaskKill -TaskkillArguments @('/PID', ([string][int]$processId), '/T', '/F') | Out-Null
        }
    }
}

function Invoke-PubtoElevatedKill {
    # An old Agent can have been started elevated. Run one complete cleanup
    # pass elevated so a normal-user installer can release the locked image.
    $powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
    $command = @'
$ErrorActionPreference = 'SilentlyContinue'
$taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
if (-not (Test-Path -LiteralPath $taskkill -PathType Leaf)) { $taskkill = 'taskkill.exe' }
foreach ($name in @('pubto.exe', 'pubto-desktop.exe', 'pubto-desktop*.exe')) {
  & $taskkill /IM $name /T /F *> $null
}
Start-Sleep -Milliseconds 150
$targets = @(Get-CimInstance Win32_Process | Where-Object {
  $name = [string]$_.Name
  $caption = [string]$_.Caption
  $description = [string]$_.Description
  $path = [string]$_.ExecutablePath
  $commandLine = [string]$_.CommandLine
  $name -match '(?i)^pubto-agent(?:-[^.]+)?\.exe$' -or
    $caption -eq 'Pubto Agent' -or
    $description -eq 'Pubto Agent' -or
    $path -match '(?i)(?:\\|/)pubto-agent(?:-[^\\/\s"]+)?\.exe' -or
    $commandLine -match '(?i)(?:\\|/)pubto-agent(?:-[^\\/\s"]+)?\.exe'
})
foreach ($target in $targets) {
  Stop-Process -Id ([int]$target.ProcessId) -Force -ErrorAction SilentlyContinue
  & $taskkill /PID ([int]$target.ProcessId) /T /F *> $null
}
foreach ($name in @('pubto-agent.exe', 'pubto-agent*.exe')) {
  & $taskkill /IM $name /T /F *> $null
}
'@
    try {
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        Start-Process -FilePath $powershell -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList @(
            '-NoProfile', '-NonInteractive', '-WindowStyle', 'Hidden', '-EncodedCommand', $encoded
        ) | Out-Null
    } catch {
    # The normal cleanup pass still runs; this is best-effort for non-elevated
    # processes and must not show a second interactive error dialog.
    }
}

function Stop-PubtoProcesses {
    Invoke-PubtoRestartManager
    Invoke-PubtoImageKill
    $elevationAttempted = $false
    $script:installPhase = "process_stop"
    foreach ($attempt in 1..12) {
        $running = @(Get-PubtoProcesses)
        if (-not $running) { return }
        if (-not $elevationAttempted) {
            Invoke-PubtoElevatedKill
            $elevationAttempted = $true
            Start-Sleep -Milliseconds 500
            $running = @(Get-PubtoProcesses)
            if (-not $running) { return }
        }
        foreach ($process in $running) {
            $processId = $process.ProcessId
            if (-not $processId) { $processId = $process.Id }
            $targetPid = [int]$processId
            if ($targetPid -gt 0) {
                Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
                Invoke-PubtoTaskKill -TaskkillArguments @('/PID', ([string]$targetPid), '/T', '/F') | Out-Null
            }
        }
        Invoke-PubtoImageKill
        Invoke-PubtoRestartManager
        Start-Sleep -Milliseconds 500
    }
    Invoke-PubtoImageKill
    Start-Sleep -Milliseconds 500
    $remaining = @(Get-PubtoProcesses)
    if ($remaining) {
        foreach ($process in $remaining) {
            $processId = if ($process.ProcessId) { $process.ProcessId } else { $process.Id }
            if ([int]$processId -gt 0) {
                Invoke-PubtoTaskKill -TaskkillArguments @('/PID', ([string][int]$processId), '/T', '/F') | Out-Null
            }
        }
    }
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
    $restoredInstall = Find-PubtoInstall $previousInstallRoot
    $restoredApp = if ($restoredInstall) { Get-PubtoDesktopExecutable $restoredInstall }
    if ($restoredApp) { Start-Process -FilePath $restoredApp }
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
        $_.component -eq "desktop" -and
        ($_.os -eq "windows" -or $_.os -eq "win32") -and
        ([string]$_.arch).ToLowerInvariant() -in @("x64", "amd64", "x86_64") -and
        ([string]$_.packageType).ToLowerInvariant() -in @("nsis", "msi", "exe")
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
    if (-not $installedInstallRoot) { throw "The Pubto Desktop app was not found in a supported installation directory." }
    $desktopApp = Get-PubtoDesktopExecutable $installedInstallRoot
    if (-not $desktopApp) { throw "The Pubto Desktop app could not be located after installation." }

    # The Desktop package carries the matching CLI sidecar.  Install it in
    # the stable per-user bin directory so Skill setup is complete in one
    # confirmation and does not depend on the installer's versioned folder.
    $cliDestination = Join-Path $env:LOCALAPPDATA "Pubto\bin\pubto.exe"
    $cliMarker = Join-Path $env:LOCALAPPDATA "Pubto\bin\.pubto-cli-managed.json"
    # Tauri keeps external binaries with their target triple in packaged
    # installers (for example pubto-cli-x86_64-pc-windows-msvc.exe), while
    # older packages used the unqualified name. Accept both layouts and look
    # only for the CLI sidecar, never the Desktop executable itself.
    $cliSource = @(
        (Join-Path $installedInstallRoot "pubto-cli.exe"),
        (Join-Path $installedInstallRoot "pubto-cli-x86_64-pc-windows-msvc.exe"),
        (Join-Path $installedInstallRoot "resources\pubto-cli.exe"),
        (Join-Path $installedInstallRoot "resources\pubto-cli-x86_64-pc-windows-msvc.exe")
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $cliSource) {
        $cliSource = Get-ChildItem -LiteralPath $installedInstallRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^pubto-cli(?:[-.]|$).*\.exe$' } |
            Select-Object -ExpandProperty FullName -First 1
    }
    if ($cliSource) {
        if ((Test-Path -LiteralPath $cliDestination -PathType Leaf) -and -not (Test-Path -LiteralPath $cliMarker -PathType Leaf)) {
            throw "An existing Pubto command is not managed by this installation; it was left unchanged."
        } else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $cliDestination) -Force | Out-Null
            $cliTemp = "$cliDestination.pubto-install.tmp"
            Copy-Item -LiteralPath $cliSource -Destination $cliTemp -Force
            $cliVersion = (& $cliTemp version 2>&1 | Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or $cliVersion -ne $releaseVersion) {
                Remove-Item -LiteralPath $cliTemp -Force -ErrorAction SilentlyContinue
                throw "The Pubto command did not pass its version check."
            }
            $cliHelp = (& $cliTemp help 2>&1 | Out-String)
            if ($LASTEXITCODE -ne 0 -or $cliHelp -notmatch 'pubto publish') {
                Remove-Item -LiteralPath $cliTemp -Force -ErrorAction SilentlyContinue
                throw "The Pubto command did not pass its command check."
            }
            Move-Item -LiteralPath $cliTemp -Destination $cliDestination -Force
            Add-PubtoUserPath (Split-Path -Parent $cliDestination)
            $marker = @{ version = $releaseVersion; source = "desktop-bundle"; path = $cliDestination; pathConfigured = $true } | ConvertTo-Json -Compress
            [IO.File]::WriteAllText($cliMarker, $marker, [Text.UTF8Encoding]::new($false))
        }
    } else {
        throw "The Desktop package does not contain its matching Pubto CLI. Re-download the official package and try again."
    }
    $resolvedCommand = Get-Command pubto -ErrorAction SilentlyContinue
    if (-not $resolvedCommand -or [IO.Path]::GetFullPath($resolvedCommand.Source) -ine [IO.Path]::GetFullPath($cliDestination)) {
        throw "The Pubto command was installed, but this session cannot resolve it from PATH."
    }
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
                        $resolvedCommand = Get-Command pubto -ErrorAction SilentlyContinue
                        if (-not $resolvedCommand -or $resolvedCommand.Source -ine $cliDestination) {
                            throw "The Pubto command was installed, but this session cannot resolve it from PATH."
                        }
                        Write-Host "Pubto Desktop and the Pubto command are installed and verified."
                        Write-Host "Open a new terminal or restart your AI CLI before running pubto."
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
