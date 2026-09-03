@echo off
rem ---------------------------------------------------------------------------
rem  Zapusk AltHub.
rem  Rabotu delaet AltHub.vbs: on startuet PowerShell voobshe bez okna konsoli.
rem  Esli .vbs otklyuchen politikoy, ostayotsya zapasnoy put nizhe.
rem ---------------------------------------------------------------------------
cd /d "%~dp0"

if exist "%~dp0AltHub.vbs" (
    start "" wscript.exe "%~dp0AltHub.vbs"
    exit /b
)

start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0AltHub.ps1"
