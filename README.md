# ALL-THE-RUNTIMES---ALL-OF-THEM
Installs everything a fresh install of windows 11 is going to ask for, no shady crap.

Universal Runtime Installer (A’s Edition)
A portable, silent, battle‑hardened runtime installer for fresh Windows setups.
Designed for power users who want a clean system with zero malware risk, zero bloat, and zero hunting for installers ever again.

This script installs every essential runtime your system will realistically need for:

Gaming

Modding

Media playback (MPV, MPC-HC, etc.)

.NET apps

Java apps

Web apps

Legacy software

Modern software

Development tools

All downloads come directly from official vendor URLs.

What It Installs
🎮 Gaming / Legacy Support
DirectX End‑User Runtimes (June 2010)

OpenAL Soft

Visual C++ Redistributables (2005 → 2022, x86 + x64)

🧩 .NET Ecosystem
.NET Desktop Runtime (LTS + Current)

.NET SDK (LTS + Current)

ASP.NET Core Hosting Bundle

Universal CRT (if missing)

☕ Java (Adoptium Temurin)
JDK LTS

JDK Current

JRE LTS

JRE Current

🌐 Web Components
Microsoft WebView2 Runtime

🖥️ Graphics / System
Vulkan Runtime (if missing)

Other Microsoft dependencies required by modern apps

Why This Exists
Windows reinstalls are annoying enough.
Hunting down runtimes from random websites is worse.

This script gives you:

A single command to install everything

Silent installs

Re‑runnable (safe to run anytime)

Portable (no system modifications beyond the runtimes)

No bundled junk

No telemetry

No shady mirrors

If you reinstall Windows often, mod games, run MPV, use .NET apps, or develop anything, this saves hours.

Usage
Download or clone this repository

Run:

Code
install.bat
or directly:

Code
powershell -ExecutionPolicy Bypass -File install.ps1
The script will:

Create an installers/ folder

Download missing installers

Install everything silently

Skip anything already installed

Folder Structure
Code
Runtimes/
 ├─ install.ps1
 ├─ install.bat
 └─ installers/   (auto‑created)
Requirements
Windows 10 or 11

PowerShell 5+ (built‑in)

Internet connection for first run

Notes
Python and MSYS2 are intentionally excluded (install manually).

All URLs point to official vendor sources (Microsoft, Adoptium, OpenAL Soft).

Safe to run after every Windows reinstall.

If you want, I can also generate a badge set, a changelog template, or a GitHub Actions workflow to auto‑validate URLs so the script never breaks.
