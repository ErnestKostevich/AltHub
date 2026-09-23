@echo off
chcp 65001 >nul
echo Запусти нужный аккаунт через AltHub, пока идёт проверка (40 секунд).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Проверка настроек Roblox.ps1"
if errorlevel 1 pause
