@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0INSTALL-GUI.ps1"
if errorlevel 1 (
  echo.
  echo Project Zomboid Server Manager setup failed.
  echo Try right-clicking INSTALL-GUI.cmd and choosing Run as administrator.
  echo.
  pause
)
