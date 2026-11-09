@echo off
rem Double-cliquez pour installer les outils de compilation (une seule fois).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\install_tools.ps1"
pause
