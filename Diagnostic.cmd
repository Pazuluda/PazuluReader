@echo off
rem Recupere les informations sur les plantages de Pazulu Reader (ne modifie rien).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\diagnostic.ps1"
pause
