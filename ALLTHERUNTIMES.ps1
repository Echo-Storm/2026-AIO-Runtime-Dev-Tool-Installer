# ================================
# UNIVERSAL RUNTIME & DEV TOOL INSTALLER
# Written by XechostormX
# Silent installs for gaming, legacy apps, modern tools, dev basics
# Skips if already present | Deletes temp_installers for fresh run
# Run elevated (batch already handles admin)
# ================================

# === HEADER (with 6 blank lines to protect from progress bar overwrite) ===
Write-Host "`n`n`n`n`n`n" -ForegroundColor Black
Write-Host "`n===== Universal Runtime & Dev Tool Installer - FINAL =====" -ForegroundColor Cyan
Write-Host "Current time: $(Get-Date)" -ForegroundColor Yellow
Write-Host "Location: $PSScriptRoot" -ForegroundColor Yellow
Write-Host "Temp folder: $(Join-Path $PSScriptRoot 'temp_installers')" -ForegroundColor Yellow
Write-Host "=======================================" -ForegroundColor Cyan
Start-Sleep -Seconds 2

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "Runtime & Dev Tool Installer - FINAL"

$Base = $PSScriptRoot
$TempDL = Join-Path $Base "temp_installers"
New-Item -ItemType Directory -Force -Path $TempDL | Out-Null

$LogFile = Join-Path $Base "RuntimeInstall_Log_$(Get-Date -Format 'yyyyMMdd_HHmm').txt"

$SevenZipExe = Join-Path $TempDL "7za.exe"

# Tracking for dynamic summary
$installed = @()
$skipped   = @()
$failed    = @()

function Log($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - $msg" | Out-File -FilePath $LogFile -Append -Encoding utf8
    Write-Host $msg
}

function Write-Status($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - [STATUS] $msg" | Out-File $LogFile -Append -Encoding utf8
    Write-Host "$ts - " -NoNewline
    Write-Host "[STATUS] $msg" -ForegroundColor Yellow
}

function Write-Success($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - [SUCCESS] $msg" | Out-File $LogFile -Append -Encoding utf8
    Write-Host "$ts - " -NoNewline
    Write-Host "[SUCCESS] $msg" -ForegroundColor Green
}

function Write-Fail($msg) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$ts - [FAIL] $msg" | Out-File $LogFile -Append -Encoding utf8
    Write-Host "$ts - " -NoNewline
    Write-Host "[FAIL] $msg" -ForegroundColor Red
}

function Get-File($url, $name) {
    $path = Join-Path $TempDL $name
    if (Test-Path $path -PathType Leaf) {
        Write-Status "Cached: $name"
        return $path
    }
    Write-Status "Downloading $name..."
    $retries = 3
    $success = $false
    for ($i = 1; $i -le $retries; $i++) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing -ErrorAction Stop
            Write-Success "Downloaded $name"
            $success = $true
            return $path
        } catch {
            Write-Fail "Download attempt $i failed: $($_.Exception.Message)"
            if ($i -lt $retries) { Start-Sleep -Seconds 5 }
        }
    }
    if (-not $success) {
        Write-Fail "Download failed after $retries attempts"
        return $null
    }
}

function Run-Silent($path, $argString = "", $name = $null) {
    if (-not $name) { $name = Split-Path $path -Leaf }
    if (-not (Test-Path $path)) { Write-Fail "Missing: $path"; return }

    Write-Status "Installing $name..."
    $cmdLine = "`"$path`" $argString"
    Log "Cmd: $cmdLine"
    try {
        $p = Start-Process cmd.exe -ArgumentList "/c $cmdLine" -Wait -NoNewWindow -PassThru
        Log "Exit: $($p.ExitCode)"
        if ($p.ExitCode -in 0, 3010, 1641, 1638) {
            Write-Success ('{0}: OK (exit {1})' -f $name, $p.ExitCode)
            $installed += $name
        } else {
            Write-Fail ('{0}: Failed (exit {1})' -f $name, $p.ExitCode)
            $failed += $name
        }
    } catch {
        Write-Fail "Exception: $($_.Exception.Message)"
        $failed += $name
    }
}

Write-Host "`n===== Starting Install =====" -ForegroundColor Yellow
Log "Started. Base: $Base   Temp: $TempDL   Log: $LogFile"

# 7-Zip portable
if (-not (Test-Path $SevenZipExe)) {
    $zipPath = Get-File "https://www.7-zip.org/a/7za920.zip" "7za.zip"
    if ($zipPath) {
        Expand-Archive $zipPath $TempDL -Force
        Move-Item "$TempDL\7za.exe" $SevenZipExe -Force
        Remove-Item $zipPath -Force
        Write-Success "7za.exe ready"
    } else {
        Write-Fail "7za.exe download failed"
    }
}

# .NET 3.5 (for legacy apps)
Write-Status ".NET Framework 3.5"
$net35Reg = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v3.5"
$skip = $false
if (Test-Path $net35Reg) {
    $installedVer = (Get-ItemProperty $net35Reg -Name Version -ErrorAction SilentlyContinue).Version
    if ($installedVer) {
        Write-Success ".NET Framework 3.5 already installed (v$installedVer) - skipped"
        $skipped += ".NET Framework 3.5"
        $skip = $true
    }
}
if (-not $skip) {
    try {
        Enable-WindowsOptionalFeature -Online -FeatureName "NetFx3" -All -NoRestart | Out-Null
        Write-Success ".NET Framework 3.5 enabled"
        $installed += ".NET Framework 3.5"
    } catch {
        Write-Fail "Failed to enable .NET Framework 3.5: $($_.Exception.Message)"
        $failed += ".NET Framework 3.5"
    }
}

# DirectX June 2010
Write-Status "DirectX June 2010"
$dxSkip = Test-Path "$env:SystemRoot\System32\d3dx9_43.dll"
if ($dxSkip) {
    Write-Success "DirectX June 2010 already installed (d3dx9_43.dll present) - skipped"
    $skipped += "DirectX June 2010"
} else {
    $dxUrl = "https://download.microsoft.com/download/8/4/A/84A35BF1-DAFE-4AE8-82AF-AD2AE20B6B14/directx_Jun2010_redist.exe"
    $dx = Get-File $dxUrl "directx_Jun2010_redist.exe"
    if ($dx -and (Test-Path $SevenZipExe)) {
        $dxTemp = Join-Path $TempDL "dx_extract"
        New-Item -ItemType Directory -Force -Path $dxTemp | Out-Null
        & $SevenZipExe x "$dx" -o"$dxTemp" -y | Out-Null
        $setupPath = Join-Path $dxTemp "DXSETUP.exe"
        if (Test-Path $setupPath) {
            Run-Silent $setupPath "/silent" "DirectX June 2010"
        } else {
            Write-Fail "DXSETUP.exe not found"
            $failed += "DirectX June 2010"
        }
    } else {
        Write-Fail "DirectX download or 7za failed"
        $failed += "DirectX June 2010"
    }
}

# Legacy OpenAL
Write-Status "Legacy OpenAL"
$oalLegacySkip = Test-Path "HKLM:\SOFTWARE\Creative Labs\OpenAL"
if ($oalLegacySkip) {
    Write-Success "Legacy OpenAL already installed (registry key present) - skipped"
    $skipped += "Legacy OpenAL"
} else {
    $oalZip = Get-File "https://openal.org/downloads/oalinst.zip" "oalinst.zip"
    if ($oalZip) {
        Expand-Archive -Path $oalZip -DestinationPath "$TempDL\oal_legacy" -Force
        $oalLegacy = "$TempDL\oal_legacy\oalinst.exe"
        if (Test-Path $oalLegacy) {
            Run-Silent $oalLegacy "/S" "Legacy OpenAL"
        } else {
            Write-Fail "oalinst.exe not found"
            $failed += "Legacy OpenAL"
        }
    } else {
        Write-Fail "Legacy OpenAL download failed"
        $failed += "Legacy OpenAL"
    }
}

# OpenAL Soft
Write-Status "OpenAL Soft"
$oalSoftSkip = (Test-Path "$env:SystemRoot\System32\OpenAL32.dll") -and (Test-Path "$env:SystemRoot\SysWOW64\OpenAL32.dll")
if ($oalSoftSkip) {
    Write-Success "OpenAL Soft already installed (DLLs present) - skipped"
    $skipped += "OpenAL Soft"
} else {
    $oalSoftZip = Get-File "https://openal-soft.org/openal-binaries/openal-soft-1.25.1-bin.zip" "openal-soft-latest-bin.zip"
    if ($oalSoftZip) {
        Expand-Archive -Path $oalSoftZip -DestinationPath "$TempDL\oal_soft" -Force
        $dll64 = Get-ChildItem "$TempDL\oal_soft" -Recurse -Filter "soft_oal.dll" | Where-Object { $_.DirectoryName -like "*Win64*" } | Select-Object -First 1 -ExpandProperty FullName
        $dll32 = Get-ChildItem "$TempDL\oal_soft" -Recurse -Filter "soft_oal.dll" | Where-Object { $_.DirectoryName -like "*Win32*" } | Select-Object -First 1 -ExpandProperty FullName
        if ($dll64 -and $dll32) {
            Copy-Item $dll64 "$env:SystemRoot\System32\OpenAL32.dll" -Force
            Copy-Item $dll32 "$env:SystemRoot\SysWOW64\OpenAL32.dll" -Force
            Write-Success "OpenAL Soft installed (DLLs copied)"
            $installed += "OpenAL Soft"
        } else {
            Write-Fail "soft_oal.dll not found"
            $failed += "OpenAL Soft"
        }
    } else {
        Write-Fail "OpenAL Soft download failed"
        $failed += "OpenAL Soft"
    }
}

# Visual C++ Redistributables (2005–2022 + 2010 SP1)
Write-Status "Visual C++ Redistributables (2005–2022 + 2010 SP1)"
$vcList = @{
    "2005_x86"   = "https://download.microsoft.com/download/8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A/vcredist_x86.exe"
    "2005_x64"   = "https://download.microsoft.com/download/8/B/4/8B42259F-5D70-43F4-AC2E-4B208FD8D66A/vcredist_x64.exe"
    "2008_x86"   = "https://download.microsoft.com/download/5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE/vcredist_x86.exe"
    "2008_x64"   = "https://download.microsoft.com/download/5/D/8/5D8C65CB-C849-4025-8E95-C3966CAFD8AE/vcredist_x64.exe"
    "2010_x86"   = "https://catalog.s.download.windowsupdate.com/msdownload/update/software/secu/2011/07/vcredist_x86_28c54491be70c38c97849c3d8cfbfdd0d3c515cb.exe"
    "2010_x64"   = "https://catalog.s.download.windowsupdate.com/msdownload/update/software/secu/2011/07/vcredist_x64_15d032d669078aa6f0f7fd1cbf4115a070bd034d.exe"
    "2012_x86"   = "https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/vcredist_x86.exe"
    "2012_x64"   = "https://download.microsoft.com/download/1/6/B/16B06F60-3B20-4FF2-B699-5E9B7962F9AE/vcredist_x64.exe"
    "2013_x86"   = "https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x86.exe"
    "2013_x64"   = "https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe"
    "2015-2022_x86" = "https://aka.ms/vs/17/release/vc_redist.x86.exe"
    "2015-2022_x64" = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
}

foreach ($kv in $vcList.GetEnumerator()) {
    $verArch = $kv.Key
    $url = $kv.Value
    $fileName = "vc_$verArch.exe"
    $file = Get-File $url $fileName

    if ($file) {
        $baseVer = switch -Regex ($verArch) {
            '^2005'   { '8.0' }
            '^2008'   { '9.0' }
            '^2010'   { '10.0' }
            '^2012'   { '11.0' }
            '^2013'   { '12.0' }
            '^2015'   { '14.0' }
        }
        $arch = $verArch -replace '^.*_', ''
        $regPaths = @(
            "HKLM:\SOFTWARE\Microsoft\VisualStudio\$baseVer\VC\VCRedist\$arch",
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\$baseVer\VC\VCRedist\$arch"
        )
        $skip = $false
        $installedVer = $null

        foreach ($reg in $regPaths) {
            if (Test-Path $reg) {
                $ver = Get-ItemProperty -Path $reg -Name Version -ErrorAction SilentlyContinue
                if ($ver) {
                    $installedVer = $ver.Version
                    Log "VC++ $verArch already installed (version $installedVer) - skipping"
                    $skip = $true
                    $skipped += "VC++ $verArch"
                    break
                }
            }
        }

        if (-not $skip) {
            Write-Status "Installing VC++ $verArch..."
            $flags = switch -Regex ($verArch) {
                '^2005'   { "/q:a" }
                '^2008'   { "/q" }
                '^2010'   { "/q" }
                '^2012|^2013' { "/passive /norestart" }
                '^2015'   { "/quiet /norestart" }
            }
            Run-Silent $file $flags "VC++ $verArch"
        } else {
            Write-Success "VC++ $verArch already installed (v$installedVer) - skipped"
        }
    } else {
        Write-Fail "VC++ $verArch download failed"
        $failed += "VC++ $verArch"
    }
}

# .NET runtimes batch (Framework 4.8.1 + Desktop & ASP.NET 6/7/8/9)
Write-Status ".NET runtimes batch (Framework 4.8.1 + Desktop & ASP.NET 6/7/8/9)"

$netRuntimes = @(
    @{ Name = "Framework 4.8.1"; Url = "https://go.microsoft.com/fwlink/?linkid=2202440"; File = "ndp481-x86-x64-allos-enu.exe"; RegPath = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"; MinRelease = 528040; Flags = "/q /norestart" }
    @{ Name = ".NET 6 ASP.NET Runtime"; Url = "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/6.0.36/aspnetcore-runtime-6.0.36-win-x64.exe"; File = "aspnetcore-runtime-6.exe"; RegPath = "HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.ASPNETCore.App"; Flags = "/quiet /norestart" }
    @{ Name = ".NET 6 Desktop Runtime"; Url = "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/6.0.36/windowsdesktop-runtime-6.0.36-win-x64.exe"; File = "windowsdesktop-runtime-6.exe"; RegPath = "HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App"; Flags = "/quiet /norestart" }
    @{ Name = ".NET 7 ASP.NET Runtime"; Url = "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/7.0.20/aspnetcore-runtime-7.0.20-win-x64.exe"; File = "aspnetcore-runtime-7.exe"; RegPath = "HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.ASPNETCore.App"; Flags = "/quiet /norestart" }
    @{ Name = ".NET 7 Desktop Runtime"; Url = "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/7.0.20/windowsdesktop-runtime-7.0.20-win-x64.exe"; File = "windowsdesktop-runtime-7.exe"; RegPath = "HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App"; Flags = "/quiet /norestart" }
    @{ Name = ".NET 8 ASP.NET Runtime"; Url = "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/8.0.23/aspnetcore-runtime-8.0.23-win-x64.exe"; File = "aspnetcore-runtime-8.exe"; RegPath = "HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.ASPNETCore.App"; Flags = "/quiet /norestart" }
    @{ Name = ".NET 8 Desktop Runtime"; Url = "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/8.0.23/windowsdesktop-runtime-8.0.23-win-x64.exe"; File = "windowsdesktop-runtime-8.exe"; RegPath = "HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App"; Flags = "/quiet /norestart" }
    @{ Name = ".NET 9 ASP.NET Runtime"; Url = "https://builds.dotnet.microsoft.com/dotnet/aspnetcore/Runtime/9.0.12/aspnetcore-runtime-9.0.12-win-x64.exe"; File = "aspnetcore-runtime-9.exe"; RegPath = "HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.ASPNETCore.App"; Flags = "/quiet /norestart" }
    @{ Name = ".NET 9 Desktop Runtime"; Url = "https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/9.0.12/windowsdesktop-runtime-9.0.12-win-x64.exe"; File = "windowsdesktop-runtime-9.exe"; RegPath = "HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App"; Flags = "/quiet /norestart" }
)

foreach ($runtime in $netRuntimes) {
    $name = $runtime.Name
    $url = $runtime.Url
    $fileName = $runtime.File
    $regPath = $runtime.RegPath
    $flags = $runtime.Flags

    $file = Get-File $url $fileName

    if ($file) {
        $skip = $false
        if (Test-Path $regPath) {
            if ($name -like "*Framework*") {
                $release = Get-ItemProperty -Path $regPath -Name Release -ErrorAction SilentlyContinue
                if ($release -and $release.Release -ge $runtime.MinRelease) {
                    Log "$name already installed (Release $($release.Release)) - skipping"
                    $skip = $true
                    $skipped += $name
                }
            } else {
                $majorVer = $name -replace '.* (\d+) .*', '$1.0'
                if (Test-Path "$regPath\$majorVer") {
                    Log "$name runtime key exists - assuming installed - skipping"
                    $skip = $true
                    $skipped += $name
                }
            }
        }

        if (-not $skip) {
            Write-Status "Installing $name..."
            Run-Silent $file $flags $name
        } else {
            Write-Success "$name already present - skipped"
        }
    } else {
        Write-Fail "$name download failed"
        $failed += $name
    }
}

# Adoptium Temurin OpenJDK + JRE (JDK 21, 17, 8)
Write-Status "Adoptium Temurin OpenJDK + JRE (JDK 21 / 17 / 8)"
$temurinList = @(
    @{ Name = "Temurin JDK 21 (latest LTS)"; Url = "https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.9%2B10/OpenJDK21U-jdk_x64_windows_hotspot_21.0.9_10.msi"; File = "temurin-jdk-21.msi"; Flags = "/quiet /norestart" }
    @{ Name = "Temurin JDK 17 (LTS)"; Url = "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.17%2B10/OpenJDK17U-jdk_x64_windows_hotspot_17.0.17_10.msi"; File = "temurin-jdk-17.msi"; Flags = "/quiet /norestart" }
    @{ Name = "Temurin JDK 8 (legacy)"; Url = "https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u472-b08/OpenJDK8U-jdk_x64_windows_hotspot_8u472b08.msi"; File = "temurin-jdk-8.msi"; Flags = "/quiet /norestart" }
)

foreach ($jdk in $temurinList) {
    $name = $jdk.Name
    $url = $jdk.Url
    $fileName = $jdk.File
    $flags = $jdk.Flags

    $file = Get-File $url $fileName

    if ($file) {
        $installPath = "C:\Program Files\Eclipse Adoptium\$($name -replace '.*JDK (\d+).*', 'jdk-$1')"
        $skip = Test-Path $installPath

        if (-not $skip) {
            Write-Status "Installing $name..."
            Run-Silent $file $flags $name
        } else {
            Write-Success "$name already installed - skipped"
            $skipped += $name
        }
    } else {
        Write-Fail "$name download failed"
        $failed += $name
    }
}

# Vulkan Runtime
Write-Status "Vulkan Runtime"
$vulkanUrl = "https://sdk.lunarg.com/sdk/download/1.4.335.0/windows/VulkanRT-X64-1.4.335.0-Installer.exe"
$vulkanFileName = "vulkan-runtime.exe"
$vulkanFile = Get-File $vulkanUrl $vulkanFileName

if ($vulkanFile) {
    $vulkanReg = "HKLM:\SOFTWARE\Khronos\Vulkan\Runtime"
    $skip = $false
    if (Test-Path $vulkanReg) {
        Log "Vulkan Runtime already installed - skipping"
        $skip = $true
        $skipped += "Vulkan Runtime"
    }

    if (-not $skip) {
        Write-Status "Installing Vulkan Runtime..."
        Run-Silent $vulkanFile "/S" "Vulkan Runtime"
    } else {
        Write-Success "Vulkan Runtime already present - skipped"
    }
} else {
    Write-Fail "Vulkan Runtime download failed"
    $failed += "Vulkan Runtime"
}

# WebView2 Runtime
Write-Status "WebView2 Runtime"
$webviewUrl = "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
$webviewFileName = "MicrosoftEdgeWebview2Setup.exe"
$webviewFile = Get-File $webviewUrl $webviewFileName

if ($webviewFile) {
    $webviewReg = "HKLM:\SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
    $skip = Test-Path $webviewReg

    if (-not $skip) {
        Write-Status "Installing WebView2 Runtime..."
        Run-Silent $webviewFile "/silent /install" "WebView2 Runtime"
    } else {
        Write-Success "WebView2 Runtime already installed - skipped"
        $skipped += "WebView2 Runtime"
    }
} else {
    Write-Fail "WebView2 Runtime download failed"
    $failed += "WebView2 Runtime"
}

# PowerShell 7.x
Write-Status "PowerShell 7.x"
$ps7Url = "https://github.com/PowerShell/PowerShell/releases/download/v7.5.4/PowerShell-7.5.4-win-x64.msi"
$ps7FileName = "PowerShell-7.5.4-win-x64.msi"
$ps7File = Get-File $ps7Url $ps7FileName

if ($ps7File) {
    $ps7Path = "$env:ProgramFiles\PowerShell\7\pwsh.exe"
    $skip = Test-Path $ps7Path

    if (-not $skip) {
        Write-Status "Installing PowerShell 7.x..."
        Run-Silent $ps7File "/quiet /norestart ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1" "PowerShell 7.x"
    } else {
        Write-Success "PowerShell 7.x already installed - skipped"
        $skipped += "PowerShell 7.x"
    }
} else {
    Write-Fail "PowerShell 7.x download failed (check if v7.5.4 is still current)"
    $failed += "PowerShell 7.x"
}

# Python 3.10 / 3.11 / 3.12 (latest known stable versions, with launcher)
Write-Status "Python 3.10 / 3.11 / 3.12 (all users + PATH + launcher)"
$pythonVersions = @(
    @{ Ver = "3.10"; Url = "https://www.python.org/ftp/python/3.10.11/python-3.10.11-amd64.exe" }
    @{ Ver = "3.11"; Url = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" }
    @{ Ver = "3.12"; Url = "https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe" }
)

foreach ($py in $pythonVersions) {
    $ver = $py.Ver
    $url = $py.Url
    $fileName = "python-$ver-amd64.exe"
    $file = Get-File $url $fileName

    if ($file) {
        $pyPath = "C:\Program Files\Python$($ver -replace '\.','')"
        $skip = Test-Path "$pyPath\python.exe"

        if (-not $skip) {
            Write-Status "Installing Python $ver (with launcher)..."
            Run-Silent $file "/quiet InstallAllUsers=1 PrependPath=1 Include_launcher=1" "Python $ver"
        } else {
            Write-Success "Python $ver already installed - skipped"
            $skipped += "Python $ver"
        }
    } else {
        Write-Fail "Python $ver download failed"
        $failed += "Python $ver"
    }
}

# Git for Windows
Write-Status "Git for Windows"
$gitUrl = "https://github.com/git-for-windows/git/releases/download/v2.52.0.windows.1/Git-2.52.0-64-bit.exe"
$gitFileName = "Git-64-bit.exe"
$gitFile = Get-File $gitUrl $gitFileName

if ($gitFile) {
    $gitSkip = Test-Path "$env:ProgramFiles\Git\bin\git.exe"
    if (-not $gitSkip) {
        Write-Status "Installing Git for Windows..."
        Run-Silent $gitFile "/VERYSILENT /NORESTART /NOCANCEL /SP- /COMPONENTS=icons,assoc,assoc_sh,gitlfs" "Git for Windows"
    } else {
        Write-Success "Git already installed - skipped"
        $skipped += "Git for Windows"
    }
} else {
    Write-Fail "Git download failed"
    $failed += "Git for Windows"
}

# Visual Studio Code
Write-Status "Visual Studio Code (latest stable)"
$vscodeUrl = "https://aka.ms/win32-x64-user-stable"
$vscodeFileName = "VSCodeSetup-x64.exe"
$vscodeFile = Get-File $vscodeUrl $vscodeFileName

if ($vscodeFile) {
    $vscodePath = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe"
    $skip = Test-Path $vscodePath

    if (-not $skip) {
        Write-Status "Installing Visual Studio Code..."
        Run-Silent $vscodeFile "/VERYSILENT /NORESTART /MERGETASKS=!runcode" "Visual Studio Code"
    } else {
        Write-Success "VS Code already installed - skipped"
        $skipped += "Visual Studio Code"
    }
} else {
    Write-Fail "VS Code download failed"
    $failed += "Visual Studio Code"
}

# Cleanup & Summary
Write-Status "Cleaning up..."
Remove-Item $TempDL -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n`n===== FINAL SUMMARY =====" -ForegroundColor Cyan

if ($installed.Count -gt 0) {
    Write-Host "Installed / Updated:" -ForegroundColor Green
    $installed | Sort-Object | ForEach-Object { Write-Host "  • $_" -ForegroundColor Green }
} else {
    Write-Host "Nothing newly installed" -ForegroundColor Green
}

if ($skipped.Count -gt 0) {
    Write-Host "`nSkipped (already present):" -ForegroundColor Yellow
    $skipped | Sort-Object | ForEach-Object { Write-Host "  • $_" -ForegroundColor Yellow }
}

if ($failed.Count -gt 0) {
    Write-Host "`nFailed:" -ForegroundColor Red
    $failed | Sort-Object | ForEach-Object { Write-Host "  • $_" -ForegroundColor Red }
}

Write-Host "`nLog: $LogFile" -ForegroundColor Cyan
Write-Host "Your system is now ready for legacy games, modern apps, scripting, dev work, and more!" -ForegroundColor Magenta
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nPress any key to exit..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")