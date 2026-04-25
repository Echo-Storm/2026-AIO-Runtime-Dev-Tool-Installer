#requires -Version 5.1
# ============================================================
#  Universal Runtime & Dev Tool Installer
#  Written by XechostormX
#  Run via RUN_ME.bat (handles elevation)
# ============================================================

$ErrorActionPreference = "Continue"

# ---------------------------------------------------------------------------
# PATHS
# ---------------------------------------------------------------------------
$Base        = $PSScriptRoot
$TempDL      = Join-Path $Base "temp_installers"
$LogFile     = Join-Path $Base "RuntimeInstall_Log_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"
$SevenZipExe = Join-Path $TempDL "7za.exe"

New-Item -ItemType Directory -Force -Path $TempDL | Out-Null

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
    if (Test-Path $path -PathType Leaf) {
        Log-Status "Cached: $name"
        return $path
    }
    Log-Status "Downloading $name..."
    for ($i = 1; $i -le 3; $i++) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing -ErrorAction Stop
            Log-Success "Downloaded: $name"
            return $path
        } catch {
            Log-Fail "Attempt $i failed: $($_.Exception.Message)"
            if ($i -lt 3) { Start-Sleep -Seconds 5 }
        }
    }
    Log-Fail "Download failed after 3 attempts: $name"
    return $null
}

function Run-Exe($path, $args, $name) {
    if (-not (Test-Path $path)) { Log-Fail "Missing: $path"; return $false }
    Log-Status "Running: $name"
    try {
        $p = Start-Process -FilePath $path -ArgumentList $args -Wait -PassThru -NoNewWindow
        Log "       Exit code: $($p.ExitCode)"
        return ($p.ExitCode -in 0, 3010, 1641, 1638)
    } catch {
        Log-Fail "Exception: $($_.Exception.Message)"
        return $false
    }
}

function Run-Msi($path, $args, $name) {
    if (-not (Test-Path $path)) { Log-Fail "Missing: $path"; return $false }
    Log-Status "Running MSI: $name"
    try {
        $p = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$path`" $args" -Wait -PassThru -NoNewWindow
        Log "       Exit code: $($p.ExitCode)"
        return ($p.ExitCode -in 0, 3010, 1641, 1638)
    } catch {
        Log-Fail "Exception: $($_.Exception.Message)"
        return $false
    }
}

# ---------------------------------------------------------------------------
# HEADER
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "  Universal Runtime & Dev Tool Installer" -ForegroundColor Cyan
Write-Host "  $(Get-Date)" -ForegroundColor Yellow
Write-Host "  Log: $LogFile" -ForegroundColor Yellow
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""
Log "Started. Base=$Base TempDL=$TempDL"

# ---------------------------------------------------------------------------
# WINGET
# ---------------------------------------------------------------------------
Write-Host "`n--- winget ---" -ForegroundColor Cyan
$cmd = Get-Command winget -ErrorAction SilentlyContinue
if ($cmd) {
    Log-Skip "winget already present at $($cmd.Source)"
    $skipped.Add("winget")
} else {
    Log-Status "winget not found - installing App Installer..."
    $file = Get-File "https://aka.ms/getwinget" "Microsoft.DesktopAppInstaller.msixbundle"
    if ($file) {
        try {
            Add-AppxPackage -Path $file -ErrorAction Stop
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                        [System.Environment]::GetEnvironmentVariable("Path","User")
            Log-Success "winget installed"
            $installed.Add("winget")
        } catch {
            Log-Fail "App Installer failed: $($_.Exception.Message)"
            $failed.Add("winget")
        }
    } else { $failed.Add("winget") }
}

# ---------------------------------------------------------------------------
# 7-ZIP PORTABLE
# ---------------------------------------------------------------------------
Write-Host "`n--- 7-Zip portable (tool) ---" -ForegroundColor Cyan
if (Test-Path $SevenZipExe) {
    Log-Skip "7za.exe already present"
    $skipped.Add("7-Zip portable")
} else {
    $zip = Get-File "https://www.7-zip.org/a/7za920.zip" "7za_bootstrap.zip"
    if ($zip) {
        Expand-Archive $zip $TempDL -Force
        if (Test-Path "$TempDL\7za.exe") {
            Log-Success "7za.exe ready"
            $installed.Add("7-Zip portable")
        } else {
            Log-Fail "7za.exe not found after extract"
            $failed.Add("7-Zip portable")
        }
    } else { $failed.Add("7-Zip portable") }
}

# ---------------------------------------------------------------------------
# .NET FRAMEWORK 3.5
# ---------------------------------------------------------------------------
Write-Host "`n--- .NET Framework 3.5 ---" -ForegroundColor Cyan
$reg35 = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5"
if ((Test-Path $reg35) -and (Get-ItemProperty $reg35 -Name Version -ErrorAction SilentlyContinue).Version) {
    Log-Skip ".NET Framework 3.5 already installed"
    $skipped.Add(".NET Framework 3.5")
} else {
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "NetFx3" -All -NoRestart | Out-Null
        Log-Success ".NET Framework 3.5 enabled"
        $installed.Add(".NET Framework 3.5")
    } catch {
        Log-Fail "Failed: $($_.Exception.Message)"
        $failed.Add(".NET Framework 3.5")
    }
}

# ---------------------------------------------------------------------------
# DIRECTX JUNE 2010
# ---------------------------------------------------------------------------
Write-Host "`n--- DirectX June 2010 ---" -ForegroundColor Cyan
if (Test-Path "$env:SystemRoot\System32\d3dx9_43.dll") {
    Log-Skip "DirectX June 2010 already installed"
    $skipped.Add("DirectX June 2010")
} else {
    $dx = Get-File "https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe" "directx_Jun2010_redist.exe"
    if ($dx -and (Test-Path $SevenZipExe)) {
        $dxTemp = Join-Path $TempDL "dx_extract"
        New-Item -ItemType Directory -Force -Path $dxTemp | Out-Null
        & $SevenZipExe x "$dx" -o"$dxTemp" -y | Out-Null
        $setup = Join-Path $dxTemp "DXSETUP.exe"
        if (Test-Path $setup) {
            if (Run-Exe $setup "/silent" "DirectX June 2010") {
                Log-Success "DirectX June 2010 installed"
                $installed.Add("DirectX June 2010")
            } else {
                Log-Fail "DirectX install failed"
                $failed.Add("DirectX June 2010")
            }
        } else {
            Log-Fail "DXSETUP.exe not found in archive"
            $failed.Add("DirectX June 2010")
        }
    } else {
        Log-Fail "Download or 7za missing"
        $failed.Add("DirectX June 2010")
    }
}

# ---------------------------------------------------------------------------
# LEGACY OPENAL
# ---------------------------------------------------------------------------
Write-Host "`n--- Legacy OpenAL ---" -ForegroundColor Cyan
if (Test-Path "HKLM:\SOFTWARE\Creative Labs\OpenAL") {
    Log-Skip "Legacy OpenAL already installed"
    $skipped.Add("Legacy OpenAL")
} else {
    $zip = Get-File "https://openal.org/downloads/oalinst.zip" "oalinst.zip"
    if ($zip) {
        Expand-Archive -Path $zip -DestinationPath "$TempDL\oal_legacy" -Force
        $exe = "$TempDL\oal_legacy\oalinst.exe"
        if (Test-Path $exe) {
            if (Run-Exe $exe "/S" "Legacy OpenAL") {
                Log-Success "Legacy OpenAL installed"
                $installed.Add("Legacy OpenAL")
            } else {
                Log-Fail "Legacy OpenAL install failed"
                $failed.Add("Legacy OpenAL")
            }
        } else {
            Log-Fail "oalinst.exe not found"
            $failed.Add("Legacy OpenAL")
        }
    } else { $failed.Add("Legacy OpenAL") }
}

# ---------------------------------------------------------------------------
# OPENAL SOFT
# ---------------------------------------------------------------------------
Write-Host "`n--- OpenAL Soft ---" -ForegroundColor Cyan
if ((Test-Path "$env:SystemRoot\System32\OpenAL32.dll") -and (Test-Path "$env:SystemRoot\SysWOW64\OpenAL32.dll")) {
    Log-Skip "OpenAL Soft already installed"
    $skipped.Add("OpenAL Soft")
} else {
    $zip = Get-File "https://openal-soft.org/openal-binaries/openal-soft-1.25.1-bin.zip" "openal-soft-latest-bin.zip"
    if ($zip) {
        Expand-Archive -Path $zip -DestinationPath "$TempDL\oal_soft" -Force
        $dll64 = Get-ChildItem "$TempDL\oal_soft" -Recurse -Filter "soft_oal.dll" |
                 Where-Object { $_.DirectoryName -like "*Win64*" } | Select-Object -First 1 -ExpandProperty FullName
        $dll32 = Get-ChildItem "$TempDL\oal_soft" -Recurse -Filter "soft_oal.dll" |
                 Where-Object { $_.DirectoryName -like "*Win32*" } | Select-Object -First 1 -ExpandProperty FullName
        if ($dll64 -and $dll32) {
            Copy-Item $dll64 "$env:SystemRoot\System32\OpenAL32.dll" -Force
            Copy-Item $dll32 "$env:SystemRoot\SysWOW64\OpenAL32.dll" -Force
            Log-Success "OpenAL Soft installed"
            $installed.Add("OpenAL Soft")
        } else {
            Log-Fail "soft_oal.dll not found in expected paths"
            $failed.Add("OpenAL Soft")
        }
    } else { $failed.Add("OpenAL Soft") }
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
    $alreadyInstalled = $false
    foreach ($reg in $regPaths) {
        if ((Test-Path $reg) -and (Get-ItemProperty $reg -Name Version -ErrorAction SilentlyContinue).Version) {
            $alreadyInstalled = $true; break
        }
    }
    if ($alreadyInstalled) {
        Log-Skip "VC++ $($vc.Key) already installed"
        $skipped.Add("VC++ $($vc.Key)")
        continue
    }
    $file = Get-File $vc.Url "vc_$($vc.Key).exe"
    if ($file) {
        if (Run-Exe $file $vc.Flags "VC++ $($vc.Key)") {
            Log-Success "VC++ $($vc.Key) installed"
            $installed.Add("VC++ $($vc.Key)")
        } else {
            Log-Fail "VC++ $($vc.Key) failed"
            $failed.Add("VC++ $($vc.Key)")
        }
    } else { $failed.Add("VC++ $($vc.Key)") }
}

# ---------------------------------------------------------------------------
# .NET RUNTIMES
# ---------------------------------------------------------------------------
Write-Host "`n--- .NET Runtimes ---" -ForegroundColor Cyan

$netDefs = @(
    @{ Name=".NET Framework 4.8.1";   File="ndp481.exe";          Flags="/q /norestart";    IsFramework=$true;  MinRelease=528040; Reg="HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full";                                                        Url="https://go.microsoft.com/fwlink/?linkid=2202440" }
    @{ Name=".NET 6 ASP.NET Runtime"; File="aspnetcore-6.exe";    Flags="/quiet /norestart"; IsFramework=$false; Ver="6.0"; Reg="HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.AspNetCore.App";    Url="https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/6.0.36/aspnetcore-runtime-6.0.36-win-x64.exe" }
    @{ Name=".NET 6 Desktop Runtime"; File="desktop-6.exe";       Flags="/quiet /norestart"; IsFramework=$false; Ver="6.0"; Reg="HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App"; Url="https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/6.0.36/windowsdesktop-runtime-6.0.36-win-x64.exe" }
    @{ Name=".NET 7 ASP.NET Runtime"; File="aspnetcore-7.exe";    Flags="/quiet /norestart"; IsFramework=$false; Ver="7.0"; Reg="HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.AspNetCore.App";    Url="https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/7.0.20/aspnetcore-runtime-7.0.20-win-x64.exe" }
    @{ Name=".NET 7 Desktop Runtime"; File="desktop-7.exe";       Flags="/quiet /norestart"; IsFramework=$false; Ver="7.0"; Reg="HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App"; Url="https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/7.0.20/windowsdesktop-runtime-7.0.20-win-x64.exe" }
    @{ Name=".NET 8 ASP.NET Runtime"; File="aspnetcore-8.exe";    Flags="/quiet /norestart"; IsFramework=$false; Ver="8.0"; Reg="HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.AspNetCore.App";    Url="https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/8.0.26/aspnetcore-runtime-8.0.26-win-x64.exe" }
    @{ Name=".NET 8 Desktop Runtime"; File="desktop-8.exe";       Flags="/quiet /norestart"; IsFramework=$false; Ver="8.0"; Reg="HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App"; Url="https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/8.0.26/windowsdesktop-runtime-8.0.26-win-x64.exe" }
    @{ Name=".NET 9 ASP.NET Runtime"; File="aspnetcore-9.exe";    Flags="/quiet /norestart"; IsFramework=$false; Ver="9.0"; Reg="HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.AspNetCore.App";    Url="https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/9.0.15/aspnetcore-runtime-9.0.15-win-x64.exe" }
    @{ Name=".NET 9 Desktop Runtime"; File="desktop-9.exe";       Flags="/quiet /norestart"; IsFramework=$false; Ver="9.0"; Reg="HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App"; Url="https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/9.0.15/windowsdesktop-runtime-9.0.15-win-x64.exe" }
)

foreach ($nd in $netDefs) {
    $skip = $false
    if (Test-Path $nd.Reg) {
        if ($nd.IsFramework) {
            $rel = (Get-ItemProperty $nd.Reg -Name Release -ErrorAction SilentlyContinue).Release
            if ($rel -and $rel -ge $nd.MinRelease) { $skip = $true }
        } else {
            if (Test-Path "$($nd.Reg)\$($nd.Ver)") { $skip = $true }
        }
    }
    if ($skip) {
        Log-Skip "$($nd.Name) already installed"
        $skipped.Add($nd.Name)
        continue
    }
    $file = Get-File $nd.Url $nd.File
    if ($file) {
        if (Run-Exe $file $nd.Flags $nd.Name) {
            Log-Success "$($nd.Name) installed"
            $installed.Add($nd.Name)
        } else {
            Log-Fail "$($nd.Name) failed"
            $failed.Add($nd.Name)
        }
    } else { $failed.Add($nd.Name) }
}

# ---------------------------------------------------------------------------
# TEMURIN JDK
# ---------------------------------------------------------------------------
Write-Host "`n--- Java (Temurin JDK) ---" -ForegroundColor Cyan

$jdkDefs = @(
    @{ Name="Temurin JDK 21"; File="temurin-jdk-21.msi"; Dir="jdk-21"; Url="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.9%2B10/OpenJDK21U-jdk_x64_windows_hotspot_21.0.9_10.msi" }
    @{ Name="Temurin JDK 17"; File="temurin-jdk-17.msi"; Dir="jdk-17"; Url="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.17%2B10/OpenJDK17U-jdk_x64_windows_hotspot_17.0.17_10.msi" }
    @{ Name="Temurin JDK 8";  File="temurin-jdk-8.msi";  Dir="jdk-8";  Url="https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u472-b08/OpenJDK8U-jdk_x64_windows_hotspot_8u472b08.msi" }
)

foreach ($jd in $jdkDefs) {
    $existing = Get-ChildItem "C:\Program Files\Eclipse Adoptium" -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "$($jd.Dir)*" }
    if ($existing) {
        Log-Skip "$($jd.Name) already installed"
        $skipped.Add($jd.Name)
        continue
    }
    $file = Get-File $jd.Url $jd.File
    if ($file) {
        if (Run-Msi $file "/quiet /norestart" $jd.Name) {
            Log-Success "$($jd.Name) installed"
            $installed.Add($jd.Name)
        } else {
            Log-Fail "$($jd.Name) failed"
            $failed.Add($jd.Name)
        }
    } else { $failed.Add($jd.Name) }
}

# ---------------------------------------------------------------------------
# VULKAN RUNTIME
# ---------------------------------------------------------------------------
Write-Host "`n--- Vulkan Runtime ---" -ForegroundColor Cyan
if (Test-Path "HKLM:\SOFTWARE\Khronos\Vulkan\Runtime") {
    Log-Skip "Vulkan Runtime already installed"
    $skipped.Add("Vulkan Runtime")
} else {
    $file = Get-File "https://sdk.lunarg.com/sdk/download/1.4.335.0/windows/VulkanRT-X64-1.4.335.0-Installer.exe" "vulkan-runtime.exe"
    if ($file) {
        if (Run-Exe $file "/S" "Vulkan Runtime") {
            Log-Success "Vulkan Runtime installed"
            $installed.Add("Vulkan Runtime")
        } else {
            Log-Fail "Vulkan Runtime failed"
            $failed.Add("Vulkan Runtime")
        }
    } else { $failed.Add("Vulkan Runtime") }
}

# ---------------------------------------------------------------------------
# WEBVIEW2
# ---------------------------------------------------------------------------
Write-Host "`n--- WebView2 Runtime ---" -ForegroundColor Cyan
if (Test-Path "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}") {
    Log-Skip "WebView2 already installed"
    $skipped.Add("WebView2")
} else {
    $file = Get-File "https://go.microsoft.com/fwlink/p/?LinkId=2124703" "MicrosoftEdgeWebview2Setup.exe"
    if ($file) {
        if (Run-Exe $file "/silent /install" "WebView2") {
            Log-Success "WebView2 installed"
            $installed.Add("WebView2")
        } else {
            Log-Fail "WebView2 failed"
            $failed.Add("WebView2")
        }
    } else { $failed.Add("WebView2") }
}

# ---------------------------------------------------------------------------
# POWERSHELL 7.6.1
# ---------------------------------------------------------------------------
Write-Host "`n--- PowerShell 7.6.1 (LTS) ---" -ForegroundColor Cyan
$pwsh = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
$psSkip = $false
if (Test-Path $pwsh) {
    $ver = & $pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null
    if ($ver -and ([version]$ver -ge [version]"7.6.0")) { $psSkip = $true }
}
if ($psSkip) {
    Log-Skip "PowerShell 7.6.x already installed"
    $skipped.Add("PowerShell 7.6.1")
} else {
    $file = Get-File "https://github.com/PowerShell/PowerShell/releases/download/v7.6.1/PowerShell-7.6.1-win-x64.msi" "PowerShell-7.6.1-win-x64.msi"
    if ($file) {
        if (Run-Msi $file "/quiet /norestart ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1" "PowerShell 7.6.1") {
            Log-Success "PowerShell 7.6.1 installed"
            $installed.Add("PowerShell 7.6.1")
        } else {
            Log-Fail "PowerShell 7.6.1 failed"
            $failed.Add("PowerShell 7.6.1")
        }
    } else { $failed.Add("PowerShell 7.6.1") }
}

# ---------------------------------------------------------------------------
# PYTHON
# ---------------------------------------------------------------------------
Write-Host "`n--- Python ---" -ForegroundColor Cyan

$pyDefs = @(
    @{ Ver="3.10"; Url="https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe" }
    @{ Ver="3.11"; Url="https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"   }
    @{ Ver="3.12"; Url="https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe" }
)

foreach ($py in $pyDefs) {
    $pyDir = "C:\Program Files\Python$($py.Ver -replace '\.', '')"
    if (Test-Path "$pyDir\python.exe") {
        Log-Skip "Python $($py.Ver) already installed"
        $skipped.Add("Python $($py.Ver)")
        continue
    }
    $file = Get-File $py.Url "python-$($py.Ver)-amd64.exe"
    if ($file) {
        if (Run-Exe $file "/quiet InstallAllUsers=1 PrependPath=1 Include_launcher=1" "Python $($py.Ver)") {
            Log-Success "Python $($py.Ver) installed"
            $installed.Add("Python $($py.Ver)")
        } else {
            Log-Fail "Python $($py.Ver) failed"
            $failed.Add("Python $($py.Ver)")
        }
    } else { $failed.Add("Python $($py.Ver)") }
}

# ---------------------------------------------------------------------------
# GIT
# ---------------------------------------------------------------------------
Write-Host "`n--- Git for Windows 2.54.0 ---" -ForegroundColor Cyan
if (Test-Path "$env:ProgramFiles\Git\bin\git.exe") {
    Log-Skip "Git already installed"
    $skipped.Add("Git")
} else {
    $file = Get-File "https://github.com/git-for-windows/git/releases/download/v2.54.0.windows.1/Git-2.54.0-64-bit.exe" "Git-2.54.0-64-bit.exe"
    if ($file) {
        if (Run-Exe $file "/VERYSILENT /NORESTART /NOCANCEL /SP- /COMPONENTS=icons,assoc,assoc_sh,gitlfs" "Git") {
            Log-Success "Git installed"
            $installed.Add("Git")
        } else {
            Log-Fail "Git failed"
            $failed.Add("Git")
        }
    } else { $failed.Add("Git") }
}

# ---------------------------------------------------------------------------
# VS CODE
# ---------------------------------------------------------------------------
Write-Host "`n--- Visual Studio Code ---" -ForegroundColor Cyan
if (Test-Path "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe") {
    Log-Skip "VS Code already installed"
    $skipped.Add("VS Code")
} else {
    $file = Get-File "https://aka.ms/win32-x64-user-stable" "VSCodeSetup-x64.exe"
    if ($file) {
        if (Run-Exe $file "/VERYSILENT /NORESTART /MERGETASKS=!runcode" "VS Code") {
            Log-Success "VS Code installed"
            $installed.Add("VS Code")
        } else {
            Log-Fail "VS Code failed"
            $failed.Add("VS Code")
        }
    } else { $failed.Add("VS Code") }
}

# ---------------------------------------------------------------------------
# CLEANUP
# ---------------------------------------------------------------------------
Write-Host "`n--- Cleanup ---" -ForegroundColor Cyan
Log-Status "Removing temp_installers..."
Remove-Item $TempDL -Recurse -Force -ErrorAction SilentlyContinue
Log-Success "Done"

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
