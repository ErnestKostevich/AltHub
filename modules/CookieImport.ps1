#requires -Version 5.1
<#
================================================================================
 CookieImport.ps1 — забрать куку из уже открытого приложения Roblox
================================================================================
 Чтобы не лазить в браузер через F12, куку можно взять прямо оттуда, где её
 хранит сам клиент Roblox:

   %LOCALAPPDATA%\Roblox\LocalStorage\RobloxCookies.dat

 Устройство файла (проверено на этой машине):
   1) обычный JSON: { "CookiesVersion": "1", "CookiesData": "<base64>" }
   2) внутри base64 — блоб, зашифрованный DPAPI на текущего пользователя
      Windows (то есть прочитать его может только твоя учётка на этом ПК);
   3) внутри — куки в формате Netscape, поля через ТАБУЛЯЦИЮ, записи через "; ":

      #HttpOnly_.roblox.com <TAB> TRUE <TAB> / <TAB> TRUE <TAB> 1822229911 <TAB> .ROBLOSECURITY <TAB> <значение>

      порядок полей: домен, поддомены, путь, secure, срок, имя, значение.

 Мы ничего не расшифровываем "взломом": DPAPI сам отдаёт данные твоей же
 учётной записи Windows.

 ВАЖНО ПРО СМЕНУ АККАУНТА.
 Кнопка "Выйти" в самом Roblox аннулирует сессию НА СЕРВЕРЕ — то есть убивает
 ту куку, которую менеджер уже забрал себе. Если добавлять аккаунты через
 "Выйти", каждый следующий вход убивает предыдущий аккаунт в менеджере.

 Поэтому здесь есть другой путь: приложение "забывает" вход только локально.
 Закрываем Roblox, откладываем RobloxCookies.dat в резервную копию и убираем
 его. Клиент при следующем запуске видит, что входа нет, и показывает экран
 логина — но на сервере старая сессия остаётся ЖИВОЙ, и забранная кука
 продолжает работать.

 Файл только читается, а при смене аккаунта — переносится в резервную копию
 (data
oblox-sessions\), но никогда не портится и не перезаписывается
 чужими данными. Любую копию можно вернуть обратно.

 Есть и запасной путь — хранилище WinINet (им пользуются старые сборки
 клиента и Internet Explorer). На новых версиях оно обычно пустое.
================================================================================
#>

Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue

if (-not ('Ram.WinInet' -as [type])) {
@'
using System;
using System.Runtime.InteropServices;
using System.Text;

namespace Ram {
    public static class WinInet {
        [DllImport("wininet.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool InternetGetCookieEx(string url, string name, StringBuilder data,
                                                       ref uint size, uint flags, IntPtr reserved);

        private const uint INTERNET_COOKIE_HTTPONLY = 0x00002000;

        public static string GetCookie(string url, string name) {
            uint size = 0;
            InternetGetCookieEx(url, name, null, ref size, INTERNET_COOKIE_HTTPONLY, IntPtr.Zero);
            if (size == 0) { return null; }
            StringBuilder sb = new StringBuilder((int)size + 8);
            uint cap = (uint)sb.Capacity;
            if (!InternetGetCookieEx(url, name, sb, ref cap, INTERNET_COOKIE_HTTPONLY, IntPtr.Zero)) { return null; }
            return sb.ToString();
        }
    }
}
'@ | ForEach-Object { Add-Type -TypeDefinition $_ -ErrorAction Stop }
}

function Get-RamRobloxCookieFile {
    Join-Path $env:LOCALAPPDATA 'Roblox\LocalStorage\RobloxCookies.dat'
}

function Test-RamRobloxCookieFile {
    Test-Path -LiteralPath (Get-RamRobloxCookieFile)
}

function Get-RamRobloxCookieFileAge {
    <# Насколько давно клиент трогал файл — подсказка «данные не обновились». #>
    $f = Get-RamRobloxCookieFile
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    return ((Get-Date) - (Get-Item -LiteralPath $f).LastWriteTime)
}

function Read-RamRobloxCookieStore {
    <#
      Возвращает список записей @{ Name; Value; Domain; Expires } из хранилища
      клиента Roblox. Файл только читается.
    #>
    $file = Get-RamRobloxCookieFile
    if (-not (Test-Path -LiteralPath $file)) {
        throw 'Файл с куками приложения Roblox не найден. Установлен ли обычный клиент Roblox и заходил ли ты в него хоть раз?'
    }

    try {
        $envelope = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $file -Raw -Encoding UTF8)
    } catch {
        throw 'Файл с куками приложения Roblox повреждён или его формат изменился.'
    }
    if ([string]::IsNullOrWhiteSpace($envelope.CookiesData)) {
        throw 'В приложении Roblox нет сохранённого входа — сначала войди в аккаунт в приложении.'
    }

    $blob = [Convert]::FromBase64String($envelope.CookiesData)
    try {
        $plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
                    $blob, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    } catch {
        throw 'Windows не отдал содержимое: файл зашифрован на другую учётную запись Windows.'
    }

    $text = [System.Text.Encoding]::UTF8.GetString($plain)
    [Array]::Clear($plain, 0, $plain.Length)

    $result = @()
    foreach ($record in ($text -split '; ')) {
        $f = $record -split "`t"
        if ($f.Count -lt 7) { continue }
        $result += [pscustomobject]@{
            Domain  = ($f[0] -replace '^#HttpOnly_', '')
            Expires = $f[4]
            Name    = $f[5]
            Value   = ($f[6..($f.Count - 1)] -join "`t")
        }
    }

    $text = $null
    return @($result)
}

function Get-RamCookieFromRobloxApp {
    <#
      Достаёт значение .ROBLOSECURITY из хранилища клиента.
      Возвращает саму куку строкой либо кидает понятную ошибку.

      ВНИМАНИЕ ДЛЯ ЧИТАЮЩЕГО КОД: возвращаемое значение — полный доступ к
      аккаунту. Оно никуда не пишется, кроме зашифрованного хранилища
      менеджера, и никогда не попадает в лог (см. Write-RamLog).
    #>
    $cookies = Read-RamRobloxCookieStore
    $hit = $cookies | Where-Object { $_.Name -eq '.ROBLOSECURITY' } | Select-Object -First 1

    if ($null -eq $hit -or [string]::IsNullOrWhiteSpace($hit.Value)) {
        throw 'В приложении Roblox нет активного входа. Войди в аккаунт в приложении и попробуй снова.'
    }
    return $hit.Value
}

function Get-RamCookieFromWinInet {
    <# Запасной путь: хранилище WinINet. На новых клиентах обычно пусто. #>
    foreach ($url in @('https://www.roblox.com', 'https://roblox.com')) {
        $raw = [Ram.WinInet]::GetCookie($url, '.ROBLOSECURITY')
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            return ($raw -replace '^\s*\.ROBLOSECURITY=', '').Trim()
        }
    }
    return $null
}

# ------------------------------------------------- смена аккаунта ----------

function Get-RamSessionBackupDir {
    $dir = Join-Path (Get-RamDataDir) 'roblox-sessions'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-RamSessionBackups {
    <# Список резервных копий входов, новые сверху. #>
    $dir = Get-RamSessionBackupDir
    return @(Get-ChildItem -LiteralPath $dir -Filter '*.dat' -File -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending)
}

function Backup-RamRobloxSession {
    <#
      Откладывает текущий RobloxCookies.dat в резервную копию.
      Имя копии содержит ник, если он известен — так проще потом разобраться.
      Возвращает путь к копии или $null, если исходного файла нет.
    #>
    param([string]$Label = '')

    $src = Get-RamRobloxCookieFile
    if (-not (Test-Path -LiteralPath $src)) { return $null }

    $safe = ($Label -replace '[^\w\-]', '_')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'session' }
    $name = '{0}_{1}.dat' -f (Get-Date).ToString('yyyyMMdd-HHmmss'), $safe
    $dst  = Join-Path (Get-RamSessionBackupDir) $name

    Copy-Item -LiteralPath $src -Destination $dst -Force
    return $dst
}

function Clear-RamRobloxSession {
    <#
      Заставляет приложение Roblox "забыть" вход, НЕ разлогинивая на сервере.

      Порядок: сначала обязательно закрытый клиент (иначе он перезапишет файл
      своей копией из памяти), потом резервная копия, потом удаление.

      Возвращает путь к резервной копии.
    #>
    param([string]$Label = '')

    if (@(Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Сначала нужно закрыть все окна Roblox — иначе клиент запишет вход обратно.'
    }

    $backup = Backup-RamRobloxSession -Label $Label
    if ($null -eq $backup) { throw 'Файла с входом нет — приложение и так никого не помнит.' }

    Remove-Item -LiteralPath (Get-RamRobloxCookieFile) -Force
    return $backup
}

function Restore-RamRobloxSession {
    <# Возвращает сохранённый вход обратно в приложение Roblox. #>
    param([Parameter(Mandatory)][string]$BackupPath)

    if (-not (Test-Path -LiteralPath $BackupPath)) { throw 'Резервная копия не найдена.' }
    if (@(Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Сначала нужно закрыть все окна Roblox.'
    }

    $dst = Get-RamRobloxCookieFile
    $dir = Split-Path -Parent $dst
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    Copy-Item -LiteralPath $BackupPath -Destination $dst -Force
    return $dst
}

function Import-RamCurrentAccountCookie {
    <#
      Главная точка входа для кнопки «Забрать из приложения».
      Сначала хранилище клиента, если пусто — WinINet.
    #>
    try {
        return Get-RamCookieFromRobloxApp
    } catch {
        $fallback = Get-RamCookieFromWinInet
        if (-not [string]::IsNullOrWhiteSpace($fallback)) { return $fallback }
        throw
    }
}
