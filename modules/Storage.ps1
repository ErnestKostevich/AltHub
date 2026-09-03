#requires -Version 5.1
<#
================================================================================
 Storage.ps1 — хранение аккаунтов на диске
================================================================================
 Что делает файл:
   1) Шифрует и расшифровывает список аккаунтов (там лежат куки .ROBLOSECURITY).
   2) Читает/пишет обычные настройки (они не секретные, лежат открыто).

 Два режима шифрования, оба стандартные средства Windows/.NET:

   DPAPI  (по умолчанию) — Windows Data Protection API.
          Ключ привязан к твоей учётке Windows. Файл, скопированный на другой
          ПК или открытый другим пользователем Windows, не расшифруется вообще
          никак. Пароль вводить не надо.
          Минус: переустановил Windows / сменил учётку — данные потеряны
          (это не страшно, просто заново вставишь куки).

   AES    (по желанию) — AES-256-CBC + HMAC-SHA256, ключ из твоего пароля
          через PBKDF2-SHA256, 200 000 итераций. Файл переносится на другой ПК,
          но при каждом запуске спрашивает пароль.

 Куда пишется: <папка программы>\data\accounts.dat  (зашифровано)
               <папка программы>\data\settings.json (открыто, без секретов)
 Никуда наружу ничего не отправляется — это чистая работа с локальным файлом.
================================================================================
#>

# Дополнительная "соль" для DPAPI. Даже если кто-то скопирует файл и войдёт
# под твоей учёткой, без этой строки из исходника он его не развернёт.
#
# НЕ МЕНЯТЬ. Эта строка входит в ключ шифрования: поменяешь хоть символ —
# и уже сохранённый dataccounts.dat перестанет расшифровываться, все
# аккаунты придётся добавлять заново. Имя внутри осталось старым намеренно,
# именно поэтому переименование проекта её не затронуло.
$script:RamEntropy = [System.Text.Encoding]::UTF8.GetBytes('RobloxManager/local-store/v1')

# ------------------------------------------------------------------ пути ----

function Get-RamDataDir {
    $dir = Join-Path (Split-Path -Parent $PSScriptRoot) 'data'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-RamAccountsPath { Join-Path (Get-RamDataDir) 'accounts.dat' }
function Get-RamSettingsPath { Join-Path (Get-RamDataDir) 'settings.json' }

# ------------------------------------------------------------- поддержка ----

function Test-RamDpapiAvailable {
    <# DPAPI есть в Windows PowerShell 5.1. В pwsh 7 может отсутствовать —
       тогда программа сама предложит режим AES с паролем. #>
    try {
        Add-Type -AssemblyName System.Security -ErrorAction Stop
        $null = [System.Security.Cryptography.ProtectedData]
        return $true
    } catch {
        return $false
    }
}

function New-RamRandomBytes {
    param([int]$Count)
    $b = New-Object byte[] $Count
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($b) } finally { $rng.Dispose() }
    return $b
}

function New-RamKeysFromPassword {
    <# PBKDF2-SHA256 → 64 байта: первые 32 на AES, вторые 32 на HMAC. #>
    param(
        [Parameter(Mandatory)][string]$Password,
        [Parameter(Mandatory)][byte[]]$Salt,
        [int]$Iterations = 200000
    )
    try {
        $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
            $Password, $Salt, $Iterations,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    } catch {
        # Очень старый .NET — откат на PBKDF2-SHA1 (тоже приемлемо).
        $kdf = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($Password, $Salt, $Iterations)
    }
    try {
        $raw = $kdf.GetBytes(64)
    } finally {
        $kdf.Dispose()
    }
    return [pscustomobject]@{
        Aes  = $raw[0..31]
        Hmac = $raw[32..63]
    }
}

# ------------------------------------------------------------ шифрование ----

function Protect-RamBytes {
    <# Возвращает объект-конверт, готовый к сериализации в JSON. #>
    param(
        [Parameter(Mandatory)][byte[]]$Data,
        [string]$Password
    )

    if ([string]::IsNullOrEmpty($Password)) {
        if (-not (Test-RamDpapiAvailable)) {
            throw 'DPAPI недоступен в этой версии PowerShell. Задай мастер-пароль в настройках.'
        }
        $blob = [System.Security.Cryptography.ProtectedData]::Protect(
            $Data, $script:RamEntropy,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [pscustomobject]@{
            v    = 1
            mode = 'dpapi'
            data = [Convert]::ToBase64String($blob)
        }
    }

    $salt = New-RamRandomBytes 16
    $iv   = New-RamRandomBytes 16
    $keys = New-RamKeysFromPassword -Password $Password -Salt $salt

    $aes = [System.Security.Cryptography.Aes]::Create()
    try {
        $aes.KeySize = 256
        $aes.Mode    = [System.Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key     = $keys.Aes
        $aes.IV      = $iv
        $enc = $aes.CreateEncryptor()
        try { $cipher = $enc.TransformFinalBlock($Data, 0, $Data.Length) }
        finally { $enc.Dispose() }
    } finally {
        $aes.Dispose()
    }

    # Encrypt-then-MAC: подписываем salt+iv+шифротекст, чтобы файл нельзя было
    # незаметно подменить и чтобы неверный пароль отсекался до расшифровки.
    $hm = New-Object System.Security.Cryptography.HMACSHA256(,$keys.Hmac)
    try { $mac = $hm.ComputeHash(($salt + $iv + $cipher)) }
    finally { $hm.Dispose() }

    return [pscustomobject]@{
        v          = 1
        mode       = 'aes'
        iterations = 200000
        salt       = [Convert]::ToBase64String($salt)
        iv         = [Convert]::ToBase64String($iv)
        mac        = [Convert]::ToBase64String($mac)
        data       = [Convert]::ToBase64String($cipher)
    }
}

function Unprotect-RamBytes {
    param(
        [Parameter(Mandatory)]$Envelope,
        [string]$Password
    )

    if ($Envelope.mode -eq 'dpapi') {
        if (-not (Test-RamDpapiAvailable)) {
            throw 'Файл зашифрован через DPAPI, но DPAPI недоступен. Запусти через powershell.exe (5.1).'
        }
        $blob = [Convert]::FromBase64String($Envelope.data)
        return [System.Security.Cryptography.ProtectedData]::Unprotect(
            $blob, $script:RamEntropy,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
    }

    if ($Envelope.mode -eq 'aes') {
        if ([string]::IsNullOrEmpty($Password)) { throw 'Нужен мастер-пароль.' }

        $salt   = [Convert]::FromBase64String($Envelope.salt)
        $iv     = [Convert]::FromBase64String($Envelope.iv)
        $cipher = [Convert]::FromBase64String($Envelope.data)
        $mac    = [Convert]::FromBase64String($Envelope.mac)

        $iters = 200000
        if ($Envelope.PSObject.Properties.Name -contains 'iterations') { $iters = [int]$Envelope.iterations }
        $keys = New-RamKeysFromPassword -Password $Password -Salt $salt -Iterations $iters

        $hm = New-Object System.Security.Cryptography.HMACSHA256(,$keys.Hmac)
        try { $calc = $hm.ComputeHash(($salt + $iv + $cipher)) }
        finally { $hm.Dispose() }

        # Сравнение за постоянное время.
        $diff = 0
        if ($calc.Length -ne $mac.Length) { $diff = 1 }
        else { for ($i = 0; $i -lt $calc.Length; $i++) { $diff = $diff -bor ($calc[$i] -bxor $mac[$i]) } }
        if ($diff -ne 0) { throw 'Неверный мастер-пароль (или файл повреждён).' }

        $aes = [System.Security.Cryptography.Aes]::Create()
        try {
            $aes.KeySize = 256
            $aes.Mode    = [System.Security.Cryptography.CipherMode]::CBC
            $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
            $aes.Key     = $keys.Aes
            $aes.IV      = $iv
            $dec = $aes.CreateDecryptor()
            try { return $dec.TransformFinalBlock($cipher, 0, $cipher.Length) }
            finally { $dec.Dispose() }
        } finally {
            $aes.Dispose()
        }
    }

    throw "Неизвестный формат хранилища: '$($Envelope.mode)'."
}

# ------------------------------------------------------------- аккаунты -----

function New-RamAccount {
    <#
      Один аккаунт. Новые поля добавляются сюда — при загрузке старого файла
      недостающие подставятся автоматически (см. Load-RamAccounts), так что
      обновление программы не ломает уже сохранённые данные.
    #>
    param(
        [string]$Alias    = 'Новый аккаунт',
        [string]$Cookie   = '',
        [string]$PlaceId  = '',
        [string]$JobId    = '',
        [string]$LinkCode = '',
        [string]$Note     = ''
    )
    [pscustomobject]@{
        Id               = [guid]::NewGuid().ToString()
        Alias            = $Alias
        Cookie           = $Cookie
        Username         = ''
        UserId           = 0

        # --- куда заходить
        PlaceId          = $PlaceId
        GameName         = ''
        JobId            = $JobId
        LinkCode         = $LinkCode

        # --- как выглядит в списке
        Note             = $Note
        Color            = ''      # цветная метка: '', red, orange, green, blue, purple
        Group            = ''      # название набора, пусто = без набора
        Order            = 0       # порядок в списке, меняется перетаскиванием

        # --- настройки клиента Roblox для этого аккаунта
        # Пустая строка означает "не трогать, оставить как есть в Roblox".
        Graphics         = ''      # '' | 'auto' | 1..10
        FramerateCap     = ''      # '' | 0 (без ограничения) | 30 | 60 | 120 | 240
        Volume           = ''      # '' | 0..100
        Fullscreen       = ''      # '' | 'yes' | 'no'

        # --- своё место окна на экране
        WindowX          = -1      # -1 = не запомнено
        WindowY          = -1
        WindowW          = -1
        WindowH          = -1

        # --- справка об аккаунте (обновляется кнопкой «Куки»)
        Robux            = -1      # -1 = не спрашивали
        Premium          = ''      # '' | 'yes' | 'no'
        Created          = ''      # дата регистрации

        # --- состояние входа
        CookieOk         = ''      # '' | 'yes' | 'no'
        CookieCheckedAt  = ''      # когда последний раз проверяли

        # --- статистика
        LaunchCount      = 0
        CrashCount       = 0
        PlaySeconds      = 0
        LastUsed         = ''

        # Свой стабильный browserTrackerId на аккаунт: так каждый аккаунт
        # выглядит для Roblox как отдельный постоянный браузер, а не как
        # новый случайный при каждом запуске.
        BrowserTrackerId = [string](Get-Random -Minimum 100000000 -Maximum 999999999) + [string](Get-Random -Minimum 100 -Maximum 999)
    }
}

function Save-RamAccounts {
    param(
        # AllowNull нужен вместе с AllowEmptyCollection: пустой список,
        # прошедший через возврат из функции, приходит сюда как $null.
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()][object[]]$Accounts,
        [string]$Password
    )
    if ($null -eq $Accounts) { $Accounts = @() }
    # Та же защита, что и у настроек, и специально ЗДЕСЬ, а не только в
    # Save-RamState: перешифровка в диалоге настроек зовёт эту функцию
    # напрямую, минуя Save-RamState. Один пропущенный вызов — и проверочный
    # запуск затрёт настоящие аккаунты, поэтому замок стоит на самой записи.
    if ($script:ReadOnly) { return }

    $json  = ConvertTo-Json -InputObject @($Accounts) -Depth 6 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $envelope = Protect-RamBytes -Data $bytes -Password $Password

    $path = Get-RamAccountsPath
    $tmp  = "$path.tmp"
    ConvertTo-Json -InputObject $envelope -Depth 4 | Set-Content -LiteralPath $tmp -Encoding UTF8 -Force
    Move-Item -LiteralPath $tmp -Destination $path -Force

    # Затираем открытый текст в памяти, насколько это возможно в .NET.
    [Array]::Clear($bytes, 0, $bytes.Length)
}

function Load-RamAccounts {
    param([string]$Password)

    $path = Get-RamAccountsPath
    if (-not (Test-Path -LiteralPath $path)) { return @() }

    $envelope = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
    $bytes    = Unprotect-RamBytes -Envelope $envelope -Password $Password
    $json     = [System.Text.Encoding]::UTF8.GetString($bytes)
    [Array]::Clear($bytes, 0, $bytes.Length)

    # ВНИМАНИЕ: в PowerShell 5.1 ConvertFrom-Json отдаёт JSON-массив ОДНИМ
    # объектом, поэтому через конвейер ($json | ConvertFrom-Json) он вкладывается
    # сам в себя и foreach выдаёт массив вместо аккаунта. Только -InputObject.
    $parsed = ConvertFrom-Json -InputObject $json

    $list = @()
    foreach ($a in @($parsed)) {
        if ($null -eq $a) { continue }
        # Добираем поля, которых могло не быть в старом файле.
        $tpl = New-RamAccount
        foreach ($p in $tpl.PSObject.Properties.Name) {
            if ($a.PSObject.Properties.Name -notcontains $p) {
                $a | Add-Member -NotePropertyName $p -NotePropertyValue $tpl.$p
            }
        }
        $list += $a
    }
    return @($list)
}

function Get-RamStorageMode {
    <# 'none' — файла ещё нет; иначе 'dpapi' / 'aes'. #>
    $path = Get-RamAccountsPath
    if (-not (Test-Path -LiteralPath $path)) { return 'none' }
    try {
        $envelope = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $path -Raw -Encoding UTF8)
        return [string]$envelope.mode
    } catch {
        return 'broken'
    }
}

# ------------------------------------------------------------- настройки ----

function Get-RamDefaultSettings {
    [pscustomobject]@{
        LaunchDelaySec  = 8      # пауза между запусками аккаунтов
        Locale          = 'ru_ru'
        Theme           = 'dark' # ключ темы (стоковой или своей)
        CustomThemes    = @()    # свои темы: @{ Key; Title; Colors=@{Bg;...} }
        Games           = @()    # сохранённые игры: @{ Title; PlaceId; LinkCode }
        TileMode        = 'grid' # grid | cascade | columns | rows | main
        Section         = 'accounts'  # какой раздел бокового меню открыть
        CompactCards    = $false      # ужатые карточки
        UseSavedWindows = $true       # ставить окна на запомненные места
        AutoStartGroup  = ''          # набор, который поднимать при старте
        AutoStartAtTime = ''          # 'ЧЧ:ММ' — запуск набора по времени
        ShowEmoji       = $true       # рисовать смайлики в названиях игр
        LogToFile       = $true       # писать журнал в data\logs
        WatchGroup      = ''          # набор, который держать в игре
        Profiles        = @()         # профили запуска: @{ Name; Group; PlaceId; LinkCode; GameName }
        HotkeySwitch    = $true       # Ctrl+1..9 переключают окна аккаунтов
        # Куда девается окно.
        #
        # Настройки «куда девать по минусу» БОЛЬШЕ НЕТ, и это намеренно: минус
        # всегда сворачивает в панель задач. Когда он прятал окно, а значок в
        # часах оказывался невидим, программа пропадала совсем — вернуть её
        # было нечем. В часы уводит только крестик и только после того, как
        # человек подтвердил, что значок видит (см. Confirm-RamTrayVisible).
        OnClose         = 'tray'      # exit | tray
        TrayHintShown   = $false      # показывали ли подсказку «ищи под стрелкой»
        TrayConfirmed   = $false      # человек подтвердил, что значок видно
        WindowFixApplied = $false     # разовая починка настроек из сломанных версий
        CheckOnStart    = $true       # проверять входы при открытии менеджера
        AutoRestart     = $false # поднимать аккаунт заново, если клиент вылетел
        AutoRestartMax  = 3      # сколько раз подряд пытаться
        RenameWindows   = $true  # писать имя аккаунта в заголовок окна
        AutoTile        = $true  # раскладывать окна сеткой после запуска
        TileColumns     = 0      # 0 = подобрать автоматически
        TileMargin      = 4
        KeepMutex       = $true  # держать мьютекс мультизапуска
        ConfirmOnExit   = $true
        FirstRunDone    = $false # прошёл ли человек мастер первого запуска
    }
}

function Load-RamSettings {
    $path = Get-RamSettingsPath
    $s = Get-RamDefaultSettings
    if (Test-Path -LiteralPath $path) {
        try {
            $loaded = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $s.PSObject.Properties.Name) {
                if ($loaded.PSObject.Properties.Name -contains $p) { $s.$p = $loaded.$p }
            }

            # РАЗОВАЯ ПОЧИНКА ТЕХ, КОГО СЛОМАЛО.
            #
            # В версиях 1.2 старый флаг MinimizeToTray переносился в
            # OnMinimize = 'tray', и минус начинал ПРЯТАТЬ окно. Если значок
            # в часах был не виден, программа пропадала насовсем. Настройки
            # такого вида надо обезвредить, иначе обновившиеся так и останутся
            # со сломанным поведением.
            $names = $loaded.PSObject.Properties.Name
            if (-not [bool]$s.WindowFixApplied) {
                $s.WindowFixApplied = $true

                # Старое значение OnClose НЕ сохраняем нарочно. До этой версии
                # «крестик в часы» был сломан: окно жило в ShowDialog(), и
                # попытка спрятать его завершала программу. Значит никто не мог
                # осознанно выбрать «в часы» и остаться доволен — у всех стояло
                # «закрывать» просто потому, что иначе не работало. Поэтому
                # один раз ставим новое умолчание, а дальше человек решает сам.
                $s.OnClose = 'tray'
                $s.TrayConfirmed = $false
            }
        } catch { }
    }

    # Мусор в файле не должен превращаться в непонятное поведение окна.
    if ($s.OnClose -notin @('exit', 'tray')) { $s.OnClose = 'exit' }
    return $s
}

function Save-RamSettings {
    param([Parameter(Mandatory)]$Settings)

    # Та же защита, что и у аккаунтов: проверочные запуски (-NoAutoStart)
    # ничего не пишут на диск, иначе тест затёр бы настройки пользователя.
    if ($script:ReadOnly) { return }

    ConvertTo-Json -InputObject $Settings -Depth 4 |
        Set-Content -LiteralPath (Get-RamSettingsPath) -Encoding UTF8 -Force
}
