@echo off
rem ---------------------------------------------------------------------------
rem  AltHub - zapusk.
rem
rem  Snachala probuem AltHub.vbs: on startuet PowerShell bez okna konsoli.
rem  Esli wscript nedostupen (otklyuchen politikoy ili antivirusom) - uhodim
rem  na obychnyy zapusk cherez PowerShell.
rem
rem  Esli okno tak i ne otkroetsya - zapusti "Zapusk s oknom.cmd":
rem  on pokazhet tochnuyu oshibku.
rem
rem  Vnimanie: fayl dolzhen lezhat RYADOM s AltHub.ps1. Zapuskat pryamo iz
rem  arhiva nelzya - snachala raspakuy ego celikom.
rem ---------------------------------------------------------------------------
cd /d "%~dp0"

if not exist "%~dp0AltHub.ps1" (
    echo.
    echo  AltHub.ps1 not found next to this file.
    echo  Raspakuy arhiv CELIKOM i zapuskay iz raspakovannoy papki,
    echo  a ne pryamo iz arhiva.
    echo.
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
