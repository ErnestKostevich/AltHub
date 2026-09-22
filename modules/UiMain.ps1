#requires -Version 5.1
<#
================================================================================
 modules\UiMain.ps1 — главное окно и его разделы
================================================================================
 Карточки аккаунтов, боковое меню, разделы «Аккаунты», «Игры», «Профили»,
 «Статистика» и «Журнал», значок в часах и сборка самого окна.
================================================================================
#>

# --------------------------------------------------------- карточки ---------

function Get-RamHeaderBottom {
    <#
      Низ самого нижнего элемента шапки раздела плюс зазор.

      ЗАЧЕМ. Шапки разделов раньше отмерялись числами: 66 у «Игр» и «Профилей»,
      46 у «Статистики» и «Журнала». Числа подбирались под шрифт 100% и под тот
      набор подписей, который был в тот день. Стоило шрифту вырасти или
      добавиться строке — список наезжал на подпись. Ровно это и произошло с
      «Профилями»: карточка профиля закрыла собой пояснение под заголовком.

      Считать по факту нельзя ошибиться: список начинается там, где кончилась
      шапка, что бы в неё ни положили.
    #>
    param(
        [Parameter(Mandatory)]$Panel,
        [int]$Gap = 0
    )
    # Visible здесь НЕ спрашиваем. Разделы кроме открытого спрятаны, а у
    # скрытой панели все дети тоже отвечают Visible = false — с этой проверкой
    # мерка возвращала ноль, и список наезжал на всю шапку целиком.
    $bottom = 0
    foreach ($c in $Panel.Controls) {
        if ($c.Bottom -gt $bottom) { $bottom = $c.Bottom }
    }
    if ($Gap -le 0) { $Gap = $Global:RamTheme.M.GapSm }
    return $bottom + $Gap
}

function Get-RamCardWidth {
    <# Раньше здесь стоял жёсткий пол в 700px (Math.Max(700, ...)) — при
       сжатии окна ниже этой ширины карточка продолжала рисоваться на 700px
       независимо от реальной ширины контейнера. Кнопки ▶/⚙/■ стоят от
       правого края КАРТОЧКИ, а не окна — поэтому при таком поле они
       визуально «не двигались» при сужении: они и не должны были, карточка
       под ними оставалась той же ширины, просто её край уезжал за видимую
       область. Теперь ширина карточки — это честная ширина контейнера,
       поэтому и узкий колоночный режим кнопок (см. $narrowBtns, порог
       680px) включается ровно тогда, когда карточка реально становится
       уже, а не когда достигается искусственный пол. #>
    if (-not $script:UI.ContainsKey('Cards')) { return 1000 }
    return Get-RamMenuCardWidth -AvailableWidth (Get-RamCardsAvailableWidth)
}

function Get-RamCachedAvatarImage {
    param([Parameter(Mandatory)][int64]$UserId, [Parameter(Mandatory)][string]$Path, [switch]$Reload)
    $key = [string]$UserId
    if ($Reload -and $script:AvatarImages.ContainsKey($key)) {
        try { $script:AvatarImages[$key].Dispose() } catch { }
        [void]$script:AvatarImages.Remove($key)
    }
    if (-not $script:AvatarImages.ContainsKey($key) -and (Test-Path -LiteralPath $Path)) {
        $img = Get-RamImageFromFile -Path $Path
        if ($null -ne $img) { $script:AvatarImages[$key] = $img }
    }
    return $script:AvatarImages[$key]
}

function Get-RamWaterCardRows {
    <#
      Вертикальная раскладка карточки вида H₂O — от высоты шрифтов.

      Раньше строки стояли на вписанных отступах 4 / 21 / 37 / 54 / 70 точек,
      умноженных на масштаб. Шрифт растёт иначе, и на 150% имя прижималось по
      высоте меньше строки шрифта — а надпись с многоточием, не влезающая по
      высоте, в WinForms не рисуется вовсе: длинное имя аккаунта исчезало.

      Высоту карточки считает это же место, чтобы строки и карточка не разошлись.
    #>
    $t = $Global:RamTheme; $m = $t.M
    $sk = { param($n) [int][Math]::Round($n * $m.Scale) }
    $rowTitle = (Measure-RamText -Text 'Ay' -Font $t.FontTitle).Height
    $rowSmall = (Measure-RamText -Text 'Ay' -Font $t.FontSmall).Height + (& $sk 1)
    $rowBody  = (Measure-RamText -Text 'Ay' -Font $t.FontBody).Height  + (& $sk 1)
    # Имя — на уровне верха аватарки (та стоит на 8 точках), а не впритык к краю.
    $nameY  = & $sk 8
    $subY   = $nameY + $rowTitle
    $gameY  = $subY  + $rowSmall
    $setY   = $gameY + $rowBody
    $factsY = $setY  + $rowSmall
    $textBottom   = $factsY + $rowSmall + (& $sk 4)
    $avatarBottom = (& $sk 8) + (& $sk 52) + (Get-RamStatusDotHeight -WithSuffix) + (& $sk 4)
    return [pscustomobject]@{
        NameY = $nameY; SubY = $subY; GameY = $gameY; SetY = $setY; FactsY = $factsY
        RowTitle = $rowTitle; RowSmall = $rowSmall; RowBody = $rowBody
        Height = [Math]::Max((& $sk 92), [Math]::Max($textBottom, $avatarBottom))
    }
}

function Get-RamCardHeight {
    <# Одно место истины для высоты карточки. Раньше узкий режим кнопок
       (три квадрата в колонку) добавлял карточке лишнюю высоту — теперь
       кнопки в этом режиме просто мельче и умещаются в ту же высоту, что
       и обычная карточка, поэтому здесь больше нечего прибавлять: высота
       зависит только от компактности, не от ширины кнопочной колонки. #>
    $t = $Global:RamTheme
    $metrics = $t.M
    $compact = [bool]$script:Settings.CompactCards
    if ($compact) { return [int][Math]::Round(56 * $metrics.Scale) }
    return (Get-RamWaterCardRows).Height
}

function Update-RamTopBarLayout {
    <#
      Переставляет поиск и кнопки раздела между «в одну строку» и «кнопки под
      поиском» по ширине ОКНА, и спускает панель раздела вслед за строкой.

      Момент переноса считает Get-RamTopBarWrapWidth по фактическим ширинам
      элементов, поэтому он верен на любом масштабе, шрифте и длине надписи.

      Вызывается при сборке окна, при смене раздела и на каждый Resize.
    #>
    if (-not $script:UI.ContainsKey('TopBar')) { return }
    $tb = $script:UI.TopBar
    if ($null -eq $tb.Search -or $tb.Search.IsDisposed) { return }

    $t = $Global:RamTheme
    $m = $t.M
    $formRef = if ($script:UI.ContainsKey('Form') -and $null -ne $script:UI.Form) { $script:UI.Form } else { $tb.Search.FindForm() }
    if ($null -eq $formRef) { return }
    $formW = $formRef.ClientSize.Width
    # ПОРОГ ПЕРЕНОСА — РАСЧЁТ, А НЕ ЧИСЛО. Здесь было пять порогов, подобранных
    # глазом под 100% (830, 776, 774, 828, 686). Все они — одно и то же
    # выражение: правый край поиска + ширины кнопок строки + зазоры. На 125%
    # и 150% числа врали: левый край содержимого выводится из замера надписей
    # меню и растёт со шрифтом не ровно в Scale раз. Здесь ширины фактические.
    $wrapThreshold      = Get-RamTopBarWrapWidth -Search $tb.Search -Buttons @($tb.BAll, $tb.BSel)
    $gamesWrapThreshold = Get-RamTopBarWrapWidth -Search $tb.Search -Buttons @($tb.BGamesPopular)
    $profWrapThreshold  = Get-RamTopBarWrapWidth -Search $tb.Search -Buttons @($tb.BProfiles)
    $logWrapThreshold   = Get-RamTopBarWrapWidth -Search $tb.Search -Buttons @($tb.BCopyLog, $tb.BClearLog)

    if ($formW -lt $wrapThreshold) {
        # КНОПКИ ПОД ПОИСКОМ, ВО ВСЮ ШИРИНУ РАЗДЕЛА.
        # Поиск остаётся на месте и той же ширины — это просто поле ввода.
        # «Все» и «С отмеченными» встают строкой ниже: «Все» слева, «С
        # отмеченными» сразу за ней. Обе кнопки той же ширины, что и в
        # широком режиме — они не резиновые, просто строка своя.
        $rowY = $tb.Search.Bottom + $m.GapSm
        $tb.BAll.Location = New-Object System.Drawing.Point($tb.ContentX, $rowY)
        $tb.BSel.Location = New-Object System.Drawing.Point(($tb.BAll.Right + $m.GapSm), $rowY)
    } else {
        # ОДНА СТРОКА: поиск, затем «Все», затем «С отмеченными» — как и
        # было исходно, кнопки по правому краю поиска на исходном Y.
        $tb.BAll.Location = New-Object System.Drawing.Point(($tb.Search.Right + $m.Gap), $tb.BtnY)
        $tb.BSel.Location = New-Object System.Drawing.Point(($tb.BAll.Right + $m.GapSm), $tb.BtnY)
    }

    # «ПОПУЛЯРНЫЕ ИЗ ROBLOX» — СВОЙ ПОРОГ, СВОЯ СТРОКА.
    # Кнопка живёт только на «Играх» и с «Все»/«С отмеченными» никогда не
    # делит строку (те скрыты на этом разделе) — поэтому у неё отдельная
    # проверка по ширине окна, не связанная с $wrapThreshold выше.
    if ($null -ne $tb.BGamesPopular -and -not $tb.BGamesPopular.IsDisposed) {
        if ($formW -lt $gamesWrapThreshold) {
            $tb.BGamesPopular.Location = New-Object System.Drawing.Point($tb.ContentX, ($tb.Search.Bottom + $m.GapSm))
        } else {
            $tb.BGamesPopular.Location = New-Object System.Drawing.Point(($tb.Search.Right + $m.Gap), $tb.BtnY)
        }
    }

    # «ГОТОВЫЕ ПРОФИЛИ» — ТОТ ЖЕ ПРИЁМ, СВОЙ ПОРОГ (774px).
    if ($null -ne $tb.BProfiles -and -not $tb.BProfiles.IsDisposed) {
        if ($formW -lt $profWrapThreshold) {
            $tb.BProfiles.Location = New-Object System.Drawing.Point($tb.ContentX, ($tb.Search.Bottom + $m.GapSm))
        } else {
            $tb.BProfiles.Location = New-Object System.Drawing.Point(($tb.Search.Right + $m.Gap), $tb.BtnY)
        }
    }

    # «СКОПИРОВАТЬ»/«ОЧИСТИТЬ» — ПАРА, ТОТ ЖЕ ПРИЁМ, ЧТО «ВСЕ»/«С
    # ОТМЕЧЕННЫМИ»: на узком окне обе встают строкой ниже поиска, «Очистить»
    # сразу за «Скопировать». Свой порог (828px), потому что здесь, как и на
    # «Аккаунтах», в строке две кнопки, а не одна.
    if ($null -ne $tb.BCopyLog -and -not $tb.BCopyLog.IsDisposed -and $null -ne $tb.BClearLog -and -not $tb.BClearLog.IsDisposed) {
        if ($formW -lt $logWrapThreshold) {
            $logRowY = $tb.Search.Bottom + $m.GapSm
            $tb.BCopyLog.Location  = New-Object System.Drawing.Point($tb.ContentX, $logRowY)
            $tb.BClearLog.Location = New-Object System.Drawing.Point(($tb.BCopyLog.Right + $m.GapSm), $logRowY)
        } else {
            $tb.BCopyLog.Location  = New-Object System.Drawing.Point(($tb.Search.Right + $m.Gap), $tb.BtnY)
            $tb.BClearLog.Location = New-Object System.Drawing.Point(($tb.BCopyLog.Right + $m.GapSm), $tb.BtnY)
        }
    }

    # «ОБНУЛИТЬ» — БЕЗ ПОРОГА СХЛОПЫВАНИЯ.
    # Кнопка узкая (120px) и в одну строку с поиском помещается вплоть до
    # минимальной ширины окна — переносить её под поиск, как «Готовые
    # профили»/«Популярные из Roblox», не за чем.
    if ($null -ne $tb.BStatsReset -and -not $tb.BStatsReset.IsDisposed) {
        $tb.BStatsReset.Location = New-Object System.Drawing.Point(($tb.Search.Right + $m.Gap), $tb.BtnY)
    }

    # РАЗДЕЛЫ ПОД ВЕРХНЕЙ СТРОКОЙ ТОЖЕ ДОЛЖНЫ СПУСКАТЬСЯ.
    # Все панели разделов (аккаунты/игры/профили/статистика/журнал) стояли
    # на жёстко зашитом Y=56 — это верно только пока «Все» и «С
    # отмеченными» живут в одной строке с поиском. Как только они
    # переезжают строкой ниже (см. выше, ширина < $wrapThreshold), низ
    # верхней строки съезжает вниз, а панели разделов раньше оставались на
    # месте — из-за этого нижняя кнопочная строка наезжала на саму панель,
    # а вместе с ней и на под-категории («Все», «Основной», «Твины» —
    # $groupBar внутри $pAcc, который стоит на Y=0 относительно неё) и на
    # список карточек. То же самое верно и для «Популярные из Roblox» на
    # «Играх» и «Готовые профили» на «Профилях» — их собственный перенос
    # ниже соответствующего порога должен так же спускать панель раздела
    # вслед за собой.
    #
    # Меряем по факту (низ самого нижнего элемента строки + зазор), а не
    # числом — число пришлось бы держать в двух местах, и оно разойдётся
    # при следующей правке шрифта или масштаба.
    #
    # НО ТОЛЬКО ПО ВИДИМЫМ ЭЛЕМЕНТАМ. «Все»/«С отмеченными» скрыты на
    # «Играх», «Профилях», «Статистике» и «Журнале» (Show-RamSection),
    # но их .Bottom при этом никуда не девается — там остаётся координата
    # с прошлого раза, когда они были видимы (однострочный режим, Y =
    # $tb.BtnY). Раньше $topRowBottom всегда включал этот .Bottom, даже
    # для скрытых кнопок — и панель без единой видимой кнопки правее
    # поиска (пустое место, «заготовленное» под будущий перенос) всё
    # равно просаживалась вниз на пустую высоту. Учитываем только то,
    # что реально видно; если ничего, кроме поиска, не видно — низ строки
    # это просто низ поля поиска.
    $topRowBottom = $tb.Search.Bottom
    if ($null -ne $tb.BAll -and -not $tb.BAll.IsDisposed -and $tb.BAll.Visible) {
        $topRowBottom = [Math]::Max($topRowBottom, $tb.BAll.Bottom)
    }
    if ($null -ne $tb.BSel -and -not $tb.BSel.IsDisposed -and $tb.BSel.Visible) {
        $topRowBottom = [Math]::Max($topRowBottom, $tb.BSel.Bottom)
    }
    if ($null -ne $tb.BGamesPopular -and -not $tb.BGamesPopular.IsDisposed -and $tb.BGamesPopular.Visible) {
        $topRowBottom = [Math]::Max($topRowBottom, $tb.BGamesPopular.Bottom)
    }
    if ($null -ne $tb.BProfiles -and -not $tb.BProfiles.IsDisposed -and $tb.BProfiles.Visible) {
        $topRowBottom = [Math]::Max($topRowBottom, $tb.BProfiles.Bottom)
    }
    if ($null -ne $tb.BStatsReset -and -not $tb.BStatsReset.IsDisposed -and $tb.BStatsReset.Visible) {
        $topRowBottom = [Math]::Max($topRowBottom, $tb.BStatsReset.Bottom)
    }
    if ($null -ne $tb.BCopyLog -and -not $tb.BCopyLog.IsDisposed -and $tb.BCopyLog.Visible) {
        $topRowBottom = [Math]::Max($topRowBottom, $tb.BCopyLog.Bottom)
    }
    if ($null -ne $tb.BClearLog -and -not $tb.BClearLog.IsDisposed -and $tb.BClearLog.Visible) {
        $topRowBottom = [Math]::Max($topRowBottom, $tb.BClearLog.Bottom)
    }
    $panelsTop = $topRowBottom + $m.Gap

    if ($script:UI.ContainsKey('Panels')) {
        foreach ($key in @($script:UI.Panels.Keys)) {
            $p = $script:UI.Panels[$key]
            if ($null -eq $p -or $p.IsDisposed) { continue }
            # Нижний край панели привязан к окну (Anchor), поэтому высоту
            # считаем от него, а не поправкой к прежней высоте.
            if ($p.Top -eq $panelsTop) { continue }
            $bottomEdge = $p.Bottom
            $p.Top    = $panelsTop
            $p.Height = [Math]::Max(1, $bottomEdge - $panelsTop)
        }
    }
}

function Update-RamSideBarLayout {
    <#
      Позиции двух нижних групп бокового меню (третья — «Проверить
      входы»/«Настройки»/«Справка», средняя — «Запустить»/«Закрыть»/«Окна»)
      зависят от РЕАЛЬНОЙ высоты $side — а она меняется при разворачивании
      окна на весь экран и обратно (боковая панель растянута на всю высоту,
      Anchor = 'Top,Left,Bottom'). Раньше обе группы вставали один раз при
      сборке окна и на этом всё — на высоком (развёрнутом) окне пустой
      хвост уходил целиком под нижний край, а обе группы оставались
      прижаты кверху, будто под ними ничего не изменилось.

      Третья группа теперь всегда у САМОГО НИЗА бокового меню — считаем
      от $side.Height, а не от накопленного сверху $y. Средняя группа —
      ровно посередине между низом первой группы (разделы + фаст-
      настройка, $script:UI.SideBar.TopGroupBottom) и верхом третьей.

      Вызывается один раз сразу после сборки бокового меню и затем на
      каждый Resize/переключение Maximized — тот же приём, что и у
      Update-RamTopBarLayout для верхней строки.
    #>
    if (-not $script:UI.ContainsKey('SideBar')) { return }
    $sb = $script:UI.SideBar
    if ($null -eq $sb.Side -or $sb.Side.IsDisposed) { return }

    $groupH = 3 * $sb.NavH + 2 * $sb.NavGap

    $bottomY = $sb.Side.Height - $sb.PadLg - $groupH
    if ($null -ne $sb.BFix -and -not $sb.BFix.IsDisposed) {
        $sb.BFix.Location = New-Object System.Drawing.Point($sb.PadLg, $bottomY)
    }
    if ($null -ne $sb.BSettings -and -not $sb.BSettings.IsDisposed) {
        $sb.BSettings.Location = New-Object System.Drawing.Point($sb.PadLg, ($bottomY + $sb.NavH + $sb.NavGap))
    }
    if ($null -ne $sb.BHelp -and -not $sb.BHelp.IsDisposed) {
        $sb.BHelp.Location = New-Object System.Drawing.Point($sb.PadLg, ($bottomY + 2 * ($sb.NavH + $sb.NavGap)))
    }

    # СВОБОДНОЕ МЕСТО — это промежуток между низом первой группы ($gapAbove)
    # и ВЕРХОМ третьей группы ($bottomY, уже посчитан выше как Y кнопки
    # «Проверить входы»). Раньше вместо верха третьей группы бралась
    # $sb.Side.Height — низ ВСЕЙ панели, то есть в «свободное место»
    # засчитывалась ещё и вся высота третьей группы целиком. Середина
    # такого раздутого диапазона съезжала вниз — визуально средняя группа
    # оказывалась прижата к первой и оторвана от третьей, ровно та
    # асимметрия, которая была видна на экране.
    # Группа «Запустить / Закрыть / Окна» — сразу под разделами, с тем же
    # отступом, что между остальными группами. Посередине пустоты она
    # оставляла на высоком окне два огромных разрыва.
    $gapAbove = $sb.TopGroupBottom
    $midY     = $gapAbove + $sb.PadLg
    # Не залезаем выше первой группы и ниже третьей, если окно настолько
    # низкое, что для центрирования просто нет места.
    if ($midY -lt $gapAbove) { $midY = $gapAbove }
    if (($midY + $groupH) -gt ($bottomY - $sb.Gap)) { $midY = $bottomY - $sb.Gap - $groupH }

    if ($null -ne $sb.BLaunch -and -not $sb.BLaunch.IsDisposed) {
        $sb.BLaunch.Location = New-Object System.Drawing.Point($sb.PadLg, $midY)
    }
    if ($null -ne $sb.BCloseAll -and -not $sb.BCloseAll.IsDisposed) {
        $sb.BCloseAll.Location = New-Object System.Drawing.Point($sb.PadLg, ($midY + $sb.NavH + $sb.NavGap))
    }
    if ($null -ne $sb.BTile -and -not $sb.BTile.IsDisposed) {
        $sb.BTile.Location = New-Object System.Drawing.Point($sb.PadLg, ($midY + 2 * ($sb.NavH + $sb.NavGap)))
    }
}

function Get-RamLabelColors {
    <# Цветные метки для группировки глазом. #>
    $t = $Global:RamTheme
    return @(
        [pscustomobject]@{ Key = '';       Text = 'без метки'; Color = $t.Border },
        [pscustomobject]@{ Key = 'red';    Text = 'красная';   Color = [System.Drawing.Color]::FromArgb(239,  68,  68) },
        [pscustomobject]@{ Key = 'orange'; Text = 'оранжевая'; Color = [System.Drawing.Color]::FromArgb(245, 158,  11) },
        [pscustomobject]@{ Key = 'green';  Text = 'зелёная';   Color = [System.Drawing.Color]::FromArgb( 34, 197,  94) },
        [pscustomobject]@{ Key = 'blue';   Text = 'синяя';     Color = [System.Drawing.Color]::FromArgb( 59, 130, 246) },
        [pscustomobject]@{ Key = 'purple'; Text = 'фиолетовая';Color = [System.Drawing.Color]::FromArgb(168,  85, 247) }
    )
}

function Get-RamLabelColor {
    param([string]$Key)
    $found = Get-RamLabelColors | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
    if ($null -eq $found -or [string]::IsNullOrWhiteSpace($Key)) { return $null }
    return $found.Color
}

function Get-RamGroups {
    <# Все существующие наборы, по алфавиту. #>
    $g = @()
    foreach ($a in $script:Accounts) {
        $name = [string]$a.Group
        if (-not [string]::IsNullOrWhiteSpace($name) -and $g -notcontains $name) { $g += $name }
    }
    return @($g | Sort-Object)
}

function Get-RamOrderedAccounts {
    <# Порядок в списке задаётся полем Order — оно меняется перетаскиванием. #>
    $i = 0
    foreach ($a in $script:Accounts) {
        if ([int]$a.Order -eq 0) { $a.Order = ++$i * 10 }
    }
    return @($script:Accounts | Sort-Object { [int]$_.Order })
}

function Set-RamAccountOrder {
    <# Переставляет аккаунт на новое место в списке, сдвигая всё, что между
       старым и новым местом. Больше не используется перетаскиванием карточек
       (см. Swap-RamAccountOrder) — оставлена на случай, если понадобится
       для чего-то ещё, где нужен именно сдвиг диапазона, а не обмен. #>
    param([string]$Id, [int]$NewIndex)

    $ordered = @(Get-RamOrderedAccounts)
    $moving  = $ordered | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if ($null -eq $moving) { return $false }

    $rest = @($ordered | Where-Object { $_.Id -ne $Id })
    if ($NewIndex -lt 0) { $NewIndex = 0 }
    if ($NewIndex -gt $rest.Count) { $NewIndex = $rest.Count }

    $final = @()
    if ($NewIndex -gt 0) { $final += $rest[0..($NewIndex - 1)] }
    $final += $moving
    if ($NewIndex -lt $rest.Count) { $final += $rest[$NewIndex..($rest.Count - 1)] }

    $step = 0
    foreach ($a in $final) { $a.Order = ($step += 10) }
    return $true
}

function Swap-RamAccountOrder {
    <# Меняет местами ДВЕ карточки — ровно ту, что тащат, и ровно ту, на
       которую навели, — не трогая порядок всех остальных. Раньше
       перетаскивание использовало Set-RamAccountOrder — «встать на позицию
       N», что для карточки, перемещаемой ЧЕРЕЗ несколько других (например,
       «1» тащат мимо «2» на «3»), сдвигало ВСЕ карточки между старым и
       новым местом («2» и «3» съезжали на шаг, а не просто менялись местами
       с «1»). Из списка 1,2,3 получалось 2,3,1 вместо ожидаемого простого
       обмена «1» и «3» местами (3,2,1) — то, что что человек и намеревался
       сделать, наводя именно на «3», а не «куда-то в район конца списка». #>
    param([string]$Id, [string]$WithId)
    if ($Id -eq $WithId) { return $false }

    $ordered = @(Get-RamOrderedAccounts)
    $a = $ordered | Where-Object { $_.Id -eq $Id }     | Select-Object -First 1
    $b = $ordered | Where-Object { $_.Id -eq $WithId } | Select-Object -First 1
    if ($null -eq $a -or $null -eq $b) { return $false }

    $tmp = $a.Order
    $a.Order = $b.Order
    $b.Order = $tmp
    return $true
}

function Test-RamAccountMatches {
    <# Подходит ли аккаунт под строку поиска. Ищем по названию, нику, ID,
       игре, заметке и набору. #>
    param($Account, [string]$Query)

    if ([string]::IsNullOrWhiteSpace($Query)) { return $true }
    $q = $Query.Trim()

    foreach ($field in @($Account.Alias, $Account.Username, [string]$Account.UserId,
                         $Account.GameName, [string]$Account.PlaceId,
                         $Account.Note, $Account.Group)) {
        if ($field -and $field.ToString().IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }
    return $false
}

function Get-RamVisibleAccounts {
    <# Что показывать: с учётом поиска и выбранного набора. #>
    $list = @(Get-RamOrderedAccounts)

    if (-not [string]::IsNullOrWhiteSpace($script:GroupFilter)) {
        $list = @($list | Where-Object { [string]$_.Group -eq $script:GroupFilter })
    }
    return @($list | Where-Object { Test-RamAccountMatches -Account $_ -Query $script:Filter })
}

function Build-RamCardsWater {
    <# Полная пересборка списка карточек. Вызывается при изменении состава,
       фильтра, порядка или режима отображения. #>
    if (-not $script:UI.ContainsKey('Cards')) { return }

    $t      = $Global:RamTheme
    # НЕ $m: ниже есть foreach ($m in ...), он бы её затёр.
    $metrics = $t.M
    $host_  = $script:UI.Cards
    $W      = Get-RamCardWidth
    $compact = [bool]$script:Settings.CompactCards
    # Высота тоже от масштаба: при 150% в прежние 92px не помещались имя,
    # подпись и заметка, набранные полуторным шрифтом. Единое место расчёта —
    # Get-RamCardHeight, чтобы это же число совпадало при перетаскивании
    # карточек (см. dragUp) и не расходилось с ним при узком режиме кнопок.
    $cardH  = Get-RamCardHeight
    $rows   = Get-RamWaterCardRows

    $sk0 = { param($n) [int][Math]::Round($n * $metrics.Scale) }

    # КНОПКИ СТОЛБИКОМ — КОГДА ИМ ТЕСНО В САМОЙ КАРТОЧКЕ, А НЕ В ОКНЕ.
    # Раньше порог был «окно уже 770 точек». Но кнопки стоят внутри карточки,
    # а карточка уже окна на боковое меню, отступы и полосу прокрутки — и это
    # расстояние не постоянно: ширина меню выводится из замера надписей, а в
    # широком меню карточек ещё и несколько в ряд. На 150% столбик включался
    # то слишком рано, то слишком поздно. Меряем саму карточку: аватарку,
    # самую узкую осмысленную подпись и три кнопки в ряд.
    $rowNeed = (& $sk0 48) + (& $sk0 52) + (& $sk0 8) +
               (Measure-RamText -Text 'Wwwwwwwwwwww' -Font $t.FontBody).Width +
               (& $sk0 14) + 3 * (& $sk0 32) + 2 * (& $sk0 6) + (& $sk0 22)
    $narrowBtns = ($W -lt $rowNeed)

    # В широком меню карточки стоят в колонки: зазор справа у каждой.
    $cardCols = Get-RamMenuCardColumns -AvailableWidth (Get-RamCardsAvailableWidth)
    $cardGap  = $metrics.Gap

    # Отметки живут в общей модели, поэтому поиск и смена меню не теряют
    # галочки у временно скрытых карточек.
    foreach ($id in @($script:Cards.Keys)) {
        $entry = $script:Cards[$id]
        if ($null -ne $entry -and $entry.Check.Tag.Checked) { $script:CheckedIds[[string]$id] = $true }
        else { [void]$script:CheckedIds.Remove([string]$id) }
    }

    $listScroll = Enter-RamListRebuild -Panel $host_
    try {
        # Controls.Clear() только вынимает элементы из списка. Каждый из них —
        # это окно Windows со своими ресурсами GDI, и без Dispose они висят до
        # сборки мусора. На пересборке по каждой букве в поиске это утекало
        # заметно, поэтому освобождаем явно.
        foreach ($old in @($host_.Controls)) {
            try {
                if ($null -ne $old.ContextMenuStrip) { $old.ContextMenuStrip.Dispose(); $old.ContextMenuStrip = $null }
                $old.Dispose()
            } catch { }
        }
        $host_.Controls.Clear()
        $script:Cards = @{}
        $script:AvatarQueue.Clear()

        $visible = @(Get-RamVisibleAccounts)

        if (@($script:Accounts).Count -eq 0) {
            # Высота — по переносу текста: на узком окне и крупном шрифте строк больше.
            $host_.Controls.Add((New-RamNoticeCard -Width $W -Title 'Пока ни одного аккаунта' `
                -Text 'Войди в приложении Roblox под нужным аккаунтом и нажми «Добавить» — менеджер заберёт вход сам, пароль вводить не надо.'))
            return
        }

        if ($visible.Count -eq 0) {
            $why = if ($script:GroupFilter) { "В наборе «$($script:GroupFilter)» ничего не нашлось" }
                   else { "По запросу «$($script:Filter)» ничего не нашлось" }
            $host_.Controls.Add((New-RamNoticeCard -Width $W -Title $why -Text 'Сбрось поиск (Esc) или выбери набор «Все» вверху.'))
            return
        }

        foreach ($a in $visible) {
            $card = New-RamCard -Width $W -Height $cardH
            if ($cardCols -gt 1) { $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, $cardGap, $cardGap) }
            $card.Tag.AccountId = $a.Id
            $card.Tag | Add-Member -NotePropertyName Stripe `
                                   -NotePropertyValue (Get-RamLabelColor -Key ([string]$a.Color)) -Force
            $host_.Controls.Add($card)

            # Цветная метка рисуется полоской слева
            $card.Add_Paint({
                param($s, $e)
                if ($null -eq $s.Tag.Stripe) { return }
                $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                $r = New-Object System.Drawing.Rectangle(1, 8, 5, ($s.Height - 16))
                $path = New-RamRoundRect -Rect $r -Radius 2
                $b = New-Object System.Drawing.SolidBrush($s.Tag.Stripe)
                $e.Graphics.FillPath($b, $path)
                $b.Dispose(); $path.Dispose()
            })

            # ВСЁ ВНУТРИ КАРТОЧКИ СЧИТАЕТСЯ ОТ МАСШТАБА, А НЕ ЧИСЛАМИ.
            # Раньше здесь стояли готовые координаты (nameX = 112, gameX = 360,
            # высота 92). Шрифт при 125% и 150% растёт, а колонки оставались на
            # месте: ник с номером не влезал в отведённые 234px и обрезался
            # многоточием, «ИГРА» жалась к имени, а точка состояния уезжала.
            # Числа ниже — те же самые пропорции при 100%, просто умноженные.
            $sk = { param($n) [int][Math]::Round($n * $metrics.Scale) }
            $pad = & $sk 18
            if ($compact) {
                $chk = New-RamCheckBox -X $pad -Y (& $sk 18)
                # Аватарку сдвигаем за галочкой: та растёт вместе со шрифтом.
                $avSize = & $sk 32
                $avY    = & $sk 12
                $avX    = [Math]::Max((& $sk 46), ($pad + $chk.Width + (& $sk 8)))
                $nameY  = & $sk 4;   $subY = & $sk 28;  $gameY = & $sk 17
                $dotY   = & $sk 17
                $btnY   = & $sk 12;  $btnH = $metrics.RowHSm
            } else {
                $chk = New-RamCheckBox -X $pad -Y (& $sk 36)
                $avSize = & $sk 52
                # Аватарку подняли ближе к верху карточки: раньше она стояла
                # по центру всего текстового блока (имя+ник+игра+настройки+
                # справка), и на глаз казалось, что имя с ником «висят» отдельно
                # от неё, выше её середины. Теперь верх аватарки — на одном
                # уровне с именем, и пара «имя · ник» читается как единая шапка
                # рядом с аватаркой, а не как подпись где-то ниже её центра.
                $avY    = & $sk 8
                $avX    = [Math]::Max((& $sk 48), ($pad + $chk.Width + (& $sk 8)))
                # Один столбец текста: имя → ник/ID → игра → настройки →
                # справка (Robux/дата), друг под другом. Раньше игра и
                # настройки стояли в отдельной колонке справа от имени —
                # теперь всё под ником, как в концепции. Подняли блок ближе
                # к нику — освободившееся место внизу отдано пятой строкой
                # под справку, которая раньше лепилась в одну строку с
                # настройками через точки.
                # Отступы между строками (name→sub→game→set→facts) были
                # неровными — 18px после имени, затем 16px везде ниже: имя
                # крупнее шрифтом, и на глаз казалось, что первая строка
                # оторвана сильнее остальных. Выровняли шаг до одинаковых
                # 16.5px (33 при sk=2х) по всем пяти строкам — сетка читается
                # ровно, а последняя строка (facts) осталась на том же месте,
                # что и раньше, так что высота карточки не выросла.
                $nameY  = $rows.NameY;  $subY   = $rows.SubY;  $gameY = $rows.GameY
                $setY   = $rows.SetY;   $factsY = $rows.FactsY
                $dotY   = & $sk 36
                $btnY   = & $sk 29;  $btnH = $metrics.RowH
            }
            $nameX = $avX + $avSize + (& $sk 8)

            # ПРАВАЯ ЗОНА ДЕЙСТВИЙ — ОДНОЙ ПОЛОСОЙ ИЛИ КОЛОНКОЙ.
            #
            # На широкой карточке три значка стоят в ряд от правого края.
            # На узкой карточке (окно сжато) ряду из трёх квадратов уже не
            # хватает места — они наезжали на имя/игру/статус, потому что
            # $avail ниже подпирался жёстким минимумом (260px), а X кнопок
            # считался независимо от него. Теперь при недостатке ширины
            # кнопки переезжают в вертикальную колонку (▶ сверху, ✎ и ■
            # в ряд под ней) — так же, как в концепции интерфейса: колонка
            # уже одного квадрата, а не трёх, и текстовым колонкам достаётся
            # заметно больше места без обрезки многоточием.
            # ▶ / ⚙ / ■ — квадратные значки без подписи. Раньше ширина (46px)
            # была ощутимо больше высоты (RowH = 34px) — кнопка получалась
            # прямоугольной, шире, чем выше, а не квадратом, как в концепции.
            # Здесь ширина и высота — одно и то же число.
            $icoW     = & $sk 32
            $btnH     = $icoW
            $icoGap   = & $sk 6
            $icoRight = $W - (& $sk 22)

            # УЗКАЯ КАРТОЧКА (≤680px) — ▶ КАПСУЛОЙ СЛЕВА, ⚙/■ СТОЛБИКОМ
            # СПРАВА ОТ НЕЁ (по образцу присланного макета).
            #
            # Раньше здесь стоял столбик из трёх одинаковых квадратов
            # (▶/⚙/■ друг под другом) — рабочий вариант, но play ничем не
            # выделялся среди второстепенных действий, хотя это основная
            # кнопка карточки. Теперь play — отдельная капсула высотой в
            # оба маленьких квадрата плюс зазор между ними.
            #
            # Первая попытка (×1.5 ширины, отступ 22px от края, блок по
            # центру карточки при фиксированном мелком icoW=24) оказалась
            # заметно просторнее образца: капсула была слишком широкой, от
            # правого края карточки оставался приличный зазор, а сверху и
            # снизу блока — пустое место, хотя в макете кнопки почти
            # упираются во все три края (право/верх/низ).
            #
            # Здесь размер квадратов (icoW/btnH) считается ИЗ доступной
            # высоты карточки, а не задаётся числом заранее — иначе X- и
            # Y-геометрия расходятся: если высоту кнопок пересчитать под
            # «почти во всю карточку» отдельно от icoW, использованного для
            # ширины/X-координат чуть выше, ⚙/■ перестают быть квадратами.
            if ($narrowBtns) {
                # Отступ от края карточки — маленький и один и тот же с
                # четырёх сторон блока кнопок (право/верх/низ), как в
                # образце, а не унаследованные 22px, рассчитанные под ряд
                # из трёх квадратов с большим запасом.
                $edgeGap = & $sk 10
                # Пара ⚙/■ стоит одна над другой на высоту (cardH - 2*gap);
                # каждый квадрат — половина этой высоты минус зазор между
                # ними. Ширина квадрата равна этой же величине (это и есть
                # icoW) — так гарантированно остаётся квадратом.
                $icoW = [int](($cardH - $edgeGap * 2 - $icoGap) / 2)
                $btnH = $icoW
                $playH = $cardH - $edgeGap * 2
                # Капсула шире квадрата, но некритично — раньше ×1.5
                # читалось как отдельная крупная деталь, выбивающаяся из
                # образца, где она лишь немного шире соседних квадратов.
                $playW = [int]($icoW * 1.15)

                $narrowIcoRight = $W - $edgeGap
                $stopX    = $narrowIcoRight - $icoW
                $editX    = $stopX
                $playX    = $stopX - $icoGap - $playW
                $btnsLeft = $playX
            } else {
                $stopX = $icoRight - $icoW
                $editX = $stopX - $icoGap - $icoW
                $playX = $editX - $icoGap - $icoW
                $btnsLeft = $playX
            }

            # ТРИ КОЛОНКИ ДЕЛЯТ ОСТАТОК, А НЕ СТОЯТ НА ГОТОВЫХ СДВИГАХ.
            # Раньше было gameX = nameX + 248, gameW = 240, dotX = +40 — при
            # 150% на узком экране их сумма выходила шире самой карточки, и
            # точка состояния вылезала за правый край. Теперь берём всё, что
            # осталось между именем и значками, и делим по долям: имени
            # больше всех, потому что там ник и номер.
            # Высоту строк меряем по шрифту. Раньше стояло 20 и 22 — при 150%
            # строка текста выше 22px, и название игры не рисовалось ВООБЩЕ:
            # надпись обрезалась по вертикали до пустого места. Подпись под
            # именем спасал только более мелкий шрифт.
            $hSm   = (Measure-RamText -Text 'Ay' -Font $t.FontSmall).Height + 4
            $hBody = (Measure-RamText -Text 'Ay' -Font $t.FontBody).Height + 4
            if (-not $compact) {
                # Высота подписи = шаг ряда: выше — и сплошная подложка
                # следующей строки закрывала бы низ предыдущей.
                $hSm = $rows.RowSmall; $hBody = $rows.RowBody
            }

            # Статус переехал под аватарку (см. ниже), а его цвет теперь
            # дублируется рамкой аватарки. В обычном режиме игра и настройки
            # больше не стоят колонкой справа от имени — весь текст идёт
            # одним столбцом на всю ширину: имя → ник/ID → игра → настройки,
            # друг под другом, как в концепции. Колонки на два столбца
            # (имя | игра+статус) остаются только в компактном режиме — там
            # карточка слишком низкая, чтобы уместить четыре строки в один
            # столбец.
            $colGap = & $sk 14
            $avail  = $btnsLeft - $colGap - $nameX
            # Раньше здесь стоял пол в 260px (Math.Max(260, avail)) — при
            # достаточно узком окне реального места оставалось меньше, но
            # ширина лейблов (имя/ник/игра/настройки/справка) всё равно
            # принудительно раздувалась до 260px «через» эту границу. Сама
            # кнопка при этом стояла на месте, а вот лейбл — шире, чем
            # зона ДО кнопки — и своим фоном заезжал поверх ▶/⚙/■, перекрывая
            # их (следствие: то самое залезание текста на кнопки при сужении
            # окна). Текстовым колонкам нельзя давать больше места, чем
            # реально есть до кнопок — обрезание многоточием (Truncatable
            # уже стоит у всех этих лейблов) выглядит нормально, а наезд на
            # кнопку — нет.
            if ($avail -lt (& $sk 40)) { $avail = & $sk 40 }
            if ($compact) {
                $textW = [int]($avail * 0.42)
                $gameX = $nameX + $textW + $colGap
                $gameW = [int]($avail * 0.31)
                $dotX  = $gameX + $gameW + $colGap
                $dotW  = [Math]::Max((& $sk 60), ($btnsLeft - $colGap - $dotX))
            } else {
                $textW = $avail
                $gameX = $nameX
                $gameW = $avail
            }

            $chk.Tag | Add-Member -NotePropertyName AccountId -NotePropertyValue $a.Id -Force
            if ($script:CheckedIds.ContainsKey([string]$a.Id)) { $chk.Tag.Checked = $true }
            $chk.Add_Click({
                $id = [string]$this.Tag.AccountId
                if ($this.Tag.Checked) { $script:CheckedIds[$id] = $true }
                else { [void]$script:CheckedIds.Remove($id) }
                Update-RamStatusLine
            })
            $card.Controls.Add($chk)

            $av = New-RamAvatarBox -Size $avSize
            $av.Location = New-Object System.Drawing.Point($avX, $avY)
            $card.Controls.Add($av)
            Set-RamAvatarImage -Box $av -Image $null -Letter $(if ($a.Alias) { $a.Alias } else { '?' })

            $cached = $null
            if ([int64]$a.UserId -gt 0) {
                $file = Join-Path (Get-RamAvatarDir) "$($a.UserId).png"
                if (Test-Path -LiteralPath $file) { $cached = Get-RamCachedAvatarImage -UserId $a.UserId -Path $file }
            }
            if ($null -ne $cached) { Set-RamAvatarImage -Box $av -Image $cached -Letter $a.Alias }

            # Имя и набор. Раньше набор («Основной»/«Твины») стоял отдельной
            # меткой в этой же строке рядом с именем и отжимал у него
            # ширину — на длинных именах («FORMULA_VODYARЫ») с узкой
            # карточкой доходило до того, что имени оставалось 15-20px, и
            # оно переставало рисоваться вообще (WinForms не показывает
            # даже многоточие на такой узкой полосе). Набор переехал в
            # подпись статуса под аватаркой (см. GroupSuffix у
            # New-RamStatusDot ниже) — там он не спорит с именем за
            # горизонталь. Имени теперь отдаётся вся ширина колонки.
            $maxTextW = $textW
            $aliasW = $maxTextW
            $aliasNeed = [System.Windows.Forms.TextRenderer]::MeasureText($a.Alias, $t.FontTitle).Width + 6
            if ($aliasNeed -lt $aliasW) { $aliasW = $aliasNeed }

            # Высота имени — по шрифту, а не «24 всегда»: на крупном масштабе
            # заголовок выше, и фиксированная высота давала наложение.
            # Ограничиваем расстоянием до подписи под ней — в ОБОИХ режимах.
            $nameH = [Math]::Max(18, (Measure-RamText -Text 'Ay' -Font $t.FontTitle).Height + 2)
            $nameH = [Math]::Min($nameH, ($subY - $nameY))
            $lblName = New-RamLabel -Text $a.Alias -X $nameX -Y $nameY -Width $aliasW -Height $nameH `
                                    -Font $t.FontTitle -Truncatable
            $card.Controls.Add($lblName)

            $sub = if ($a.Username) { "@$($a.Username)  ·  ID $($a.UserId)" } else { 'вход не проверен' }
            # Коротко: длинная подсказка съедала строку целиком и прятала ник.
            # Что делать — написано на красной кнопке внизу.
            if ([string]$a.CookieOk -eq 'no') { $sub = 'вход мёртв   ·   ' + $sub }
            if ($compact -and -not [string]::IsNullOrWhiteSpace($a.Group)) { $sub = "[$($a.Group)]  $sub" }
            $subColor = if ([string]$a.CookieOk -eq 'no') { $t.Danger } else { $t.Muted }
            $lblSub = New-RamLabel -Text $sub -X $nameX -Y $subY -Width $maxTextW -Height $hSm `
                                   -Font $t.FontSmall -Color $subColor -Truncatable
            $card.Controls.Add($lblSub)

            $lblNote = $null
            $noteText = $null
            if (-not [string]::IsNullOrWhiteSpace($a.Note)) { $noteText = $a.Note }
            if ($compact -and $noteText) {
                $lblNote = New-RamLabel -Text $noteText -X $nameX -Y (& $sk 60) -Width $maxTextW -Height $hSm `
                                        -Font $t.FontSmall -Color $t.Muted -Truncatable
                $card.Controls.Add($lblNote)
            }

            if ($compact) {
                $card.Controls.Add((New-RamLabel -Text 'ИГРА' -X $gameX -Y (& $sk 14) -Width $gameW -Height (& $sk 16) -Font $t.FontSmall -Color $t.Muted))
            }

            $gameTxt = if ($a.GameName) { $a.GameName }
                       elseif ($a.PlaceId) { "ID $($a.PlaceId)" }
                       else { 'просто Roblox' }
            if ($a.LinkCode) { $gameTxt += '  · приват' }
            $lblGame = New-RamLabel -Text $gameTxt -X $gameX -Y $gameY -Width $gameW -Height $hBody `
                                    -Color $(if ($a.PlaceId) { $t.Text } else { $t.Muted }) -Truncatable
            $card.Controls.Add($lblGame)

            if (-not $compact) {
                # Настройки (+заметка) — четвёртая строка. Справка
                # (Robux/Premium/дата) — теперь отдельная пятая строка под
                # ней: блок подняли ближе к нику, и место на неё нашлось.
                $summary = Get-RamAccountSettingsSummary -Account $a
                $parts = @($noteText, $summary) | Where-Object { $_ }
                $summaryLine = $parts -join '   ·   '
                if ($summaryLine) {
                    $card.Controls.Add((New-RamLabel -Text $summaryLine -X $gameX -Y $setY -Width $gameW -Height $hSm `
                                                    -Font $t.FontSmall -Color $t.Muted -Truncatable))
                }

                $facts = @()
                if ([int]$a.Robux -ge 0)      { $facts += "$($a.Robux) R$" }
                if ([string]$a.Premium -eq 'yes') { $facts += 'Premium' }
                if ($a.Created)               { $facts += "с $($a.Created)" }
                if ($facts.Count -gt 0) {
                    $card.Controls.Add((New-RamLabel -Text ($facts -join '  ·  ') -X $gameX -Y $factsY -Width $gameW -Height $hSm `
                                                    -Font $t.FontSmall -Color $t.Muted -Truncatable))
                }
            }

            if ($compact) {
                # Тесно: под маленькой аватаркой (32px) не хватает высоты
                # карточки под подпись статуса — оставляем как было, в
                # колонке справа, с кружком-индикатором. Компактный режим
                # уже показывает набор отдельно, в строке [Группа] @ник
                # (см. $sub выше) — здесь его дублировать не нужно.
                $dot = New-RamStatusDot -X $dotX -Y $dotY -Width $dotW
            } else {
                # Статус — под аватаркой, по центру, без кружка: цвет уже
                # виден по рамке аватарки (см. Set-RamStatusDot -Avatar),
                # текст здесь просто дублирует его подписью. Вплотную к
                # рамке (без зазора) — раньше зазор в 2px визуально читался
                # как «оторванная» подпись. Ширина — от края аватарки до
                # начала колонки с именем, чтобы не наезжать на текст.
                #
                # Сюда же, отдельной строкой снизу (не в одну строку через
                # « · » — там даже сам статус переставал влезать целиком),
                # дописывается короткая метка набора (см. Get-RamGroupShort
                # и GroupSuffix у New-RamStatusDot) — раньше она стояла в
                # строке имени и на длинных именах при узкой карточке
                # отжимала у имени всю ширину. Тут она ничего не теснит по
                # горизонтали, только использует место под аватаркой.
                #
                # Y панели — ТОТ ЖЕ, что и раньше (без GroupSuffix): сама
                # строка статуса не должна никуда сдвигаться, иначе она
                # заезжает под аватарку и обрезается сверху (это и была
                # прошлая ошибка — подъём всей панели вверх, чтобы вторая
                # строка влезала до низа карточки, поднимал заодно и первую
                # строку с места, где её ждёт глаз). Вместо подъёма панель
                # растёт ВНИЗ, за пределы прежних 22px — места до низа
                # карточки под это хватает (см. Build-RamCards/$cardH), а
                # если бы вдруг не хватило, лучше обрезать метку снизу,
                # чем сдвигать сам статус.
                $dotUnderX = $avX - (& $sk 8)
                # Сразу ПОД аватаркой: заливка подписи не должна срезать низ её рамки.
                $dotUnderY = $avY + $avSize
                $dotUnderW = $nameX - $dotUnderX
                $groupSuffix = if (-not [string]::IsNullOrWhiteSpace($a.Group)) { Get-RamGroupShort -Group $a.Group } else { $null }
                $dot = New-RamStatusDot -X $dotUnderX -Y $dotUnderY -Width $dotUnderW -NoDot -Center -GroupSuffix $groupSuffix
            }
            $card.Controls.Add($dot)

            # УЗКИЙ РЕЖИМ: ▶ — капсула почти на всю высоту карточки, ⚙/■ —
            # пара квадратов той же суммарной высоты рядом с ней. Раньше
            # блок кнопок центрировался по высоте карточки при фиксированной
            # (некрупной) высоте капсулы — сверху и снизу оставался приличный
            # зазор. В образце кнопки почти упираются в верхний и нижний
            # край карточки, с совсем небольшим отступом — той же величины,
            # что и отступ от правого края ($edgeGap выше).
            #
            # $icoW/$btnH/$playH/$playW уже посчитаны выше вместе с
            # X-координатами (один источник истины для размеров — см.
            # комментарий там), здесь только позиционирование по Y.
            if ($narrowBtns) {
                $btnTopY = $edgeGap
                $playY = $btnTopY
                $midY  = $btnTopY
                $lowY  = $btnTopY + $btnH + $icoGap
                $playRowW = $playW
                $playRowH = $playH
                # Капсула: радиус — половина ширины. У обычной кнопки
                # (Radius по умолчанию 7) в квадрате 24px это выглядело бы
                # как слабое скругление уголков — здесь же нужен настоящий
                # «таблеточный» контур, как в присланном образце. Ограничен
                # половиной высоты тоже — иначе на такой вытянутой кнопке
                # обычный прямоугольник со слишком большим радиусом рисует
                # самопересекающиеся дуги вместо капсулы.
                $playRadius = [Math]::Min([int]($playRowW / 2), [int]($playH / 2))
            } else {
                $playRowW = $icoW
                $playRowH = $btnH
                $playRadius = 7
                $playY = $btnY
                $midY  = $btnY
                $lowY  = $btnY
            }


            # -Fixed: это квадратные значки, их ширина задана намеренно.
            # Без него кнопка подгоняется под текст и налезает на соседнюю.
            # У аккаунта с умершим входом «пуск» бесполезен: клиент откроется
            # и выкинет на страницу входа. Вместо него ставим «войти заново» —
            # то самое действие, которое человеку и нужно в этот момент.
            # Продлить куку снаружи нечем (проверено, см. «Проверка входов.ps1»),
            # поэтому единственный рабочий выход — войти ещё раз.
            if ([string]$a.CookieOk -eq 'no') {
                # Глифов вида «обновить/войти заново» в наборе нет — оставляем
                # текстовый символ ↻, просто в квадратном формате IconOnly не
                # трогаем (только play/gear/stop заменены на глифы по просьбе
                # пользователя).
                $bPlay = New-RamButton -Text '↻' -Width $playRowW -Height $playRowH -Fixed -Kind 'danger' -Radius $playRadius `
                                       -Tooltip 'Войти в этот аккаунт заново — вход умер' -OnClick {
                    Invoke-RamRelogin -Id $this.Tag.AccountId
                }
            } else {
                $bPlay = New-RamButton -Text '' -Icon 'play' -IconOnly -Width $playRowW -Height $playRowH -Fixed -Kind 'primary' -Radius $playRadius -Tooltip 'Запустить этот аккаунт' -OnClick {
                    Add-RamToLaunchQueue -Accounts @((Get-RamAccountById -Id $this.Tag.AccountId))
                }
            }
            $bPlay.Tag | Add-Member -NotePropertyName AccountId -NotePropertyValue $a.Id -Force
            $bPlay.Location = New-Object System.Drawing.Point($playX, $playY)
            $card.Controls.Add($bPlay)

            # Значок настроек аккаунта — та же шестерёнка ('gear'), что и у
            # кнопки «Настройки» в боковом меню. Раньше здесь стоял символ
            # псевдографики «✎» — на мелком шрифте карточки он не читался как
            # карандаш и больше напоминал крапинку/изюминку, чем действие
            # «настроить».
            $bEdit = New-RamButton -Text '' -Icon 'gear' -IconOnly -Width $icoW -Height $btnH -Fixed -Tooltip 'Настройки аккаунта' -OnClick {
                $old = Get-RamAccountById -Id $this.Tag.AccountId
                if ($null -eq $old) { return }
                $new = Show-RamAccountDialog -Account $old
                if ($null -ne $new) {
                    foreach ($p in $new.PSObject.Properties.Name) { $old.$p = $new.$p }
                    Save-RamState
                    Build-RamCards
                    Write-RamLog "Изменён аккаунт '$($old.Alias)'." 'ok'
                }
            }
            $bEdit.Tag | Add-Member -NotePropertyName AccountId -NotePropertyValue $a.Id -Force
            $bEdit.Location = New-Object System.Drawing.Point($editX, $midY)
            $card.Controls.Add($bEdit)

            $bStop = New-RamButton -Text '' -Icon 'stop' -IconOnly -Width $icoW -Height $btnH -Fixed -Tooltip 'Закрыть окно этого аккаунта' -OnClick {
                $id   = [string]$this.Tag.AccountId
                $inst = $script:Instances[$id]
                $acc  = Get-RamAccountById -Id $id
                if ($null -eq $inst) {
                    # Ответ и на «делать нечего»: молчащая кнопка неотличима от сломанной.
                    Set-RamStatus ("Окно «{0}» сейчас не запущено — закрывать нечего." -f $acc.Alias)
                    return
                }
                # Закрытие руками — не вылет: счётчик вылетов не трогаем.
                $inst | Add-Member -NotePropertyName ClosedByUser -NotePropertyValue $true -Force
                if ($null -eq $script:Stopping) { $script:Stopping = @{} }
                $script:Stopping[$id] = $true
                Update-RamCardStates
                try {
                    if (Stop-RamRobloxInstance -ProcessId $inst.ProcessId) {
                        $script:Instances.Remove($id)
                        Write-RamLog "'$($acc.Alias)' закрыт." 'ok'
                    } else {
                        Write-RamLog "Не удалось закрыть '$($acc.Alias)' — окно остаётся под контролем менеджера." 'warn'
                        Show-RamMessage -Kind 'warn' -Message ("Окно «$($acc.Alias)» закрыть не вышло. Оно по-прежнему под присмотром AltHub — попробуй ещё раз или закрой его вручную.")
                    }
                } finally {
                    # Иначе при сбое закрытия карточка навсегда застревала в «выход...».
                    $script:Stopping.Remove($id)
                    Update-RamCardStates
                }
            }
            $bStop.Tag | Add-Member -NotePropertyName AccountId -NotePropertyValue $a.Id -Force
            $bStop.Location = New-Object System.Drawing.Point($stopX, $lowY)
            $card.Controls.Add($bStop)

            # --- клик по пустому месту переключает отметку
            $toggle = {
                if ($script:DragMoved) { return }   # это было перетаскивание, а не клик
                $c = $this
                while ($null -ne $c -and $null -eq $c.Tag.AccountId) { $c = $c.Parent }
                if ($null -eq $c) { return }
                $entry = $script:Cards[$c.Tag.AccountId]
                if ($null -eq $entry) { return }
                $entry.Check.Tag.Checked = -not $entry.Check.Tag.Checked
                if ($entry.Check.Tag.Checked) { $script:CheckedIds[[string]$c.Tag.AccountId] = $true }
                else { [void]$script:CheckedIds.Remove([string]$c.Tag.AccountId) }
                $entry.Check.Invalidate()
                Update-RamStatusLine
            }

            # --- перетаскивание карточки меняет порядок
            $dragDown = {
                param($s, $e)
                if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
                $c = $s
                while ($null -ne $c -and $null -eq $c.Tag.AccountId) { $c = $c.Parent }
                if ($null -eq $c) { return }
                $script:DragId     = $c.Tag.AccountId
                $script:DragMoved  = $false
                $script:DragStart  = [System.Windows.Forms.Cursor]::Position
                $script:DragOverId = ''
                $script:DragOverLine = $null

                # Подсветка сразу по нажатию, ещё до сдвига мыши — чтобы захват
                # ощущался мгновенным, а не только после порога. Обычному клику
                # (переключение отметки) это не мешает: $toggle смотрит на
                # DragMoved, а не на подсветку.
                $c.Tag.Selected = $true
                Sync-RamCardLabelFill -Card $c
                $c.Invalidate()
            }
            $dragMove = {
                param($s, $e)
                if ([string]::IsNullOrEmpty($script:DragId)) { return }

                # Порог снижен с 12 до 6 пикселей: раньше карточку надо было
                # заметно протащить, и при обычном неуверенном движении мыши
                # перетаскивание выглядело неработающим.
                if (-not $script:DragMoved -and
                    (([Math]::Abs([System.Windows.Forms.Cursor]::Position.X - $script:DragStart.X) + [Math]::Abs([System.Windows.Forms.Cursor]::Position.Y - $script:DragStart.Y)) -gt [System.Windows.Forms.SystemInformation]::DragSize.Width)) {
                    $script:DragMoved = $true
                    $script:UI.Cards.Cursor = [System.Windows.Forms.Cursors]::SizeAll
                }
                if (-not $script:DragMoved) { return }

                # Ищем карточку под курсором и рисуем черту у её верхнего или
                # нижнего края — туда карточка встанет, если отпустить сейчас.
                $host2 = $script:UI.Cards
                $pt = $host2.PointToClient([System.Windows.Forms.Cursor]::Position)
                $overId = ''
                $wantLine = $null
                foreach ($ctl in $host2.Controls) {
                    if ([string]::IsNullOrEmpty($ctl.Tag.AccountId)) { continue }
                    # Попадание по ПРЯМОУГОЛЬНИКУ карточки, а не только по высоте:
                    # в широком меню карточки стоят в несколько колонок, и проверка
                    # одной Y выбирала карточку из чужой колонки. Подсветка у цели
                    # одна — «с этой карточкой поменяемся местами».
                    if ($ctl.Bounds.Contains($pt)) {
                        $overId   = $ctl.Tag.AccountId
                        $wantLine = 'swap'
                        break
                    }
                }
                if ($overId -eq $script:DragId) { $overId = ''; $wantLine = $null }

                # Перерисовываем ТОЛЬКО когда черта действительно должна
                # переехать. Сравниваем и карточку, и край: иначе при переходе
                # из верхней половины карточки в нижнюю черта осталась бы
                # сверху, а перерисовка на каждое движение мыши даёт мерцание.
                $curCard  = if ($script:DragOverId -and $script:Cards.ContainsKey($script:DragOverId)) {
                    $script:Cards[$script:DragOverId].Card
                } else { $null }
                $curLine  = if ($null -ne $curCard) { $curCard.Tag.DropLine } else { $null }
                if ($overId -ne $script:DragOverId -or $wantLine -ne $curLine) {
                    if ($null -ne $curCard) {
                        $curCard.Tag.DropLine = $null
                        # Фон карточки-цели подсвечивается не только сам по
                        # себе (Add_Paint), но и синхронизируется с фоном
                        # текстовых подписей поверх него (см.
                        # Sync-RamCardLabelFill) — без этого при снятии
                        # подсветки фон карточки возвращался бы к обычному,
                        # а фон текста так и оставался бы подсвеченным.
                        Sync-RamCardLabelFill -Card $curCard
                        $curCard.Invalidate()
                    }
                    $script:DragOverId = $overId
                    $script:DragOverLine = $wantLine
                    if ($overId -and $script:Cards.ContainsKey($overId)) {
                        $newCard = $script:Cards[$overId].Card
                        $newCard.Tag.DropLine = $wantLine
                        Sync-RamCardLabelFill -Card $newCard
                        $newCard.Invalidate()
                    }
                }
            }
            $dragUp = {
                param($s, $e)
                if ([string]::IsNullOrEmpty($script:DragId)) { return }
                $id = $script:DragId
                $script:DragId = ''
                $script:UI.Cards.Cursor = [System.Windows.Forms.Cursors]::Default

                # Цель обмена — запоминаем ДО того, как ниже обнулим
                # $script:DragOverId для снятия подсветки. Раньше здесь была
                # ошибка: строка "$script:DragOverId = ''" шла до того места,
                # где эта же переменная читалась для самого свопа — то есть
                # к моменту вызова Swap-RamAccountOrder цель уже была
                # стёрта, и перетаскивание визуально работало (подсветка
                # честно ходила за курсором), а фактический обмен карточек
                # никогда не срабатывал.
                $targetId = $script:DragOverId

                # Снимаем и подсветку схваченной карточки, и подсветку
                # карточки-цели. Обе могут указывать на карточки, которых
                # уже нет после Build-RamCards, поэтому проверяем наличие
                # в словаре.
                if ($script:Cards.ContainsKey($id)) {
                    $script:Cards[$id].Card.Tag.Selected = $false
                    Sync-RamCardLabelFill -Card $script:Cards[$id].Card
                    $script:Cards[$id].Card.Invalidate()
                }
                if ($targetId -and $script:Cards.ContainsKey($targetId)) {
                    $overCard = $script:Cards[$targetId].Card
                    $overCard.Tag.DropLine = $null
                    Sync-RamCardLabelFill -Card $overCard
                    $overCard.Invalidate()
                }
                $script:DragOverId = ''

                if (-not $script:DragMoved) { return }

                # ПРОСТОЙ ОБМЕН МЕСТАМИ — РОВНО С ТОЙ КАРТОЧКОЙ, НА КОТОРУЮ
                # НАВЕЛИ, БЕЗ СДВИГА ОСТАЛЬНЫХ.
                #
                # Раньше здесь вычислялся индекс вставки (сперва грубо по
                # Y-координате, потом — по позиции карточки-цели в списке
                # без перетаскиваемого элемента) и звался Set-RamAccountOrder
                # — «встать на позицию N», что сдвигает всё между старым и
                # новым местом. Для карточки, которую тащат ЧЕРЕЗ несколько
                # других (например, «1» мимо «2» на «3»), это давало не
                # обмен «1» и «3» местами, а «вытащить 1 и вставить в
                # конец» — список 1,2,3 превращался в 2,3,1 вместо ожидаемых
                # 3,2,1. Человек навёл на «3» и ожидал поменяться местами
                # именно с «3», а не «переехать в конец списка, задев 2 по
                # дороге» — половина карточки (before/after), на которую
                # смотрел старый код, тут вообще ни при чём: наводишь на
                # карточку — меняешься с ней местами, независимо от того, в
                # верхнюю или нижнюю её половину попал курсор.
                # Вернуть можно Ctrl+Z — как и любую другую перестановку.
                if ($targetId -and $targetId -ne $id) { Push-RamUndo -Label 'обмен карточек местами' }
                if ($targetId -and (Swap-RamAccountOrder -Id $id -WithId $targetId)) {
                    Save-RamState
                    Build-RamCards
                }
            }

            $clickable = @($card, $lblName, $lblSub, $lblGame, $av)
            if ($null -ne $lblGroup) { $clickable += $lblGroup }
            foreach ($ctl in $clickable) {
                $ctl.Add_MouseDown($dragDown)
                $ctl.Add_MouseMove($dragMove)
                $ctl.Add_MouseUp($dragUp)
                $ctl.Add_Click($toggle)
            }
            if ($null -ne $lblNote) { $lblNote.Add_Click($toggle) }

            # Правый клик по карточке — меню действий ровно для неё.
            $menu = New-RamCardMenu -AccountId $a.Id
            foreach ($ctl in $clickable) { $ctl.ContextMenuStrip = $menu }
            if ($null -ne $lblNote) { $lblNote.ContextMenuStrip = $menu }
            $dot.ContextMenuStrip = $menu

            $script:Cards[$a.Id] = @{
                Card = $card; Check = $chk; Avatar = $av
                Name = $lblName; Sub = $lblSub; Game = $lblGame; Dot = $dot
                Play = $bPlay; Edit = $bEdit; Stop = $bStop
                AvatarLoaded = ($null -ne $cached)
            }

            if ([int64]$a.UserId -gt 0 -and $null -eq $cached) { [void]$script:AvatarQueue.Add($a.Id) }
        }
    } finally {
        Exit-RamListRebuild -Panel $host_ -ScrollY $listScroll
    }

    Update-RamCardStates
    Update-RamHeaderCounts
    Update-RamGroupBar
    Update-RamStatusLine
}

function Update-RamCardStatesWater {
    <# Обновляет только статусы — вызывается по таймеру, карточки не пересоздаёт. #>
    $t = $Global:RamTheme

    foreach ($a in $script:Accounts) {
        $entry = $script:Cards[$a.Id]
        if ($null -eq $entry) { continue }

        $inst = $script:Instances[$a.Id]
        # Флаг ClosingByOs (см. Update-RamInstances в Accounts.ps1) — окно
        # закрыли крестиком/Alt+F4, минуя кнопку «■» в AltHub. Раньше это
        # ничем не отличалось от «клиент только запускается» (в обоих
        # случаях Handle временно Zero), и на карточке ошибочно висела
        # «загрузка...» для аккаунта, который на самом деле выходит.
        $osClosing = ($null -ne $inst -and $inst.PSObject.Properties.Name -contains 'ClosingByOs' -and [bool]$inst.ClosingByOs)
        if ($null -ne $script:Stopping -and $script:Stopping.ContainsKey($a.Id)) {
            # "Закрывается" всё ещё обрезалось многоточием в узкой подписи
            # под аватаркой. "Выход" короче и садится без обрезки — и по
            # регистру теперь совпадает с соседними подписями ("не запущен",
            # "в игре", "в очереди" — все со строчной буквы).
            Set-RamStatusDot -Dot $entry.Dot -Caption 'выход...' -Color $t.Danger -Avatar $entry.Avatar
        } elseif ($osClosing) {
            Set-RamStatusDot -Dot $entry.Dot -Caption 'выход...' -Color $t.Danger -Avatar $entry.Avatar
        } elseif ($null -ne $inst) {
            if ($inst.Handle -ne [IntPtr]::Zero) {
                Set-RamStatusDot -Dot $entry.Dot -Caption 'в игре' -Color $t.Ok -Avatar $entry.Avatar
            } else {
                # Со строчной "з" — единственная подпись, где буква была
                # заглавной вопреки остальным ("не запущен", "в игре",
                # "в очереди", "выход").
                Set-RamStatusDot -Dot $entry.Dot -Caption 'загрузка...' -Color $t.Warn -Avatar $entry.Avatar
            }
        } elseif ($script:LaunchQueue -contains $a.Id) {
            Set-RamStatusDot -Dot $entry.Dot -Caption 'в очереди' -Color $t.Accent -Avatar $entry.Avatar
        } else {
            # Мёртвый вход виден сразу, а не только по кнопке ↻: красная
            # подпись и красная рамка аватарки.
            if ([string]$a.CookieOk -eq 'no') {
                Set-RamStatusDot -Dot $entry.Dot -Caption 'вход мёртв' -Color $t.Danger -Avatar $entry.Avatar
            } else {
                Set-RamStatusDot -Dot $entry.Dot -Caption 'не запущен' -Color $t.Muted -Avatar $entry.Avatar
            }
        }
    }
    Update-RamHeaderCounts
    Update-RamStatusLine
}

function Update-RamOneAvatar {
    <#
      Аватарки грузятся НЕ БЛОКИРУЯ окно.

      Раньше здесь был обычный синхронный запрос, да ещё и три подряд за такт
      двухсекундного таймера. При таймауте клиента 25 секунд и мёртвой сети
      окно замирало почти на две с половиной минуты за один тик — это и была
      самая дорогая операция во всей программе.

      Теперь это маленький автомат: за такт делается ОДИН короткий шаг.
      Если запрос ещё в пути — сразу выходим, не потратив ничего.

      Шаги:
        нет задачи + очередь не пуста -> спросить адрес картинки
        адрес получен                 -> начать скачивание
        картинка скачана              -> сохранить и показать
    #>

    # --- есть незавершённая задача?
    if ($null -ne $script:AvatarJob) {
        $job = $script:AvatarJob
        if (-not $job.Net.Task.IsCompleted) { return }   # ещё летит, ждать не будем

        $script:AvatarJob = $null
        $a = Get-RamAccountById -Id $job.Id
        $entry = $script:Cards[$job.Id]

        if ($job.Stage -eq 'url') {
            $r = Complete-RamGetAsync -Job $job.Net
            $imageUrl = ''
            if ($r.Ok) {
                try {
                    $data = ($r.Body | ConvertFrom-Json).data
                    if ($data -and $data.Count -gt 0) { $imageUrl = [string]$data[0].imageUrl }
                } catch { }
            }
            if ([string]::IsNullOrWhiteSpace($imageUrl) -or $null -eq $a) {
                $script:AvatarSkip[[string]$job.UserId] = [int]$script:AvatarSkip[[string]$job.UserId] + 1
                return
            }
            $script:AvatarJob = [pscustomobject]@{
                Id = $job.Id; UserId = $job.UserId; Stage = 'img'
                Net = (Start-RamGetAsync -Url $imageUrl -TimeoutSec 10)
            }
            return
        }

        # --- пришла сама картинка
        $r = Complete-RamGetAsync -Job $job.Net -AsBytes
        if (-not $r.Ok -or $null -eq $r.Bytes -or $r.Bytes.Length -lt 100) {
            $script:AvatarSkip[[string]$job.UserId] = [int]$script:AvatarSkip[[string]$job.UserId] + 1
            return
        }
        try {
            $dir = Get-RamAvatarDir
            if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            $file = Join-Path $dir "$($job.UserId).png"
            [System.IO.File]::WriteAllBytes($file, $r.Bytes)

            if ($null -ne $a -and $null -ne $entry) {
                $img = Get-RamCachedAvatarImage -UserId $job.UserId -Path $file -Reload
                if ($null -ne $img) {
                    Set-RamAvatarImage -Box $entry.Avatar -Image $img -Letter $a.Alias
                    $entry.AvatarLoaded = $true
                }
            }
        } catch { }
        return
    }

    # --- задачи нет: берём следующего из очереди
    if ($script:AvatarQueue.Count -eq 0) { return }

    $id = $script:AvatarQueue[0]
    $script:AvatarQueue.RemoveAt(0)

    $a = Get-RamAccountById -Id $id
    $entry = $script:Cards[$id]
    if ($null -eq $a -or $null -eq $entry -or $a.UserId -le 0) { return }

    # Два неудачных захода подряд — больше не дёргаем до перезапуска.
    # Иначе при недоступном интернете очередь долбится вечно.
    if ([int]$script:AvatarSkip[[string]$a.UserId] -ge 2) { return }

    # Свежая копия уже лежит в кэше — сеть не нужна вовсе.
    $cached = Get-RamCachedAvatarFile -UserId $a.UserId -CacheDir (Get-RamAvatarDir)
    if ($null -ne $cached) {
        $img = Get-RamCachedAvatarImage -UserId $a.UserId -Path $cached
        if ($null -ne $img) {
            Set-RamAvatarImage -Box $entry.Avatar -Image $img -Letter $a.Alias
            $entry.AvatarLoaded = $true
        }
        return
    }

    $script:AvatarJob = [pscustomobject]@{
        Id = $id; UserId = $a.UserId; Stage = 'url'
        Net = (Start-RamGetAsync -Url (Get-RamAvatarUrl -UserId $a.UserId) -TimeoutSec 10)
    }
}

function Save-RamMainWindowGeometry {
    <#
      Запоминает место и размер главного окна, чтобы при следующем запуске
      оно открылось таким же, каким его оставили — а не пересчиталось заново.

      Размер пишем как ClientSize (без рамки и заголовка), потому что именно
      его читает New-RamMainForm при создании окна — Size/Bounds включают
      рамку, и подстановка одного вместо другого понемногу «подрастила» бы
      окно при каждом перезапуске.

      Место и размер берём из RestoreBounds, а не из текущих Location/Size:
      если окно сейчас развёрнуто, обычные Location/Size укажут на весь
      экран, и именно «весь экран» запомнится как обычный размер — окно
      потеряет способность возвращаться в прежний, несвёрнутый вид.
    #>
    param([Parameter(Mandatory)]$Form)

    $maximized = ($Form.WindowState -eq [System.Windows.Forms.FormWindowState]::Maximized)
    $bounds = if ($Form.WindowState -eq [System.Windows.Forms.FormWindowState]::Normal) {
        $Form.Bounds
    } else {
        $Form.RestoreBounds
    }

    if ($bounds.Width -le 0 -or $bounds.Height -le 0) { return }

    $borderW = [Math]::Max(0, $Form.Width  - $Form.ClientSize.Width)
    $borderH = [Math]::Max(0, $Form.Height - $Form.ClientSize.Height)

    $script:Settings.MainWindowMaximized = $maximized
    $script:Settings.MainWindowX = $bounds.X
    $script:Settings.MainWindowY = $bounds.Y
    $script:Settings.MainWindowW = [Math]::Max(1, $bounds.Width  - $borderW)
    $script:Settings.MainWindowH = [Math]::Max(1, $bounds.Height - $borderH)

    $styleKey = if ($script:UI.ContainsKey('MenuStyleKey') -and $script:UI.MenuStyleKey) {
        [string]$script:UI.MenuStyleKey
    } elseif ($script:Settings.MenuStyle) { [string]$script:Settings.MenuStyle } else { 'classic' }
    $records = @()
    if ($script:Settings.PSObject.Properties.Name -contains 'MenuWindowGeometry') {
        $records = @($script:Settings.MenuWindowGeometry | Where-Object { $_ -and [string]$_.Key -ne $styleKey })
    }
    $records += [pscustomobject]@{
        Key=$styleKey; X=$bounds.X; Y=$bounds.Y
        W=[Math]::Max(1, $bounds.Width - $borderW); H=[Math]::Max(1, $bounds.Height - $borderH)
        Maximized=$maximized
    }
    $script:Settings.MenuWindowGeometry = @($records)
    Save-RamSettingsNow
}

function Show-RamMainWindow {
    <# Вернуть главное окно из часов. Одно место на все способы: значок,
       его меню, повторный запуск программы. #>
    $f = $script:UI.Form
    if ($null -eq $f) { return }
    try {
        $f.Show()
        if ($f.WindowState -eq 'Minimized') { $f.WindowState = 'Normal' }
        [void]$f.Activate()
        $f.BringToFront()
    } catch { }
}

function Confirm-RamTrayVisible {
    <#
      Спрашивает один раз: видно ли значок в часах.

      Зачем спрашивать, а не проверить. У Windows нельзя узнать, видит ли
      человек значок: Shell_NotifyIcon возвращает успех и когда значок уехал
      под стрелку «^». Именно на этом программа и терялась — окно пряталось,
      значка не было, вернуть было нечем.

      Возвращает $true, если в часы прятать можно.
    #>
    if ([bool]$script:Settings.TrayConfirmed) { return $true }
    if (-not $script:UI.TrayOk) { return $false }

    # Сначала показываем значок и подсказку, потом спрашиваем — чтобы человеку
    # было куда посмотреть.
    try {
        $script:UI.Tray.BalloonTipTitle = 'Это значок AltHub'
        $script:UI.Tray.BalloonTipText  = 'Он рядом с часами. Если не видно — нажми стрелку ^ слева от часов.'
        $script:UI.Tray.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
        $script:UI.Tray.ShowBalloonTip(6000)
    } catch { }

    $ans = Show-RamMessage -Title 'Крестик убирает в часы' -Kind 'info' -Message (
        "Сейчас рядом с часами должен был появиться значок AltHub.`n`n" +
        "В Windows 11 новые значки часто прячутся под стрелку ^ слева от часов — " +
        "загляни туда и, если он там, перетащи его наружу.`n`n" +
        "Видишь значок?"
    ) -Buttons @(
        @{ Text = 'Да, вижу';            Value = 'yes'; Kind = 'primary' },
        @{ Text = 'Нет — просто закрывай'; Value = 'no' }
    )

    if ([string]$ans -eq 'yes') {
        $script:Settings.TrayConfirmed = $true
        Save-RamSettingsNow
        return $true
    }

    # Не видит — значит прятать нельзя. Переключаем крестик на закрытие
    # и говорим об этом прямо, чтобы не выглядело как «программа сама решила».
    $script:Settings.OnClose = 'exit'
    $script:Settings.TrayConfirmed = $false
    Save-RamSettingsNow
    Write-RamLog 'Значок в часах не виден — крестик переключён на обычное закрытие.' 'warn'
    Show-RamInfo ("Тогда крестик будет просто закрывать программу — так её точно не потеряешь.`n`n" +
                  'Поменять это можно в «Настройки» -> «Прочее».')
    return $false
}

function Show-RamTrayHint {
    <#
      Один раз объясняем, куда делось окно.

      В Windows 11 новый значок в часах по умолчанию уезжает под стрелку «^»,
      и человек видит только то, что программа пропала. Именно так и звучала
      жалоба: «свернул минусиком — закрылось всё приложение».
    #>
    if ([bool]$script:Settings.TrayHintShown) { return }
    if (-not $script:UI.TrayOk -or $null -eq $script:UI.Tray) { return }

    $script:Settings.TrayHintShown = $true
    Save-RamSettingsNow

    try {
        $script:UI.Tray.BalloonTipTitle = "$($script:AppName) продолжает работать"
        # Раз крестик больше не закрывает программу, человеку надо сразу
        # сказать, как её всё-таки закрыть — иначе он будет искать.
        $script:UI.Tray.BalloonTipText  =
            'Окно ушло в часы. Клик по значку возвращает его, правый клик — меню, там же «Выход».'
        $script:UI.Tray.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
        $script:UI.Tray.ShowBalloonTip(7000)
    } catch { }
}

function Update-RamOneGameName {
    <#
      Догружает НАЗВАНИЕ игры для аккаунтов, у которых есть placeId, но имя
      пустое — на карточке такой аккаунт выглядит как «ID 10515146389».

      Так бывает, когда игру назначали в момент, когда Roblox не ответил:
      Get-RamPlaceName возвращает пустую строку, и она уезжает в аккаунт.
      Чинить это разово нельзя — данные уже сохранены на диске, поэтому
      имя подтягивается фоном, как аватарки.

      Тот же принцип: ОДИН короткий шаг за такт, ничего не ждём.
      Шаги: placeId -> universeId -> название.
    #>

    if ($null -ne $script:GameNameJob) {
        $job = $script:GameNameJob
        if (-not $job.Net.Task.IsCompleted) { return }
        $script:GameNameJob = $null

        if ($job.Stage -eq 'universe') {
            $r = Complete-RamGetAsync -Job $job.Net
            $universeId = ''
            if ($r.Ok) {
                try { $universeId = [string](($r.Body | ConvertFrom-Json).universeId) } catch { }
            }
            if ([string]::IsNullOrWhiteSpace($universeId)) {
                $script:GameNameSkip[$job.PlaceId] = [int]$script:GameNameSkip[$job.PlaceId] + 1
                return
            }
            $script:GameNameJob = [pscustomobject]@{
                PlaceId = $job.PlaceId; Stage = 'name'
                Net = (Start-RamGetAsync -Url "https://games.roblox.com/v1/games?universeIds=$universeId" -TimeoutSec 10)
            }
            return
        }

        # --- пришло название
        $r = Complete-RamGetAsync -Job $job.Net
        $name = ''
        if ($r.Ok) {
            try {
                $data = ($r.Body | ConvertFrom-Json).data
                if ($data -and $data.Count -gt 0) { $name = [string]$data[0].name }
            } catch { }
        }
        if ([string]::IsNullOrWhiteSpace($name)) {
            $script:GameNameSkip[$job.PlaceId] = [int]$script:GameNameSkip[$job.PlaceId] + 1
            return
        }

        $touched = 0
        foreach ($a in @($script:Accounts)) {
            if ($null -ne $a -and [string]$a.PlaceId -eq $job.PlaceId -and -not $a.GameName) {
                $a.GameName = $name; $touched++
            }
        }
        # И в сохранённых играх, если там тоже стоит заглушка «ID …».
        foreach ($g in @($script:Settings.Games)) {
            if ($null -ne $g -and [string]$g.PlaceId -eq $job.PlaceId -and ([string]::IsNullOrWhiteSpace([string]$g.Title) -or [string]$g.Title -match '^ID \d+$')) {
                $g.Title = $name; $touched++
            }
        }
        if ($touched -gt 0) {
            Save-RamState
            Save-RamSettingsNow
            Build-RamCards
            if ($script:Section -eq 'games') { Update-RamGamesPanel }
            Write-RamLog "Название игры подтянулось: «$name»." 'info'
        }
        return
    }

    # --- задачи нет: ищем, кому имени не хватает
    $need = ''
    foreach ($a in @($script:Accounts)) {
        if ($null -eq $a) { continue }
        $pid2 = [string]$a.PlaceId
        if (-not $pid2 -or $a.GameName) { continue }
        if ([int]$script:GameNameSkip[$pid2] -ge 2) { continue }
        $need = $pid2; break
    }
    if (-not $need) {
        foreach ($g in @($script:Settings.Games)) {
            if ($null -eq $g) { continue }
            $pid2 = [string]$g.PlaceId
            if (-not $pid2 -or -not ([string]::IsNullOrWhiteSpace([string]$g.Title) -or [string]$g.Title -match '^ID \d+$')) { continue }
            if ([int]$script:GameNameSkip[$pid2] -ge 2) { continue }
            $need = $pid2; break
        }
    }
    if (-not $need) { return }

    # Может, имя уже известно по соседям — тогда сеть не нужна.
    $known = Get-RamKnownGameName -PlaceId $need
    if ($known) {
        foreach ($a in @($script:Accounts)) {
            if ($null -ne $a -and [string]$a.PlaceId -eq $need -and -not $a.GameName) { $a.GameName = $known }
        }
        Save-RamState
        Build-RamCards
        return
    }

    $script:GameNameJob = [pscustomobject]@{
        PlaceId = $need; Stage = 'universe'
        Net = (Start-RamGetAsync -Url "https://apis.roblox.com/universes/v1/places/$need/universe" -TimeoutSec 10)
    }
}

function Set-RamCookieAlive {
    <# Пометить вход живым — после удачной проверки или починки. #>
    param([Parameter(Mandatory)]$Account)
    $Account.CookieOk        = 'yes'
    $Account.CookieCheckedAt = (Get-Date).ToString('s')
}

function Clear-RamAppSession {
    <#
      Заставляет приложение Roblox забыть текущий вход, НЕ разлогинивая
      аккаунт на сервере: файл входа уезжает в копию, а сама сессия остаётся
      живой. Возвращает $true, если получилось.

      Менять аккаунт надо именно так. Кнопка «Выйти» внутри Roblox убивает
      вход на сервере — и сохранённая здесь кука мгновенно становится
      мёртвой. С этого начинается почти каждое «аккаунт перестал запускаться».
    #>
    param([string]$Label = 'session')

    $running = @(Get-RamRobloxProcesses)
    if ($running.Count -gt 0) {
        if (-not (Confirm-Ram "Чтобы сменить аккаунт, надо закрыть Roblox (открыто окон: $($running.Count)).`n`nЗакрыть сейчас?")) { return $false }
        foreach ($p in $running) { [void](Stop-RamRobloxInstance -ProcessId $p.Id) }
        Start-Sleep -Milliseconds 2000
    }

    try {
        $backup = Clear-RamRobloxSession -Label $Label
        Write-RamLog ('Вход приложения отложен в копию: ' + (Split-Path -Leaf $backup)) 'ok'
        return $true
    } catch {
        Show-RamError $_.Exception.Message
        return $false
    }
}

function Build-RamCardMenuItems {
    <#
      Наполняет меню карточки пунктами по текущему состоянию аккаунта.
      Возвращает $false, если аккаунта уже нет — тогда меню не открываем.

      Вынесено из обработчика отдельной функцией, чтобы Самопроверка могла
      позвать её напрямую и посмотреть, что получилось.
    #>
    param([Parameter(Mandatory)]$Menu, [Parameter(Mandatory)][string]$AccountId)

    $m   = $Menu
    $id  = $AccountId
    $acc = Get-RamAccountById -Id $id
    if ($null -eq $acc) { return $false }

    $t       = $Global:RamTheme
    $running = ($null -ne $script:Instances[$id])
    $dead    = ([string]$acc.CookieOk -eq 'no')

    $m.Items.Clear()

    [void](Add-RamMenuItem -Menu $m -Text $acc.Alias -Disabled)
    [void](Add-RamMenuItem -Menu $m -Separator)

    [void](Add-RamMenuItem -Menu $m -Text '▶  Запустить' -Tag $id -OnClick {
        Add-RamToLaunchQueue -Accounts @((Get-RamAccountById -Id ([string]$this.Tag)))
    })

    if ($running) {
        [void](Add-RamMenuItem -Menu $m -Text 'Показать окно' -Tag $id -OnClick {
            $inst = $script:Instances[[string]$this.Tag]
            if ($null -ne $inst -and $inst.Handle -ne [IntPtr]::Zero) {
                [void](Set-RamWindowForeground -Handle $inst.Handle)
            }
        })
        [void](Add-RamMenuItem -Menu $m -Text '■  Закрыть окно' -Tag $id -OnClick {
            $id2  = [string]$this.Tag
            $inst = $script:Instances[$id2]
            if ($null -eq $inst) {
                Set-RamStatus 'Окно этого аккаунта сейчас не запущено — закрывать нечего.'
                return
            }
            $acc2 = Get-RamAccountById -Id $id2
            if ($null -eq $script:Stopping) { $script:Stopping = @{} }
            $inst | Add-Member -NotePropertyName ClosedByUser -NotePropertyValue $true -Force
            $script:Stopping[$id2] = $true
            Update-RamCardStates
            try {
                if (Stop-RamRobloxInstance -ProcessId $inst.ProcessId) {
                    $script:Instances.Remove($id2)
                    Write-RamLog "'$($acc2.Alias)' закрыт." 'ok'
                } else {
                    Write-RamLog "Не удалось закрыть '$($acc2.Alias)' — окно остаётся под контролем менеджера." 'warn'
                    Show-RamMessage -Kind 'warn' -Message ("Окно «$($acc2.Alias)» закрыть не вышло. Попробуй ещё раз или закрой его вручную.")
                }
            } finally {
                # Раньше при сбое здесь стоял return, и карточка навсегда
                # застревала в «выход...».
                $script:Stopping.Remove($id2)
                Update-RamCardStates
            }
        })
    }

    [void](Add-RamMenuItem -Menu $m -Separator)

    [void](Add-RamMenuItem -Menu $m -Text 'Задать игру...' -Tag $id -OnClick {
        Invoke-RamAssignGame -Accounts @((Get-RamAccountById -Id ([string]$this.Tag)))
    })
    [void](Add-RamMenuItem -Menu $m -Text 'Настройки аккаунта...' -Tag $id -OnClick {
        $old = Get-RamAccountById -Id ([string]$this.Tag)
        if ($null -eq $old) { return }
        $new = Show-RamAccountDialog -Account $old
        if ($null -ne $new) {
            foreach ($p in $new.PSObject.Properties.Name) { $old.$p = $new.$p }
            Save-RamState
            Build-RamCards
            Write-RamLog "Изменён аккаунт '$($old.Alias)'." 'ok'
        }
    })

    # Готовые наборы — подменю, чтобы не растягивать основное на четыре пункта.
    # Ключ набора и аккаунт лежат в Tag одной строкой: обработчик берёт своё,
    # а не последнее из цикла.
    $sub = New-Object System.Windows.Forms.ToolStripMenuItem
    $sub.Text      = 'Готовый набор настроек'
    $sub.ForeColor = $t.Text
    $sub.Tag       = $id
    $cur = Get-RamMatchingPreset -Account $acc
    foreach ($p in Get-RamAccountPresets) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem
        $mi.Text      = $(if ([string]$p.Key -eq $cur) { '● ' + $p.Title } else { '    ' + $p.Title })
        $mi.ToolTipText = [string]$p.Hint
        $mi.ForeColor = $t.Text
        $mi.Tag       = ($id + '|' + $p.Key)
        $mi.Add_Click({
            $parts = ([string]$this.Tag) -split '\|'
            $acc2  = Get-RamAccountById -Id $parts[0]
            if ($null -eq $acc2) { return }
            if (Set-RamAccountPreset -Account $acc2 -Key $parts[1]) {
                Save-RamState
                Build-RamCards
                $pr = Get-RamPreset -Key $parts[1]
                Write-RamLog "'$($acc2.Alias)': набор «$($pr.Title)» — $(Get-RamAccountSettingsSummary -Account $acc2)." 'ok'
            }
        })
        [void]$sub.DropDownItems.Add($mi)
    }
    [void]$m.Items.Add($sub)

    $fixText  = if ($dead) { 'Починить вход  —  сейчас мёртв' } else { 'Обновить вход из приложения Roblox' }
    # Красный оставлен разрушительному пункту («Убрать»). Мёртвый вход — это
    # предупреждение, а не опасность: чинить его совершенно безопасно.
    $fixColor = if ($dead) { $t.Warn } else { $null }
    [void](Add-RamMenuItem -Menu $m -Text $fixText -Tag $id -Color $fixColor -OnClick {
        $acc2 = Get-RamAccountById -Id ([string]$this.Tag)
        if ($null -eq $acc2) { return }
        if (Invoke-RamRepairCookie -Account $acc2) {
            Set-RamCookieAlive -Account $acc2
            Save-RamState
            Build-RamCards
            Show-RamInfo "Вход «$($acc2.Alias)» на месте."
        }
    })

    # «Обновить страницу» для одного аккаунта: человек только что вошёл под
    # ним где-то ещё и хочет увидеть это здесь, не гоняя проверку по всем.
    [void](Add-RamMenuItem -Menu $m -Text 'Проверить этот вход' -Tag $id -OnClick {
        Invoke-RamRecheckOne -Id ([string]$this.Tag)
    })

    [void](Add-RamMenuItem -Menu $m -Separator)

    [void](Add-RamMenuItem -Menu $m -Text 'Скопировать приглашение (для переноса себе)' -Tag $id -OnClick {
        $acc2 = Get-RamAccountById -Id ([string]$this.Tag)
        if ($null -eq $acc2) { return }
        if ([string]::IsNullOrWhiteSpace($acc2.Cookie)) { Show-RamInfo 'У этого аккаунта нет сохранённого входа.'; return }
        $code = ConvertTo-RamInviteCode -Account $acc2
        try { [System.Windows.Forms.Clipboard]::SetText($code) } catch { }
        Show-RamInfo ("Приглашение скопировано в буфер обмена.`n`nВнутри — доступ к аккаунту, поэтому это для переноса СЕБЕ на другой компьютер, а не для раздачи. " +
                      "На другом компьютере открой «Добавить» -> «Ещё способы» -> «Вставить пачкой» и вставь его.")
        Write-RamLog "Создано приглашение для «$($acc2.Alias)» (в буфер обмена)." 'info'
    })

    [void](Add-RamMenuItem -Menu $m -Separator)

    [void](Add-RamMenuItem -Menu $m -Text 'Убрать из менеджера' -Tag $id -Color $t.Danger -OnClick {
        Invoke-RamDeleteSelected -Accounts @((Get-RamAccountById -Id ([string]$this.Tag)))
    })

    return $true
}

function New-RamCardMenu {
    <#
      Меню по правому клику на карточке — то же, что кнопки, но без
      расстановки галочек: действие применяется ровно к этому аккаунту.

      Пункты пересобираются в момент открытия. Пока меню не открыли, аккаунт
      мог запуститься или вылететь, и «Закрыть окно» должно быть по факту,
      а не по тому, что было при отрисовке карточки.
    #>
    param([Parameter(Mandatory)][string]$AccountId)

    $menu = New-RamContextMenu
    $menu.Tag = $AccountId
    $menu.Add_Opening({
        param($s, $e)
        if (-not (Build-RamCardMenuItems -Menu $s -AccountId ([string]$s.Tag))) { $e.Cancel = $true }
    })
    return $menu
}


function Show-RamQuickSetup {
    <#
      Мастер быстрой настройки под типичный расклад: один основной аккаунт,
      которым играешь, и твины, которые просто стоят на приватном сервере.

      Что делает:
        основному  — свой набор, графика на максимум, звук включён;
        твинам     — свой набор, графика 1, звук 0, 30 FPS и общая игра;
        раскладка  — основной крупно, твины мелко справа;
        профиль    — «Твины на випку», чтобы поднимать их одной кнопкой.

      Ничего не делает молча: показывает, что именно поменяется, и спрашивает.
    #>
    param(
        # Только для Самопроверка.ps1: собрать окно и вернуть, не показывая.
        [switch]$BuildOnly
    )

    if (@($script:Accounts).Count -lt 2) {
        Show-RamInfo 'Для быстрой настройки нужно хотя бы два аккаунта: основной и твин.'
        return
    }

    $t = $Global:RamTheme
    $m = $t.M

    # Ширина считается от самой длинной строки подсказки, а не назначается
    # числом: раньше окно было 690x470 на любом масштабе, и при 150% полоска
    # сверху обрывалась, а кнопки прижимались к краю.
    $hintLines = @(
        'Одним играешь, остальные стоят на приватном сервере.',
        '  основному — графика на максимум, звук включён',
        '  твинам    — графика 1, звук 0, 30 кадров, общая игра',
        '  окна      — основной крупно слева, твины мелко справа',
        '  профиль   — «Твины на випку», одной кнопкой'
    )
    $wide = 0
    foreach ($l in $hintLines) {
        $w = (Measure-RamText -Text $l -Font $t.FontBody).Width
        if ($w -gt $wide) { $wide = $w }
    }
    $pageW = [Math]::Max($wide + $m.GapLg, [int][Math]::Round(560 * $m.Scale))

    $dlg = New-RamForm
    $dlg.Text            = 'Быстрая настройка'
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.StartPosition   = 'CenterParent'
    $dlg.MaximizeBox     = $false; $dlg.MinimizeBox = $false
    $dlg.BackColor       = $t.Bg
    $dlg.Font            = $t.FontBody
    $dlg.ClientSize      = New-Object System.Drawing.Size(($pageW + $m.PadX * 2), 480)
    $dlg.Add_HandleCreated({ Set-RamDarkTitleBar $this })
    Set-RamWindowIcon $dlg

    $stripe = New-Object System.Windows.Forms.Panel
    $stripe.Location  = New-Object System.Drawing.Point(0, 0)
    $stripe.Size      = New-Object System.Drawing.Size($dlg.ClientSize.Width, $m.StripeH)
    $stripe.BackColor = $t.Accent
    $dlg.Controls.Add($stripe)

    $lay = New-RamLayout -Container $dlg
    [void](Add-RamGap -Layout $lay -Height $m.StripeH)

    $titleH = (Measure-RamText -Text 'Ay' -Font $t.FontBig).Height + 2
    [void](Add-RamRow -Layout $lay -Height $titleH -Gap $m.GapSm -Items @(
        @{ Control = (New-RamLabel -Text 'Быстрая настройка' -X 0 -Y 0 -Width 10 -Height $titleH -Font $t.FontBig)
           Width   = $lay.Width }
    ))

    $hintText = $hintLines -join [Environment]::NewLine
    $hintH = (Measure-RamText -Text $hintText -Font $t.FontBody -MaxWidth $lay.Width).Height + 4
    [void](Add-RamRow -Layout $lay -Height $hintH -Items @(
        @{ Control = (New-RamLabel -Text $hintText -X 0 -Y 0 -Width 10 -Height $hintH -Font $t.FontBody -Color $t.Muted)
           Width   = $lay.Width }
    ))
    [void](Add-RamGap -Layout $lay -Height $m.GapSm)

    $capH = (Measure-RamText -Text 'Ay' -Font $t.FontSmall).Height + 2
    $addCap = {
        param([string]$text)
        [void](Add-RamRow -Layout $lay -Height $capH -Gap $m.GapSm -Items @(
            @{ Control = (New-RamLabel -Text $text -X 0 -Y 0 -Width 10 -Height $capH -Font $t.FontSmall -Color $t.Muted)
               Width   = $lay.Width }
        ))
    }

    & $addCap 'ОСНОВНОЙ АККАУНТ — ИМ ТЫ ИГРАЕШЬ'
    $accItems = @()
    foreach ($a in (Get-RamOrderedAccounts)) {
        $lbl = $a.Alias
        if ($a.Username) { $lbl += "  (@$($a.Username))" }
        $accItems += [pscustomobject]@{ Text = $lbl; Value = $a.Id }
    }
    $cbMain = New-RamCombo -X 0 -Y 0 -Width $lay.Width -Items $accItems -Value $accItems[0].Value
    [void](Add-RamRow -Layout $lay -Items @(@{ Control = $cbMain; Width = $lay.Width }))

    & $addCap 'ИГРА ДЛЯ ТВИНОВ'
    $gameItems = @([pscustomobject]@{ Text = '— оставить как есть —'; Value = '' })
    foreach ($g in (Get-RamGameSuggestions)) { $gameItems += $g }
    $cbGame = New-RamCombo -X 0 -Y 0 -Width $lay.Width -Items $gameItems -Value ''
    [void](Add-RamRow -Layout $lay -Items @(@{ Control = $cbGame; Width = $lay.Width }))

    $btnPaste = New-RamButton -Text 'Вставить' -Width 1 -Height $m.RowHSm -OnClick {
        try {
            if ([System.Windows.Forms.Clipboard]::ContainsText()) {
                $tbGame.Tag.Text = [System.Windows.Forms.Clipboard]::GetText().Trim()
            }
        } catch { }
    }
    $pasteW = (Measure-RamControl -Control $btnPaste).Width
    $tbGame = New-RamTextBox -Width ($lay.Width - $pasteW - $m.Gap) -Height $m.RowHSm -Value ''
    [void](Add-RamRow -Layout $lay -VAlign 'middle' -Items @(
        @{ Control = $tbGame;   Width = ($lay.Width - $pasteW - $m.Gap) },
        @{ Control = $btnPaste; Width = $pasteW }
    ))

    $noteH = (Measure-RamText -Text 'Поле важнее списка: если вставишь сюда ссылку, возьмётся она.' -Font $t.FontSmall -MaxWidth $lay.Width).Height + 2
    [void](Add-RamRow -Layout $lay -Height $noteH -Gap $m.GapSm -Items @(
        @{ Control = (New-RamLabel -Text 'Поле важнее списка: если вставишь сюда ссылку, возьмётся она.' `
                                   -X 0 -Y 0 -Width 10 -Height $noteH -Font $t.FontSmall -Color $t.Muted)
           Width   = $lay.Width }
    ))

    $cbSameGame = New-RamCheckBox -X 0 -Y 0
    $sameH = (Measure-RamText -Text 'Основному поставить ту же игру' -Font $t.FontBody).Height + 2
    $lblSame = New-RamLabel -Text 'Основному поставить ту же игру' -X 0 -Y 0 -Width 10 -Height $sameH
    $lblSame.Cursor = [System.Windows.Forms.Cursors]::Hand
    $lblSame.Tag = $cbSameGame
    $lblSame.Add_Click({ $this.Tag.Tag.Checked = -not $this.Tag.Tag.Checked; $this.Tag.Invalidate() })
    [void](Add-RamRow -Layout $lay -VAlign 'middle' -Gap $m.Gap -Items @(
        @{ Control = $cbSameGame; Width = $cbSameGame.Width },
        @{ Control = $lblSame;    Width = ($lay.Width - $cbSameGame.Width - $m.Gap) }
    ))

    [void](Add-RamGap -Layout $lay -Height $m.Gap)
    $btnGo = New-RamButton -Text 'Настроить' -Width 1 -Height $m.RowHLg -Kind 'primary' -OnClick {
        $this.FindForm().Tag = $true; $this.FindForm().Close()
    }
    $btnNo = New-RamButton -Text 'Отмена' -Width 1 -Height $m.RowHLg -OnClick {
        $this.FindForm().Tag = $false; $this.FindForm().Close()
    }
    [void](Add-RamButtonBar -Layout $lay -Primary $btnGo -Secondary @($btnNo))
    [void](Complete-RamLayout -Layout $lay -ClampToScreen)
    $stripe.Size = New-Object System.Drawing.Size($dlg.ClientSize.Width, $m.StripeH)
    $dlg.Tag = $false

    if ($BuildOnly) { return $dlg }

    [void]$dlg.ShowDialog()
    $go       = [bool]$dlg.Tag
    $mainId   = Get-RamComboValue $cbMain
    $gamePick = Get-RamComboValue $cbGame
    $gameText = $tbGame.Tag.Text.Trim()
    $sameGame = [bool]$cbSameGame.Tag.Checked
    $dlg.Dispose()

    if (-not $go) { return }

    # Разбираем игру: поле важнее выпадающего списка.
    $game = $null
    $raw = if ($gameText) { $gameText } else { $gamePick }
    if ($raw) {
        $script:UI.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        try   { $game = Resolve-RamGameInput -Value $raw }
        catch { Show-RamError $_.Exception.Message; return }
        finally { $script:UI.Form.Cursor = [System.Windows.Forms.Cursors]::Default }
    }

    Push-RamUndo -Label 'быстрая настройка'
    $main   = Get-RamAccountById -Id $mainId
    $twinks = @($script:Accounts | Where-Object { $_.Id -ne $mainId })

    if ($null -eq $main) { Show-RamError 'Основной аккаунт не найден.'; return }

    # --- основной
    $main.Group        = 'Основной'
    $main.Color        = 'green'
    $main.Graphics     = '10'
    $main.Volume       = '80'
    $main.FramerateCap = ''
    $main.Fullscreen   = ''
    $main.Order        = 10
    if ($null -ne $game -and $sameGame -and $game.PlaceId) {
        $main.PlaceId  = $game.PlaceId
        # Пустым именем не затираем: если Roblox не ответил, лучше оставить
        # то название, которое уже было, чем показать голый ID.
        if ($game.GameName) { $main.GameName = $game.GameName }
        $main.LinkCode = $game.LinkCode
    }

    # --- твины
    $i = 1
    foreach ($a in $twinks) {
        $a.Group        = 'Твины'
        $a.Color        = 'blue'
        $a.Graphics     = '1'
        $a.Volume       = '0'
        $a.FramerateCap = '30'
        $a.Fullscreen   = 'no'
        $a.Order        = 10 + ($i++ * 10)
        if ($null -ne $game -and $game.PlaceId) {
            $a.PlaceId  = $game.PlaceId
            if ($game.GameName) { $a.GameName = $game.GameName }
            $a.LinkCode = $game.LinkCode
        }
    }

    # --- раскладка и профиль
    #
    # ВАЖНО: раньше здесь ещё и безусловно включался и СОХРАНЯЛСЯ
    # $script:Settings.AutoTile = $true — то есть один прогон этого мастера
    # молча взводил галочку «Раскладывать окна сеткой сразу после запуска»
    # в общих настройках навсегда, даже если пользователь её осознанно
    # снял. Человек потом идёт в настройки, видит галочку снятой (или не
    # идёт вовсе) и не понимает, почему окна всё равно раскладываются —
    # хотя на деле их переключил этот мастер, а не баг раскладки. Режим
    # раскладки ('main') можно проставить — это назначение самого мастера
    # («твины на випку»), а вот включать/выключать AutoTile — решение
    # пользователя, мастер его трогать не должен.
    $script:Settings.TileMode = 'main'
    if ($null -ne $game -and $game.PlaceId) {
        Add-RamSavedGame -PlaceId $game.PlaceId -LinkCode $game.LinkCode `
                         -Title $(if ($game.GameName) { $game.GameName } else { "ID $($game.PlaceId)" })

        $prof = [pscustomobject]@{
            Name     = 'Твины на випку'
            Group    = 'Твины'
            PlaceId  = $game.PlaceId
            GameName = $game.GameName
            LinkCode = $game.LinkCode
        }
        $rest = @(Get-RamProfiles | Where-Object { $_.Name -ne $prof.Name })
        $script:Settings.Profiles = @(@($prof) + $rest | Select-Object -First 20)
    }

    Save-RamSettings -Settings $script:Settings
    Save-RamState
    Build-RamCards
    Update-RamProfilesPanel

    $what = if ($null -ne $game -and $game.GameName) { $game.GameName }
            elseif ($null -ne $game -and $game.PlaceId) { "ID $($game.PlaceId)" }
            else { 'игра не менялась' }

    Write-RamLog "Быстрая настройка: основной «$($main.Alias)», твинов $($twinks.Count), игра — $what." 'ok'
    Show-RamInfo ("Готово.`n`nОсновной: $($main.Alias) — графика 10, звук 80%.`n" +
                  "Твины ($($twinks.Count)): графика 1, звук 0, 30 кадров.`n" +
                  "Игра: $what`n`n" +
                  'Окна теперь раскладываются «основной крупно, твины мелко». ' +
                  'В разделе «Профили» появился «Твины на випку».')
}

function Invoke-RamScheduleCheck {
    <#
      Автозапуск по расписанию. Проверяется раз в 30 секунд.
      Срабатывает один раз за сутки в указанную минуту.
    #>
    if ($null -eq $script:Settings) { return }
    $time = [string]$script:Settings.AutoStartAtTime
    if ([string]::IsNullOrWhiteSpace($time)) { return }
    if ($time -notmatch '^(\d{1,2}):(\d{2})$') { return }

    $h = [int]$Matches[1]; $m = [int]$Matches[2]
    $now = Get-Date
    if ($now.Hour -ne $h -or $now.Minute -ne $m) { return }

    # «Сегодня уже сработало» хранится в настройках, а не в памяти: иначе
    # перезапуск AltHub в ту же минуту поднимал все окна второй раз.
    $today = $now.ToString('yyyy-MM-dd')
    if ([string]$script:Settings.LastScheduleRun -eq $today) { return }
    $script:Settings.LastScheduleRun = $today
    Save-RamSettingsNow

    $group = [string]$script:Settings.AutoStartGroup
    $targets = if ([string]::IsNullOrWhiteSpace($group)) { @(Get-RamOrderedAccounts) }
               else { @($script:Accounts | Where-Object { [string]$_.Group -eq $group }) }

    if ($targets.Count -eq 0) {
        Write-RamLog "Расписание ${time} сработало, но запускать нечего." 'warn'
        Set-RamStatus "Расписание ${time} сработало, но в наборе нет аккаунтов."
        return
    }

    Write-RamLog "Расписание ${time}: поднимаю $($targets.Count) аккаунтов$(if($group){" из набора «$group»"})." 'ok'
    Add-RamToLaunchQueue -Accounts $targets -Unattended
}

# --------------------------------------------------------------- окно -------

function Get-RamSections {
    @(
        [pscustomobject]@{ Key = 'accounts'; Text = 'Аккаунты';   Icon = 'user' },
        [pscustomobject]@{ Key = 'games';    Text = 'Игры';       Icon = 'gamepad' },
        [pscustomobject]@{ Key = 'profiles'; Text = 'Профили';    Icon = 'profile' },
        [pscustomobject]@{ Key = 'stats';    Text = 'Статистика'; Icon = 'chart' },
        [pscustomobject]@{ Key = 'log';      Text = 'Журнал';     Icon = 'history' }
    )
}

function Show-RamSection {
    <# Переключение разделов бокового меню. #>
    param([string]$Key)

    $script:Section = $Key
    if ($script:Settings) {
        $script:Settings.Section = $Key
        Save-RamSettings -Settings $script:Settings
    }

    foreach ($k in $script:UI.Panels.Keys) {
        $script:UI.Panels[$k].Visible = ($k -eq $Key)
    }
    # Список, пересобранный, пока раздел был скрыт, WinForms раскладывает по
    # прежней ширине и при показе не перекладывает: размер-то не менялся. На
    # узком окне вторая карточка оставалась в ряду и торчала за край.
    if ($script:UI.Panels.ContainsKey($Key) -and $null -ne $script:UI.Panels[$Key]) {
        foreach ($ctl in @($script:UI.Panels[$Key].Controls)) {
            if ($ctl -is [System.Windows.Forms.FlowLayoutPanel]) { $ctl.PerformLayout() }
        }
    }
    foreach ($k in $script:UI.NavButtons.Keys) {
        $b = $script:UI.NavButtons[$k]
        $isActive = ($k -eq $Key)
        # РАНЬШЕ: активная кнопка красилась сплошным цветом темы (Accent) с
        # белым текстом — заливка на всю кнопку, довольно ярко и жирно.
        # ТЕПЕРЬ: фон активной кнопки — тот же акцентный цвет, но с низкой
        # непрозрачностью (лёгкая тонировка, а не плашка), а сам акцентный
        # цвет переехал на иконку и подпись — они окрашиваются, вместо
        # прежнего белого текста поверх сплошной заливки.
        #
        # FromArgb(alpha, color) берёт готовый Accent/AccentHov и подмешивает
        # его в фон с прозрачностью — 46/255 ≈ 18%, заметно, но не забивает
        # фон панели меню под ним. У наведения (Hover) alpha чуть выше
        # (72/255 ≈ 28%) — курсор на неактивной кнопке должен читаться
        # заметнее лёгкой тонировки активной.
        $b.Tag.Back  = if ($isActive) { [System.Drawing.Color]::FromArgb(46, $Global:RamTheme.Accent) } else { $Global:RamTheme.Panel }
        $b.Tag.Hover = if ($isActive) { [System.Drawing.Color]::FromArgb(72, $Global:RamTheme.Accent) } else { $Global:RamTheme.CardHover }
        $b.Tag.Fore  = if ($isActive) { $Global:RamTheme.Accent } else { $Global:RamTheme.Text }
        # Пункты с надписью слева (Pulse) отмечают активный ещё и полоской.
        if ($b.Tag.PSObject.Properties.Name -contains 'ActiveBar') {
            $b.Tag.ActiveBar = ($isActive -and [string]$b.Tag.Align -eq 'left')
        }
        $b.Invalidate()
    }
    # Вкладки вида «Новое» — своя отрисовка, им достаточно знать, какая активна.
    if ($script:UI.ContainsKey('Tabs') -and $null -ne $script:UI.Tabs) {
        foreach ($k in @($script:UI.Tabs.Keys)) {
            $tab = $script:UI.Tabs[$k]
            if ($null -eq $tab -or $tab.IsDisposed) { continue }
            $tab.Tag.Active = ($k -eq $Key)
            $tab.Invalidate()
        }
    }

    # «ВСЕ» / «С ОТМЕЧЕННЫМИ» — ТОЛЬКО НА РАЗДЕЛЕ «АККАУНТЫ».
    #
    # Поиск ($search) остаётся видимым на всех разделах — сам по себе
    # безобидный элемент, просто пустое поле, если раздел его не использует.
    # А вот «Все»/«С отмеченными» ($bAll/$bSel) управляют отметками и
    # групповыми действиями именно над карточками аккаунтов — на «Играх»,
    # «Профилях», «Статистике», «Журнале» они не делают ничего осмысленного,
    # только занимают место и сбивают с толку.
    if ($script:UI.ContainsKey('TopBar')) {
        $tb = $script:UI.TopBar
        $showAccBtns = ($Key -eq 'accounts')
        if ($null -ne $tb.BAll -and -not $tb.BAll.IsDisposed) { $tb.BAll.Visible = $showAccBtns }
        if ($null -ne $tb.BSel -and -not $tb.BSel.IsDisposed) { $tb.BSel.Visible = $showAccBtns }
    }

    # Вторая группа бокового меню (Запустить/Закрыть/Окна) работает только
    # над карточками аккаунтов — видна только на разделе «Аккаунты», на
    # всех остальных («Игры», «Профили», «Статистика», «Журнал») просто
    # прячется, оставляя под собой пустое место. «Популярные из Roblox» и
    # «Готовые профили» — не здесь, а в шапке страницы, рядом с поиском
    # (см. $bGamesPopular/$bProfiles в Update-RamTopBarLayout и в сборке
    # верхней строки).
    if ($script:UI.ContainsKey('NavGroupAcc')) {
        $showAccGroup = ($Key -eq 'accounts')
        foreach ($btn in $script:UI.NavGroupAcc) { $btn.Visible = $showAccGroup }
    }
    if ($script:UI.ContainsKey('TopBar') -and $null -ne $script:UI.TopBar.BGamesPopular) {
        $script:UI.TopBar.BGamesPopular.Visible = ($Key -eq 'games')
    }
    if ($script:UI.ContainsKey('TopBar') -and $null -ne $script:UI.TopBar.BProfiles) {
        $script:UI.TopBar.BProfiles.Visible = ($Key -eq 'profiles')
    }
    if ($script:UI.ContainsKey('TopBar') -and $null -ne $script:UI.TopBar.BStatsReset) {
        $script:UI.TopBar.BStatsReset.Visible = ($Key -eq 'stats')
    }
    if ($script:UI.ContainsKey('TopBar') -and $null -ne $script:UI.TopBar.BCopyLog) {
        $script:UI.TopBar.BCopyLog.Visible = ($Key -eq 'log')
    }
    if ($script:UI.ContainsKey('TopBar') -and $null -ne $script:UI.TopBar.BClearLog) {
        $script:UI.TopBar.BClearLog.Visible = ($Key -eq 'log')
    }

    # ПЕРЕСЧЁТ СРАЗУ, А НЕ ТОЛЬКО НА СЛЕДУЮЩИЙ RESIZE.
    # Update-RamTopBarLayout решает, на сколько опустить панели разделов
    # ($panelsTop), глядя на то, какие кнопки строки поиска СЕЙЧАС видны.
    # Видимость этих кнопок только что поменялась строками выше — но сам
    # пересчёт раньше не запускался при переключении раздела, только при
    # изменении размера окна. Из-за этого на «Играх»/«Профилях» (где справа
    # от поиска либо пусто, либо всего одна кнопка) панель продолжала
    # висеть на отступе, посчитанном для «Аккаунтов» (где отступ больше —
    # там «Все» и «С отмеченными» в две кнопки), и создавала пустую полосу
    # сверху ровно на высоту недостающей кнопки.
    Invoke-RamSafe -What 'раскладка верхней строки при смене раздела' -Body { Update-RamTopBarLayout }
    if ($script:UI.ContainsKey('Modern') -or $script:UI.ContainsKey('Pulse')) {
        Invoke-RamSafe -What 'раскладка окна при смене раздела' -Body { Update-RamShellLayout }
    }

    if ($Key -eq 'stats')    { Update-RamStatsPanel }
    if ($Key -eq 'games')    { Update-RamGamesPanel }
    if ($Key -eq 'profiles') { Update-RamProfilesPanel }
}

function Update-RamAccountsBar {
    <#
      Держит полосу кнопок «Все / С отмеченными» шириной во всю панель и
      ставит всё, что ниже, от её фактического низа. Вызывается при сборке
      окна и на каждое изменение размера панели аккаунтов.

      Раньше здесь было ДВЕ полосы (левая ограничивалась правой) — правая
      («Окна», «Закрыть», «Запустить», «Проверить входы») переехала в
      боковое меню, и полоса в разделе аккаунтов осталась одна, во всю
      ширину.
    #>
    if (-not $script:UI.ContainsKey('AccBar')) { return }
    $bar  = $script:UI.AccBar
    if ($null -eq $bar -or $bar.IsDisposed) { return }

    $m = $Global:RamTheme.M
    $w = $bar.Parent.ClientSize.Width
    # В классике справа стоит вторая полоса (Запустить/Закрыть/Окна) — левая
    # кончается до неё, иначе её кнопки при переносе уходят под правую.
    if ($script:UI.ContainsKey('AccBarR') -and $null -ne $script:UI.AccBarR -and -not $script:UI.AccBarR.IsDisposed) {
        $w = $script:UI.AccBarR.Left - $m.GapLg
    }
    if ($w -lt [int](260 * $m.Scale)) { $w = [int](260 * $m.Scale) }
    if ($bar.Width -ne $w) {
        $bar.Width = $w
        $bar.PerformLayout()
    }

    # Высота — по ФАКТИЧЕСКОМУ низу кнопок, а не по PreferredSize.
    # У FlowLayoutPanel с переносом PreferredSize отдаёт размер БЕЗ переноса:
    # на 150% он говорил «974x57», хотя панель шириной 708 и кнопки уже
    # уехали на вторую строку. Высота оставалась в одну строку, и вторая
    # строка кнопок обрезалась краем панели.
    $bottom = $script:UI.AccBarH
    foreach ($c in $bar.Controls)  { if ($c.Bottom + $c.Margin.Bottom -gt $bottom) { $bottom = $c.Bottom + $c.Margin.Bottom } }
    if ($bar.Height -ne $bottom) { $bar.Height = $bottom }

    $gb = $script:UI.AccGroupBar
    $cards = $script:UI.Cards
    if ($null -ne $gb -and -not $gb.IsDisposed) {
        $y = $bottom + $m.GapSm
        if ($gb.Top -ne $y) { $gb.Location = New-Object System.Drawing.Point($gb.Left, $y) }
    }
    if ($null -ne $cards -and -not $cards.IsDisposed) {
        # От фактического низа полоски наборов, а не «+40»: при 150% и 200%
        # полоска выше сорока точек, и список наезжал на неё.
        $y = $bottom + $m.GapSm
        if ($null -ne $gb -and -not $gb.IsDisposed -and $script:UI.GroupBarShown) { $y = $gb.Top + $gb.Height + $m.GapSm }
        if ($cards.Top -ne $y) {
            # Высоту задаём ОТ НИЗА панели, а не поправкой к прежней. Поправка
            # накапливала ошибку: когда полоса кнопок переставала переносить
            # строку и становилась ниже, список рос вниз и вылезал за край
            # панели — на 18 пикселей, ровно на разницу.
            $cards.Location = New-Object System.Drawing.Point($cards.Left, $y)
            $free = $cards.Parent.ClientSize.Height - $y
            $cards.Height = [Math]::Max(80, $free)
        }

        # Карточки собираются по ширине панели на момент сборки, а панель
        # к тому моменту ещё не села на свой настоящий размер: на 150%
        # карточки получались 1533px внутри панели в 1241px и торчали за
        # правый край. Пересобираем, когда ширина действительно изменилась —
        # ResizeEnd этого не ловит, он бывает только при протаскивании
        # мышью, а не при первой раскладке или развороте окна.
        $w = Get-RamCardWidth
        if ($script:LastCardW -ne $w) {
            $script:LastCardW = $w
            if ($script:UI.ContainsKey('Cards') -and $null -ne $script:Accounts) {
                Invoke-RamSafe -What 'пересборка карточек по ширине' -Body { Build-RamCards }
            }
        }
    }
}

function Get-RamBridgeStatusText {
    <#
      Короткая строка про приём входа из браузера — для нижней строки окна.

      ПОЧЕМУ НЕ ОТДЕЛЬНОЙ НАДПИСЬЮ В РАЗДЕЛЕ «АККАУНТЫ». Пробовал — она дважды
      подралась за место с полосой кнопок и набором: вертикаль там считает
      Update-RamAccountsBar, и второй расчёт неминуемо расходится с первым.
      Нижняя строка уже существует, живёт на всех разделах и ни с чем не
      спорит — состоянию место там.

      Возвращает пустую строку, если сказать нечего.
    #>
    if ($null -eq $script:Settings) { return '' }
    if (-not [bool]$script:Settings.BridgeEnabled) { return '' }
    if ((Get-RamBridgePort) -le 0) { return 'вход из браузера: порт занять не вышло' }
    # Показываем клавишу, которую Windows РЕАЛЬНО отдала. Настройка говорит,
    # чего человек хочет; она не говорит, получилось ли. Раньше здесь стояла
    # именно настройка — и строка обещала F10, которой у программы нет.
    $key = Get-RamBridgeHotkey
    if (-not $key) { return 'вход из браузера: клавиша занята — жми значок AltHub в браузере' }
    if (Test-RamBridgeExtensionSeen) { return "вход из браузера: $key" }
    return "вход из браузера: жду на $key, расширение не отзывалось"
}

function Update-RamGroupBar {
    <# Полоска наборов над списком: Все + по одной кнопке на набор. #>
    if ($script:UI.ContainsKey('ModernChips')) { Update-RamModernChips; return }
    if (-not $script:UI.ContainsKey('GroupBar')) { return }

    $t   = $Global:RamTheme
    $bar = $script:UI.GroupBar
    $bar.SuspendLayout()
    try {
        $bar.Controls.Clear()

        $items = @([pscustomobject]@{ Key = ''; Text = 'Все' })
        foreach ($g in Get-RamGroups) { $items += [pscustomobject]@{ Key = $g; Text = $g } }

        # Показана ли полоска, помним отдельно: Visible у элемента скрытого раздела
        # всегда отвечает false, и список ставился поверх полоски, если его
        # пересобирали, пока открыта другая вкладка.
        $script:UI.GroupBarShown = ($items.Count -gt 1)
        if ($items.Count -le 1) { $bar.Visible = $false; return }
        $bar.Visible = $true

        foreach ($it in $items) {
            $active = ([string]$script:GroupFilter -eq [string]$it.Key)
            $w = [System.Windows.Forms.TextRenderer]::MeasureText($it.Text, $t.FontSmall).Width + 28

            $b = New-RamButton -Text $it.Text -Width $w -Height (Get-RamScaled 28) -Radius 14 `
                               -Kind $(if ($active) { 'primary' } else { 'ghost' }) -OnClick {
                $script:GroupFilter = $this.Tag.GroupKey
                Build-RamCards
            }
            $b.Tag | Add-Member -NotePropertyName GroupKey -NotePropertyValue $it.Key -Force
            $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, $Global:RamTheme.M.Gap, 0)
            $bar.Controls.Add($b)
        }
    } finally {
        $bar.ResumeLayout()
        if ($script:UI.ContainsKey('Cards')) {
            $cards = $script:UI.Cards
            $top = if ($script:UI.GroupBarShown) { $bar.Bottom + $Global:RamTheme.M.GapSm } else { $bar.Top }
            $cards.Location = New-Object System.Drawing.Point(0, $top)
            $cards.Height = [Math]::Max(1, $bar.Parent.ClientSize.Height - $top)
        }
    }
}

function Update-RamStatsPanelWater {
    <# Раздел «Статистика»: сколько раз запускался, сколько наиграно, вылеты. #>
    if (-not $script:UI.ContainsKey('StatsHost')) { return }
    $h = $script:UI.StatsHost
    if ($null -eq $h -or $h.IsDisposed) { return }
    $h.SuspendLayout()
    try {
        Clear-RamPanelControls -Panel $h
        Add-RamStatsRows -Panel $h -Width (Get-RamListWidth -Panel $h)
    } finally {
        $h.ResumeLayout()
    }
}

function Get-RamTextRowH {
    <# Высота строки подписи этим шрифтом — с запасом в две точки масштаба.
       Подпись ниже строки своего шрифта WinForms не рисует вовсе. #>
    param($Font)
    return (Measure-RamText -Text 'Ау' -Font $Font).Height + [int][Math]::Round(2 * $Global:RamTheme.M.Scale)
}

function Get-RamListWidth {
    <# Ширина строк списка: место под полосу прокрутки и зазор — всегда. #>
    param([Parameter(Mandatory)]$Panel)
    return [Math]::Max(1, $Panel.Width - [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth - $Global:RamTheme.M.Gap)
}

function New-RamNoticeCard {
    <# Карточка «заголовок и пояснение» — высота по переносу текста. #>
    param([int]$Width, [string]$Title, [string]$Text)
    $t = $Global:RamTheme; $m = $t.M
    $pad  = $m.CardPad
    $padY = $m.GapLg + $m.GapSm
    $textW  = [Math]::Max(1, $Width - $pad * 2)
    $titleH = Get-RamTextRowH $t.FontTitle
    $textH  = (Measure-RamText -Text $Text -Font $t.FontBody -MaxWidth ([Math]::Max(1, $textW - $m.Gap))).Height + $m.GapSm
    $c = New-RamCard -Width $Width -Height ($padY + $titleH + $m.GapSm + $textH + $padY)
    $c.Controls.Add((New-RamLabel -Text $Title -X $pad -Y $padY -Width $textW -Height $titleH -Font $t.FontTitle -Truncatable))
    $c.Controls.Add((New-RamLabel -Text $Text -X $pad -Y ($padY + $titleH + $m.GapSm) -Width $textW -Height $textH -Font $t.FontBody -Color $t.Muted))
    return $c
}

function New-RamRowCard {
    <#
      Строка-карточка: заголовок и подпись слева, кнопки справа.
      Высота — от шрифтов и самой высокой кнопки, кнопки по центру высоты,
      подписи ровно до первой кнопки.
    #>
    param([int]$Width, [string]$Title, [string]$Meta, [object[]]$Buttons)
    $t = $Global:RamTheme; $m = $t.M
    $pad  = [int][Math]::Round(16 * $m.Scale)
    $padY = [int][Math]::Round(12 * $m.Scale)
    $titleH = Get-RamTextRowH $t.FontTitle
    $metaH  = Get-RamTextRowH $t.FontSmall
    $btnH = 0
    foreach ($b in $Buttons) { if ($b.Height -gt $btnH) { $btnH = $b.Height } }
    $H = [Math]::Max($titleH + $metaH, $btnH) + $padY * 2

    $row = New-RamCard -Width $Width -Height $H
    $x = $Width - $pad
    for ($i = $Buttons.Count - 1; $i -ge 0; $i--) {
        $b = $Buttons[$i]
        $x -= $b.Width
        $b.Location = New-Object System.Drawing.Point($x, [int](($H - $b.Height) / 2))
        $row.Controls.Add($b)
        $x -= $m.Gap
    }
    $textW = [Math]::Max([int][Math]::Round(60 * $m.Scale), $x - $pad)
    $textY = [int](($H - $titleH - $metaH) / 2)
    $row.Controls.Add((New-RamLabel -Text $Title -X $pad -Y $textY -Width $textW -Height $titleH -Font $t.FontTitle -Truncatable))
    $row.Controls.Add((New-RamLabel -Text $Meta -X $pad -Y ($textY + $titleH) -Width $textW -Height $metaH -Font $t.FontSmall -Color $t.Muted -Truncatable))
    return $row
}

function Add-RamStatsRows {
    <#
      «Всего» и по строке на аккаунт — общая часть «Статистики» классики и H₂O.
      Колонок четыре в ряд, а когда самой длинной подписи тесно — сетка 2×2.
    #>
    param([Parameter(Mandatory)]$Panel, [int]$Width)
    $t = $Global:RamTheme; $m = $t.M
    $k = { param($n) [int][Math]::Round($n * $m.Scale) }
    $W = $Width
    $pad  = $m.CardPad
    $padY = & $k 12
    $titleH = Get-RamTextRowH $t.FontTitle
    $smallH = Get-RamTextRowH $t.FontSmall
    $bodyH  = Get-RamTextRowH $t.FontBody

    $totalLaunch = 0; $totalCrash = 0; $totalSec = 0
    foreach ($a in $script:Accounts) {
        $totalLaunch += [int]$a.LaunchCount
        $totalCrash  += [int]$a.CrashCount
        $totalSec    += [int]$a.PlaySeconds
    }
    $head = New-RamCard -Width $W -Height ($padY * 2 + $smallH + $titleH)
    $head.Controls.Add((New-RamLabel -Text 'Всего' -X $pad -Y $padY -Width ($W - $pad * 2) -Height $smallH -Font $t.FontSmall -Color $t.Muted))
    $head.Controls.Add((New-RamLabel -Text ("запусков: $totalLaunch    ·    вылетов: $totalCrash    ·    наиграно: " + (Format-RamDuration $totalSec)) `
                                     -X $pad -Y ($padY + $smallH) -Width ($W - $pad * 2) -Height $titleH -Font $t.FontTitle -Truncatable))
    $Panel.Controls.Add($head)

    $nameW    = [Math]::Max((& $k 220), [int](($W - $pad * 2) * 0.28))
    $restW    = [Math]::Max(1, $W - $pad * 2 - $nameW)
    $minColW  = (Measure-RamText -Text 'ПОСЛЕДНИЙ ЗАПУСК' -Font $t.FontSmall).Width + (& $k 8)
    $grid2x2  = ([int]($restW / 4)) -lt $minColW
    $perRow   = if ($grid2x2) { 2 } else { 4 }
    $colW     = [int]($restW / $perRow)
    $cellH    = $smallH + $bodyH
    $cellsH   = if ($grid2x2) { $cellH * 2 + $m.GapSm } else { $cellH }
    $rowH     = [Math]::Max($titleH + $smallH, $cellsH) + $padY * 2

    foreach ($a in (Get-RamOrderedAccounts)) {
        $row = New-RamCard -Width $W -Height $rowH
        $row.Tag | Add-Member -NotePropertyName Stripe -NotePropertyValue (Get-RamLabelColor -Key ([string]$a.Color)) -Force
        # Метка — полоса по левому краю, ровно по скруглению строки (как у строк аккаунтов).
        $row.Add_Paint({
            param($s, $e)
            if ($null -eq $s.Tag.Stripe) { return }
            $sc = $Global:RamTheme.M.Scale
            $g = $e.Graphics
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
            $path = New-RamRoundRect -Rect (New-Object System.Drawing.Rectangle(0, 0, ($s.Width - 1), ($s.Height - 1))) -Radius $s.Tag.Radius
            $state = $g.Save()
            try {
                $g.SetClip($path)
                $b = New-Object System.Drawing.SolidBrush($s.Tag.Stripe)
                $g.FillRectangle($b, 0, 0, [Math]::Max(3, [int][Math]::Round(4 * $sc)), $s.Height)
                $b.Dispose()
            } finally { $g.Restore($state); $path.Dispose() }
        })

        $nameY = [int](($rowH - $titleH - $smallH) / 2)
        $row.Controls.Add((New-RamLabel -Text $a.Alias -X $pad -Y $nameY -Width ($nameW - $m.Gap) -Height $titleH -Font $t.FontTitle -Truncatable))
        $sub = if ($a.Username) { "@$($a.Username)" } else { 'вход не проверен' }
        $row.Controls.Add((New-RamLabel -Text $sub -X $pad -Y ($nameY + $titleH) -Width ($nameW - $m.Gap) -Height $smallH -Font $t.FontSmall -Color $t.Muted -Truncatable))

        $last = if ($a.LastUsed) {
            try { ([datetime]$a.LastUsed).ToString('dd.MM HH:mm') } catch { [string]$a.LastUsed }
        } else { 'ни разу' }
        $cols = @(
            @{ Cap = 'ЗАПУСКОВ';         Val = [string][int]$a.LaunchCount; Color = $t.Text },
            @{ Cap = 'ВЫЛЕТОВ';          Val = [string][int]$a.CrashCount; Color = $(if ([int]$a.CrashCount -gt 0) { $t.Warn } else { $t.Text }) },
            @{ Cap = 'НАИГРАНО';         Val = (Format-RamDuration ([int]$a.PlaySeconds)); Color = $t.Text },
            @{ Cap = 'ПОСЛЕДНИЙ ЗАПУСК'; Val = $last; Color = $t.Text }
        )
        $gridTop = [int](($rowH - $cellsH) / 2)
        for ($i = 0; $i -lt $cols.Count; $i++) {
            $cx = $pad + $nameW + $colW * ($i % $perRow)
            $cy = $gridTop + [int][Math]::Floor($i / $perRow) * ($cellH + $m.GapSm)
            $row.Controls.Add((New-RamLabel -Text $cols[$i].Cap -X $cx -Y $cy -Width ($colW - $m.GapSm) -Height $smallH -Font $t.FontSmall -Color $t.Muted -Truncatable))
            $row.Controls.Add((New-RamLabel -Text $cols[$i].Val -X $cx -Y ($cy + $smallH) -Width ($colW - $m.GapSm) -Height $bodyH -Color $cols[$i].Color -Truncatable))
        }
        $Panel.Controls.Add($row)
    }
}

function Format-RamDuration {
    param([int]$Seconds)
    if ($Seconds -le 0) { return '—' }
    $ts = [TimeSpan]::FromSeconds($Seconds)
    if ($ts.TotalHours -ge 1) { return ('{0} ч {1} мин' -f [int]$ts.TotalHours, $ts.Minutes) }
    if ($ts.TotalMinutes -ge 1) { return ('{0} мин' -f [int]$ts.TotalMinutes) }
    return ('{0} с' -f $ts.Seconds)
}

function Show-RamPopularGamesDialog {
    <#
      Показывает популярные сейчас игры из Roblox и даёт добавить выбранные в
      «Мои игры». Список тянется вживую (Get-RamPopularGames); если интернета
      нет — честно об этом говорим и не притворяемся.
    #>
    param([switch]$BuildOnly)

    $t = $Global:RamTheme; $m = $t.M
    $k = { param($n) [int][Math]::Round($n * $m.Scale) }
    $shell = New-RamDialogShell -WindowText 'Популярные игры Roblox' -Caption 'Популярные сейчас' -Width (& $k 560)
    $dlg = $shell.Form
    $lay = $shell.Layout
    [void](Add-RamTextBlock -Layout $lay -Text 'Список берётся прямо из Roblox. Отметь нужные и добавь.' -Font $t.FontSmall -Color $t.Muted)

    # Высота списка — не больше половины экрана, чтобы кнопки внизу не уехали.
    $listH = & $k 400
    try {
        $waH = if ($null -ne $Global:RamForceWorkArea) { [int]$Global:RamForceWorkArea.Height } else { [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height }
        $listH = [Math]::Min($listH, [int]($waH * 0.5))
    } catch { }
    $listHost = New-RamScrollPanel -Width $lay.Width -Height $listH
    [void](Add-RamRow -Layout $lay -Height $listH -Items @(@{ Control = $listHost; Width = $lay.Width }))

    $rowChecks = @{}
    $fill = {
        Clear-RamPanelControls -Panel $listHost
        $rowChecks.Clear()
        $listHost.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $games = @(Get-RamPopularGames -Limit 30)
        $listHost.Cursor = [System.Windows.Forms.Cursors]::Default

        $rowW = Get-RamListWidth -Panel $listHost
        if ($games.Count -eq 0) {
            $listHost.Controls.Add((New-RamNoticeCard -Width $rowW -Title 'Roblox не ответил' -Text 'Проверь интернет и нажми «Обновить».'))
            return
        }
        $pad    = & $k 14
        $titleH = Get-RamTextRowH $t.FontTitle
        $smallH = Get-RamTextRowH $t.FontSmall
        $rowH   = $titleH + $smallH + (& $k 10) * 2
        foreach ($g in $games) {
            $card = New-RamCard -Width $rowW -Height $rowH
            $chk = New-RamCheckBox -X $pad -Y 0
            $chk.Top = [int](($rowH - $chk.Height) / 2)
            $card.Controls.Add($chk)
            $textX = $chk.Right + (& $k 12)
            $textW = [Math]::Max(1, $rowW - $textX - $pad)
            $textY = [int](($rowH - $titleH - $smallH) / 2)
            $card.Controls.Add((New-RamLabel -Text ([string]$g.Title) -X $textX -Y $textY -Width $textW -Height $titleH -Font $t.FontTitle -Truncatable))
            $players = if ($g.Players -ge 1000) { "$([math]::Round($g.Players/1000.0,1))K играют" } else { "$($g.Players) играют" }
            $card.Controls.Add((New-RamLabel -Text "$players   ·   ID $($g.PlaceId)" -X $textX -Y ($textY + $titleH) -Width $textW -Height $smallH -Font $t.FontSmall -Color $t.Muted -Truncatable))
            $listHost.Controls.Add($card)
            $rowChecks[$g.PlaceId] = [pscustomobject]@{ Check = $chk; Game = $g }
        }
    }.GetNewClosure()

    $btnRefresh = New-RamButton -Text 'Обновить' -Width 1 -Height $m.RowH -Kind 'ghost' -OnClick ({ & $fill }.GetNewClosure())
    $btnAdd = New-RamButton -Text 'Добавить отмеченные' -Width $m.BtnMinW -Height $m.RowH -Kind 'primary' -OnClick ({
        $picked = @($rowChecks.Values | Where-Object { $_.Check.Tag.Checked })
        if ($picked.Count -eq 0) { Show-RamInfo 'Отметь галочками нужные игры.'; return }
        foreach ($row in $picked) { Add-RamSavedGame -PlaceId $row.Game.PlaceId -LinkCode '' -Title $row.Game.Title }
        Save-RamSettingsNow
        Write-RamLog "В «Мои игры» добавлено из популярных: $($picked.Count)." 'ok'
        Show-RamInfo "Добавлено игр: $($picked.Count). Они теперь в разделе «Игры» и в списке при назначении."
        $this.FindForm().Close()
    }.GetNewClosure())
    $btnClose = New-RamButton -Text 'Закрыть' -Width $m.BtnMinW -Height $m.RowH -OnClick { $this.FindForm().Close() }
    [void](Add-RamGap -Layout $lay -Height $m.Gap)
    [void](Add-RamButtonBar -Layout $lay -Primary $btnAdd -Secondary @($btnClose) -Extra @($btnRefresh))
    [void](Complete-RamDialogShell -Shell $shell)

    if ($BuildOnly) { return $dlg }

    $dlg.Add_Shown({ & $fill }.GetNewClosure())
    [void]$dlg.ShowDialog()
    $dlg.Dispose()
}

function Update-RamGamesPanelWater {
    <# Раздел «Игры»: сохранённые игры, назначить отмеченным, удалить. #>
    if (-not $script:UI.ContainsKey('GamesHost')) { return }
    $t = $Global:RamTheme
    $h = $script:UI.GamesHost
    if ($null -eq $h -or $h.IsDisposed) { return }
    $W = Get-RamListWidth -Panel $h

    $h.SuspendLayout()
    try {
        Clear-RamPanelControls -Panel $h
        $games = @($script:Settings.Games | Where-Object { $null -ne $_ })
        if ($games.Count -eq 0) {
            $h.Controls.Add((New-RamNoticeCard -Width $W -Title 'Список пуст' `
                -Text 'Нажми «＋ Своя игра» и вставь ссылку — или возьми готовую из популярных. Игры также попадают сюда сами, когда назначаешь их аккаунтам.'))
            return
        }
        foreach ($g in $games) {
            # Квадратные значки вида H₂O: подпись — в подсказке при наведении.
            $bSet = New-RamButton -Text '' -Icon 'assign' -IconOnly -Width $t.M.RowH -Height $t.M.RowH -Fixed -Kind 'primary' -Tooltip 'Назначить отмеченным' -OnClick {
                $targets = @(Get-RamTargetAccounts)
                if ($targets.Count -eq 0) { Show-RamInfo 'Сначала отметь аккаунты в разделе «Аккаунты».'; return }
                $g2 = $this.Tag.Game
                foreach ($a in $targets) {
                    $a.PlaceId  = [string]$g2.PlaceId
                    $a.GameName = ([string]$g2.Title) -replace ' \(приватный сервер\)$', ''
                    $a.LinkCode = [string]$g2.LinkCode
                }
                Save-RamState
                Build-RamCards
                Write-RamLog "«$($g2.Title)» назначена аккаунтам: $($targets.Count)." 'ok'
            }
            $bDel = New-RamButton -Text '' -Icon 'trash' -IconOnly -Width $t.M.RowH -Height $t.M.RowH -Fixed -Tooltip 'Удалить' -OnClick {
                $g2 = $this.Tag.Game
                $script:Settings.Games = @(@($script:Settings.Games) | Where-Object {
                    -not ($_.PlaceId -eq $g2.PlaceId -and [string]$_.LinkCode -eq [string]$g2.LinkCode)
                })
                Save-RamSettings -Settings $script:Settings
                Update-RamGamesPanel
                Write-RamLog "«$($g2.Title)» убрана из списка игр." 'ok'
            }
            $bSet.Tag | Add-Member -NotePropertyName Game -NotePropertyValue $g -Force
            $bDel.Tag | Add-Member -NotePropertyName Game -NotePropertyValue $g -Force
            $hasTitle = (-not [string]::IsNullOrWhiteSpace([string]$g.Title)) -and ([string]$g.Title -notmatch '^ID \d+$')
            $title = if ($hasTitle) { [string]$g.Title } else { "ID $($g.PlaceId)" }
            $metaParts = @()
            if ($hasTitle) { $metaParts += "ID $($g.PlaceId)" } else { $metaParts += 'название ещё не подтянулось' }
            if ($g.LinkCode) { $metaParts += 'приватный сервер' }
            $h.Controls.Add((New-RamRowCard -Width $W -Title $title -Meta ($metaParts -join '   ·   ') -Buttons @($bSet, $bDel)))
        }
    } finally {
        $h.ResumeLayout()
    }
}

function Get-RamStarterProfiles {
    <#
      Готовые профили запуска для старта. Все — на «все аккаунты» (набор пустой),
      поэтому работают у любого сразу, без настройки наборов. Игры — известные
      и стабильные по placeId, так что ссылки не протухают.

      Это шаблоны: выбранный превращается в обычный профиль пользователя,
      который дальше можно править и удалять как свой.
    #>
    @(
        [pscustomobject]@{ Name = 'Все в Blox Fruits';       Group = ''; PlaceId = '2753915549'; GameName = 'Blox Fruits';       LinkCode = '' }
        [pscustomobject]@{ Name = 'Все в Brookhaven';        Group = ''; PlaceId = '4924922222'; GameName = 'Brookhaven RP';     LinkCode = '' }
        [pscustomobject]@{ Name = 'Все в Adopt Me!';         Group = ''; PlaceId = '920587237';  GameName = 'Adopt Me!';         LinkCode = '' }
        [pscustomobject]@{ Name = 'Все в Murder Mystery 2';  Group = ''; PlaceId = '142823291';  GameName = 'Murder Mystery 2';  LinkCode = '' }
        [pscustomobject]@{ Name = 'Все в Pet Simulator 99';  Group = ''; PlaceId = '8737899170'; GameName = 'Pet Simulator 99';  LinkCode = '' }
        [pscustomobject]@{ Name = 'Все в Grow a Garden';     Group = ''; PlaceId = '126884695634066'; GameName = 'Grow a Garden'; LinkCode = '' }
        [pscustomobject]@{ Name = 'Все просто в Roblox';     Group = ''; PlaceId = '';           GameName = '';                  LinkCode = '' }
    )
}

function Add-RamStarterProfile {
    <# Кладёт готовый профиль в список пользователя (как обычный сохранённый). #>
    param([Parameter(Mandatory)]$Profile)

    $entry = [pscustomobject]@{
        Name     = [string]$Profile.Name
        Group    = [string]$Profile.Group
        PlaceId  = [string]$Profile.PlaceId
        GameName = [string]$Profile.GameName
        LinkCode = [string]$Profile.LinkCode
    }
    $rest = @(Get-RamProfiles | Where-Object { $_.Name -ne $entry.Name })
    $script:Settings.Profiles = @(@($entry) + $rest | Select-Object -First 20)
    Save-RamSettings -Settings $script:Settings
    Write-RamLog "Готовый профиль «$($entry.Name)» добавлен." 'ok'
}

function Update-RamProfilesPanelWater {
    <# Раздел «Профили»: сохранённые связки набор+игра. #>
    if (-not $script:UI.ContainsKey('ProfilesHost')) { return }
    $t = $Global:RamTheme
    $h = $script:UI.ProfilesHost
    if ($null -eq $h -or $h.IsDisposed) { return }
    $W = Get-RamListWidth -Panel $h

    $h.SuspendLayout()
    try {
        Clear-RamPanelControls -Panel $h
        $profiles = @(Get-RamProfiles)
        if ($profiles.Count -eq 0) {
            $h.Controls.Add((New-RamNoticeCard -Width $W -Title 'Профилей пока нет' `
                -Text 'Отметь нужные аккаунты в разделе «Аккаунты», задай им игру, потом сохрани текущее как профиль. Дальше весь набор запускается одной кнопкой.'))
            return
        }
        foreach ($pr in $profiles) {
            $bRun = New-RamButton -Text '' -Icon 'play' -IconOnly -Width $t.M.RowH -Height $t.M.RowH -Fixed -Kind 'primary' -Tooltip 'Запустить профиль' -OnClick {
                Invoke-RamRunProfile -Profile $this.Tag.Profile
            }
            $bDel = New-RamButton -Text '' -Icon 'trash' -IconOnly -Width $t.M.RowH -Height $t.M.RowH -Fixed -Tooltip 'Убрать' -OnClick {
                $nm = $this.Tag.Profile.Name
                $script:Settings.Profiles = @(Get-RamProfiles | Where-Object { $_.Name -ne $nm })
                Save-RamSettings -Settings $script:Settings
                Update-RamProfilesPanel
                Write-RamLog "Профиль «$nm» убран." 'ok'
            }
            $bRun.Tag | Add-Member -NotePropertyName Profile -NotePropertyValue $pr -Force
            $bDel.Tag | Add-Member -NotePropertyName Profile -NotePropertyValue $pr -Force
            $prIds = @()
            if ($pr.PSObject.Properties.Name -contains 'Ids') { $prIds = @($pr.Ids | Where-Object { $_ }) }
            $meta = if ($pr.Group)          { "набор «$($pr.Group)»" }
                    elseif ($prIds.Count)   { "аккаунтов: $($prIds.Count)" }
                    else                    { 'все аккаунты' }
            if ($pr.GameName) { $meta += "   ·   $($pr.GameName)" }
            elseif ($pr.PlaceId) { $meta += "   ·   ID $($pr.PlaceId)" }
            if ($pr.LinkCode) { $meta += '   ·   приватный сервер' }
            $h.Controls.Add((New-RamRowCard -Width $W -Title ([string]$pr.Name) -Meta $meta -Buttons @($bRun, $bDel)))
        }
    } finally {
        $h.ResumeLayout()
    }
}

function Update-RamTrayMenu {
    <# Меню значка в часах: быстрый запуск без открытия окна. #>
    if ($null -eq $script:UI.TrayMenu) { return }

    $m = $script:UI.TrayMenu
    $m.Items.Clear()

    $mShow = New-Object System.Windows.Forms.ToolStripMenuItem('Открыть AltHub')
    # Жирным: это действие, за которым в меню значка приходят в 9 случаях из 10.
    $mShow.Font = New-Object System.Drawing.Font($mShow.Font, [System.Drawing.FontStyle]::Bold)
    $mShow.Add_Click({ Show-RamMainWindow })
    [void]$m.Items.Add($mShow)
    [void]$m.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))

    foreach ($pr in (Get-RamProfiles)) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem("Профиль: $($pr.Name)")
        $mi.Tag = $pr
        $mi.Add_Click({ Invoke-RamRunProfile -Profile $this.Tag })
        [void]$m.Items.Add($mi)
    }

    foreach ($g in (Get-RamGroups)) {
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem("Набор: $g")
        $mi.Tag = $g
        $mi.Add_Click({
            $gr = $this.Tag
            Add-RamToLaunchQueue -Accounts @($script:Accounts | Where-Object { [string]$_.Group -eq $gr })
        })
        [void]$m.Items.Add($mi)
    }

    if ($m.Items.Count -gt 2) { [void]$m.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) }

    $mStop = New-Object System.Windows.Forms.ToolStripMenuItem('Закрыть все окна Roblox')
    $mStop.Add_Click({
        foreach ($pr in (Get-RamRobloxProcesses)) { [void](Stop-RamRobloxInstance -ProcessId $pr.Id) }
        $script:Instances.Clear()
        Update-RamCardStates
    })
    [void]$m.Items.Add($mStop)

    $mExit = New-Object System.Windows.Forms.ToolStripMenuItem('Выход')
    $mExit.Add_Click({ $script:UI.Form.Close() })
    [void]$m.Items.Add($mExit)
}

function Get-RamCheckableWindows {
    <#
      Все окна программы — списком, чтобы Самопроверка обходила их все.

      ЗАЧЕМ РЕЕСТР. Раньше окна перечислялись прямо в проверке вручную, и
      список отстал: проверялись четыре окна из одиннадцати. Именно поэтому
      наложение в конструкторе тем (кнопка «Подробно» поверх превью) никто
      не замечал — это окно просто не проверялось.

      Правило: появилось новое окно с -BuildOnly — добавь его сюда.
    #>
    @(
        @{ Name = 'главное';       Main = $true
           Sections = @('accounts','games','profiles','stats','log')
           Build = { New-RamMainForm } }
        @{ Name = 'мастер';        Build = { Show-RamAddWizard -BuildOnly } }
        @{ Name = 'аккаунт';       Build = { Show-RamAccountDialog -Account $script:Accounts[0] -BuildOnly } }
        @{ Name = 'настройки';     Build = { Show-RamSettingsDialog -BuildOnly } }
        @{ Name = 'конструктор';   Build = { Show-RamThemeConstructor -BuildOnly } }
        @{ Name = 'пачкой';        Build = { Show-RamBatchAddDialog -BuildOnly } }
        @{ Name = 'из браузера';   Build = { Show-RamBrowserGuide -BuildOnly } }
        @{ Name = 'выбор способа'; Build = { Show-RamAddChooser -BuildOnly } }
        @{ Name = 'расширение';    Build = { Show-RamExtensionGuide -BuildOnly } }
        @{ Name = 'согласие CfT';  Build = { Show-RamChromeForTestingConsent -BuildOnly } }
        @{ Name = 'популярные';    Build = { Show-RamPopularGamesDialog -BuildOnly } }
        @{ Name = 'быстрая';       Build = { Show-RamQuickSetup -BuildOnly } }
        @{ Name = 'мастер1';       Build = { Show-RamFirstRun -StartStep 0 -BuildOnly }; Pages = $true }
        @{ Name = 'мастер1/тема';  Build = { Show-RamFirstRun -StartStep 1 -BuildOnly }; Pages = $true }
        @{ Name = 'мастер1/акк';   Build = { Show-RamFirstRun -StartStep 2 -BuildOnly }; Pages = $true }
        @{ Name = 'мастер1/осн';   Build = { Show-RamFirstRun -StartStep 3 -BuildOnly }; Pages = $true }
        @{ Name = 'мастер1/готово';Build = { Show-RamFirstRun -StartStep 4 -BuildOnly }; Pages = $true }
        @{ Name = 'сообщение';     Build = { Show-RamMessage -Message 'Короткое сообщение для проверки вёрстки.' -BuildOnly } }
        @{ Name = 'сообщение/дл';  Build = { Show-RamMessage -Message ('Длинное сообщение. ' * 12) -Kind 'warn' -BuildOnly } }
        @{ Name = 'сообщение/да';  Build = { Show-RamMessage -Message 'Вопрос с двумя кнопками?' -YesNo -BuildOnly } }
        @{ Name = 'сообщение/4';   Build = { Show-RamMessage -Message 'Выбор из нескольких действий.' -Buttons @(
                                                @{ Text = 'Забрать вход';    Value = 'take';   Kind = 'primary' },
                                                @{ Text = 'Сменить аккаунт'; Value = 'switch' },
                                                @{ Text = 'Пропустить';      Value = 'skip'   },
                                                @{ Text = 'Хватит';          Value = 'stop'   }) -BuildOnly } }
        @{ Name = 'ввод';          Build = { Show-RamInputDialog -Title 'Ввод' -Prompt 'Вставь ссылку на игру или её номер.' -BuildOnly } }
        @{ Name = 'ввод/список';   Build = { Show-RamInputDialog -Title 'Игра' -Prompt 'Выбери из сохранённых или вставь свою.' -Suggestions @(
                                                [pscustomobject]@{ Text = 'Blox Fruits'; Value = '1' },
                                                [pscustomobject]@{ Text = 'Очень длинное название игры для проверки'; Value = '2' }) -BuildOnly } }
    )
}

function Dispose-RamFormRuntime {
    foreach ($key in @('StartupTimer','SearchTimer','ResizeLiveTimer','CookieCheckTimer','LaunchTimer','UpdateTimer','ScheduleTimer','FreshFocusTimer')) {
        if ($script:UI.ContainsKey($key) -and $null -ne $script:UI[$key]) {
            try { $script:UI[$key].Stop(); $script:UI[$key].Dispose() } catch { }
            $script:UI[$key] = $null
        }
    }
    if ($script:UI.ContainsKey('Tray') -and $null -ne $script:UI.Tray) {
        try { $script:UI.Tray.Visible = $false; $script:UI.Tray.Dispose() } catch { }
        $script:UI.Tray = $null
    }
}

function New-RamMainFormWater {
    $t = $Global:RamTheme
    $metrics = $t.M   # НЕ $m: ниже есть foreach ($m in ...), он бы её затёр
    $menuStyle = Get-RamMenuStyle
    $script:UI.MenuLayout = 'water'

    # ------------------------------------------------------------------------
    # РАЗМЕРЫ СЧИТАЮТСЯ, А НЕ ВПИСЫВАЮТСЯ.
    #
    # Раньше здесь стояли числа: боковое меню 210, кнопки в нём 178, панель
    # разделов 1120. Пока экран обычный, всё сходилось. Но надписи меряются
    # шрифтом, а шрифт растёт вместе с масштабом экрана: при 150% кнопке
    # «Быстрая настройка» нужен 261 пиксель, а меню оставалось 210 — и она
    # вылезала за край. То же и с панелями кнопок.
    #
    # Теперь ширина меню выводится из самой длинной надписи в нём. Значок у
    # всех кнопок — фиксированный слот (см. New-RamButton -Icon), поэтому его
    # ширину прибавляем к каждой надписи отдельно, а не встраиваем в текст.
    # ------------------------------------------------------------------------
    $iconSlotW0 = [int][Math]::Round(28 * $metrics.Scale)
    $navTexts = @()
    foreach ($sec in Get-RamSections) { $navTexts += ('  ' + $sec.Text) }
    $navTexts += @('  Фаст-настройка', '  Настройки', '  Справка',
                   '  Запустить', '  Закрыть', '  Окна', '  Проверить входы',
                   '  Починить входы (99)')

    $navW = 0
    foreach ($tx in $navTexts) {
        $w = (Measure-RamText -Text $tx -Font $t.FontBody).Width + $metrics.BtnPadX + $iconSlotW0
        if ($w -gt $navW) { $navW = $w }
    }
    # Pulse — компактный рабочий вид. Ширина боковой панели фиксирована,
    # иначе длинная подпись раздувала её почти до трети окна.
    $navBtnW = [int](210 * $metrics.Scale)
    $sideW   = $navBtnW + ($metrics.GapLg * 2)
    $contentX = $sideW + $metrics.GapLg

    # Раньше здесь стоял пол в 1360px (и содержимому отводилось 1120px) —
    # число из тех времён, когда окно тянулось до экрана без ограничения
    # сверху. Теперь верхний предел ширины окна — 1000px (см. MaximumSize
    # ниже), и старый пол в 1360 не давал окну открыться уже этого предела
    # даже по умолчанию — оно рождалось шире потолка и сразу упиралось в
    # MaximumSize, обрезая расчёт вхолостую. Пола по ширине теперь нет:
    # формула считает ровно то, что нужно боковому меню и содержимому.
    # Стартовая ширина содержимого — своя у каждого вида меню: H₂O рассчитан
    # на компактное окно, широкое — на большой монитор.
    $formW = $contentX + [int]([int]$menuStyle.BaseContent * $metrics.Scale) + $metrics.GapLg

    # Высота окна должна учитывать и содержимое бокового меню: заголовок,
    # версия, автор, пять разделов, «Фаст-настройка», четыре перенесённых
    # кнопки (запустить, закрыть, окна, проверить входы) и две нижних
    # (настройки, справка). Раньше высота была одним фиксированным числом
    # (820) — когда в меню добавились новые кнопки, «Справка» перестала бы
    # помещаться и обрезалась бы снизу без предупреждения.
    $nameH0 = (Measure-RamText -Text 'Ay' -Font $t.FontBig).Height + 4
    $verH0  = (Measure-RamText -Text 'Ay' -Font $t.FontSmall).Height + 2
    $authH0 = (Measure-RamText -Text 'Ay' -Font $t.FontSmall).Height + 2
    $navH0  = Get-RamScaled 42
    $navGap0 = Get-RamScaled 6
    $sideTopH = (Get-RamScaled 20) + $nameH0 + $verH0 + (Get-RamScaled 2) + $authH0 + (Get-RamScaled 34)
    $sideRowsCount = (Get-RamSections).Count + 1 + 4  # разделы + фаст-настройка + запустить/закрыть/окна/входы
    $sideBottomCount = 2                              # настройки/справка
    $sideNeededH = $sideTopH + ($sideRowsCount * ($navH0 + $navGap0)) + $metrics.Gap +
                   ($sideBottomCount * ($navH0 + $navGap0)) + $metrics.GapLg

    # Раньше здесь стоял жёсткий минимум 820 (при любом реальном содержимом
    # бокового меню) — если контент оказывался ниже этой цифры, окно всё
    # равно растягивалось до 820, и под «Справкой» повисал пустой отступ во
    # весь остаток высоты. Теперь высота — это реальная потребность бокового
    # меню ($sideNeededH), без искусственного пола: под последней кнопкой
    # остаётся тот же небольшой отступ ($metrics.GapLg), что и между
    # остальными группами кнопок, а не произвольная пустота.
    $formH = $sideNeededH

    # В экран окно тоже должно влезать.
    #
    # $Global:RamForceWorkArea — подмена для Самопроверки. Настоящий экран
    # со 150% — это, как правило, и физически больший экран (2560 или 3840
    # точек), поэтому проверять крупный шрифт на маленьком рабочем столе
    # нечестно: получится теснота, которой у людей не бывает.
    $waW = 0; $waH = 0
    try {
        $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
        $waW = $wa.Width; $waH = $wa.Height
        if ($null -ne $Global:RamForceWorkArea) {
            $waW = [int]$Global:RamForceWorkArea.Width
            $waH = [int]$Global:RamForceWorkArea.Height
        }
        if ($formW -gt $waW) { $formW = $waW }
        if ($formH -gt $waH) { $formH = $waH }
    } catch { }

    $form = New-RamForm
    $form.Text          = $script:AppName
    $form.ClientSize    = New-Object System.Drawing.Size($formW, $formH)

    # MinimumSize относится к окну ЦЕЛИКОМ, вместе с рамкой, а раскладка
    # внутри считается по ClientSize. Рамку меряем по факту.
    $frameW = $form.Width  - $form.ClientSize.Width
    $frameH = $form.Height - $form.ClientSize.Height

    # В рабочую область окно обязано влезать ВМЕСТЕ с рамкой. Раньше с
    # WorkingArea сравнивали ClientSize — и на 150% нижняя строка окна
    # уезжала под панель задач ровно на высоту заголовка.
    if ($waW -gt 0 -and $waH -gt 0) {
        $formW = [Math]::Min($formW, [Math]::Max(640, $waW - $frameW))
        $formH = [Math]::Min($formH, [Math]::Max(480, $waH - $frameH))
        $form.ClientSize = New-Object System.Drawing.Size($formW, $formH)
    }

    # Минимум ширины уточняется по фактической верхней строке, когда она
    # построена (Update-RamMinimumWindowSize). Потолка НЕТ: широкий монитор —
    # повод показать больше, а не держать окно в 1000 точек посреди пустоты.
    # И высота не закреплена намертво — иначе окно нельзя развернуть.
    $form.MinimumSize = New-Object System.Drawing.Size(
        ([Math]::Min($formW, $contentX + [int](460 * $metrics.Scale)) + $frameW),
        ([Math]::Min($formH, $sideNeededH) + $frameH))
    $form.StartPosition = 'CenterScreen'
    $form.BackColor     = $t.Bg
    $form.ForeColor     = $t.Text
    $form.Font          = $t.FontBody
    Set-RamDoubleBuffered $form
    $form.Add_HandleCreated({ Set-RamDarkTitleBar $this })

    Set-RamWindowIcon $form

    # Перетаскивание файла на окно: список кук/приглашений или файл настроек.
    # Курсор «копировать» показываем только для файлов — на текст и прочее не
    # реагируем, чтобы не сбивать с толку.
    $form.AllowDrop = $true
    $form.Add_DragEnter({
        param($src, $e)
        if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) {
            $e.Effect = [System.Windows.Forms.DragDropEffects]::Copy
        } else {
            $e.Effect = [System.Windows.Forms.DragDropEffects]::None
        }
    })
    $form.Add_DragDrop({
        param($src, $e)
        $files = @($e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))
        foreach ($f in $files) { Import-RamDroppedFile -Path $f }
    })

    $script:UI.Panels     = @{}
    $script:UI.NavButtons = @{}

    # =================================================== боковое меню ========
    $side = New-Object System.Windows.Forms.Panel
    $side.Location  = New-Object System.Drawing.Point(0, 0)
    $side.Size      = New-Object System.Drawing.Size($sideW, $formH)
    $side.BackColor = $t.Panel
    $side.Anchor    = 'Top,Left,Bottom'
    $form.Controls.Add($side)

    # Заголовок и версия — крупнее и по центру колонки, а не прижаты к левому
    # краю: так меню читается как титульный блок, а не как случайная подпись
    # сверху. Имя автора — сразу под ними, а не внизу окна: там оно повисало
    # ниже последней кнопки меню на пустом месте и терялось.
    # $nameH0/$verH0/$authH0 уже посчитаны выше для оценки высоты окна —
    # переиспользуем те же числа, чтобы вёрстка не разошлась с расчётом.
    $nameH = $nameH0
    $verH  = $verH0
    $authH = $authH0

    # Заголовок близко к верхней границе, но не вплотную. Раньше отступ был
    # 10px — с этим блок "AltHub / v1.3 / by Эрнест Костевич" стоял почти
    # вплотную к кнопкам меню снизу, а сверху, наоборот, оставалось много
    # воздуха до рамки окна. Уменьшили отступ сверху — освободившееся место
    # ушло в зазор перед кнопками (см. $y ниже), и первая кнопка «Аккаунты»
    # стала визуально отделена от шапки, а не жаться к ней.
    $headY = Get-RamScaled 4

    $lblName = New-RamLabel -Text $script:AppName -X 0 -Y $headY -Width $sideW -Height $nameH -Font $t.FontBig -Align 'center'
    $side.Controls.Add($lblName)

    $lblVer = New-RamLabel -Text "v$($script:AppVersion)" -X 0 -Y ($headY + $nameH) -Width $sideW -Height $verH `
                           -Font $t.FontSmall -Color $t.Muted -Align 'center'
    $side.Controls.Add($lblVer)

    $lblAuthor = New-RamLabel -Text "by $($script:AppAuthor)" -X 0 -Y ($headY + $nameH + $verH + (Get-RamScaled 2)) `
                             -Width $sideW -Height $authH -Font $t.FontSmall -Color $t.Muted -Align 'center'
    $side.Controls.Add($lblAuthor)

    # Шаг между кнопками бокового меню считается от ИХ ВЫСОТЫ, а не задан
    # числом. Раньше высота была 40, а шаг 46 — оба вписаны под 100%. Когда
    # высоту привязали к масштабу, шаг остался прежним, и на 125% кнопки
    # наехали друг на друга на 4 пикселя. Число в одном месте всегда рано
    # или поздно разъезжается с числом в другом.
    $navH  = Get-RamScaled 42
    $navGap = Get-RamScaled 6
    $y = Get-RamScaled 84

    foreach ($sec in Get-RamSections) {
        $isAcc = ($sec.Key -eq 'accounts')
        $isGames = ($sec.Key -eq 'games')
        $isProf = ($sec.Key -eq 'profiles')
        $b = New-RamButton -Text ('  ' + $sec.Text) -Icon $sec.Icon -Width $navBtnW -Height $navH -Radius 10 -OnClick {
            Show-RamSection -Key $this.Tag.SectionKey
        }
        $b.Tag | Add-Member -NotePropertyName SectionKey -NotePropertyValue $sec.Key -Force
        $b.Tag.Border = $null
        $b.Location = New-Object System.Drawing.Point($metrics.GapLg, $y)
        $side.Controls.Add($b)
        $script:UI.NavButtons[$sec.Key] = $b

        # «+» — КНОПКА НА КНОПКЕ, а не рядом с ней: маленький квадрат,
        # добавленный как дочерний контрол ПРЯМО В САМУ кнопку раздела,
        # прижатый к её правому краю. Раньше «+» была самостоятельной
        # кнопкой сбоку, и пункту «Аккаунты» приходилось быть уже
        # остальных, чтобы освободить ей место — теперь «Аккаунты»
        # той же ширины, что и все прочие разделы. «Игры» получили тот же
        # оверлей тем же способом: «＋ Своя игра» переехала сюда из шапки
        # страницы, где она вместе с «Популярные из Roblox» была одной из
        # причин наезда на карточки при узком окне. «Профили» получили
        # его следом: «Сохранить текущее как профиль» была отдельной
        # кнопкой в шапке страницы — теперь это «Создать профиль» здесь.
        if ($isAcc -or $isGames -or $isProf) {
            $addOverlayW = $navH - (Get-RamScaled 8)
            $addTooltip  = if ($isAcc) { 'Все способы добавить аккаунт' } elseif ($isGames) { 'Добавить свою игру' } else { 'Создать профиль' }
            $addAction   = if ($isAcc) {
                { Show-RamAddChooser }
            } elseif ($isGames) {
                {
                    $val = Show-RamInputDialog -Title 'Своя игра' `
                             -Prompt ("Вставь ссылку на игру, приглашение на приватный сервер или просто её номер.`n" +
                                      'Название подтянется само.')
                    if ([string]::IsNullOrWhiteSpace($val)) { return }

                    $script:UI.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
                    try   { $g = Resolve-RamGameInput -Value $val }
                    catch { Show-RamError $_.Exception.Message; return }
                    finally { $script:UI.Form.Cursor = [System.Windows.Forms.Cursors]::Default }

                    if ($null -eq $g -or -not $g.PlaceId) {
                        Show-RamError 'Не удалось понять, что это за игра. Нужна ссылка на игру, приглашение на приватный сервер или номер игры.'
                        return
                    }
                    $title = if ($g.GameName) { $g.GameName } else { "ID $($g.PlaceId)" }
                    Add-RamSavedGame -PlaceId $g.PlaceId -LinkCode $g.LinkCode -Title $title
                    Update-RamGamesPanel
                    Write-RamLog "В список игр добавлена «$title»." 'ok'
                }
            } else {
                { Invoke-RamSaveProfile }
            }
            $bAdd = New-RamButton -Text '+' -Width $addOverlayW -Height $addOverlayW -Radius 6 -Fixed -Kind 'primary' `
                                  -Tooltip $addTooltip -OnClick $addAction
            $bAdd.Location = New-Object System.Drawing.Point(($navBtnW - $addOverlayW - (Get-RamScaled 4)), (Get-RamScaled 4))
            $b.Controls.Add($bAdd)
            if ($isGames) { $script:UI.BtnAddGame = $bAdd }
            if ($isProf)  { $script:UI.BtnAddProfile = $bAdd }
        }
        $y += $navH + $navGap
    }

    # «Фаст-настройка» — под «Журналом», того же стиля, что и разделы выше
    # (не приглушённая, как «Настройки»/«Справка» ниже): по сути это ещё
    # один быстрый переход, а не второстепенное действие.
    $bQuick = New-RamButton -Text '  Фаст-настройка' -Icon 'bolt' -Width $navBtnW -Height $navH -Radius 10 `
                            -Tooltip 'Разложить всё под расклад «основной + твины на випке»' -OnClick {
        Show-RamQuickSetup
    }
    $bQuick.Tag.Border = $null
    $bQuick.Location = New-Object System.Drawing.Point($metrics.GapLg, $y)
    $side.Controls.Add($bQuick)
    $y += $navH + $navGap

    # ----------------------------------- проверка входов/настройки/справка ---
    # Третья группа из трёх кнопок — теперь у НИЖНЕЙ границы бокового меню,
    # а не сразу под серединой группой. Раньше все три группы стояли одна
    # под другой вплотную, и на высоком окне (боковая панель растягивается
    # на всю высоту, Anchor = 'Top,Left,Bottom' — см. её создание выше) под
    # «Справкой» повисал пустой хвост во всю оставшуюся высоту.
    #
    # Позиции этой группы и группы «Запустить/Закрыть/Окна» ниже зависят от
    # $side.Height — а она в момент сборки окна ещё не настоящая: если
    # человек в прошлый раз закрыл программу развёрнутой (WindowState уже
    # выставлен в Maximized чуть выше по коду), WinForms применяет реальные
    # границы окна только когда появляется его хендл, а не в момент простого
    # присваивания свойства. Поэтому саму раскладку вынесли в отдельную
    # функцию (Update-RamSideBarLayout) и здесь только создают кнопки —
    # правильные Y она посчитает следом, при первом вызове после сборки
    # (Add_Shown) и на каждом Resize (переход в развёрнутый режим и обратно).

    $bFix = New-RamButton -Text '  Проверить входы' -Icon 'key' -Width $navBtnW -Height $navH -Radius 10 -Fixed `
                          -Tooltip 'Проверить, живы ли входы. Если есть мёртвые — пройтись по ним и взять заново из приложения Roblox' `
                          -OnClick {
                              if ([string]$this.Tag.Mode -like 'fix*') { Invoke-RamRepairAll }
                              else { Invoke-RamCheckCookies }
                          }
    $bFix.Tag | Add-Member -NotePropertyName Mode -NotePropertyValue 'check' -Force
    $bFix.Tag.Border = $null
    $bFix.Anchor   = 'Left,Bottom'
    $side.Controls.Add($bFix)
    $script:UI.FixAll = $bFix

    $bSettings = New-RamButton -Text '  Настройки' -Icon 'gear' -Width $navBtnW -Height $navH -Radius 10 -OnClick {
        Show-RamSettingsDialog
    }
    $bSettings.Tag.Border = $null
    $bSettings.Anchor   = 'Left,Bottom'
    $side.Controls.Add($bSettings)

    $bHelp = New-RamButton -Text '  Справка' -Icon 'help' -Width $navBtnW -Height $navH -Radius 10 -OnClick {
        $ans = Show-RamMessage -Title 'Справка' -Kind 'info' -Message (
            "Пройти настройку заново — тот самый мастер первого запуска: железо, тема, аккаунты, наборы.`n`n" +
            "Открыть README — подробное описание всего, что умеет AltHub."
        ) -Buttons @(
            @{ Text = 'Пройти настройку заново'; Value = 'wizard'; Kind = 'primary' },
            @{ Text = 'Открыть README';          Value = 'readme' },
            @{ Text = 'Закрыть';                 Value = 'no'     }
        )
        switch ([string]$ans) {
            'wizard' {
                Invoke-RamFirstRun -Force
                Build-RamCards
            }
            'readme' {
                $readme = Join-Path $script:Root 'README.md'
                if (Test-Path -LiteralPath $readme) { Start-Process notepad.exe $readme }
                else { Show-RamInfo 'README.md не найден рядом со скриптом.' }
            }
        }
    }
    $bHelp.Tag.Border = $null
    $bHelp.Anchor   = 'Left,Bottom'
    $side.Controls.Add($bHelp)

    # ------------------------------------------------- запуск/закрытие/окна ---
    # Раньше эти кнопки жили в правой полосе над списком карточек — там они
    # первыми страдали при сжатии окна (см. предыдущий разбор про
    # «склеенные» кнопки). Перенос в боковое меню решает это раз и навсегда:
    # меню не сжимается вместе с содержимым, у него собственная фиксированная
    # ширина, посчитанная от самой длинной надписи.
    #
    # ПОЛОЖЕНИЕ: РОВНО ПОСЕРЕДИНЕ МЕЖДУ ПЕРВОЙ ГРУППОЙ (разделы + фаст-
    # настройка) И ТРЕТЬЕЙ (проверка входов/настройки/справка) — считает
    # Update-RamSideBarLayout, здесь только создание кнопок. Anchor —
    # 'Left,Top', а не 'Bottom': группа висит в свободном месте между двумя
    # другими, а не прижата к какому-то краю, поэтому WinForms её саму
    # никуда не двигает при ресайзе — новую середину каждый раз считает
    # заново Update-RamSideBarLayout.
    #
    # Группа контекстная: это Запустить/Закрыть/Окна, работают с
    # отмеченными карточками аккаунтов — видна только на разделе
    # «Аккаунты», там им и место. На всех остальных разделах («Игры»,
    # «Профили», «Статистика», «Журнал») тройка не делает ничего
    # осмысленного (нет карточек аккаунтов на экране, некого «отмечать»),
    # поэтому там просто прячется, оставляя под собой пустое место —
    # см. Show-RamSection ($script:UI.NavGroupAcc).
    $bLaunch = New-RamButton -Text '  Запустить' -Icon 'play' -Width $navBtnW -Height $navH -Radius 10 -Kind 'primary' -OnClick {
        $targets = @(Get-RamTargetAccounts)
        if ($targets.Count -eq 0) { $targets = @(Get-RamVisibleAccounts) }
        Add-RamToLaunchQueue -Accounts $targets
    }
    $side.Controls.Add($bLaunch)
    $script:UI.BtnLaunch = $bLaunch

    $bCloseAll = New-RamButton -Text '  Закрыть' -Icon 'stop' -Width $navBtnW -Height $navH -Radius 10 -Kind 'ghost' `
                               -Tooltip 'Закрыть окна отмеченных' -OnClick { Invoke-RamStopSelected }
    $side.Controls.Add($bCloseAll)

    $bTile = New-RamButton -Text '  Окна' -Icon 'windows' -Width $navBtnW -Height $navH -Radius 10 -Kind 'ghost' `
                           -Tooltip 'Левый клик — разложить, правый — выбрать раскладку' -OnClick { Invoke-RamTileWindows }
    $side.Controls.Add($bTile)
    $script:UI.BtnTile = $bTile

    $script:UI.NavGroupAcc = @($bLaunch, $bCloseAll, $bTile)

    # $y на этот момент — низ первой группы (разделы + фаст-настройка).
    # Update-RamSideBarLayout использует его как верхнюю границу свободного
    # места для центрирования — запоминаем в $script:UI, ресайз вызывает
    # эту функцию уже без доступа к локальной переменной $y.
    $script:UI.SideBar = [pscustomobject]@{
        Side = $side; NavH = $navH; NavGap = $navGap; PadLg = $metrics.GapLg; Gap = $metrics.Gap
        TopGroupBottom = $y
        BFix = $bFix; BSettings = $bSettings; BHelp = $bHelp
        BLaunch = $bLaunch; BCloseAll = $bCloseAll; BTile = $bTile
    }
    Update-RamSideBarLayout

    # Полезная ширина и высота содержимого — от них пляшут все пять разделов.
    $contentW = $formW - $contentX - $metrics.GapLg
    $contentH = $formH - 56 - [int](28 * $metrics.Scale)

    # =================================================== верхняя строка ======
    # Счётчик "аккаунтов: N · запущено: M" переехал вниз, в строку
    # статуса, справа от "отмечено: X из Y" (через ";") — см.
    # Update-RamStatusLine в AltHub.ps1. На прежнем месте счётчика слева
    # теперь поле поиска. Эту метку (Subtitle) больше никто не читает —
    # держу скрытой на случай, если куда-то ещё пригодится текст
    # Update-RamHeaderCounts.
    # Ширина — всё, что остаётся слева от поля поиска. Раньше тут стояло
    # «-340» без масштаба, а поиск шириной 300 точек масштабируется — и на
    # 125% и 150% подпись заезжала под поле поиска.
    $subH = (Measure-RamText -Text 'Ay' -Font $t.FontSmall).Height + 4
    $sub = New-RamLabel -Text '' -X ($contentX + 8) -Y (Get-RamScaled 22) `
                        -Width ($formW - $contentX - 8 - (Get-RamScaled 300) - $metrics.GapLg * 2) -Height $subH `
                        -Font $t.FontSmall -Color $t.Muted -Truncatable
    $sub.Anchor  = 'Top,Left,Right'
    $sub.Visible = $false
    $form.Controls.Add($sub)
    $script:UI.Subtitle = $sub

    # Поиск встал на место счётчика — слева, а не у правого края.
    $searchW = Get-RamScaled 300
    $search = New-RamTextBox -Width $searchW -Height (Get-RamScaled 32)
    $search.Location = New-Object System.Drawing.Point($contentX, (Get-RamScaled 16))
    $search.Anchor   = 'Top,Left'
    $form.Controls.Add($search)
    $script:UI.Search = $search

    # «Все» и «С отмеченными» встали справа от поиска, в той же строке —
    # раньше стояли отдельной полосой над списком карточек. Кнопки (38px)
    # выше поля поиска (32px), и обе стояли по одному Y — из-за этого
    # кнопки «висели» ниже центра строки, а не по центру относительно
    # поисковика. Поднимаем кнопки на половину разницы высот, чтобы их
    # середина совпала с серединой поля поиска.
    #
    # НИЖЕ 830px ШИРИНЫ ОКНА — КНОПКИ ПЕРЕЕЗЖАЮТ ПОД ПОИСК.
    # На узком окне поиск (300px) и обе кнопки («Все» + «С отмеченными») в
    # одну строку не помещаются — раньше они просто наезжали друг на друга
    # или вылезали за правый край панели. 830px — порог по ширине ОКНА
    # (Update-RamTopBarLayout ниже пересчитывает раскладку на каждый
    # ресайз), при котором ещё есть место под обе кнопки правее поиска на
    # ширинах между 830 и максимумом; ниже него кнопки встают отдельной
    # строкой под полем поиска, во всю доступную ширину раздела.
    $bw = { param($n) [int][Math]::Round($n * $metrics.Scale) }
    $topBtnH = $metrics.RowHLg
    $topBtnY = (Get-RamScaled 16) - [int][Math]::Round(($topBtnH - $search.Height) / 2)
    $topBtnX = $search.Right + $metrics.Gap

    $bAll = New-RamButton -Text 'Все' -Width (& $bw 70) -Height $topBtnH -Tooltip 'Отметить или снять отметку со всех' -OnClick {
        $any = $false
        foreach ($id in $script:Cards.Keys) { if (-not $script:Cards[$id].Check.Tag.Checked) { $any = $true } }
        Set-RamAllChecked $any
    }
    $bAll.Location = New-Object System.Drawing.Point($topBtnX, $topBtnY)
    $bAll.Anchor   = 'Top,Left'
    $form.Controls.Add($bAll)
    $topBtnX = $bAll.Right + $metrics.GapSm

    # ЧЕТЫРЕ ДЕЙСТВИЯ НАД ОТМЕЧЕННЫМИ — В ОДНОЙ КНОПКЕ С МЕНЮ.
    #
    # Раньше «Игра», «Набор», «Метка» и «Удалить» стояли отдельными кнопками.
    # Шесть кнопок в строку помещаются не всегда, и полоса разъезжалась
    # лесенкой на две-три строки. Попытка сворачивать их «когда не влезает»
    # сломалась трижды подряд: то не сворачивалось, то показывались оба
    # варианта разом. Переменная раскладка — источник этих поломок, поэтому
    # её больше нет: строка всегда одна, на любой ширине и любом масштабе.
    #
    # Смысл группировки тот же, что у кнопки: все четыре действия работают
    # над ОТМЕЧЕННЫМИ аккаунтами, и в меню это наконец написано словами.
    $bSel = New-RamButton -Text 'С отмеченными  ▾' -Width (& $bw 190) -Height $topBtnH `
                          -Tooltip 'Игра, набор, метка, удаление — для отмеченных аккаунтов'
    $selMenu = New-RamContextMenu
    [void](Add-RamMenuItem -Menu $selMenu -Text 'Назначить игру'      -OnClick { Invoke-RamAssignGame })
    [void](Add-RamMenuItem -Menu $selMenu -Text 'Собрать в набор'     -OnClick { Invoke-RamAssignGroup })
    [void](Add-RamMenuItem -Menu $selMenu -Text 'Поставить метку'     -OnClick { Invoke-RamAssignColor })
    [void](Add-RamMenuItem -Menu $selMenu -Separator)
    [void](Add-RamMenuItem -Menu $selMenu -Text 'Убрать из менеджера' -OnClick { Invoke-RamDeleteSelected })
    $bSel.Add_Click({ $selMenu.Show($this, (New-Object System.Drawing.Point(0, $this.Height))) }.GetNewClosure())
    $bSel.Location = New-Object System.Drawing.Point($topBtnX, $topBtnY)
    $bSel.Anchor   = 'Top,Left'
    $form.Controls.Add($bSel)

    # «Популярные из Roblox» — раньше жила в боковом меню (заменяла собой
    # Запустить/Закрыть/Окна на разделе «Игры»), теперь стоит в шапке
    # страницы, правее поиска — тем же приёмом, что «Все»/«С отмеченными»:
    # та же высота ($topBtnH) и тот же Y ($topBtnY), поэтому центр кнопки
    # совпадает с центром поля поиска, как и у соседей. Видна только на
    # «Играх» — Show-RamSection переключает Visible при смене раздела.
    $bGamesPopular = New-RamButton -Text '  Популярные из Roblox' -Icon 'gamepad' -Width (& $bw 210) -Height $topBtnH -Kind 'primary' `
                                   -Tooltip 'Показать игры, в которые сейчас играют больше всего, и добавить их в список' -OnClick {
        Show-RamPopularGamesDialog
        Update-RamGamesPanel
    }
    $bGamesPopular.Location = New-Object System.Drawing.Point(($search.Right + $metrics.Gap), $topBtnY)
    $bGamesPopular.Anchor   = 'Top,Left'
    $bGamesPopular.Visible  = ($script:Section -eq 'games')
    $form.Controls.Add($bGamesPopular)

    # «Готовые профили» — та же схема, что «Популярные из Roblox» выше:
    # раньше была кнопкой «＋ Готовый профиль ▾» в шапке страницы «Профили»
    # (там же соседствовала со «Сохранить текущее как профиль», которая
    # переехала на оверлей «+» кнопки «Профили» в боковом меню). Те же
    # пропорции ($topBtnH, ширина через $bw), тот же Y — центр совпадает с
    # центром поля поиска. Видна только на «Профилях».
    $bProfiles = New-RamButton -Text '  Готовые профили  ▾' -Icon 'profile' -Width (& $bw 210) -Height $topBtnH -Kind 'primary' `
                               -Tooltip 'Добавить готовый профиль с популярной игрой — работает сразу'
    $profMenu = New-RamContextMenu
    foreach ($sp in Get-RamStarterProfiles) {
        [void](Add-RamMenuItem -Menu $profMenu -Text $sp.Name -Tag $sp -OnClick {
            Add-RamStarterProfile -Profile $this.Tag
            Update-RamProfilesPanel
        })
    }
    $bProfiles.Add_Click({ $profMenu.Show($this, (New-Object System.Drawing.Point(0, $this.Height))) }.GetNewClosure())
    $bProfiles.Location = New-Object System.Drawing.Point(($search.Right + $metrics.Gap), $topBtnY)
    $bProfiles.Anchor   = 'Top,Left'
    $bProfiles.Visible  = ($script:Section -eq 'profiles')
    $form.Controls.Add($bProfiles)

    # «ОБНУЛИТЬ» — ТА ЖЕ СХЕМА, ЧТО «ПОПУЛЯРНЫЕ ИЗ ROBLOX»/«ГОТОВЫЕ ПРОФИЛИ»:
    # раньше стояла в правом верхнем углу собственной шапки раздела
    # «Статистика», рядом с лейблом «Статистика» (который теперь снят —
    # заголовок раздела и так виден в боковом меню). Кнопка переехала в
    # общую верхнюю строку, правее поиска — те же $topBtnH/$topBtnY, что и
    # у «Готовых профилей», поэтому высота и вертикальное выравнивание
    # совпадают. Видна только на «Статистике».
    $bStatsReset = New-RamButton -Text 'Обнулить' -Width (& $bw 120) -Height $topBtnH -Kind 'ghost' -OnClick {
        if (-not (Confirm-Ram 'Обнулить всю статистику? Сами аккаунты и игры останутся на месте.')) { return }
        foreach ($a in $script:Accounts) { $a.LaunchCount = 0; $a.CrashCount = 0; $a.PlaySeconds = 0 }
        Save-RamState
        Update-RamStatsPanel
        Write-RamLog 'Статистика обнулена.' 'ok'
    }
    $bStatsReset.Location = New-Object System.Drawing.Point(($search.Right + $metrics.Gap), $topBtnY)
    $bStatsReset.Anchor   = 'Top,Left'
    $bStatsReset.Visible  = ($script:Section -eq 'stats')
    $form.Controls.Add($bStatsReset)

    # «СКОПИРОВАТЬ»/«ОЧИСТИТЬ» — ТА ЖЕ СХЕМА, ЧТО «ВСЕ»/«С ОТМЕЧЕННЫМИ»:
    # раньше стояли в правом верхнем углу собственной шапки раздела
    # «Журнал», рядом с лейблом «Журнал» (который теперь снят — заголовок
    # раздела и так виден в боковом меню). Пара переехала в общую верхнюю
    # строку правее поиска — та же высота/Y ($topBtnH/$topBtnY), поэтому
    # центр совпадает с центром поля поиска, как у соседних кнопок. Видна
    # только на «Журнале».
    $bCopyLog = New-RamButton -Text 'Скопировать' -Width (& $bw 130) -Height $topBtnH -Kind 'ghost' -OnClick {
        try {
            [System.Windows.Forms.Clipboard]::SetText($script:UI.Log.Text)
            Set-RamStatus 'Журнал скопирован в буфер обмена.'
        } catch {
            # Буфер обмена бывает занят другой программой. Раньше ошибку
            # глотал пустой catch, и кнопка выглядела сломанной.
            Show-RamMessage -Kind 'warn' -Message "Скопировать журнал не вышло: буфер обмена сейчас занят другой программой.`n`nПопробуй ещё раз через секунду."
        }
    }
    $bCopyLog.Location = New-Object System.Drawing.Point(($search.Right + $metrics.Gap), $topBtnY)
    $bCopyLog.Anchor   = 'Top,Left'
    $bCopyLog.Visible  = ($script:Section -eq 'log')
    $form.Controls.Add($bCopyLog)

    $bClearLog = New-RamButton -Text 'Очистить' -Width (& $bw 120) -Height $topBtnH -Kind 'ghost' -OnClick {
        $script:UI.Log.Clear()
        [void]$script:LogLines.Clear()
        Set-RamStatus 'Журнал в окне очищен. Файлы журнала в data\logs не тронуты.'
    }
    $bClearLog.Location = New-Object System.Drawing.Point(($bCopyLog.Right + $metrics.GapSm), $topBtnY)
    $bClearLog.Anchor   = 'Top,Left'
    $bClearLog.Visible  = ($script:Section -eq 'log')
    $form.Controls.Add($bClearLog)

    $script:UI.TopBar = [pscustomobject]@{
        Search = $search; BAll = $bAll; BSel = $bSel; BGamesPopular = $bGamesPopular; BProfiles = $bProfiles
        BStatsReset = $bStatsReset; BCopyLog = $bCopyLog; BClearLog = $bClearLog
        SearchY = $search.Top; BtnY = $topBtnY; ContentX = $contentX
    }
    Update-RamTopBarLayout


    $script:SearchIsHint      = $true
    # Раньше здесь стоял текст-подсказка «поиск: имя, ник, игра, заметка» —
    # при какой-то правке переменная перестала присваиваться и осталась
    # пустой строкой, из-за чего подсказка в пустом поле пропала молча
    # (сам механизм подсказки ниже работал исправно, просто показывать
    # было нечего). Возвращаю текст на место.
    $script:SearchPlaceholder = 'поиск: имя, ник, игра, заметка'

    $sTb = $search.Tag
    $sTb.Text      = $script:SearchPlaceholder
    $sTb.ForeColor = $t.Muted
    # Кнопки у нас нарисованные панели, фокус они не принимают. Без этого
    # WinForms при открытии окна сам ставит фокус в поиск, срабатывает
    # GotFocus и подсказка стирается ещё до того, как её кто-то увидел.
    $sTb.TabStop = $false

    $sTb.Add_GotFocus({
        if ($script:SearchIsHint) {
            $script:SearchIsHint = $false
            $this.Text = ''
            $this.ForeColor = $Global:RamTheme.Text
        }
    })
    $sTb.Add_LostFocus({
        if ([string]::IsNullOrEmpty($this.Text)) {
            $script:SearchIsHint = $true
            $this.Text = $script:SearchPlaceholder
            $this.ForeColor = $Global:RamTheme.Muted
        }
    })
    # Поиск с задержкой. Раньше Build-RamCards звалась на КАЖДОЕ нажатие
    # клавиши — полная пересборка всего списка с созданием десятка контролов
    # и своего меню на каждую карточку. Теперь ждём, пока человек перестанет
    # печатать, и пересобираем один раз.
    $searchTimer = New-Object System.Windows.Forms.Timer
    $searchTimer.Interval = 250
    $searchTimer.Add_Tick({
        $this.Stop()
        Invoke-RamSafe -What 'поиск' -Body { Build-RamCards }
    })
    $script:UI.SearchTimer = $searchTimer

    $sTb.Add_TextChanged({
        if ($script:SearchIsHint) { return }
        $script:Filter = $this.Text
        $script:UI.SearchTimer.Stop()
        $script:UI.SearchTimer.Start()
    })

    # Все разделы начинаются от фактического низа поиска, а не от числа,
    # подобранного для 100% DPI.
    $contentTop = $search.Bottom + $metrics.GapSm
    # Нижняя строка: высота кнопки «Проверить входы» или строки текста — что выше.
    $footH = [Math]::Max($metrics.RowHSm, (Get-RamTextRowH $t.FontSmall)) + $metrics.Gap * 2
    $contentH = [Math]::Max(1, $formH - $contentTop - $footH)

    # =================================================== раздел: аккаунты ====
    $pAcc = New-Object System.Windows.Forms.Panel
    $pAcc.Location  = New-Object System.Drawing.Point($contentX, $contentTop)
    $pAcc.Size      = New-Object System.Drawing.Size($contentW, $contentH)
    $pAcc.BackColor = $t.Bg
    $pAcc.Anchor    = 'Top,Left,Right,Bottom'
    $form.Controls.Add($pAcc)
    $script:UI.Panels['accounts'] = $pAcc

    # «Все» и «С отмеченными» переехали в верхнюю строку, к полю поиска
    # (см. выше) — своей полосы над списком карточек здесь больше нет,
    # список начинается сразу от верха панели.

    # Здесь жёлоб убирали, но отрисовщика темы не ставили: рамка и подсветка
    # наведения оставались системными. Обёртка делает и то, и другое.
    $tileMenu = New-RamContextMenu
    foreach ($m in @(
        @{ K = 'main';    T = 'Основной крупно, твины мелко' },
        @{ K = 'grid';    T = 'Сеткой' },
        @{ K = 'cascade'; T = 'Каскадом' },
        @{ K = 'columns'; T = 'Колонками' },
        @{ K = 'rows';    T = 'Строками' })) {
        # $m — элемент списка выше. Когда-то по файлу прошлись заменой
        # «$m.» на «$metrics.», и здесь она сработала не по адресу: все пять
        # пунктов получали пустое имя и Tag = $null, то есть меню выбора
        # раскладки состояло из пяти безымянных строк, а клик по любой из них
        # записывал в настройки пустой режим.
        $mi = New-Object System.Windows.Forms.ToolStripMenuItem($m.T)
        $mi.Tag = $m.K
        $mi.Add_Click({
            $script:Settings.TileMode = $this.Tag
            Save-RamSettings -Settings $script:Settings
            Invoke-RamTileWindows -Mode $this.Tag
        })
        [void]$tileMenu.Items.Add($mi)
    }
    $miSave = New-Object System.Windows.Forms.ToolStripMenuItem('Запомнить места окон')
    $miSave.Add_Click({ Save-RamWindowPositions })
    [void]$tileMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    [void]$tileMenu.Items.Add($miSave)
    $script:UI.TileMenu = $tileMenu

    $bTile.Add_MouseUp({
        param($sender, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
            $script:UI.TileMenu.Show($sender, $e.Location)
        }
    })

    # полоска наборов — раньше стояла от фактического низа полосы кнопок,
    # той полосы больше нет, поэтому обе секции просто начинаются от верха
    # панели аккаунтов.
    $groupBar = New-Object System.Windows.Forms.FlowLayoutPanel
    $groupBar.Location      = New-Object System.Drawing.Point(0, 0)
    $groupBar.Size          = New-Object System.Drawing.Size($contentW, ([int](34 * $metrics.Scale) + 6))
    $groupBar.BackColor     = $t.Bg
    $groupBar.FlowDirection = 'LeftToRight'
    $groupBar.WrapContents  = $false
    $groupBar.Anchor        = 'Top,Left,Right'
    $groupBar.Visible       = $false
    $pAcc.Controls.Add($groupBar)
    $script:UI.GroupBar = $groupBar

    $cardsTop = $groupBar.Top
    $cards = New-RamScrollPanel -Width $contentW -Height ($contentH - $cardsTop)
    $cards.Location = New-Object System.Drawing.Point(0, $cardsTop)
    $cards.Anchor   = 'Top,Left,Right,Bottom'
    $pAcc.Controls.Add($cards)
    $script:UI.Cards = $cards

    # ШИРОКОЕ МЕНЮ: карточки встают в колонки. Сам по себе список — поток
    # сверху вниз без переноса, то есть ВСЕГДА одна колонка: карточки просто
    # становились уже, а справа оставалась пустота.
    if ([int]$menuStyle.MaxColumns -gt 1) {
        $cards.FlowDirection = 'LeftToRight'
        $cards.WrapContents  = $true
    }
    $script:UI.AccGroupBar = $groupBar


    # ПОЧЕМУ ЭТО ЗДЕСЬ, А НЕ ОДИН РАЗ ПРИ СБОРКЕ.
    # $contentW считается от предполагаемой ширины окна ($formW), а фактическая
    # ширина панели после раскладки Windows оказывается другой — на 150% это
    # 1241 вместо 1557. Правая полоса прижата якорем и уезжает на своё место,
    # левая с якорем Top,Left остаётся прежней ширины — и накрывается правой.
    # Update-RamAccountsBar раньше подгонял под это ширину полосы «Все/С
    # отмеченными» — той полосы в разделе аккаунтов больше нет (кнопки
    # переехали в верхнюю строку, к поиску), поэтому и вызов убрал.

    # =================================================== раздел: игры =======
    $pGames = New-Object System.Windows.Forms.Panel
    $pGames.Location  = New-Object System.Drawing.Point($contentX, $contentTop)
    $pGames.Size      = New-Object System.Drawing.Size($contentW, $contentH)
    $pGames.BackColor = $t.Bg
    $pGames.Anchor    = 'Top,Left,Right,Bottom'
    $pGames.Visible   = $false
    $form.Controls.Add($pGames)
    $script:UI.Panels['games'] = $pGames

    # Заголовок и подсказка убраны из шапки страницы совсем: раздел и так
    # подписан кнопкой в боковом меню, «＋ Своя игра» переехала на оверлей
    # той же кнопки (см. Get-RamSections), а «Популярные из Roblox» — в
    # верхнюю строку рядом с поиском (см. $bGamesPopular в сборке верхней
    # строки и Update-RamTopBarLayout). Здесь, в самой панели «Игры»,
    # шапке рисовать больше нечего — список игр начинается сразу от Y=0.
    $gamesHost = New-RamScrollPanel -Width $contentW -Height $contentH
    $gamesHost.Location = New-Object System.Drawing.Point(0, 0)
    $gamesHost.Anchor   = 'Top,Left,Right,Bottom'
    $pGames.Controls.Add($gamesHost)
    $script:UI.GamesHost = $gamesHost

    # =================================================== раздел: профили ====
    $pProf = New-Object System.Windows.Forms.Panel
    $pProf.Location  = New-Object System.Drawing.Point($contentX, $contentTop)
    $pProf.Size      = New-Object System.Drawing.Size($contentW, $contentH)
    $pProf.BackColor = $t.Bg
    $pProf.Anchor    = 'Top,Left,Right,Bottom'
    $pProf.Visible   = $false
    $form.Controls.Add($pProf)
    $script:UI.Panels['profiles'] = $pProf

    # Шапка страницы теперь пустая: «Готовые профили» переехала в верхнюю
    # строку рядом с поиском (тем же приёмом, что «Популярные из Roblox» на
    # «Играх» — см. $bProfiles в сборке верхней строки), а «Сохранить
    # текущее как профиль» стала оверлеем «+» на самой кнопке «Профили» в
    # боковом меню под именем «Создать профиль» (см. Get-RamSections выше).
    # Список профилей начинается сразу от Y=0.
    $profHost = New-RamScrollPanel -Width $contentW -Height $contentH
    $profHost.Location = New-Object System.Drawing.Point(0, 0)
    $profHost.Anchor   = 'Top,Left,Right,Bottom'
    $pProf.Controls.Add($profHost)
    $script:UI.ProfilesHost = $profHost

    # =================================================== раздел: статистика ==
    $pStats = New-Object System.Windows.Forms.Panel
    $pStats.Location  = New-Object System.Drawing.Point($contentX, $contentTop)
    $pStats.Size      = New-Object System.Drawing.Size($contentW, $contentH)
    $pStats.BackColor = $t.Bg
    $pStats.Anchor    = 'Top,Left,Right,Bottom'
    $pStats.Visible   = $false
    $form.Controls.Add($pStats)
    $script:UI.Panels['stats'] = $pStats

    # Шапка страницы теперь пустая: лейбл «Статистика» снят (раздел и так
    # виден по подсвеченной кнопке бокового меню), а «Обнулить» переехала в
    # верхнюю строку рядом с поиском (тем же приёмом, что «Готовые
    # профили» на «Профилях» — см. $bStatsReset в сборке верхней строки).
    # Список начинается сразу от Y=0, как на «Профилях».
    $statsHost = New-RamScrollPanel -Width $contentW -Height $contentH
    $statsHost.Location = New-Object System.Drawing.Point(0, 0)
    $statsHost.Anchor   = 'Top,Left,Right,Bottom'
    $pStats.Controls.Add($statsHost)
    $script:UI.StatsHost = $statsHost

    # =================================================== раздел: журнал ======
    $pLog = New-Object System.Windows.Forms.Panel
    $pLog.Location  = New-Object System.Drawing.Point($contentX, $contentTop)
    $pLog.Size      = New-Object System.Drawing.Size($contentW, $contentH)
    $pLog.BackColor  = $t.Bg
    $pLog.Anchor    = 'Top,Left,Right,Bottom'
    $pLog.Visible   = $false
    $form.Controls.Add($pLog)
    $script:UI.Panels['log'] = $pLog

    # Шапка страницы теперь пустая: лейбл «Журнал» снят (раздел и так виден
    # по подсвеченной кнопке бокового меню), а «Скопировать»/«Очистить»
    # переехали в общую верхнюю строку рядом с поиском (тем же приёмом, что
    # «Все»/«С отмеченными» на «Аккаунтах» — та же пара из двух кнопок, тот
    # же перенос под поиск на узком окне, см. $bCopyLog/$bClearLog в сборке
    # верхней строки). Панель раздела ($pLog) сама сдвигается вниз вслед за
    # переносом кнопок — это уже делает Update-RamTopBarLayout для всех
    # разделов разом (см. $panelsTop там), поэтому хост журнала просто
    # заполняет её целиком от Y=0, как $profHost/$statsHost.
    $logHost = New-Object System.Windows.Forms.Panel
    $logHost.Location  = New-Object System.Drawing.Point(0, 0)
    $logHost.Size      = New-Object System.Drawing.Size($contentW, $contentH)
    $logHost.BackColor = $t.LogBack
    $logHost.Padding   = New-Object System.Windows.Forms.Padding(12, 10, 12, 10)
    $logHost.Anchor    = 'Top,Left,Right,Bottom'
    $pLog.Controls.Add($logHost)

    $log = New-Object System.Windows.Forms.TextBox
    $log.Multiline   = $true
    $log.ReadOnly    = $true
    $log.ScrollBars  = 'Vertical'
    $log.BorderStyle = 'None'
    $log.BackColor   = $t.LogBack
    $log.ForeColor   = $t.Muted
    $log.Font        = $t.FontMono
    $log.Dock        = 'Fill'
    Set-RamScrollTheme -Control $log
    $logHost.Controls.Add($log)
    $script:UI.Log = $log
    if ($script:LogLines.Count -gt 0) {
        $log.Text = (@($script:LogLines) -join [Environment]::NewLine) + [Environment]::NewLine
        $log.SelectionStart = $log.TextLength
        $log.ScrollToCaret()
    }

    # =================================================== строка состояния ====
    # Кнопка «Проверить входы» переехала в боковое меню (см. выше) — здесь
    # остаётся только сама строка статуса, и теперь она может занимать всю
    # полезную ширину раздела, а не уступать место кнопке справа.
    $statusH = Get-RamTextRowH $t.FontSmall
    $lineY = $formH - $footH
    $st = New-RamLabel -Text '' -X $contentX -Y ($lineY + [int](($footH - $statusH) / 2)) -Width $contentW -Height $statusH -Font $t.FontSmall -Color $t.Muted -Truncatable
    $st.Anchor = 'Left,Right,Bottom'
    # По строке состояния можно кликнуть, когда в ней висит предложение
    # добавить аккаунт, замеченный в приложении Roblox. В остальное время
    # клик ничего не делает — см. Invoke-RamAppOffer.
    $st.Add_Click({ Invoke-RamAppOffer })
    $form.Controls.Add($st)
    $script:UI.Status = $st

    # =================================================== таймеры ============
    $lt = New-Object System.Windows.Forms.Timer
    $lt.Interval = 500
    $lt.Add_Tick({ Invoke-RamSafe -What 'очередь запуска' -Body { Invoke-RamNextLaunch } })
    $script:UI.LaunchTimer = $lt
    $script:UI.FreshFocusTimer = New-RamFreshWindowTimer

    $ut = New-Object System.Windows.Forms.Timer
    $ut.Interval = 2000
    $ut.Add_Tick({ Invoke-RamSafe -What 'обновление состояния' -Body { Update-RamInstances } })
    $ut.Start()
    $script:UI.UpdateTimer = $ut

    $sch = New-Object System.Windows.Forms.Timer
    $sch.Interval = 30000
    $sch.Add_Tick({ Invoke-RamSafe -What 'расписание и присмотр' -Body { Invoke-RamScheduleCheck; Invoke-RamWatchCheck } })
    $sch.Start()
    $script:UI.ScheduleTimer = $sch

    $form.Add_ResizeEnd({
        Invoke-RamSafe -What 'перестройка после изменения размера' -Body { Update-RamAfterResize }
        Invoke-RamSafe -What 'запоминание размера окна' -Body { Save-RamMainWindowGeometry -Form $this }
    })

    # =================================================== горячие клавиши ====
    $form.KeyPreview = $true
    $form.Add_KeyDown({
        param($sender, $e)
        $inText = ($sender.ActiveControl -is [System.Windows.Forms.TextBox])

        if ($e.Control -and $e.KeyCode -eq 'F') {
            Show-RamSection -Key 'accounts'
            $script:UI.Search.Tag.Focus()
            if (-not $script:SearchIsHint) { $script:UI.Search.Tag.SelectAll() }
            $e.Handled = $true; return
        }
        if ($e.KeyCode -eq 'Escape') {
            if ($script:Filter) {
                $script:UI.Search.Tag.Text = ''
                $script:Filter = ''
                $sender.ActiveControl = $null
                Build-RamCards
            }
            $e.Handled = $true; return
        }
        if ($inText) { return }

        switch ($e.KeyCode) {
            'F5'     { Build-RamCards; Update-RamStatsPanel; Write-RamLog 'Обновлено.' 'info'; $e.Handled = $true }
            'Delete' { Invoke-RamDeleteSelected; $e.Handled = $true }
            'A'      { if ($e.Control) { Set-RamAllChecked $true; $e.Handled = $true } }
            'T'      { if ($e.Control) { Invoke-RamTileWindows; $e.Handled = $true } }
            'Z'      { if ($e.Control) { Invoke-RamUndo;         $e.Handled = $true } }
            'Return' {
                $t2 = @(Get-RamTargetAccounts)
                if ($t2.Count -eq 0) { $t2 = @(Get-RamVisibleAccounts) }
                Add-RamToLaunchQueue -Accounts $t2
                $e.Handled = $true
            }
            'D1' { Show-RamSection -Key 'accounts'; $e.Handled = $true }
            'D2' { Show-RamSection -Key 'games';    $e.Handled = $true }
            # Цифры идут в порядке пунктов бокового меню. Раньше 3 открывала
            # «Статистику», 4 — «Журнал», а «Профили» с клавиатуры были недоступны.
            'D3' { Show-RamSection -Key 'profiles'; $e.Handled = $true }
            'D4' { Show-RamSection -Key 'stats';    $e.Handled = $true }
            'D5' { Show-RamSection -Key 'log';      $e.Handled = $true }
        }
    })

    $form.Add_FormClosing({
        param($sender, $e)

        $internalClose = ($script:RebuildUi -or $script:RestartRequested)

        # Крестик убирает в часы — так делают Discord и Telegram.
        #
        # Но прятать окно можно ТОЛЬКО когда человек своими глазами подтвердил,
        # что значок в часах он видит. Узнать это у Windows нельзя:
        # Shell_NotifyIcon отвечает «успех» и тогда, когда значок уехал под
        # стрелку и человеку не виден. Поэтому спрашиваем прямо, один раз.
        # UserClosing — это именно крестик и Alt+F4, а не выключение Windows
        # и не Restart-AltHub.
        if (-not $internalClose -and $script:Settings.OnClose -eq 'tray' -and $script:UI.TrayOk -and
            $e.CloseReason -eq [System.Windows.Forms.CloseReason]::UserClosing) {

            if (Confirm-RamTrayVisible) {
                $e.Cancel = $true
                Invoke-RamSafe -What 'запоминание размера окна' -Body { Save-RamMainWindowGeometry -Form $sender }
                $sender.Hide()
                Show-RamTrayHint
                return
            }
            # Не подтвердил — крестик закрывает, как раньше. Настройка уже
            # переключена внутри Confirm-RamTrayVisible.
        }

        if (-not $internalClose -and $script:Settings.ConfirmOnExit -and $script:Instances.Count -gt 0) {
            if (-not (Confirm-Ram "Запущено клиентов: $($script:Instances.Count).`n`nЗакрыть менеджер? Сами окна Roblox продолжат работать, но новые аккаунты запустить будет нельзя, пока менеджер закрыт.")) {
                $e.Cancel = $true
                return
            }
        }
        Invoke-RamSafe -What 'запоминание размера окна' -Body { Save-RamMainWindowGeometry -Form $sender }
        Dispose-RamFormRuntime
        if ($script:RebuildUi) { return }

        Invoke-RamSafe -What 'сохранение при закрытии' -Body { Save-RamState }
        Invoke-RamSafe -What 'снятие замков'          -Body { Disable-RamMultiInstance }
        Invoke-RamSafe -What 'снятие горячих клавиш'  -Body { Unregister-RamHotkeys }
        Invoke-RamSafe -What 'снятие замка копии'     -Body { Clear-RamSingleInstance }
        if ($null -ne $script:UI.Tray) {
            $script:UI.Tray.Visible = $false
            $script:UI.Tray.Dispose()
        }
    })

    # =================================================== значок в часах =====
    # Значок нужен, когда в часы уводит крестик. Минус в часы не уводит
    # никогда — см. Add_Resize.
    $script:UI.TrayOk = $false
    if ($script:Settings.OnClose -eq 'tray') {
        $ni = New-Object System.Windows.Forms.NotifyIcon
        # ЗДЕСЬ БЫЛ catch { } — и это дорого стоило. Если значок не создавался,
        # NotifyIcon оставался с Icon = $null, Windows такой значок не рисует,
        # а окно всё равно пряталось. Человек сворачивал программу, и она
        # исчезала совсем: ни в панели задач, ни в часах. Теперь при сбое
        # мы честно говорим об этом и НЕ прячем окно (см. TrayOk).
        try {
            # Тот же значок, что у окна и у ярлыка — рисуется один раз за запуск.
            $icon = Get-RamAppIcon
            if ($null -eq $icon) { throw 'значок не нарисовался' }

            $ni.Icon    = $icon
            $ni.Text    = $script:AppName
            $ni.Visible = $true
            $script:UI.TrayOk = ($null -ne $ni.Icon -and $ni.Visible)
            if (-not $script:UI.TrayOk) { throw 'значок задан, но система его не приняла' }
        } catch {
            # МОЛЧА ЭТО ГЛОТАТЬ НЕЛЬЗЯ. Если значка нет, крестик обязан просто
            # закрывать программу — иначе окно спрячется в никуда.
            $script:UI.TrayOk = $false
            Write-RamLog "Значок в часах не создался ($($_.Exception.Message)) — крестик будет просто закрывать программу." 'warn'
        }
        $script:UI.Tray = $ni

        # Одиночный клик тоже возвращает окно: двойной по значку в часах
        # находят не все, а спрятанную программу ищут долго.
        $ni.Add_Click({
            param($sender, $e)
            if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
            Show-RamMainWindow
        })
        $ni.Add_DoubleClick({ Show-RamMainWindow })

        # Через New-RamContextMenu, а не сырым ContextMenuStrip.
        # У обычного меню слева остаётся «жёлоб под значки», который тема не
        # красит: на тёмном оформлении это была белая полоса во всю высоту.
        # Обёртка убирает жёлоб и ставит отрисовщик в цветах темы — ровно то,
        # что уже работает в меню по правому клику на карточке.
        $trayMenu = New-RamContextMenu
        $ni.ContextMenuStrip = $trayMenu
        $script:UI.TrayMenu = $trayMenu

        $ni.Add_MouseUp({
            param($sender, $e)
            if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) { Update-RamTrayMenu }
        })
    }

    # Пересборка карточек ВО ВРЕМЯ перетаскивания края окна, а не только по
    # его отпусканию (ResizeEnd). Раньше при сужении/расширении мышью
    # карточка (и кнопки ▶/⚙/■ на ней) оставалась прежней ширины до самого
    # отпускания — выглядело так, будто кнопки «прилипли» и не следуют за
    # краем. Полная пересборка на КАЖДЫЙ пиксель перетаскивания была бы
    # слишком дорогой (это создание контролов заново для каждой карточки),
    # поэтому — тот же приём, что и в дебounce-поиске чуть ниже: таймер
    # перезапускается на каждое событие Resize и стреляет, как только
    # движение на мгновение замирает.
    $resizeLiveTimer = New-Object System.Windows.Forms.Timer
    $resizeLiveTimer.Interval = 75
    $resizeLiveTimer.Add_Tick({
        $this.Stop()
        # Пересобираем, только если ширина карточки действительно поменялась:
        # раньше список пересоздавался на каждый тик, даже при движении окна.
        Invoke-RamSafe -What 'пересборка карточек при перетаскивании края' -Body { Update-RamAfterResize }
    })
    $script:UI.ResizeLiveTimer = $resizeLiveTimer

    $form.Add_Resize({
        # МИНУС ВСЕГДА СВОРАЧИВАЕТ В ПАНЕЛЬ ЗАДАЧ, И НИКОГДА НЕ ПРЯЧЕТ.
        #
        # Раньше при настройке «в часы» здесь звался Hide(): окно уходило и из
        # панели задач тоже. Если значок в часах при этом был не виден (в
        # Windows 11 новые значки уезжают под стрелку), программа исчезала
        # целиком, и вернуть её было нечем. Выбора тут больше нет — в часы
        # уводит только крестик, и только с проверкой, что значок видно.
        if ($this.WindowState -eq 'Minimized') { return }

        # Раскладка верхней строки (поиск + «Все»/«С отмеченными») зависит
        # только от ширины окна, а не от состава карточек — пересчитываем
        # её сразу, не дожидаясь таймера ниже (тот ждёт 30мс и вдобавок
        # пересобирает карточки целиком, а тут двигать нужно только две
        # кнопки).
        Invoke-RamSafe -What 'раскладка верхней строки' -Body { Update-RamTopBarLayout }
        Invoke-RamSafe -What 'раскладка бокового меню' -Body { Update-RamSideBarLayout }

        if ($null -ne $script:UI.ResizeLiveTimer) {
            $script:UI.ResizeLiveTimer.Stop()
            $script:UI.ResizeLiveTimer.Start()
        }

        # ПОЧЕМУ ЗДЕСЬ, А НЕ ТОЛЬКО В ResizeEnd.
        # ResizeEnd бывает лишь когда окно тянут за край мышью. Разворот на
        # весь экран и возврат обратно его НЕ поднимают — поэтому карточки
        # оставались прежней ширины, и в полноэкранном режиме справа зияла
        # пустота. Ловим смену состояния окна и пересобираем списки.
        if ($script:LastWindowState -ne $this.WindowState) {
            $script:LastWindowState = $this.WindowState
            if ($this.WindowState -ne 'Minimized') {
                Invoke-RamSafe -What 'перестройка после разворота' -Body { Update-RamAfterResize -Force }
                Invoke-RamSafe -What 'запоминание размера окна' -Body { Save-RamMainWindowGeometry -Form $this }
            }
        }
    })

    # На всякий случай снимаем фокус и после показа окна.
    $form.Add_Shown({
        $this.ActiveControl = $null
        Show-RamSection -Key $script:Section

        # ПОВТОРНАЯ РАСКЛАДКА ВЕРХНЕЙ СТРОКИ — УЖЕ СО ВСЕМИ ПАНЕЛЯМИ.
        #
        # Update-RamTopBarLayout вызывается один раз сразу после создания
        # $bAll/$bSel — но панели разделов ($pAcc и другие, $script:UI.Panels)
        # создаются ПОЗЖЕ в этой же функции построения окна. При первом
        # вызове $script:UI.Panels ещё пуст, и сдвиг вниз (для случая, когда
        # «Все»/«С отмеченными» переносятся под поиск на узком окне) просто
        # не применяется — панели остаются на исходном Y, рассчитанном под
        # однострочную раскладку.
        #
        # Обычно это незаметно: следующий Resize (пользователь чуть подвинул
        # окно) пересчитывает всё как надо. Но если окно стартует уже узким
        # (сохранённый размер из прошлого запуска), первый кадр показывается
        # ДО того как случится любой Resize — и «Все»/«Основной»/«Твины»
        # оказываются перекрыты нижней кнопочной строкой сразу при запуске,
        # без явного действия пользователя. Add_Shown срабатывает уже после
        # того, как все панели созданы — здесь можно пересчитать раскладку
        # ещё раз и получить верный результат сразу, без ожидания ресайза.
        Invoke-RamSafe -What 'раскладка верхней строки при показе окна' -Body { Update-RamTopBarLayout }
        # То же самое для бокового меню: если окно стартует уже развёрнутым
        # (Maximized запомнен с прошлого раза), $side.Height в момент сборки
        # ещё не настоящий (см. разбор в Update-RamSideBarLayout) — Shown
        # срабатывает уже после того, как WinForms применил реальные границы.
        Invoke-RamSafe -What 'раскладка бокового меню при показе окна' -Body { Update-RamSideBarLayout }
        Invoke-RamSafe -What 'минимальный размер окна' -Body { Update-RamMinimumWindowSize }

        # ПОДСТРАХОВКА ОТ НЕВИДИМОГО ОКНА.
        # Если процессу досталось SW_HIDE в STARTUPINFO (так бывает, когда
        # программу запускают скриптом или ярлыком со «спрятать окно»), Windows
        # применяет это к ПЕРВОМУ окну процесса. Программа при этом работает,
        # но её нигде не видно — со стороны выглядит как «не запускается».
        #
        # Проверять надо ИМЕННО через Win32: свойство .Visible у формы при этом
        # остаётся true — WinForms уверен, что окно показал, а спрятала его
        # система уже после.
        try {
            $h = $this.Handle
            if ($h -ne [IntPtr]::Zero -and -not [Ram.Native]::IsWindowVisible($h)) {
                [void][Ram.Native]::ShowWindow($h, 1)   # SW_SHOWNORMAL
                [void][Ram.Native]::SetForegroundWindow($h)
                Write-RamLog 'Окно было скрыто способом запуска — показал его принудительно.' 'warn'
            }
        } catch { }

        if ($this.WindowState -eq 'Minimized') { $this.WindowState = 'Normal' }
    })

    # Размер и место, с которыми окно закрыли в прошлый раз. В самом конце
    # сборки: у панелей Anchor на четыре стороны, они растянутся следом.
    Restore-RamMainWindowBounds -Form $form
    $script:LastWindowState = $form.WindowState
    $script:UI.MenuLayout = 'water'
    $script:UI.Form = $form
    return $form
}

# ================================================================ виды меню ===
#
# Шесть функций раскладки существуют в двух вариантах:
#   ...Classic — привычный вид AltHub 1.3: кнопки над списком, карточка в две
#                колонки, шапки у разделов;
#   ...Water   — раскладка H₂O: действия в боковом меню, единая верхняя строка,
#                значки-рисунки, карточка в одну колонку. На ней же стоит и
#                «Новое широкое» — с карточками в несколько колонок.
#
# Данные, элементы темы и все остальные функции окна — общие. Разошлось ровно
# то, что по-разному РАСКЛАДЫВАЕТ: копировать весь файл трижды значило бы
# чинить каждую ошибку в трёх местах.
#
# Остальной код зовёт функции без суффикса. Какой вариант сработает, решает
# окно, построенное СЕЙЧАС ($script:UI.MenuLayout), а не настройка: между
# сменой настройки и пересборкой окна может успеть тикнуть таймер, и карточки
# вида H₂O полезли бы в классическое окно.

function Get-RamActiveMenuLayout {
    if ($script:UI.ContainsKey('MenuLayout') -and $script:UI.MenuLayout) { return [string]$script:UI.MenuLayout }
    return [string](Get-RamMenuStyle).Layout
}

function New-RamMainForm {
    <# Окно строится по НАСТРОЙКЕ — это и есть момент, когда вид меню меняется. #>
    $style = Get-RamMenuStyle
    $script:UI.MenuStyleKey = [string]$style.Key
    switch ([string]$style.Layout) {
        'classic' { return (New-RamMainFormClassic) }
        'modern'  { return (New-RamMainFormModern) }
        default   { return (New-RamMainFormWater) }
    }
}

function Invoke-RamLayoutVariant {
    <# Зовёт вариант функции под окно, построенное СЕЙЧАС: ...Classic, ...Water или ...Modern. #>
    param([Parameter(Mandatory)][string]$Name)
    $suffix = switch (Get-RamActiveMenuLayout) { 'classic' { 'Classic' } 'modern' { 'Modern' } default { 'Water' } }
    & ($Name + $suffix)
}

function Build-RamCards          { Invoke-RamLayoutVariant -Name 'Build-RamCards' }
function Update-RamCardStates    { Invoke-RamLayoutVariant -Name 'Update-RamCardStates' }
function Update-RamGamesPanel    { Invoke-RamLayoutVariant -Name 'Update-RamGamesPanel' }
function Update-RamProfilesPanel { Invoke-RamLayoutVariant -Name 'Update-RamProfilesPanel' }
function Update-RamStatsPanel    { Invoke-RamLayoutVariant -Name 'Update-RamStatsPanel' }

function Get-RamCardsAvailableWidth {
    <#
      Ширина, которую реально могут занять карточки.

      Полосу прокрутки резервируем ВСЕГДА, а не только когда она видна: иначе
      с появлением двадцатого аккаунта полоса съедала 17 точек, карточки
      становились уже, список пересобирался — и правый край дёргался.
    #>
    if (-not $script:UI.ContainsKey('Cards') -or $null -eq $script:UI.Cards) { return 1000 }
    $scroll = [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth
    # От ПОЛНОЙ ширины списка: ClientSize при видимой полосе уже без неё, и
    # полоса вычиталась дважды — плитки кончались левее кнопок над ними.
    return [Math]::Max(1, $script:UI.Cards.Width - $scroll - $Global:RamTheme.M.Gap)
}

function Get-RamTopBarWrapWidth {
    <#
      Ширина окна (ClientSize.Width), ниже которой перечисленные кнопки уже не
      помещаются в одну строку правее поля поиска.

      Кнопки считаем все переданные, а не только видимые: порог — свойство
      раздела, а не текущего кадра.
    #>
    param([Parameter(Mandatory)]$Search, [object[]]$Buttons)
    $m   = $Global:RamTheme.M
    $vis = @($Buttons | Where-Object { $null -ne $_ -and -not $_.IsDisposed })
    if ($vis.Count -eq 0) { return 0 }
    $need = $m.Gap
    for ($i = 0; $i -lt $vis.Count; $i++) {
        $need += $vis[$i].Width
        if ($i -gt 0) { $need += $m.GapSm }
    }
    return $Search.Right + $need + $m.GapLg
}

function Update-RamMinimumWindowSize {
    <#
      Минимальная ширина окна вида H₂O — по фактической верхней строке.

      Кнопка «Обнулить» на «Статистике» своего порога переноса не имеет и
      всегда стоит в одну строку с поиском. Уже этого окно сжимать нельзя —
      кнопка уехала бы за правый край.
    #>
    if (-not $script:UI.ContainsKey('TopBar') -or -not $script:UI.ContainsKey('Form')) { return }
    $form = $script:UI.Form
    $tb   = $script:UI.TopBar
    if ($null -eq $form -or $form.IsDisposed -or $null -eq $tb -or $null -eq $tb.Search) { return }
    $m = $Global:RamTheme.M
    $needClient = [Math]::Max((Get-RamTopBarWrapWidth -Search $tb.Search -Buttons @($tb.BStatsReset)),
                              ($tb.Search.Right + $m.GapLg))
    $frameW = $form.Width - $form.ClientSize.Width
    $screenW = [System.Windows.Forms.Screen]::FromControl($form).WorkingArea.Width
    $minW = [Math]::Min($needClient + $frameW, $screenW)
    if ($form.MinimumSize.Width -ne $minW) {
        $form.MinimumSize = New-Object System.Drawing.Size($minW, $form.MinimumSize.Height)
    }
}

function Restore-RamMainWindowBounds {
    <#
      Возвращает окну размер и место, с которыми его закрыли в прошлый раз.

      Место берём, только если окно действительно окажется на одном из
      нынешних экранов: монитор могли отключить или сменить разрешение, и тогда
      лучше центр экрана, чем окно за его пределами. Меньше минимума и больше
      рабочей области окно не станет.

      Переменная экрана названа $target, а не $home: $HOME в PowerShell —
      встроенная и неизменяемая, и присваивание в неё роняло запуск у
      каждого, кто хоть раз менял размер окна.
    #>
    param([Parameter(Mandatory)]$Form)
    $s = $script:Settings
    if ($null -eq $s) { return }
    $styleKey = if ($s.MenuStyle) { [string]$s.MenuStyle } else { 'classic' }
    $record = $null
    if ($s.PSObject.Properties.Name -contains 'MenuWindowGeometry') {
        $record = @($s.MenuWindowGeometry | Where-Object { $_ -and [string]$_.Key -eq $styleKey } | Select-Object -First 1)
        if ($record.Count -gt 0) { $record = $record[0] } else { $record = $null }
    }
    # Старые общие поля используем только до появления первой записи нового
    # формата. Иначе размер Pulse растягивал Dashboard на пол-экрана.
    $hasAnyStyleRecord = ($s.PSObject.Properties.Name -contains 'MenuWindowGeometry' -and @($s.MenuWindowGeometry).Count -gt 0)
    if ($null -ne $record) {
        $w=[int]$record.W; $h=[int]$record.H; $x=[int]$record.X; $y=[int]$record.Y; $maximized=[bool]$record.Maximized
    } elseif (-not $hasAnyStyleRecord) {
        $w=[int]$s.MainWindowW; $h=[int]$s.MainWindowH; $x=[int]$s.MainWindowX; $y=[int]$s.MainWindowY; $maximized=[bool]$s.MainWindowMaximized
    } else { return }
    if ($w -le 0 -or $h -le 0) { return }

    $frameW = $Form.Width  - $Form.ClientSize.Width
    $frameH = $Form.Height - $Form.ClientSize.Height
    $w = [Math]::Max($w, $Form.MinimumSize.Width  - $frameW)
    $h = [Math]::Max($h, $Form.MinimumSize.Height - $frameH)

    $rect = New-Object System.Drawing.Rectangle($x, $y, ($w + $frameW), ($h + $frameH))
    $target = $null
    foreach ($scr in [System.Windows.Forms.Screen]::AllScreens) {
        $cross = [System.Drawing.Rectangle]::Intersect($scr.WorkingArea, $rect)
        if ($cross.Width -ge 200 -and $cross.Height -ge 120) { $target = $scr; break }
    }
    $wa = if ($null -ne $target) { $target.WorkingArea } else { [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea }
    $w = [Math]::Min($w, $wa.Width  - $frameW)
    $h = [Math]::Min($h, $wa.Height - $frameH)
    $Form.ClientSize = New-Object System.Drawing.Size($w, $h)
    if ($null -ne $target) {
        $Form.StartPosition = 'Manual'
        $Form.Location = New-Object System.Drawing.Point($x, $y)
    } else {
        $Form.StartPosition = 'CenterScreen'
    }
    if ($maximized) { $Form.WindowState = 'Maximized' }
}

function Update-RamAfterResize {
    <#
      Пересборка списков после изменения размера окна.

      Карточки пересоздаются, только если их ширина действительно изменилась:
      раньше полная пересборка шла на каждый пиксель протаскивания края, с
      чтением аватарок с диска внутри цикла, — отсюда мигание и подтормаживание.
      -Force — после разворота на весь экран и обратно.
    #>
    param([switch]$Force)
    $w = Get-RamCardWidth
    if ($Force -or $script:LastCardW -ne $w) {
        $script:LastCardW = $w
        Build-RamCards
    }
    $pw = 0
    if ($script:UI.ContainsKey('Panels') -and $null -ne $script:UI.Panels -and $script:UI.Panels.ContainsKey('stats')) {
        $pw = $script:UI.Panels['stats'].ClientSize.Width
    }
    if ($Force -or $script:LastPanelW -ne $pw) {
        $script:LastPanelW = $pw
        Update-RamStatsPanel
        Update-RamGamesPanel
        Update-RamProfilesPanel
    }
}




function Update-RamGamesPanelClassic {
    <# Раздел «Игры»: сохранённые игры, назначить отмеченным, удалить. #>
    if (-not $script:UI.ContainsKey('GamesHost')) { return }
    $t = $Global:RamTheme
    $h = $script:UI.GamesHost
    if ($null -eq $h -or $h.IsDisposed) { return }
    $W = Get-RamListWidth -Panel $h

    $h.SuspendLayout()
    try {
        Clear-RamPanelControls -Panel $h
        $games = @($script:Settings.Games | Where-Object { $null -ne $_ })
        if ($games.Count -eq 0) {
            $h.Controls.Add((New-RamNoticeCard -Width $W -Title 'Список пуст' `
                -Text 'Нажми «Добавить игру» и вставь ссылку — или возьми готовую из популярных. Игры также попадают сюда сами, когда назначаешь их аккаунтам.'))
            return
        }
        foreach ($g in $games) {
            $bSet = New-RamButton -Text 'Назначить отмеченным' -Width 1 -Height $t.M.RowHSm -Kind 'primary' -OnClick {
                $targets = @(Get-RamTargetAccounts)
                if ($targets.Count -eq 0) { Show-RamInfo 'Сначала отметь аккаунты в разделе «Аккаунты».'; return }
                $g2 = $this.Tag.Game
                foreach ($a in $targets) {
                    $a.PlaceId  = [string]$g2.PlaceId
                    $a.GameName = ([string]$g2.Title) -replace ' \(приватный сервер\)$', ''
                    $a.LinkCode = [string]$g2.LinkCode
                }
                Save-RamState
                Build-RamCards
                Write-RamLog "«$($g2.Title)» назначена аккаунтам: $($targets.Count)." 'ok'
            }
            $bDel = New-RamButton -Text 'Убрать' -Width 1 -Height $t.M.RowHSm -OnClick {
                $g2 = $this.Tag.Game
                $script:Settings.Games = @(@($script:Settings.Games) | Where-Object {
                    -not ($_.PlaceId -eq $g2.PlaceId -and [string]$_.LinkCode -eq [string]$g2.LinkCode)
                })
                Save-RamSettings -Settings $script:Settings
                Update-RamGamesPanel
                Write-RamLog "«$($g2.Title)» убрана из списка игр." 'ok'
            }
            $bSet.Tag | Add-Member -NotePropertyName Game -NotePropertyValue $g -Force
            $bDel.Tag | Add-Member -NotePropertyName Game -NotePropertyValue $g -Force
            $hasTitle = (-not [string]::IsNullOrWhiteSpace([string]$g.Title)) -and ([string]$g.Title -notmatch '^ID \d+$')
            $title = if ($hasTitle) { [string]$g.Title } else { "ID $($g.PlaceId)" }
            $metaParts = @()
            if ($hasTitle) { $metaParts += "ID $($g.PlaceId)" } else { $metaParts += 'название ещё не подтянулось' }
            if ($g.LinkCode) { $metaParts += 'приватный сервер' }
            $h.Controls.Add((New-RamRowCard -Width $W -Title $title -Meta ($metaParts -join '   ·   ') -Buttons @($bSet, $bDel)))
        }
    } finally {
        $h.ResumeLayout()
    }
}

function Update-RamProfilesPanelClassic {
    <# Раздел «Профили»: сохранённые связки набор+игра. #>
    if (-not $script:UI.ContainsKey('ProfilesHost')) { return }
    $t = $Global:RamTheme
    $h = $script:UI.ProfilesHost
    if ($null -eq $h -or $h.IsDisposed) { return }
    $W = Get-RamListWidth -Panel $h

    $h.SuspendLayout()
    try {
        Clear-RamPanelControls -Panel $h
        $profiles = @(Get-RamProfiles)
        if ($profiles.Count -eq 0) {
            $h.Controls.Add((New-RamNoticeCard -Width $W -Title 'Профилей пока нет' `
                -Text 'Отметь нужные аккаунты в разделе «Аккаунты», задай им игру, потом сохрани текущее как профиль. Дальше весь набор запускается одной кнопкой.'))
            return
        }
        foreach ($pr in $profiles) {
            $bRun = New-RamButton -Text 'Запустить профиль' -Width 1 -Height $t.M.RowHSm -Kind 'primary' -OnClick {
                Invoke-RamRunProfile -Profile $this.Tag.Profile
            }
            $bDel = New-RamButton -Text 'Убрать' -Width 1 -Height $t.M.RowHSm -OnClick {
                $nm = $this.Tag.Profile.Name
                $script:Settings.Profiles = @(Get-RamProfiles | Where-Object { $_.Name -ne $nm })
                Save-RamSettings -Settings $script:Settings
                Update-RamProfilesPanel
                Write-RamLog "Профиль «$nm» убран." 'ok'
            }
            $bRun.Tag | Add-Member -NotePropertyName Profile -NotePropertyValue $pr -Force
            $bDel.Tag | Add-Member -NotePropertyName Profile -NotePropertyValue $pr -Force
            $prIds = @()
            if ($pr.PSObject.Properties.Name -contains 'Ids') { $prIds = @($pr.Ids | Where-Object { $_ }) }
            $meta = if ($pr.Group)          { "набор «$($pr.Group)»" }
                    elseif ($prIds.Count)   { "аккаунтов: $($prIds.Count)" }
                    else                    { 'все аккаунты' }
            if ($pr.GameName) { $meta += "   ·   $($pr.GameName)" }
            elseif ($pr.PlaceId) { $meta += "   ·   ID $($pr.PlaceId)" }
            if ($pr.LinkCode) { $meta += '   ·   приватный сервер' }
            $h.Controls.Add((New-RamRowCard -Width $W -Title ([string]$pr.Name) -Meta $meta -Buttons @($bRun, $bDel)))
        }
    } finally {
        $h.ResumeLayout()
    }
}

function Update-RamStatsPanelClassic {
    <# Раздел «Статистика»: сколько раз запускался, сколько наиграно, вылеты. #>
    if (-not $script:UI.ContainsKey('StatsHost')) { return }
    $h = $script:UI.StatsHost
    if ($null -eq $h -or $h.IsDisposed) { return }
    $h.SuspendLayout()
    try {
        Clear-RamPanelControls -Panel $h
        Add-RamStatsRows -Panel $h -Width (Get-RamListWidth -Panel $h)
    } finally {
        $h.ResumeLayout()
    }
}
