@echo off
rem ---------------------------------------------------------------------------
rem  Sozdayot yarlyk "AltHub" na rabochem stole.
rem  Yarlyk ukazyvaet na AltHub.vbs - zapusk bez okna konsoli.
rem  Ikonka beryotsya iz data\althub.ico, kotoruyu AltHub risuet sam pri
rem  pervom zapuske.
rem ---------------------------------------------------------------------------
cd /d "%~dp0"

if not exist "%~dp0AltHub.vbs" (
    echo  AltHub.vbs not found next to this file. Raspakuy arhiv celikom.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\shortcut.ps1"
pause
