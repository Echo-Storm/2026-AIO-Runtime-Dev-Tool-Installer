I write stuff when I get annoyed that something I need doesn't exist. So here's an AIO that gives you everything you need to get gaming, or installing your build environment, mysys etc.
just doubleclick the .bat file, it will ask for Admin permissions.

Universal Runtime & Dev Tool Installer
======================================

Author: XechostormX
Purpose: One-click (elevated) PowerShell script to silently install or enable a full suite of legacy and modern runtimes, libraries, and developer tools needed for old games, modern applications, and development work.

Key Features
------------
- Skips components already present (path/registry/file checks)
- Retries failed downloads up to 3 times with 5-second delay
- Detailed timestamped logging to console and file
- Clean final summary: Installed/Updated (green), Skipped (yellow), Failed (red)
- Cleans up all temporary files at the end
- Protects header from progress bar overwrite with blank lines
- Handles reboot-required exit codes (3010/1641/1638) as success
- No forced reboots (/norestart everywhere)

What It Installs / Enables (Full Itemized List)
-----------------------------------------------

1. 7-Zip portable (7za.exe)
   - Downloaded only if missing
   - Used internally for DirectX extraction
   - Not shown in final summary (helper only)

2. .NET Framework 3.5
   - Enabled via Windows Optional Feature (NetFx3)
   - Skipped if registry shows it's already installed

3. DirectX June 2010 Redistributable (full legacy DirectX 9.0c)
   - Downloads directx_Jun2010_redist.exe
   - Extracts entire ~140 MB archive (~hundreds of .cab files) using 7za
   - Runs DXSETUP.exe /silent → installs ALL included components:
     - Direct3D 9 (including d3dx9_1 to d3dx9_43.dll)
     - DirectDraw / Direct3D Retained Mode (d3drm.dll)
     - DirectInput, DirectPlay, DirectSound, DirectMusic
     - XAudio2, XACT, XInput 1.3/1.4
     - Managed DirectX (rare .NET usage)
     - All legacy codecs/filters for old games
   - Skipped if d3dx9_43.dll already exists in System32
   - Covers backwards compatibility for most DirectX 7/8 games

4. Legacy OpenAL (Creative Labs oalinst.exe)
   - Classic OpenAL installer
   - Skipped if HKLM\SOFTWARE\Creative Labs\OpenAL registry key exists

5. OpenAL Soft (modern replacement, v1.25.1)
   - Downloads openal-soft-1.25.1-bin.zip
   - Extracts and copies soft_oal.dll → OpenAL32.dll in System32 and SysWOW64
   - Skipped if both OpenAL32.dll files already exist

6. Visual C++ Redistributables (2005–2022)
   - 2005 x86/x64
   - 2008 x86/x64
   - 2010 x86/x64 (from Windows Update catalog)
   - 2012 x86/x64
   - 2013 x86/x64
   - 2015–2022 merged x86/x64
   - Skipped individually if correct registry version key exists

7. .NET Runtimes
   - Framework 4.8.1 (offline installer)
   - .NET 6 ASP.NET Core Runtime
   - .NET 6 Desktop Runtime
   - .NET 7 ASP.NET Core Runtime
   - .NET 7 Desktop Runtime
   - .NET 8 ASP.NET Core Runtime
   - .NET 8 Desktop Runtime
   - .NET 9 ASP.NET Core Runtime
   - .NET 9 Desktop Runtime
   - Skips based on registry (major version folder for Core, Release value for Framework)

8. Adoptium Temurin OpenJDK
   - JDK 21 (latest LTS)
   - JDK 17 (LTS)
   - JDK 8 (legacy)
   - Skipped if install folder already exists under C:\Program Files\Eclipse Adoptium\

9. Vulkan Runtime (latest version)
   - Silent installer
   - Skipped if HKLM\SOFTWARE\Khronos\Vulkan\Runtime exists

10. Microsoft Edge WebView2 Runtime
    - Evergreen bootstrapper (silent)
    - Skipped if client registry key exists

11. PowerShell 7.5.4
    - MSI installer with context menu, remoting, manifest
    - Skipped if pwsh.exe exists in Program Files\PowerShell\7

12. Python (pinned versions)
    - 3.10.11
    - 3.11.9
    - 3.12.10
    - All-users install, adds to PATH, includes the 'launcher'
    - Skipped if python.exe exists in versioned folder

13. Git for Windows (v2.52.0 64-bit)
    - Very silent with icons, shell assoc, git-lfs
    - Skipped if git.exe exists in Program Files\Git\bin

14. Visual Studio Code (latest stable user x64)
    - Very silent, no auto-run
    - Skipped if Code.exe exists in %LOCALAPPDATA%\Programs\Microsoft VS Code

Behavior Notes
--------------
- All downloads use retry logic (3 attempts)
- DirectX extraction installs hundreds of files (DLLs, .inf, .cat, etc.) via official DXSETUP.exe
- No separate DirectX 7/8 installers (June 2010 provides backwards compatibility)
- Summary lists every major component (except 7za helper)
- Temp folder fully deleted at end
- Designed to run elevated (batch wrapper recommended)

Enjoy your fully loaded legacy + modern runtime setup!
