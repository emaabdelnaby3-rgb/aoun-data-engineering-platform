@echo off
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0RUN_UCP_FULL_PROJECT.ps1"
pause
