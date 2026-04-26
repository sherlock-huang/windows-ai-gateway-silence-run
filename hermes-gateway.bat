@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%hermes-gateway-hidden.ps1"
set "ACTION=%~1"

if "%ACTION%"=="" set "ACTION=status"

if /I "%ACTION%"=="help" goto :run
if /I "%ACTION%"=="install" goto :run
if /I "%ACTION%"=="uninstall" goto :run
if /I "%ACTION%"=="start" goto :run
if /I "%ACTION%"=="stop" goto :run
if /I "%ACTION%"=="restart" goto :run
if /I "%ACTION%"=="status" goto :run
if /I "%ACTION%"=="logs" goto :run
if /I "%ACTION%"=="errors" goto :run
if /I "%ACTION%"=="follow" goto :run
if /I "%ACTION%"=="tail" goto :run

echo Unknown action: %ACTION%
echo.
echo Usage:
echo   hermes-gateway install
echo   hermes-gateway restart
echo   hermes-gateway status
echo   hermes-gateway logs
echo   hermes-gateway errors
echo   hermes-gateway follow
echo   hermes-gateway stop
echo   hermes-gateway uninstall
echo.
exit /b 2

:run
if not exist "%PS_SCRIPT%" (
  echo Cannot find PowerShell script:
  echo   "%PS_SCRIPT%"
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Action "%ACTION%"
exit /b %ERRORLEVEL%
