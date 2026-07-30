@echo off
:: ============================================
::  ALLTHERUNTIMES.bat  (Elevation Wrapper)
:: ============================================

:: Check for admin rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrative privileges...
    powershell -Command "Start-Process '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b
)

:: Run the PowerShell installer
:: Pass -DryRun to preview what would happen without installing anything, e.g.:
::   RUN_ME.bat -DryRun
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0ALLTHERUNTIMES.ps1" %*
pause

