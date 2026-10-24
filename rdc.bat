@echo off
title RDCMan color
rem Starts Set-RdcmanTreeColor.ps1 (same folder) and keeps this window open,
rem even if PowerShell hits an error before the script itself starts.
powershell.exe -NoProfile -NoExit -ExecutionPolicy Bypass -File "%~dp0Set-RdcmanTreeColor.ps1" %*
echo.
echo PowerShell ended (exit code %errorlevel%).
pause