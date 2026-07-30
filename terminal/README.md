Windows Terminal Profile
=========================

A companion `settings.json` for Windows Terminal, color-coded and profiled to match what `ALLTHERUNTIMES.ps1` installs: PowerShell 7, Python 3.10-3.13, Git, Node.js, and a JShell (JDK 21) REPL, on top of the usual Command Prompt / Windows PowerShell profiles.

Every path in this file lives under `C:\Program Files\...`, so it's portable across machines - nothing here is tied to a specific username or drive layout.

Installing it
--------------
1. Close Windows Terminal.
2. Copy `settings.json` over:
   `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`
   (back up your existing one first if you've customized it - this replaces the whole file, not just individual profiles.)
3. Reopen Windows Terminal.

Known caveats
--------------
- **MSYS2 (MinGW64/Clang64/MSYS2) profiles are hidden by default.** The installer doesn't set up MSYS2 - these only do something if you have `C:\msys64` from a separate MSYS2 install. Un-hide them in Settings if that's you.
- **The two VS 2022 dev-shell profiles are optional too.** The installer doesn't touch Visual Studio (a much bigger, separately-licensed product) - these only populate if you already have VS 2022 installed.
- **The JShell profile's icon points at a specific JDK 21 patch folder** (it'll go stale as Adoptium ships newer patches, since Windows Terminal icons can't be resolved dynamically). The profile still launches correctly either way - the *icon* just falls back to a generic one until this file gets refreshed. The launch command itself resolves the current JDK 21 install dynamically, so that part never breaks.

This file is refreshed occasionally as the installer's tool list changes - check back if you re-run the installer and pick up something new.
