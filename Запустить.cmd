@echo off
rem ---------------------------------------------------------------------------
rem  Zapusk AltHub.
rem
rem  Snachala probuem AltHub.vbs — on startuet PowerShell voobshe bez okna
rem  konsoli. Esli wscript otklyuchen politikoy ili zablokirovan antivirusom,
rem  srazu uhodim na obychnyy zapusk cherez PowerShell.
rem
rem  Esli okno tak i ne otkroetsya — zapusti "Запустить с окном.cmd",
rem  on pokazhet, chto imenno poshlo ne tak.
rem ---------------------------------------------------------------------------
cd /d "%~dp0"

if not exist "%~dp0AltHub.ps1" (
    echo Ryadom net AltHub.ps1. Raspakuy arhiv celikom, ne po odnomu faylu.
    pause
    exit /b 1
)

if exist "%~dp0AltHub.vbs" (
    where wscript.exe >nul 2>&1
    if not errorlevel 1 (
        start "" wscript.exe "%~dp0AltHub.vbs"
        exit /b
    )
)

start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0AltHub.ps1"
