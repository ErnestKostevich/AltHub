#requires -Version 5.1
<#
================================================================================
 Диагностика.ps1 — узнать, что именно отвечает Roblox
================================================================================
 Запускать, когда менеджер пишет что-то вроде «Roblox отказал в билете запуска».

 ЧТО ОНА ПОКАЗЫВАЕТ: только коды ответов сервера и короткие куски ответов.
 ЧТО ОНА НЕ ПОКАЗЫВАЕТ: куки. Ни целиком, ни кусками. Перед выводом каждая
 строка прогоняется через вырезание секретов, а сами куки в переменные вывода
 вообще не попадают.

 Вывод можно спокойно копировать и показывать — в нём нет ничего секретного.
================================================================================
#>

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

. (Join-Path $root 'AltHub.ps1') -NoAutoStart

function Protect-RamOutput {
    <# Страховка: что бы ни попало в строку, секреты вырезаем. #>
    param([string]$Text)
    if ($null -eq $Text) { return '' }
    $t = $Text -replace '_\|WARNING[^\s"'',]*', '<кука вырезана>'
    $t = $t     -replace '[A-Za-z0-9_\-]{60,}', '<длинный токен вырезан>'
    return $t
}

function Show-Line {
    param([string]$Text, [string]$Color = 'Gray')
    Write-Host (Protect-RamOutput $Text) -ForegroundColor $Color
}

Write-Host ''
Write-Host 'AltHub — диагностика связи с Roblox' -ForegroundColor Cyan
Write-Host '======================================================'
Write-Host 'Куки в этом выводе не показываются. Его можно копировать целиком.' -ForegroundColor DarkGray
Write-Host ''

# ---------------------------------------------------------------- аккаунты --
$accounts = @()
try {
    $mode = Get-RamStorageMode
    if ($mode -eq 'aes') {
        $pw = Read-Host 'Хранилище под мастер-паролем. Введи его' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw)
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        $accounts = Load-RamAccounts -Password $plain
        $plain = $null
    } else {
        $accounts = Load-RamAccounts -Password ''
    }
} catch {
    Show-Line ("Не смог прочитать список аккаунтов: " + $_.Exception.Message) 'Red'
    Write-Host ''
    Write-Host 'Нажми Enter, чтобы закрыть.' -ForegroundColor DarkGray
    [void](Read-Host); return
}

Show-Line ("Аккаунтов в менеджере: " + @($accounts).Count) 'White'
Write-Host ''

# ------------------------------------------------------------- окружение ----
Write-Host 'ОКРУЖЕНИЕ' -ForegroundColor Cyan
Show-Line ("  Windows PowerShell : " + $PSVersionTable.PSVersion.ToString())
Show-Line ("  Клиентов Roblox    : " + @(Get-RamRobloxProcesses).Count)
try { Show-Line ("  Клиент             : " + (Split-Path -Leaf (Split-Path -Parent (Get-RamRobloxPlayerPath)))) }
catch { Show-Line ("  Клиент             : не найден") 'Red' }
Show-Line ("  Вход в приложении  : " + $(if (Test-RamRobloxCookieFile) { 'хранилище есть' } else { 'нет' }))
Write-Host ''

# ------------------------------------------------------------- проверки -----
$i = 0
foreach ($a in $accounts) {
    $i++
    Write-Host ("АККАУНТ $i из $(@($accounts).Count): $($a.Alias)") -ForegroundColor Cyan
    Show-Line ("  сохранённый ник: $($a.Username), ID $($a.UserId), длина куки $($a.Cookie.Length)")

    if ([string]::IsNullOrWhiteSpace($a.Cookie)) {
        Show-Line '  куки нет — пропускаю' 'Yellow'
        Write-Host ''
        continue
    }

    # --- шаг 1: жива ли кука вообще
    try {
        $who = Get-RamAuthenticatedUser -Cookie $a.Cookie
        Show-Line ("  [1] кто я         : 200 OK, $($who.Name) (ID $($who.Id))") 'Green'
    } catch {
        Show-Line ("  [1] кто я         : ОШИБКА — " + $_.Exception.Message) 'Red'
        Show-Line '      -> кука мертва, добавь аккаунт заново через мастер' 'Yellow'
        Write-Host ''
        continue
    }

    # --- шаг 2: какой код отдаёт каждый источник CSRF
    $sources = @(
        @{ N = 'authentication-ticket'; Url = 'https://auth.roblox.com/v1/authentication-ticket/';   Body = '' },
        @{ N = 'sharelinks/resolve';    Url = 'https://apis.roblox.com/sharelinks/v1/resolve-link';  Body = '{"linkId":"0","linkType":"Server"}' },
        @{ N = 'catalog/items/details'; Url = 'https://catalog.roblox.com/v1/catalog/items/details'; Body = '{"items":[{"itemType":"Asset","id":1}]}' }
    )
    $csrf = $null
    foreach ($s in $sources) {
        try {
            $r = Invoke-RamRequest -Method POST -Url $s.Url -Cookie $a.Cookie -Body $s.Body
            $hasTok = $r.Headers.ContainsKey('x-csrf-token')
            Show-Line ("  [2] CSRF {0,-22}: HTTP {1}, токен: {2}" -f $s.N, $r.Status, $(if ($hasTok) { 'ЕСТЬ' } else { 'нет' })) `
                      $(if ($hasTok) { 'Green' } else { 'Yellow' })
            if (-not $hasTok -and $r.Body) {
                $snippet = $r.Body.Substring(0, [Math]::Min(160, $r.Body.Length))
                Show-Line ("      ответ: " + $snippet) 'DarkGray'
            }
            if ($hasTok -and $null -eq $csrf) { $csrf = $r.Headers['x-csrf-token'] }
        } catch {
            Show-Line ("  [2] CSRF {0,-22}: исключение — {1}" -f $s.N, $_.Exception.Message) 'Red'
        }
    }

    if ($null -eq $csrf) {
        Show-Line '      -> ни один источник не дал токен, билет получить нельзя' 'Red'
        Write-Host ''
        continue
    }

    # --- шаг 3: сам билет запуска
    try {
        $r3 = Invoke-RamRequest -Method POST -Url 'https://auth.roblox.com/v1/authentication-ticket/' `
                                -Cookie $a.Cookie -Csrf $csrf -Body ''
        $hasTicket = $r3.Headers.ContainsKey('rbx-authentication-ticket')
        Show-Line ("  [3] билет запуска : HTTP {0}, билет: {1}" -f $r3.Status, $(if ($hasTicket) { 'ВЫДАН' } else { 'НЕ ВЫДАН' })) `
                  $(if ($hasTicket) { 'Green' } else { 'Red' })
        if (-not $hasTicket) {
            if ($r3.Body) {
                $snippet = $r3.Body.Substring(0, [Math]::Min(300, $r3.Body.Length))
                Show-Line ("      ответ: " + $snippet) 'DarkGray'
            }
            $interesting = $r3.Headers.Keys | Where-Object { $_ -match 'csrf|challenge|rbx|retry|www-auth' }
            foreach ($k in $interesting) {
                Show-Line ("      заголовок {0}: {1}" -f $k, $r3.Headers[$k]) 'DarkGray'
            }
        }
    } catch {
        Show-Line ("  [3] билет запуска : исключение — " + $_.Exception.Message) 'Red'
    }

    Write-Host ''
}

Write-Host '======================================================'
Write-Host 'Готово. Этот вывод можно копировать и показывать — куки в нём нет.' -ForegroundColor Green
Write-Host ''
Write-Host 'Нажми Enter, чтобы закрыть.' -ForegroundColor DarkGray
[void](Read-Host)
