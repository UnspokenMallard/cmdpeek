@echo off
setlocal
set "SCRIPT=%~dp0src\cmdpeek.ps1"
where pwsh >nul 2>&1 && (
  pwsh -NoProfile -File "%SCRIPT%" %*
  exit /b %ERRORLEVEL%
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
