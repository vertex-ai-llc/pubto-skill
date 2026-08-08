[CmdletBinding()]
param(
    [string]$Manifest = "https://pubto.dev/downloads/manifest.json",
    [switch]$Yes,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

if (-not $IsWindows) {
    throw "This installer supports Windows. Use install-desktop.sh on macOS."
}
if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne [System.Runtime.InteropServices.Architecture]::X64) {
    throw "Pubto Desktop currently supports Windows x64."
}

$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("pubto-install-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $workDir | Out-Null
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
    $artifact = @($release.artifacts) | Where-Object {
        $_.component -eq "desktop" -and $_.os -eq "windows" -and $_.arch -eq "amd64"
    } | Select-Object -First 1
    if ($null -eq $artifact) {
        throw "No compatible Pubto Desktop artifact is present in the release manifest."
    }
    if ([Uri]$artifact.url).Scheme -ne "https" -or $artifact.sha256 -notmatch "^[0-9a-fA-F]{64}$" -or $artifact.packageType -notin @("nsis", "msi")) {
        throw "The selected Desktop artifact has invalid URL, checksum, or installer metadata."
    }

    Write-Host "Pubto Desktop: Windows x64"
    Write-Host "Package: $($artifact.url)"
    if ($DryRun) {
        Write-Host "Dry run complete; no package was downloaded or installed."
        return
    }

    if (-not $Yes) {
        $answer = Read-Host "Install or upgrade Pubto Desktop for this user? [y/N]"
        if ($answer -notin @("y", "Y")) { return }
    }

    $extension = if ($artifact.packageType -eq "msi") { ".msi" } else { ".exe" }
    $packagePath = Join-Path $workDir ("Pubto-Setup" + $extension)
    Invoke-WebRequest -UseBasicParsing -Uri ([Uri]$artifact.url) -OutFile $packagePath
    $actualSha = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha -ne $artifact.sha256.ToLowerInvariant()) {
        throw "Pubto Desktop checksum verification failed."
    }

    if ($artifact.packageType -eq "msi") {
        $process = Start-Process -FilePath "msiexec.exe" -ArgumentList @("/i", $packagePath) -Wait -PassThru
    } else {
        $process = Start-Process -FilePath $packagePath -Wait -PassThru
    }
    if ($process.ExitCode -ne 0) {
        throw "Pubto Desktop installer exited with code $($process.ExitCode)."
    }

    $candidateApps = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Pubto\Pubto.exe"),
        (Join-Path $env:ProgramFiles "Pubto\Pubto.exe")
    )
    $desktopApp = $candidateApps | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if ($desktopApp) { Start-Process -FilePath $desktopApp }

    $discovery = Join-Path $env:APPDATA "pubto\agent-discovery.json"
    foreach ($attempt in 1..30) {
        if (Test-Path -LiteralPath $discovery -PathType Leaf) {
            try {
                $agent = Get-Content -LiteralPath $discovery -Raw | ConvertFrom-Json
                $agentUri = [Uri]$agent.url
                if ($agentUri.Scheme -eq "http" -and $agentUri.Host -in @("127.0.0.1", "localhost", "[::1]")) {
                    Invoke-RestMethod -Method Get -Uri ($agent.url.TrimEnd("/") + "/v1/health") | Out-Null
                    Write-Host "Pubto Desktop is installed and its local Agent is ready."
                    return
                }
            } catch {
                # Retry while Desktop starts and rewrites discovery atomically.
            }
        }
        Start-Sleep -Seconds 1
    }
    throw "Pubto Desktop was installed, but the local Agent did not become ready within 30 seconds."
} finally {
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
}
