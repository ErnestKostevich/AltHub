#requires -Version 5.1
<#
================================================================================
 tools\shortcut.ps1 — создаёт ярлык «AltHub» на рабочем столе
================================================================================
 Вызывается из «Ярлык на рабочий стол.cmd». Вынесено отдельным файлом нарочно:
 длинная команда PowerShell внутри .cmd разваливалась на кавычках, а .cmd ещё
 и обязан быть в чистом ASCII — по-русски там ничего не напишешь.

 Ярлык указывает на AltHub.vbs (запуск без окна консоли) и берёт иконку из
 data\althub.ico, которую AltHub рисует сам при первом запуске.
================================================================================
#>

$ErrorActionPreference = 'Stop'

# Папка программы — на уровень выше этого файла.
$root = Split-Path -Parent $PSScriptRoot

$target = Join-Path $root 'AltHub.vbs'
if (-not (Test-Path -LiteralPath $target)) {
    Write-Host ''
    Write-Host '  Рядом с программой нет AltHub.vbs.' -ForegroundColor Red
    Write-Host '  Распакуй архив целиком, не по одному файлу.'
    Write-Host ''
    exit 1
}

try {
    $lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'AltHub.lnk'
    $sh  = New-Object -ComObject WScript.Shell
    $s   = $sh.CreateShortcut($lnk)
    $s.TargetPath       = 'wscript.exe'
    $s.Arguments        = '"' + $target + '"'
    $s.WorkingDirectory = $root
    $s.Description      = 'AltHub — менеджер аккаунтов Roblox'

    $ico = Join-Path $root 'data\althub.ico'
    if (Test-Path -LiteralPath $ico) { $s.IconLocation = $ico }

    $s.Save()

    Write-Host ''
    Write-Host '  Готово. Ярлык на рабочем столе:' -ForegroundColor Green
    Write-Host ("  " + $lnk)
    if (-not (Test-Path -LiteralPath $ico)) {
        Write-Host ''
        Write-Host '  Иконка появится после первого запуска программы —' -ForegroundColor DarkGray
        Write-Host '  тогда просто создай ярлык ещё раз.' -ForegroundColor DarkGray
    }
    Write-Host ''
} catch {
    Write-Host ''
    Write-Host ('  Не вышло создать ярлык: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ''
    exit 1
}
