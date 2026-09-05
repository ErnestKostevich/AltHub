#requires -Version 5.1
<#
  CookieBridge.ps1
  ----------------
  Приём входа из ТВОЕГО обычного браузера — того, в котором ты уже сидишь на
  roblox.com. Нажал горячую клавишу (по умолчанию F10) или кнопку AltHub на
  панели браузера — и аккаунт появился в списке. Ни F12, ни копирования.

  ПОЧЕМУ ЭТО УСТРОЕНО ЧЕРЕЗ РАСШИРЕНИЕ, А НЕ ПРОЩЕ.
  Кука .ROBLOSECURITY помечена HttpOnly — её не видит ни один скрипт на
  странице, поэтому закладкой-букмарклетом её не достать. В файле браузера
  она лежит зашифрованной ключом Windows и заперта, пока браузер запущен;
  лезть туда — это ровно то, чем занимаются программы-воришки, и делать так
  AltHub не будет. Остаётся единственный честный путь: попросить сам браузер
  отдать куку через его же официальный интерфейс. Это и есть расширение-мост
  из папки extension\, которое ставится руками один раз.

  ЧТО ЗДЕСЬ СЛУШАЕТ СЕТЬ. HttpListener на 127.0.0.1 — это петля внутри твоего
  компьютера, наружу такой порт не выходит. Слушаем, только пока приём включён
  в настройках; выключен — порт не занят вовсе. Три адреса, больше ничего:
    GET  /hello  — «да, это AltHub» (по нему расширение нас и находит)
    GET  /grab   — страничка-будильник для F10, сама себя закрывает
    POST /cookie — сюда расширение кладёт куку

  ЧТО СЮДА МОЖЕТ ПОСТУЧАТЬСЯ ЕЩЁ. Любая программа на этом же компьютере —
  порт общий для машины. Поэтому кука, пришедшая на /cookie, не принимается
  на веру: она проверяется на серверах Roblox тем же Get-RamAuthenticatedUser,
  что и все остальные способы. Не подтвердилась — аккаунт не добавляется.
#>

# Небольшой фиксированный диапазон: расширение обходит его подряд и находит
# нас само. Один жёсткий порт был бы хрупок — его может занять соседняя
# программа; тот же список продублирован в extension\background.js.
$script:BridgePorts = @(52713, 52714, 52715, 52716, 52717)

$script:Bridge = @{
    Listener = $null
    Port     = 0
    Task     = $null
    Timer    = $null
    ExtSeen  = $false      # расширение хоть раз поздоровалось
    LastHello = $null
}

function Get-RamBridgePort {
    <# Порт, на котором сейчас ждём, или 0. #>
    if ($null -eq $script:Bridge) { return 0 }
    return [int]$script:Bridge.Port
}

function Test-RamBridgeRunning {
    return ($null -ne $script:Bridge.Listener -and $script:Bridge.Listener.IsListening)
}

function Test-RamBridgeExtensionSeen {
    <# Здоровалось ли расширение с нами хоть раз за этот запуск. #>
    return [bool]$script:Bridge.ExtSeen
}

function Get-RamBridgeGrabPage {
    <#
      Страница-будильник для F10. Расширение MV3 засыпает, если ничего не
      происходит, и разбудить его снаружи нечем — но переход на страницу оно
      видит всегда. Поэтому F10 открывает вот это, расширение просыпается,
      отдаёт куку и закрывает вкладку само.
    #>
    return @'
<!doctype html><meta charset="utf-8"><title>AltHub</title>
<style>
 body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;
      font:16px "Segoe UI",system-ui,sans-serif;background:#16121f;color:#e8e3f5}
 div{text-align:center;line-height:1.6}
 b{color:#a78bfa}
</style>
<div><b>AltHub</b><br>Забираю вход и закрываю вкладку…<br>
<small>Если вкладка не закрылась — расширение AltHub не установлено в этом браузере.</small></div>
'@
}

function Save-RamExtensionIcons {
    <#
      Рисует значки расширения прямо в папку extension\.

      ЗАЧЕМ. Без значка Chrome не показывает кнопку расширения на панели —
      она есть, но выглядит как безымянный кусочек в меню-пазле, и найти её
      нельзя. Человек ставит расширение, смотрит на панель и справедливо
      говорит: «поставил, а ничего нет».

      ПОЧЕМУ РИСУЕМ, А НЕ КЛАДЁМ ФАЙЛ В РЕПОЗИТОРИЙ. Весь смысл проекта в том,
      что внутри только читаемый текст. Значок — двоичный файл, и он рождается
      здесь, на твоей машине, из того же рисунка, что и значок в часах.

      Рисуем один раз: если файлы уже есть, ничего не делаем.
    #>
    param([switch]$Force)

    $dir = Get-RamExtensionDir
    if (-not (Test-Path -LiteralPath $dir)) { return $false }

    $sizes = @(16, 48, 128)
    $need = $false
    foreach ($n in $sizes) {
        if (-not (Test-Path -LiteralPath (Join-Path $dir ("icon{0}.png" -f $n)))) { $need = $true }
    }
    if (-not $need -and -not $Force) { return $true }

    $accent = $Global:RamTheme.Accent
    try {
        foreach ($n in $sizes) {
            $bmp = New-Object System.Drawing.Bitmap($n, $n)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            try {
                $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
                $g.Clear([System.Drawing.Color]::Transparent)

                $pad = [Math]::Max(1, [int]($n * 0.06))
                $r   = [int]($n * 0.22)
                $rect = New-Object System.Drawing.Rectangle($pad, $pad, ($n - $pad * 2), ($n - $pad * 2))
                $path = New-Object System.Drawing.Drawing2D.GraphicsPath
                $d = $r * 2
                $path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
                $path.AddArc(($rect.Right - $d), $rect.Y, $d, $d, 270, 90)
                $path.AddArc(($rect.Right - $d), ($rect.Bottom - $d), $d, $d, 0, 90)
                $path.AddArc($rect.X, ($rect.Bottom - $d), $d, $d, 90, 90)
                $path.CloseFigure()
                $br = New-Object System.Drawing.SolidBrush($accent)
                $g.FillPath($br, $path)
                $br.Dispose(); $path.Dispose()

                # Буква A — та же, что на значке программы.
                $fs = [float]($n * 0.62)
                $fnt = New-Object System.Drawing.Font('Segoe UI', $fs, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
                $sf = New-Object System.Drawing.StringFormat
                $sf.Alignment = 'Center'; $sf.LineAlignment = 'Center'
                $wb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
                $g.DrawString('A', $fnt, $wb, (New-Object System.Drawing.RectangleF(0, 0, $n, $n)), $sf)
                $wb.Dispose(); $sf.Dispose(); $fnt.Dispose()
            } finally { $g.Dispose() }

            $bmp.Save((Join-Path $dir ("icon{0}.png" -f $n)), [System.Drawing.Imaging.ImageFormat]::Png)
            $bmp.Dispose()
        }
        Write-RamLog 'Значки расширения нарисованы в папке extension.' 'info'
        return $true
    } catch {
        Write-RamLog "Не вышло нарисовать значки расширения: $($_.Exception.Message)" 'warn'
        return $false
    }
}

function Start-RamCookieBridge {
    <#
      Занимает первый свободный порт из диапазона и начинает слушать.
      Возвращает порт или 0, если ни один не свободен.
    #>
    if (Test-RamBridgeRunning) { return $script:Bridge.Port }

    foreach ($port in $script:BridgePorts) {
        $l = New-Object System.Net.HttpListener
        $l.Prefixes.Add("http://127.0.0.1:$port/")
        try {
            $l.Start()
        } catch {
            try { $l.Close() } catch { }
            continue
        }
        $script:Bridge.Listener = $l
        $script:Bridge.Port     = $port
        $script:Bridge.Task     = $l.GetContextAsync()

        # Разбираем запросы в таймере окна, а не в отдельном потоке: у нас
        # однопоточный интерфейс, и добавление аккаунта всё равно должно
        # происходить в нём.
        $t = New-Object System.Windows.Forms.Timer
        $t.Interval = 200
        # Под защитой: это обработчик таймера, и необработанная ошибка внутри
        # него роняет весь интерфейс. Проверка «Есть защита от падения» на
        # этом месте и сработала, когда защиты не было.
        $t.Add_Tick({ Invoke-RamSafe -What 'приём из браузера' -Body { Invoke-RamBridgePump } })
        $t.Start()
        $script:Bridge.Timer = $t

        Write-RamLog "Приём из браузера включён, жду на 127.0.0.1:$port." 'ok'
        return $port
    }

    Write-RamLog 'Приём из браузера: все порты диапазона заняты, включить не вышло.' 'warn'
    return 0
}

function Stop-RamCookieBridge {
    <# Освобождает порт. После этого снаружи достучаться некуда. #>
    if ($null -ne $script:Bridge.Timer) {
        try { $script:Bridge.Timer.Stop(); $script:Bridge.Timer.Dispose() } catch { }
        $script:Bridge.Timer = $null
    }
    if ($null -ne $script:Bridge.Listener) {
        try { $script:Bridge.Listener.Stop() } catch { }
        try { $script:Bridge.Listener.Close() } catch { }
        Write-RamLog "Приём из браузера выключен, порт $($script:Bridge.Port) освобождён." 'info'
    }
    $script:Bridge.Listener = $null
    $script:Bridge.Task     = $null
    $script:Bridge.Port     = 0
}

function Invoke-RamBridgePump {
    <# Один заход: если запрос пришёл — обработать и снова встать в ожидание. #>
    if (-not (Test-RamBridgeRunning)) { return }
    $task = $script:Bridge.Task
    if ($null -eq $task -or -not $task.IsCompleted) { return }

    $ctx = $null
    try { $ctx = $task.GetAwaiter().GetResult() } catch { }
    $script:Bridge.Task = $script:Bridge.Listener.GetContextAsync()
    if ($null -eq $ctx) { return }

    try {
        $req  = $ctx.Request
        $resp = $ctx.Response
        # Расширение обращается к нам со своего origin chrome-extension://...
        # '*' здесь безопасен: слушаем только петлю на своей же машине.
        $resp.Headers.Add('Access-Control-Allow-Origin', '*')
        $resp.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        $resp.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')

        if ($req.HttpMethod -eq 'OPTIONS') {
            $resp.StatusCode = 204
            $resp.Close()
            return
        }

        $path = $req.Url.AbsolutePath.ToLowerInvariant()
        $body = ''
        if ($req.HasEntityBody) {
            $rd = New-Object System.IO.StreamReader($req.InputStream, [System.Text.Encoding]::UTF8)
            $body = $rd.ReadToEnd()
            $rd.Dispose()
        }

        switch ($path) {
            '/hello' {
                $script:Bridge.ExtSeen   = $true
                $script:Bridge.LastHello = Get-Date
                Write-RamBridgeText -Response $resp -Text 'althub' -Type 'text/plain'
            }
            '/grab' {
                Write-RamBridgeText -Response $resp -Text (Get-RamBridgeGrabPage) -Type 'text/html; charset=utf-8'
            }
            '/cookie' {
                $script:Bridge.ExtSeen = $true
                Write-RamBridgeText -Response $resp -Text 'ok' -Type 'text/plain'
                if (-not [string]::IsNullOrWhiteSpace($body)) {
                    Receive-RamBridgeCookie -Cookie $body.Trim()
                }
            }
            '/problem' {
                $script:Bridge.ExtSeen = $true
                Write-RamBridgeText -Response $resp -Text 'ok' -Type 'text/plain'
                if (-not [string]::IsNullOrWhiteSpace($body)) {
                    $why = $body.Trim()
                    Write-RamLog "Приём из браузера: $why" 'warn'
                    Show-RamMessage -Kind 'warn' -Message ('Не вышло забрать вход из браузера.' +
                        [Environment]::NewLine + [Environment]::NewLine + $why)
                    Show-RamMainWindow
                }
            }
            default {
                $resp.StatusCode = 404
                Write-RamBridgeText -Response $resp -Text 'no' -Type 'text/plain'
            }
        }
    } catch {
        Write-RamLog "Приём из браузера: сбой при разборе запроса: $($_.Exception.Message)" 'warn'
        try { $ctx.Response.Close() } catch { }
    }
}

function Write-RamBridgeText {
    param(
        [Parameter(Mandatory)]$Response,
        [string]$Text = '',
        [string]$Type = 'text/plain'
    )
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $Response.ContentType = $Type
        $Response.ContentLength64 = $bytes.Length
        $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } catch { }
    try { $Response.Close() } catch { }
}

function Receive-RamBridgeCookie {
    <#
      Пришла кука от расширения. Дальше — обычный путь любого способа:
      Import-RamAccountLine сам проверит её на серверах Roblox и либо добавит
      аккаунт, либо обновит существующий. Сама кука в журнал не попадает —
      Write-RamLog её вырезает.
    #>
    param([Parameter(Mandatory)][string]$Cookie)

    $r = $null
    try {
        $r = Import-RamAccountLine -Line $Cookie
    } catch {
        Write-RamLog "Приём из браузера: не удалось добавить аккаунт: $($_.Exception.Message)" 'err'
        return
    }

    if ($r -and $r.Ok) {
        Write-RamLog "Из браузера добавлен аккаунт: $($r.Alias)" 'ok'
        Save-RamState
        if ($script:UI.ContainsKey('Cards')) {
            Invoke-RamSafe -What 'обновление списка после приёма из браузера' -Body {
                Build-RamCards
                Update-RamHeaderCounts
            }
        }

        # УСПЕХ НЕ ДОЛЖЕН БЫТЬ МОЛЧАЛИВЫМ.
        # Раньше он уходил ОДНОЙ СТРОКОЙ В ЖУРНАЛ — а окно AltHub в этот
        # момент за браузером, человек его не видит. Кука доезжала, аккаунт
        # обновлялся, в журнале стояло «добавлен» — и со стороны это выглядело
        # как «нажал, ничего не произошло». Восемь раз подряд.
        #
        # Поэтому: поднимаем окно и говорим словами, что именно приехало.
        Show-RamMainWindow
        $what = if ($r.New) { 'Добавлен аккаунт' } else { 'Обновлён вход' }
        Show-RamMessage -Kind 'ok' -Message ("$what из браузера:" + [Environment]::NewLine + [Environment]::NewLine +
                                             $r.Alias)
    } else {
        $why = if ($r -and $r.Error) { $r.Error } else { 'Roblox не подтвердил вход' }
        Write-RamLog "Приём из браузера: кука пришла, но аккаунт не добавлен — $why" 'warn'
    }
}

function Set-RamBridgeHotkeyWithFallback {
    <#
      Вешает клавишу приёма, а если Windows её не отдала — берёт следующую
      свободную и ГОВОРИТ об этом.

      ПОЧЕМУ ЭТО ВАЖНО. F10 — обычная клавиша, её часто держит что-то другое:
      игра, оверлей, другой менеджер. RegisterHotKey в таком случае просто
      отвечает «нет». Раньше на этом всё и заканчивалось: в журнал уходила
      строчка, которую никто не читает, а человек жал F10 на странице Roblox
      и не понимал, почему ничего не происходит. Молчаливый отказ — худший
      вид поломки: программа выглядит сломанной целиком, хотя не работает
      одна клавиша.
    #>
    param(
        [Parameter(Mandatory)][string]$Preferred,
        [switch]$Announce
    )

    if (Register-RamBridgeHotkey -Key $Preferred) {
        Write-RamLog "Приём из браузера: клавиша $Preferred." 'ok'
        return $Preferred
    }

    foreach ($k in (Get-RamBridgeHotkeyChoices)) {
        if ($k -eq $Preferred) { continue }
        if (Register-RamBridgeHotkey -Key $k) {
            $script:Settings.BridgeHotkey = $k
            Save-RamSettings -Settings $script:Settings
            Write-RamLog "Клавишу $Preferred держит другая программа — приём переехал на $k." 'warn'
            if ($Announce) {
                Show-RamMessage -Kind 'warn' -Message (
                    "Клавишу $Preferred в этой системе уже занимает другая программа, и Windows не отдала её AltHub." +
                    [Environment]::NewLine + [Environment]::NewLine +
                    "Приём входа переехал на $k — жми её на странице roblox.com." +
                    [Environment]::NewLine + [Environment]::NewLine +
                    'Клавишу можно выбрать другую в настройках, раздел «Из браузера». А можно вообще не пользоваться клавишей: на панели браузера есть значок AltHub, он делает то же самое.')
            }
            return $k
        }
    }

    Write-RamLog 'Все клавиши приёма заняты другими программами.' 'err'
    if ($Announce) {
        Show-RamMessage -Kind 'warn' -Message (
            'Ни одну из клавиш приёма Windows не отдала — их держат другие программы.' +
            [Environment]::NewLine + [Environment]::NewLine +
            'Приём из браузера всё равно работает: нажми значок AltHub на панели браузера, он делает ровно то же самое.')
    }
    return ''
}

function Invoke-RamBrowserGrab {
    <#
      Действие горячей клавиши. Открывает страницу-будильник в браузере ПО
      УМОЛЧАНИЮ — в том самом, где человек и сидит на roblox.com.

      Почему не «просто попросить расширение»: снаружи его не позвать. MV3
      усыпляет расширение через полминуты бездействия, и разбудить его может
      только событие внутри браузера — например, переход на страницу. Отсюда
      и вкладка, которая мелькает и закрывается сама.
    #>
    $port = Get-RamBridgePort
    if ($port -le 0) {
        # Молча ничего не делать нельзя: человек нажал клавишу и ждёт
        # результата. Если приёма нет — надо сказать и сразу предложить
        # включить, а не отправлять искать настройку самому.
        Write-RamLog 'Приём из браузера выключен.' 'warn'
        if (Confirm-Ram ('Приём входа из браузера сейчас выключен, поэтому нажатие ничего не сделало.' +
                         [Environment]::NewLine + [Environment]::NewLine + 'Включить его?')) {
            $script:Settings.BridgeEnabled = $true
            Save-RamSettings -Settings $script:Settings
            Update-RamCookieBridgeState
            if (-not (Test-RamBridgeExtensionSeen)) { Show-RamExtensionGuide }
        }
        return $false
    }
    $url = "http://127.0.0.1:$port/grab?althub_grab=$port"
    try {
        Start-Process $url | Out-Null
        Write-RamLog 'Прошу браузер отдать текущий вход…' 'info'
        return $true
    } catch {
        Write-RamLog "Не удалось открыть браузер: $($_.Exception.Message)" 'err'
        return $false
    }
}

function Get-RamExtensionDir {
    <# Папка расширения — её человек и указывает в «Загрузить распакованное». #>
    return (Join-Path $script:Root 'extension')
}
function Update-RamCookieBridgeState {
    <#
      Приводит приём в соответствие с настройками — включает, выключает или
      перевешивает клавишу. Зовётся при сохранении настроек, чтобы галочка
      срабатывала сразу, а не после перезапуска: иначе человек её ставит,
      жмёт клавишу и решает, что ничего не работает.
    #>
    $want = [bool]$script:Settings.BridgeEnabled
    $key  = [string]$script:Settings.BridgeHotkey

    Unregister-RamBridgeHotkey

    if (-not $want) {
        Stop-RamCookieBridge
        return
    }

    $port = Start-RamCookieBridge
    if ($port -le 0) { return }

    # Окно горячих клавиш могло быть не создано: Ctrl+1..9 выключены, а приём
    # человек только что включил.
    if ($null -eq $Global:RamHotkeyWindow) {
        [void](Register-RamHotkeys -OnPressed {
            param($sender, $e)
            if ($e.Id -eq 20) {
                Invoke-RamSafe -What 'приём входа из браузера' -Body { [void](Invoke-RamBrowserGrab) }
            } else {
                Invoke-RamFocusAccountByIndex -Index $e.Id
            }
        } -SkipSwitchKeys:(-not $script:Settings.HotkeySwitch))
    }

    [void](Set-RamBridgeHotkeyWithFallback -Preferred $key -Announce)
}
