#requires -Version 5.1

function Get-RamMenuStyleList {
    @(Get-RamClassicMenuStyle; Get-RamWaterMenuStyle; Get-RamWideMenuStyle)
}

function Get-RamMenuStyle {
    param([string]$Key = '')
    if ([string]::IsNullOrWhiteSpace($Key) -and $script:Settings) { $Key = [string]$script:Settings.MenuStyle }
    $style = Get-RamMenuStyleList | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
    if ($null -eq $style) { $style = Get-RamMenuStyleList | Where-Object Key -eq 'classic' | Select-Object -First 1 }
    return $style
}

function Get-RamMenuStyleItems {
    @(Get-RamMenuStyleList | ForEach-Object {
        [pscustomobject]@{ Text=("{0} — {1}" -f $_.Title,$_.Description); Value=$_.Key }
    })
}

function Get-RamMenuCardColumns {
    <#
      Сколько карточек встаёт в ряд. Считается от минимальной ширины карточки
      вида меню и зазора темы — оба масштабируются, поэтому на 150% колонок
      ровно столько, сколько физически помещается.
    #>
    param([Parameter(Mandatory)][int]$AvailableWidth)
    $style = Get-RamMenuStyle
    $max = [int]$style.MaxColumns
    if ($max -le 1) { return 1 }
    $m = $Global:RamTheme.M
    $minW = [int][Math]::Round([int]$style.MinCardWidth * $m.Scale)
    $cols = [int][Math]::Floor(($AvailableWidth + $m.Gap) / ($minW + $m.Gap))
    return [Math]::Max(1, [Math]::Min($max, $cols))
}

function Get-RamMenuCardWidth {
    <#
      Ширина одной карточки. Пол есть только у классической: две колонки текста
      и ряд кнопок в ней сжиматься не умеют. Карточка H₂O уходит в узкий режим
      сама, и пол ей только мешал — кнопки уезжали за видимый край.
    #>
    param([Parameter(Mandatory)][int]$AvailableWidth)
    $style = Get-RamMenuStyle
    $m = $Global:RamTheme.M
    $cols = Get-RamMenuCardColumns -AvailableWidth $AvailableWidth
    $w = [int][Math]::Floor(($AvailableWidth - ($cols - 1) * $m.Gap) / $cols)
    $floor = 1
    if ([string]$style.Layout -eq 'classic') { $floor = [int][Math]::Round([int]$style.MinCardWidth * $m.Scale) }
    return [Math]::Max($floor, $w)
}

function Show-RamMenuStyleUpgradeChoice {
    if (-not $script:NeedsMenuStyleChoice) { return }
    $answer = Show-RamMessage -Title 'AltHub 1.4 — выбери меню' -Kind 'info' -Message (
        "В версии 1.4 есть три независимых вида меню. Цветовую тему можно менять отдельно.`n`n" +
        "Dashboard — вкладки сверху и адаптивная сетка карточек.`nH₂O Original — авторская раскладка H₂O с рисованными иконками.`nPulse — компактный рабочий список без иконок H₂O."
    ) -Buttons @(
        @{ Text='Dashboard'; Value='wide'; Kind='primary' },
        @{ Text='H₂O Original'; Value='water' },
        @{ Text='Pulse'; Value='classic' }
    )
    if ($answer -notin @('classic','water','wide')) { $answer = 'classic' }
    $script:Settings.MenuStyle = [string]$answer
    $script:Settings.SettingsSchemaVersion = 14
    $script:NeedsMenuStyleChoice = $false
    Save-RamSettings -Settings $script:Settings
}
