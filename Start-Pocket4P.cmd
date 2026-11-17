@echo off
setlocal
if exist "%~dp0dist\Pocket4PPort\PocketMotion.exe" (
  start "" "%~dp0dist\Pocket4PPort\PocketMotion.exe"
) else (
  echo The Windows app has not been built yet.
  echo Run: powershell -File "%~dp0tools\build_windows.ps1"
  pause
)
