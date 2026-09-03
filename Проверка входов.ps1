#requires -Version 5.1
<#
================================================================================
 Проверка входов.ps1 — почему входы «ложатся» и можно ли их продлевать
================================================================================
 Запуск:
   powershell -NoProfile -ExecutionPolicy Bypass -File "Проверка входов.ps1"

 ЧТО ЭТО. Аккаунты со временем «ложатся»: рядом появляется красная метка, а
 при запуске Roblox говорит, что надо войти заново. Есть расхожее мнение, что
 Roblox продлевает вход при обращении к нему, и достаточно раз в час куда-то
 сходить. Этот скрипт проверяет, правда ли это — на ТВОИХ аккаунтах, здесь и
 сейчас, а не по слухам.

 КАК. Обходит несколько обычных запросов, которые AltHub и так делает, и
 смотрит, прислал ли Roblox в ответ новую .ROBLOSECURITY (заголовок Set-Cookie).
 Если хоть один прислал — продление возможно, и его имеет смысл встроить.
 Если ни один — значит продлевать нечем, и надо честно это писать, а не
 обещать людям несбыточное.

 БЕЗОПАСНОСТЬ. Все запросы — ТОЛЬКО ЧТЕНИЕ, ничего на аккаунте не меняется.
 Куки не показываются и никуда не пишутся: в выводе только ники и длины.
 Файл accounts.dat открывается на чтение и не перезаписывается.
================================================================================
#>

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

. (Join-Path $root 'AltHub.ps1') -NoAutoStart
$script:Settings = Load-RamSettings

Write-Host ''
Write-Host 'AltHub — проверка продления входов' -ForegroundColor Cyan
Write-Host '--------------------------------------------------'

# --- берём аккаунты
$mode = Get-RamStorageMode
$pass = ''
if ($mode -eq 'aes') {
    $sec = Read-Host 'Хранилище под мастер-паролем. Введи пароль' -AsSecureString
    $pass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}

try {
    $accounts = @(Load-RamAccounts -Password $pass)
} catch {
    Write-Host "Не удалось прочитать аккаунты: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host 'Enter — выход'; exit 1
}

$alive = @($accounts | Where-Object { $_.Cookie })
if ($alive.Count -eq 0) {
    Write-Host 'Аккаунтов с сохранённым входом нет — проверять нечего.' -ForegroundColor Yellow
    Read-Host 'Enter — выход'; exit
}

Write-Host ("Аккаунтов с входом: {0}. Беру первый живой." -f $alive.Count)
Write-Host ''

# --- ищем первый живой вход
$acc = $null
foreach ($a in $alive) {
    try {
        $u = Get-RamAuthenticatedUser -Cookie $a.Cookie
        if ($null -ne $u -and $u.Id -gt 0) { $acc = $a; break }
    } catch { }
}
if ($null -eq $acc) {
    Write-Host 'Все входы уже мёртвые — продлевать нечего. Почини их в менеджере.' -ForegroundColor Yellow
    Read-Host 'Enter — выход'; exit
}

Write-Host ("Проверяю на аккаунте: {0}" -f $acc.Alias) -ForegroundColor Green
Write-Host ''

# --- какие запросы пробуем. Все — только чтение.
$probes = @(
    @{ Name = 'кто я';             Url = 'https://users.roblox.com/v1/users/authenticated' },
    @{ Name = 'сколько Robux';     Url = 'https://economy.roblox.com/v1/user/currency' },
    @{ Name = 'есть ли Premium';   Url = ('https://premiumfeatures.roblox.com/v1/users/' + $acc.UserId + '/validate-membership') },
    @{ Name = 'мои настройки';     Url = 'https://accountsettings.roblox.com/v1/email' },
    @{ Name = 'главная страница';  Url = 'https://www.roblox.com/home' }
)

$rotated = @()
foreach ($p in $probes) {
    $line = '{0,-22}' -f $p.Name
    try {
        $r = Invoke-RamRequest -Method GET -Url $p.Url -Cookie $acc.Cookie
        $fresh = Get-RamRefreshedCookie -SetCookieHeaders $r.SetCookies

        if ($fresh -and $fresh -ne $acc.Cookie) {
            $line += ('код {0}   ПРИСЛАЛ НОВУЮ КУКУ (длина {1})' -f $r.Status, $fresh.Length)
            Write-Host $line -ForegroundColor Green
            $rotated += $p.Name
        } else {
            $line += ('код {0}   новой куки нет' -f $r.Status)
            Write-Host $line -ForegroundColor DarkGray
        }
    } catch {
        Write-Host ($line + 'ошибка: ' + $_.Exception.Message) -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '--------------------------------------------------'
if ($rotated.Count -gt 0) {
    Write-Host ('Продление РАБОТАЕТ. Куку обновляют: ' + ($rotated -join ', ')) -ForegroundColor Green
    Write-Host 'Значит фоновое продление входов имеет смысл встроить в менеджер.'
} else {
    Write-Host 'Продление НЕ работает: ни один запрос новой куки не прислал.' -ForegroundColor Yellow
    Write-Host 'Значит обещать «входы больше не будут вылетать» нельзя — это'
    Write-Host 'сторона Roblox. Рабочее средство остаётся одно: кнопка «Починить'
    Write-Host 'входы», она забирает свежий вход из приложения Roblox.'
}
Write-Host ''
Read-Host 'Enter — закрыть'
