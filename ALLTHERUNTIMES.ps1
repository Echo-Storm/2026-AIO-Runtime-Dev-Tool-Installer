#requires -Version 5.1
# ============================================================
#  Universal Runtime & Dev Tool Installer
#  Written by XechostormX
#  Run via RUN_ME.bat (handles elevation)
# ============================================================

param(
    [switch]$DryRun
)

$ErrorActionPreference = "Continue"

# Fresh Windows installs / WinPS 5.1 sometimes negotiate TLS 1.0 by default,
# which several of the download hosts below reject outright.
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------
# PATHS
# ---------------------------------------------------------------------------
$Base        = $PSScriptRoot
$TempDL      = Join-Path $Base "temp_installers"
$LogFile     = Join-Path $Base "RuntimeInstall_Log_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"
$SevenZipExe = Join-Path $TempDL "7za.exe"

if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path $TempDL | Out-Null
}

# ---------------------------------------------------------------------------
# LOGGING
# ---------------------------------------------------------------------------
function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts - $msg"
    $line | Out-File -FilePath $LogFile -Append -Encoding utf8
    Write-Host $line
}

function Log-Status($msg)  { Log "[....] $msg" }
function Log-Success($msg) { Log "[ OK ] $msg" }
function Log-Skip($msg)    { Log "[SKIP] $msg" }
function Log-Fail($msg)    { Log "[FAIL] $msg" }
function Log-Dry($msg)     { Log "[ DRY] $msg" }

# ---------------------------------------------------------------------------
# TRACKING
# ---------------------------------------------------------------------------
$installed = [System.Collections.Generic.List[string]]::new()
$skipped   = [System.Collections.Generic.List[string]]::new()
$failed    = [System.Collections.Generic.List[string]]::new()

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------
function Get-File($url, $name) {
    $path = Join-Path $TempDL $name
    if ($DryRun) {
        Log-Dry "Would download: $name  <-  $url"
        return $path
    }
    if (Test-Path $path -PathType Leaf) {
        Log-Status "Cached: $name"
        return $path
    }
    Log-Status "Downloading $name..."
    for ($i = 1; $i -le 3; $i++) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing -ErrorAction Stop
            # Sanity check: a redirect to an error/landing page instead of the real
            # binary shows up as a suspiciously tiny file, not a request exception.
            if ((Get-Item $path).Length -lt 10KB) {
                throw "Downloaded file is implausibly small ($((Get-Item $path).Length) bytes) - likely not the real installer"
            }
            Log-Success "Downloaded: $name"
            return $path
        } catch {
            Log-Fail "Attempt $i failed: $($_.Exception.Message)"
            Remove-Item $path -Force -ErrorAction SilentlyContinue
            if ($i -lt 3) { Start-Sleep -Seconds 5 }
        }
    }
    Log-Fail "Download failed after 3 attempts: $name"
    return $null
}

# Warn-only: some legitimate tools (7za.exe) ship unsigned, so an invalid/missing
# signature isn't treated as a hard failure - just surfaced so it's not silent.
function Test-Signature($path, $name) {
    try {
        $sig = Get-AuthenticodeSignature -FilePath $path -ErrorAction Stop
        if ($sig.Status -ne 'Valid') {
            Log-Status "WARNING: $name is not Authenticode-signed (status: $($sig.Status)) - proceeding anyway"
        }
    } catch { }
}

function Run-Exe($path, $argStr, $name) {
    if ($DryRun) {
        Log-Dry "Would run: $name  ($path $argStr)"
        return $true
    }
    if (-not (Test-Path $path)) { Log-Fail "Missing: $path"; return $false }
    Test-Signature $path $name
    Log-Status "Running: $name"
    try {
        $p = Start-Process -FilePath $path -ArgumentList $argStr -Wait -PassThru -NoNewWindow
        Log "       Exit code: $($p.ExitCode)"
        return ($p.ExitCode -in 0, 3010, 1641, 1638)
    } catch {
        Log-Fail "Exception: $($_.Exception.Message)"
        return $false
    }
}

function Run-Msi($path, $argStr, $name) {
    if ($DryRun) {
        Log-Dry "Would run MSI: $name  ($path $argStr)"
        return $true
    }
    if (-not (Test-Path $path)) { Log-Fail "Missing: $path"; return $false }
    Test-Signature $path $name
    Log-Status "Running MSI: $name"
    try {
        $p = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$path`" $argStr" -Wait -PassThru -NoNewWindow
        Log "       Exit code: $($p.ExitCode)"
        return ($p.ExitCode -in 0, 3010, 1641, 1638)
    } catch {
        Log-Fail "Exception: $($_.Exception.Message)"
        return $false
    }
}

# Runs -Install only if -IsInstalled says it's missing, then re-runs -IsInstalled
# afterward so "installed" always means "verified present", not just "exit code
# looked fine". This is the piece the old script got wrong: it trusted installer
# exit codes alone and could report success when nothing actually landed.
function Install-Component {
    param(
        [Parameter(Mandatory)] [string]$Name,
        [Parameter(Mandatory)] [scriptblock]$IsInstalled,
        [Parameter(Mandatory)] [scriptblock]$Install
    )
    $already = $false
    try { $already = [bool](& $IsInstalled) } catch { $already = $false }

    if ($already) {
        Log-Skip "$Name already installed"
        $script:skipped.Add($Name)
        return
    }

    $ranOk = $false
    try { $ranOk = [bool](& $Install) } catch {
        Log-Fail "$Name threw an exception: $($_.Exception.Message)"
        $script:failed.Add($Name)
        return
    }

    if (-not $ranOk) {
        Log-Fail "$Name install step failed (download or installer error)"
        $script:failed.Add($Name)
        return
    }

    if ($DryRun) {
        Log-Dry "Skipping post-install verification for $Name (dry run)"
        $script:installed.Add($Name)
        return
    }

    $nowInstalled = $false
    try { $nowInstalled = [bool](& $IsInstalled) } catch { $nowInstalled = $false }

    if ($nowInstalled) {
        Log-Success "$Name installed"
        $script:installed.Add($Name)
    } else {
        Log-Fail "$Name installer exited cleanly but could not be verified afterward (may need a reboot to finish)"
        $script:failed.Add($Name)
    }
}

# Looks up the newest GitHub release asset matching a filename pattern, falling
# back to a pinned known-good URL/version if the API is unreachable or rate-limited.
function Get-LatestGitHubAsset {
    param(
        [Parameter(Mandatory)] [string]$Repo,
        [Parameter(Mandatory)] [string]$AssetPattern,
        [Parameter(Mandatory)] [string]$FallbackUrl,
        [Parameter(Mandatory)] [string]$FallbackVersion
    )
    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
                                  -Headers @{ "User-Agent" = "AIO-Runtime-Installer" } -ErrorAction Stop
        $asset = $rel.assets | Where-Object { $_.name -match $AssetPattern } | Select-Object -First 1
        if ($asset) {
            return @{ Url = $asset.browser_download_url; Version = $rel.tag_name.TrimStart('v'); FileName = $asset.name }
        }
        Log-Status "$Repo latest release had no asset matching '$AssetPattern'; using pinned fallback"
    } catch {
        Log-Status "Could not query GitHub for $Repo latest release ($($_.Exception.Message)); using pinned fallback"
    }
    return @{ Url = $FallbackUrl; Version = $FallbackVersion; FileName = ($FallbackUrl -split '/')[-1] }
}

# ---------------------------------------------------------------------------
# HEADER
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Universal Runtime & Dev Tool Installer" -ForegroundColor Cyan
Write-Host "  $(Get-Date)" -ForegroundColor Yellow
if ($DryRun) {
    Write-Host "  DRY RUN - nothing will actually be downloaded or installed" -ForegroundColor Magenta
}
Write-Host "  Log: $LogFile" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Log "Started. Base=$Base TempDL=$TempDL DryRun=$($DryRun.IsPresent)"

# ---------------------------------------------------------------------------
# WINGET
# ---------------------------------------------------------------------------
Write-Host "`n--- winget ---" -ForegroundColor Cyan
Install-Component -Name "winget" `
    -IsInstalled { [bool](Get-Command winget -ErrorAction SilentlyContinue) } `
    -Install {
        $file = Get-File "https://aka.ms/getwinget" "Microsoft.DesktopAppInstaller.msixbundle"
        if (-not $file) { return $false }
        if ($DryRun) { Log-Dry "Would Add-AppxPackage $file"; return $true }
        try {
            Add-AppxPackage -Path $file -ErrorAction Stop
        } catch {
            Log-Status "Direct winget install failed ($($_.Exception.Message)); fetching dependency bundle and retrying..."
            $deps = Get-File "https://github.com/microsoft/winget-cli/releases/latest/download/DesktopAppInstaller_Dependencies.zip" "DesktopAppInstaller_Dependencies.zip"
            if (-not $deps) { return $false }
            try {
                $depDir = Join-Path $TempDL "winget_deps"
                Expand-Archive -Path $deps -DestinationPath $depDir -Force
                Get-ChildItem $depDir -Recurse -Filter "*x64.appx" | ForEach-Object {
                    Add-AppxPackage -Path $_.FullName -ErrorAction SilentlyContinue
                }
                Add-AppxPackage -Path $file -ErrorAction Stop
            } catch {
                Log-Fail "winget dependency retry failed: $($_.Exception.Message)"
                return $false
            }
        }
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")
        return $true
    }

# ---------------------------------------------------------------------------
# 7-ZIP PORTABLE
# ---------------------------------------------------------------------------
Write-Host "`n--- 7-Zip portable (tool) ---" -ForegroundColor Cyan
Install-Component -Name "7-Zip portable" `
    -IsInstalled { Test-Path $SevenZipExe } `
    -Install {
        $zip = Get-File "https://www.7-zip.org/a/7za920.zip" "7za_bootstrap.zip"
        if (-not $zip) { return $false }
        if ($DryRun) { return $true }
        Expand-Archive $zip $TempDL -Force
        return (Test-Path $SevenZipExe)
    }

# ---------------------------------------------------------------------------
# .NET FRAMEWORK 3.5
# ---------------------------------------------------------------------------
Write-Host "`n--- .NET Framework 3.5 ---" -ForegroundColor Cyan
$reg35 = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5"
Install-Component -Name ".NET Framework 3.5" `
    -IsInstalled { (Test-Path $reg35) -and (Get-ItemProperty $reg35 -Name Version -ErrorAction SilentlyContinue).Version } `
    -Install {
        if ($DryRun) { Log-Dry "Would enable NetFx3 Windows feature"; return $true }
        try {
            Enable-WindowsOptionalFeature -Online -FeatureName "NetFx3" -All -NoRestart | Out-Null
            return $true
        } catch {
            Log-Fail "Failed: $($_.Exception.Message)"
            return $false
        }
    }

# ---------------------------------------------------------------------------
# DIRECTX JUNE 2010
# ---------------------------------------------------------------------------
Write-Host "`n--- DirectX June 2010 ---" -ForegroundColor Cyan
Install-Component -Name "DirectX June 2010" `
    -IsInstalled { Test-Path "$env:SystemRoot\System32\d3dx9_43.dll" } `
    -Install {
        $dx = Get-File "https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe" "directx_Jun2010_redist.exe"
        if (-not $dx) { return $false }
        if (-not (Test-Path $SevenZipExe) -and -not $DryRun) { Log-Fail "7za.exe missing, cannot extract DirectX"; return $false }
        if ($DryRun) { return $true }
        $dxTemp = Join-Path $TempDL "dx_extract"
        New-Item -ItemType Directory -Force -Path $dxTemp | Out-Null
        & $SevenZipExe x "$dx" -o"$dxTemp" -y | Out-Null
        $setup = Join-Path $dxTemp "DXSETUP.exe"
        if (-not (Test-Path $setup)) { Log-Fail "DXSETUP.exe not found in archive"; return $false }
        return (Run-Exe $setup "/silent" "DirectX June 2010")
    }

# ---------------------------------------------------------------------------
# LEGACY OPENAL
# ---------------------------------------------------------------------------
Write-Host "`n--- Legacy OpenAL ---" -ForegroundColor Cyan
Install-Component -Name "Legacy OpenAL" `
    -IsInstalled { Test-Path "HKLM:\SOFTWARE\Creative Labs\OpenAL" } `
    -Install {
        $zip = Get-File "https://openal.org/downloads/oalinst.zip" "oalinst.zip"
        if (-not $zip) { return $false }
        if ($DryRun) { return $true }
        Expand-Archive -Path $zip -DestinationPath "$TempDL\oal_legacy" -Force
        $exe = "$TempDL\oal_legacy\oalinst.exe"
        if (-not (Test-Path $exe)) { Log-Fail "oalinst.exe not found"; return $false }
        return (Run-Exe $exe "/S" "Legacy OpenAL")
    }

# ---------------------------------------------------------------------------
# OPENAL SOFT
# ---------------------------------------------------------------------------
Write-Host "`n--- OpenAL Soft ---" -ForegroundColor Cyan
Install-Component -Name "OpenAL Soft" `
    -IsInstalled { (Test-Path "$env:SystemRoot\System32\OpenAL32.dll") -and (Test-Path "$env:SystemRoot\SysWOW64\OpenAL32.dll") } `
    -Install {
        $zip = Get-File "https://openal-soft.org/openal-binaries/openal-soft-1.25.1-bin.zip" "openal-soft-latest-bin.zip"
        if (-not $zip) { return $false }
        if ($DryRun) { return $true }
        Expand-Archive -Path $zip -DestinationPath "$TempDL\oal_soft" -Force
        $dll64 = Get-ChildItem "$TempDL\oal_soft" -Recurse -Filter "soft_oal.dll" |
                 Where-Object { $_.DirectoryName -like "*Win64*" } | Select-Object -First 1 -ExpandProperty FullName
        $dll32 = Get-ChildItem "$TempDL\oal_soft" -Recurse -Filter "soft_oal.dll" |
                 Where-Object { $_.DirectoryName -like "*Win32*" } | Select-Object -First 1 -ExpandProperty FullName
        if (-not ($dll64 -and $dll32)) { Log-Fail "soft_oal.dll not found in expected paths"; return $false }
        try {
            Copy-Item $dll64 "$env:SystemRoot\System32\OpenAL32.dll" -Force -ErrorAction Stop
            Copy-Item $dll32 "$env:SystemRoot\SysWOW64\OpenAL32.dll" -Force -ErrorAction Stop
            return $true
        } catch {
            Log-Fail "Copy-Item failed: $($_.Exception.Message)"
            return $false
        }
    }

# ---------------------------------------------------------------------------
# VISUAL C++ REDISTRIBUTABLES
# ---------------------------------------------------------------------------
Write-Host "`n--- Visual C++ Redistributables ---" -ForegroundColor Cyan

$vcDefs = @(
    @{ Key="2005_x86"; Base="8.0";  Flags="/q:a";                Url="https://download.microsoft.com/download/8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A/vcredist_x86.exe" }
    @{ Key="2005_x64"; Base="8.0";  Flags="/q:a";                Url="https://download.microsoft.com/download/8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A/vcredist_x64.exe" }
    @{ Key="2008_x86"; Base="9.0";  Flags="/q";                  Url="https://download.microsoft.com/download/5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE/vcredist_x86.exe" }
    @{ Key="2008_x64"; Base="9.0";  Flags="/q";                  Url="https://download.microsoft.com/download/5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE/vcredist_x64.exe" }
    @{ Key="2010_x86"; Base="10.0"; Flags="/q";                  Url="https://catalog.s.download.windowsupdate.com/msdownload/update/software/secu/2011/07/vcredist_x86_28c54491be70c38c97849c3d8cfbfdd0d3c515cb.exe" }
    @{ Key="2010_x64"; Base="10.0"; Flags="/q";                  Url="https://catalog.s.download.windowsupdate.com/msdownload/update/software/secu/2011/07/vcredist_x64_15d032d669078aa6f0f7fd1cbf4115a070bd034d.exe" }
    @{ Key="2012_x86"; Base="11.0"; Flags="/passive /norestart"; Url="https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/vcredist_x86.exe" }
    @{ Key="2012_x64"; Base="11.0"; Flags="/passive /norestart"; Url="https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/vcredist_x64.exe" }
    @{ Key="2013_x86"; Base="12.0"; Flags="/passive /norestart"; Url="https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x86.exe" }
    @{ Key="2013_x64"; Base="12.0"; Flags="/passive /norestart"; Url="https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe" }
    @{ Key="2015-2022_x86"; Base="14.0"; Flags="/quiet /norestart"; Url="https://aka.ms/vs/17/release/vc_redist.x86.exe" }
    @{ Key="2015-2022_x64"; Base="14.0"; Flags="/quiet /norestart"; Url="https://aka.ms/vs/17/release/vc_redist.x64.exe" }
)

foreach ($vc in $vcDefs) {
    $arch = $vc.Key -replace '^.*_', ''
    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\VisualStudio\$($vc.Base)\VC\VCRedist\$arch",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\$($vc.Base)\VC\VCRedist\$arch"
    )
    Install-Component -Name "VC++ $($vc.Key)" `
        -IsInstalled {
            foreach ($reg in $regPaths) {
                if ((Test-Path $reg) -and (Get-ItemProperty $reg -Name Version -ErrorAction SilentlyContinue).Version) { return $true }
            }
            return $false
        } `
        -Install {
            $file = Get-File $vc.Url "vc_$($vc.Key).exe"
            if (-not $file) { return $false }
            return (Run-Exe $file $vc.Flags "VC++ $($vc.Key)")
        }
}

# ---------------------------------------------------------------------------
# .NET RUNTIMES
# ---------------------------------------------------------------------------
Write-Host "`n--- .NET Runtimes ---" -ForegroundColor Cyan
# .NET 6/7 are past end-of-support (EOL May 2024 / Nov 2024) and intentionally
# omitted. 8 (LTS) and 9 (STS) are current through Nov 2026; 10 is the active LTS.
# Using the aka.ms evergreen links means these never need re-pinning by hand.

$netDefs = @(
    @{ Name=".NET Framework 4.8.1";        File="ndp481.exe";       Flags="/q /norestart";     IsFramework=$true;  MinRelease=528040; Reg="HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full";                                                     Url="https://go.microsoft.com/fwlink/?linkid=2202440" }
    @{ Name=".NET 8 ASP.NET Core Runtime";  File="aspnetcore-8.exe"; Flags="/quiet /norestart"; IsFramework=$false; Ver="8.0";  Reg="HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.AspNetCore.App";    Url="https://aka.ms/dotnet/8.0/aspnetcore-runtime-win-x64.exe" }
    @{ Name=".NET 8 Desktop Runtime";       File="desktop-8.exe";    Flags="/quiet /norestart"; IsFramework=$false; Ver="8.0";  Reg="HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App"; Url="https://aka.ms/dotnet/8.0/windowsdesktop-runtime-win-x64.exe" }
    @{ Name=".NET 9 ASP.NET Core Runtime";  File="aspnetcore-9.exe"; Flags="/quiet /norestart"; IsFramework=$false; Ver="9.0";  Reg="HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.AspNetCore.App";    Url="https://aka.ms/dotnet/9.0/aspnetcore-runtime-win-x64.exe" }
    @{ Name=".NET 9 Desktop Runtime";       File="desktop-9.exe";    Flags="/quiet /norestart"; IsFramework=$false; Ver="9.0";  Reg="HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App"; Url="https://aka.ms/dotnet/9.0/windowsdesktop-runtime-win-x64.exe" }
    @{ Name=".NET 10 ASP.NET Core Runtime"; File="aspnetcore-10.exe";Flags="/quiet /norestart"; IsFramework=$false; Ver="10.0"; Reg="HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.AspNetCore.App";    Url="https://aka.ms/dotnet/10.0/aspnetcore-runtime-win-x64.exe" }
    @{ Name=".NET 10 Desktop Runtime";      File="desktop-10.exe";   Flags="/quiet /norestart"; IsFramework=$false; Ver="10.0"; Reg="HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App"; Url="https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-x64.exe" }
)

foreach ($nd in $netDefs) {
    Install-Component -Name $nd.Name `
        -IsInstalled {
            if (-not (Test-Path $nd.Reg)) { return $false }
            if ($nd.IsFramework) {
                $rel = (Get-ItemProperty $nd.Reg -Name Release -ErrorAction SilentlyContinue).Release
                return ($rel -and $rel -ge $nd.MinRelease)
            }
            return (Test-Path "$($nd.Reg)\$($nd.Ver)")
        } `
        -Install {
            $file = Get-File $nd.Url $nd.File
            if (-not $file) { return $false }
            return (Run-Exe $file $nd.Flags $nd.Name)
        }
}

# ---------------------------------------------------------------------------
# TEMURIN JDK
# ---------------------------------------------------------------------------
Write-Host "`n--- Java (Temurin JDK) ---" -ForegroundColor Cyan
# Pulled from Adoptium's "latest" API so these track new patch releases (CVE
# fixes, etc.) automatically instead of pinning a specific build forever.

$jdkDefs = @(
    @{ Name="Temurin JDK 21"; File="temurin-jdk-21.msi"; Dir="jdk-21"; Url="https://api.adoptium.net/v3/installer/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk" }
    @{ Name="Temurin JDK 17"; File="temurin-jdk-17.msi"; Dir="jdk-17"; Url="https://api.adoptium.net/v3/installer/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk" }
    @{ Name="Temurin JDK 8";  File="temurin-jdk-8.msi";  Dir="jdk-8";  Url="https://api.adoptium.net/v3/installer/latest/8/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk" }
)

foreach ($jd in $jdkDefs) {
    Install-Component -Name $jd.Name `
        -IsInstalled { [bool](Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$($jd.Dir)*" }) } `
        -Install {
            $file = Get-File $jd.Url $jd.File
            if (-not $file) { return $false }
            # INSTALLLEVEL=1 pulls in every optional MSI feature (PATH update,
            # JAVA_HOME, .jar file association) - a bare /quiet install skips all of them.
            return (Run-Msi $file "/quiet /norestart INSTALLLEVEL=1" $jd.Name)
        }
}

# ---------------------------------------------------------------------------
# VULKAN RUNTIME
# ---------------------------------------------------------------------------
Write-Host "`n--- Vulkan Runtime ---" -ForegroundColor Cyan
Install-Component -Name "Vulkan Runtime" `
    -IsInstalled { Test-Path "HKLM:\SOFTWARE\Khronos\Vulkan\Runtime" } `
    -Install {
        $file = Get-File "https://sdk.lunarg.com/sdk/download/latest/windows/vulkan-runtime.exe" "vulkan-runtime.exe"
        if (-not $file) { return $false }
        return (Run-Exe $file "/S" "Vulkan Runtime")
    }

# ---------------------------------------------------------------------------
# WEBVIEW2
# ---------------------------------------------------------------------------
Write-Host "`n--- WebView2 Runtime ---" -ForegroundColor Cyan
Install-Component -Name "WebView2" `
    -IsInstalled { Test-Path "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}" } `
    -Install {
        $file = Get-File "https://go.microsoft.com/fwlink/p/?LinkId=2124703" "MicrosoftEdgeWebview2Setup.exe"
        if (-not $file) { return $false }
        return (Run-Exe $file "/silent /install" "WebView2")
    }

# ---------------------------------------------------------------------------
# POWERSHELL (LATEST)
# ---------------------------------------------------------------------------
Write-Host "`n--- PowerShell 7 ---" -ForegroundColor Cyan
$pwshInfo = Get-LatestGitHubAsset -Repo "PowerShell/PowerShell" -AssetPattern '^PowerShell-[\d.]+-win-x64\.msi$' `
    -FallbackUrl "https://github.com/PowerShell/PowerShell/releases/download/v7.6.1/PowerShell-7.6.1-win-x64.msi" -FallbackVersion "7.6.1"
$pwshExe = "$env:ProgramFiles\PowerShell\7\pwsh.exe"

Install-Component -Name "PowerShell $($pwshInfo.Version)" `
    -IsInstalled {
        if (-not (Test-Path $pwshExe)) { return $false }
        $ver = & $pwshExe -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null
        return ($ver -and ([version]$ver -ge [version]$pwshInfo.Version))
    } `
    -Install {
        $file = Get-File $pwshInfo.Url $pwshInfo.FileName
        if (-not $file) { return $false }
        return (Run-Msi $file "/quiet /norestart ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1 ADD_PATH=1" "PowerShell $($pwshInfo.Version)")
    }

# ---------------------------------------------------------------------------
# PYTHON
# ---------------------------------------------------------------------------
Write-Host "`n--- Python ---" -ForegroundColor Cyan

$pyDefs = @(
    @{ Ver="3.10"; Url="https://www.python.org/ftp/python/3.10.20/python-3.10.20-amd64.exe" }
    @{ Ver="3.11"; Url="https://www.python.org/ftp/python/3.11.15/python-3.11.15-amd64.exe" }
    @{ Ver="3.12"; Url="https://www.python.org/ftp/python/3.12.13/python-3.12.13-amd64.exe" }
    @{ Ver="3.13"; Url="https://www.python.org/ftp/python/3.13.14/python-3.13.14-amd64.exe" }
)

foreach ($py in $pyDefs) {
    $pyDir = "C:\Program Files\Python$($py.Ver -replace '\.', '')"
    Install-Component -Name "Python $($py.Ver)" `
        -IsInstalled { Test-Path "$pyDir\python.exe" } `
        -Install {
            $file = Get-File $py.Url "python-$($py.Ver)-amd64.exe"
            if (-not $file) { return $false }
            return (Run-Exe $file "/quiet InstallAllUsers=1 PrependPath=1 Include_launcher=1" "Python $($py.Ver)")
        }
}

# ---------------------------------------------------------------------------
# GIT (LATEST)
# ---------------------------------------------------------------------------
Write-Host "`n--- Git for Windows ---" -ForegroundColor Cyan
$gitInfo = Get-LatestGitHubAsset -Repo "git-for-windows/git" -AssetPattern '^Git-[\d.]+-64-bit\.exe$' `
    -FallbackUrl "https://github.com/git-for-windows/git/releases/download/v2.54.0.windows.1/Git-2.54.0-64-bit.exe" -FallbackVersion "2.54.0"

Install-Component -Name "Git $($gitInfo.Version)" `
    -IsInstalled { Test-Path "$env:ProgramFiles\Git\bin\git.exe" } `
    -Install {
        $file = Get-File $gitInfo.Url $gitInfo.FileName
        if (-not $file) { return $false }
        return (Run-Exe $file "/VERYSILENT /NORESTART /NOCANCEL /SP- /COMPONENTS=icons,assoc,assoc_sh,gitlfs" "Git $($gitInfo.Version)")
    }

# ---------------------------------------------------------------------------
# NODE.JS (LATEST LTS)
# ---------------------------------------------------------------------------
Write-Host "`n--- Node.js (LTS) ---" -ForegroundColor Cyan
$nodeInfo = $null
try {
    $nodeIndex = Invoke-RestMethod -Uri "https://nodejs.org/dist/index.json" -Headers @{ "User-Agent" = "AIO-Runtime-Installer" } -ErrorAction Stop
    $ltsRow = $nodeIndex | Where-Object { $_.lts -ne $false } | Select-Object -First 1
    if ($ltsRow) {
        $nodeInfo = @{ Version = $ltsRow.version.TrimStart('v'); Url = "https://nodejs.org/dist/$($ltsRow.version)/node-$($ltsRow.version)-x64.msi" }
    }
} catch {
    Log-Status "Could not query Node.js dist index ($($_.Exception.Message)); using pinned fallback"
}
if (-not $nodeInfo) {
    $nodeInfo = @{ Version = "24.18.1"; Url = "https://nodejs.org/dist/v24.18.1/node-v24.18.1-x64.msi" }
}

Install-Component -Name "Node.js $($nodeInfo.Version) (LTS)" `
    -IsInstalled { Test-Path "$env:ProgramFiles\nodejs\node.exe" } `
    -Install {
        $file = Get-File $nodeInfo.Url "node-$($nodeInfo.Version)-x64.msi"
        if (-not $file) { return $false }
        return (Run-Msi $file "/quiet /norestart ADDLOCAL=ALL" "Node.js $($nodeInfo.Version)")
    }

# ---------------------------------------------------------------------------
# CMAKE (LATEST)
# ---------------------------------------------------------------------------
Write-Host "`n--- CMake ---" -ForegroundColor Cyan
$cmakeInfo = Get-LatestGitHubAsset -Repo "Kitware/CMake" -AssetPattern '^cmake-[\d.]+-windows-x86_64\.msi$' `
    -FallbackUrl "https://github.com/Kitware/CMake/releases/download/v4.4.1/cmake-4.4.1-windows-x86_64.msi" -FallbackVersion "4.4.1"

Install-Component -Name "CMake $($cmakeInfo.Version)" `
    -IsInstalled { Test-Path "$env:ProgramFiles\CMake\bin\cmake.exe" } `
    -Install {
        $file = Get-File $cmakeInfo.Url $cmakeInfo.FileName
        if (-not $file) { return $false }
        # ADD_CMAKE_TO_PATH=System is undocumented but stable - it's what CMake's own
        # WiX installer exposes, and what GitHub Actions' runner-images setup uses.
        return (Run-Msi $file "/quiet /norestart ADD_CMAKE_TO_PATH=System" "CMake $($cmakeInfo.Version)")
    }

# ---------------------------------------------------------------------------
# VS CODE
# ---------------------------------------------------------------------------
Write-Host "`n--- Visual Studio Code ---" -ForegroundColor Cyan
Install-Component -Name "VS Code" `
    -IsInstalled { Test-Path "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe" } `
    -Install {
        $file = Get-File "https://aka.ms/win32-x64-user-stable" "VSCodeSetup-x64.exe"
        if (-not $file) { return $false }
        return (Run-Exe $file "/VERYSILENT /NORESTART /MERGETASKS=!runcode" "VS Code")
    }

# ---------------------------------------------------------------------------
# CLEANUP
# ---------------------------------------------------------------------------
Write-Host "`n--- Cleanup ---" -ForegroundColor Cyan
if ($DryRun) {
    Log-Dry "Would remove temp_installers"
} else {
    Log-Status "Removing temp_installers..."
    Remove-Item $TempDL -Recurse -Force -ErrorAction SilentlyContinue
    Log-Success "Done"

    # Keep only the 10 most recent run logs so they don't accumulate forever.
    Get-ChildItem -Path $Base -Filter "RuntimeInstall_Log_*.txt" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -Skip 10 |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
# SUMMARY
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

if ($installed.Count -gt 0) {
    Write-Host "`nInstalled:" -ForegroundColor Green
    $installed | ForEach-Object { Write-Host "  + $_" -ForegroundColor Green }
}
if ($skipped.Count -gt 0) {
    Write-Host "`nSkipped (already present):" -ForegroundColor Yellow
    $skipped | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
}
if ($failed.Count -gt 0) {
    Write-Host "`nFailed:" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  x $_" -ForegroundColor Red }
}

Write-Host ""
Write-Host "Log saved to: $LogFile" -ForegroundColor Cyan
Write-Host ""
Log "Finished. Installed=$($installed.Count) Skipped=$($skipped.Count) Failed=$($failed.Count)"

Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
