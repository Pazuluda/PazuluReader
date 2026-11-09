@echo off
rem Pazulu Reader Windows uniquement : compile, teste et genere un EXE.
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\build.ps1" %*
pause
