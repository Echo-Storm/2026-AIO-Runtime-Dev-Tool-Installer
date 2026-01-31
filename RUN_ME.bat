@echo off
:: ============================================
::  ALLTHERUNTIMES.bat  (Elevation Wrapper)
:: ============================================

:: Check for admin rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrative privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Run the PowerShell installer
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0ALLTHERUNTIMES.ps1"

pause
