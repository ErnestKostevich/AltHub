#requires -Version 5.1
<#
================================================================================
 RobloxSettings.ps1 — свои настройки графики и звука для каждого аккаунта
================================================================================
 Roblox хранит настройки клиента здесь:

   %LOCALAPPDATA%\Roblox\GlobalBasicSettings_13.xml

 Это обычный XML. Нужные нам поля:

   GraphicsQualityLevel  int    1..21   положение ползунка качества
   SavedQualityLevel     token  0..10   0 = Авто, 1..10 = уровень
   MasterVolume          float  0..1    общая громкость
   FramerateCap          int            0 = без ограничения
   Fullscreen            bool

 ВАЖНОЕ ОГРАНИЧЕНИЕ, О КОТОРОМ НАДО ЗНАТЬ.
 Файл у Roblox ОДИН на все окна. Поэтому "настройки для каждого аккаунта"
 работают так: прямо перед стартом очередного клиента мы записываем в файл
 его настройки, клиент читает их при запуске и дальше держит у себя в памяти.
 Следующий клиент стартует уже со своими.

 Отсюда два следствия:
   1) менять настройки внутри уже запущенного Roblox не стоит — при выходе
      он запишет их обратно в общий файл;
   2) перед первой записью мы делаем резервную копию исходного файла
      (data\roblox-settings-backup.xml), чтобы всегда можно было вернуть как было.

 Файл трогается ТОЛЬКО когда у аккаунта реально что-то задано. Если все поля
 пустые — Roblox запускается с твоими обычными настройками, файл не читается
 и не пишется вообще.
================================================================================
#>

function Get-RamRobloxSettingsCandidates {
    <#
      Roblox менял размещение файла между обычным установщиком и пакетной
      версией. Возвращаем сначала канонические пути, затем реально найденные
      точные файлы. Studio-файл сюда не попадает.
    #>
    $candidates = New-Object System.Collections.ArrayList
    [void]$candidates.Add((Join-Path $env:LOCALAPPDATA 'Roblox\GlobalBasicSettings_13.xml'))

    $normalRoot = Join-Path $env:LOCALAPPDATA 'Roblox'
    if (Test-Path -LiteralPath $normalRoot) {
        foreach ($file in Get-ChildItem -LiteralPath $normalRoot -File -Recurse -Filter 'GlobalBasicSettings_13.xml' -ErrorAction SilentlyContinue) {
            [void]$candidates.Add($file.FullName)
        }
    }

    $packages = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path -LiteralPath $packages) {
        foreach ($dir in Get-ChildItem -LiteralPath $packages -Directory -Filter '*ROBLOX*' -ErrorAction SilentlyContinue) {
            [void]$candidates.Add((Join-Path $dir.FullName 'LocalState\GlobalBasicSettings_13.xml'))
            foreach ($file in Get-ChildItem -LiteralPath $dir.FullName -File -Recurse -Filter 'GlobalBasicSettings_13.xml' -ErrorAction SilentlyContinue) {
                [void]$candidates.Add($file.FullName)
            }
        }
    }

    return @($candidates | Select-Object -Unique)
}

function Get-RamRobloxSettingsPath {
    $candidates = @(Get-RamRobloxSettingsCandidates)
    $existing = @($candidates | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Get-Item -LiteralPath $_ })
    if ($existing.Count -gt 0) { return ($existing | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName }
    return $candidates[0]
}

function Test-RamRobloxSettingsFile {
    Test-Path -LiteralPath (Get-RamRobloxSettingsPath)
}

function Get-RamSettingsBackupPath {
    Join-Path (Get-RamDataDir) 'roblox-settings-backup.xml'
}

function Get-RamSettingsBackupMetaPath {
    Join-Path (Get-RamDataDir) 'roblox-settings-backup.json'
}

function Backup-RamRobloxSettings {
    <# Одноразовая копия исходных настроек Roblox. Делается перед самой первой
       записью и больше не перезаписывается — чтобы «как было» осталось «как
       было», а не «как было в прошлый раз». #>
    $src = Get-RamRobloxSettingsPath
    $dst = Get-RamSettingsBackupPath
    $metaPath = Get-RamSettingsBackupMetaPath
    if (-not (Test-Path -LiteralPath $src)) { return $null }

    # Старые версии оставляли один снимок навсегда. Не используем его как
    # базу новой операции: сохраняем в историю и снимаем свежий слепок.
    if ((Test-Path -LiteralPath $dst) -and -not (Test-Path -LiteralPath $metaPath)) {
        $legacyDir = Join-Path (Get-RamDataDir) 'backups\roblox-settings'
        if (-not (Test-Path -LiteralPath $legacyDir)) { [void](New-Item -ItemType Directory -Path $legacyDir -Force) }
        Move-Item -LiteralPath $dst -Destination (Join-Path $legacyDir ("legacy-{0}.xml" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))) -Force
    }
    if ((Test-Path -LiteralPath $dst) -and (Test-Path -LiteralPath $metaPath)) { return $dst }

    Copy-Item -LiteralPath $src -Destination $dst -Force
    [pscustomobject]@{
        CreatedAt       = (Get-Date).ToString('o')
        OriginalHash    = (Get-FileHash -Algorithm SHA256 -LiteralPath $dst).Hash
        LastManagedHash = ''
    } | ConvertTo-Json | Set-Content -LiteralPath $metaPath -Encoding UTF8 -Force
    return $dst
}

function Set-RamSettingsManagedHash {
    $path = Get-RamRobloxSettingsPath
    $metaPath = Get-RamSettingsBackupMetaPath
    if (-not (Test-Path -LiteralPath $path) -or -not (Test-Path -LiteralPath $metaPath)) { return }
    $meta = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8)
    $meta.LastManagedHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash
    $meta | ConvertTo-Json | Set-Content -LiteralPath $metaPath -Encoding UTF8 -Force
}

function Restore-RamRobloxSettings {
    <# Вернуть исходные настройки Roblox из копии. #>
    $src = Get-RamSettingsBackupPath
    $metaPath = Get-RamSettingsBackupMetaPath
    if (-not (Test-Path -LiteralPath $src)) { throw 'Резервной копии настроек Roblox нет — значит, они и не менялись.' }
    if (@(Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'Сначала закрой все окна Roblox — иначе клиент запишет свои настройки обратно.'
    }
    $dst = Get-RamRobloxSettingsPath
    if (Test-Path -LiteralPath $metaPath) {
        $meta = ConvertFrom-Json -InputObject (Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8)
        if ((Test-Path -LiteralPath $dst) -and $meta.LastManagedHash) {
            $currentHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $dst).Hash
            if ($currentHash -ne [string]$meta.LastManagedHash) {
                throw 'Файл настроек Roblox изменился после записи AltHub. Автовосстановление отменено, чтобы не затереть более новые ручные изменения.'
            }
        }
    }
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Remove-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $metaPath -Force -ErrorAction SilentlyContinue
    return $true
}

function Recover-RamPendingRobloxSettings {
    <# После сбоя/выключения возвращает незавершённую транзакцию прошлого запуска. #>
    if (-not (Test-Path -LiteralPath (Get-RamSettingsBackupPath))) { return $false }
    if (-not (Test-Path -LiteralPath (Get-RamSettingsBackupMetaPath))) { return $false }
    if (@(Get-Process -Name 'RobloxPlayerBeta' -ErrorAction SilentlyContinue).Count -gt 0) {
        $script:SettingsTouched = $true
        return $false
    }
    [void](Restore-RamRobloxSettings)
    $script:SettingsTouched = $false
    return $true
}

function Test-RamAccountHasClientSettings {
    <# Задано ли у аккаунта хоть что-то из настроек клиента. #>
    param($Account)
    foreach ($f in @('Graphics','FramerateCap','Volume','Fullscreen')) {
        if ($Account.PSObject.Properties.Name -notcontains $f) { continue }
        if (-not [string]::IsNullOrWhiteSpace([string]$Account.$f)) { return $true }
    }
    return $false
}

function Set-RamXmlValue {
    <#
      Меняет значение одного поля в XML настроек Roblox.
      Ищем узел по атрибуту name — тип узла (int/float/bool/token) не важен,
      меняем только текст внутри.
      Возвращает $true, если поле нашлось и поменялось.
    #>
    param(
        [Parameter(Mandatory)][xml]$Xml,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Value
    )
    $node = $Xml.SelectSingleNode("//*[@name='$Name']")
    if ($null -eq $node) {
        $types = @{
            SavedQualityLevel='token'; GraphicsQualityLevel='int'; MaxQualityEnabled='bool'
            FramerateCap='int'; MasterVolume='float'; Fullscreen='bool'
        }
        if (-not $types.ContainsKey($Name)) { throw "Неизвестное поле настроек Roblox: $Name" }
        $anchor = $Xml.SelectSingleNode("//*[@name='GraphicsQualityLevel']")
        if ($null -eq $anchor) { $anchor = $Xml.SelectSingleNode("//*[@name='MasterVolume']") }
        if ($null -eq $anchor -or $null -eq $anchor.ParentNode) {
            throw "В XML Roblox не найден раздел пользовательских настроек; поле $Name создать негде."
        }
        $node = $Xml.CreateElement([string]$types[$Name])
        [void]$node.SetAttribute('name', $Name)
        [void]$anchor.ParentNode.AppendChild($node)
    }
    $node.InnerText = $Value
    return $true
}

function Convert-RamGraphicsToLevels {
    <#
      Из понятного «качество 1..10» делает пару значений, которые ждёт Roblox.

      SavedQualityLevel   — 0 (Авто) либо 1..10
      GraphicsQualityLevel— положение ползунка 1..21; Roblox раскладывает
                            10 уровней по шкале 21, поэтому пересчитываем.
    #>
    param([string]$Graphics)

    if ([string]::IsNullOrWhiteSpace($Graphics)) { return $null }

    if ($Graphics -eq 'auto') {
        return [pscustomobject]@{ Saved = 0; Slider = 1; MaxQuality = 'false' }
    }

    $lvl = 0
    if (-not [int]::TryParse($Graphics, [ref]$lvl)) { return $null }
    if ($lvl -lt 1)  { $lvl = 1 }
    if ($lvl -gt 10) { $lvl = 10 }

    # 10 уровней на шкалу 1..21
    $slider = [int][math]::Round(1 + ($lvl - 1) * (20.0 / 9.0))
    if ($slider -lt 1)  { $slider = 1 }
    if ($slider -gt 21) { $slider = 21 }

    return [pscustomobject]@{
        Saved      = $lvl
        Slider     = $slider
        MaxQuality = $(if ($lvl -ge 10) { 'true' } else { 'false' })
    }
}

function Get-RamClientSettingsKey {
    <#
      Слепок тех настроек, которые уходят в общий файл Roblox.

      Нужен, чтобы понять, отличаются ли настройки двух соседних запусков.
      Если одинаковые — перезапись файла тем же самым безвредна и ждать
      перед следующим запуском незачем.
    #>
    param([Parameter(Mandatory)]$Account)

    if (-not (Test-RamAccountHasClientSettings -Account $Account)) { return '' }

    return ('g={0}|fps={1}|vol={2}|fs={3}' -f
            [string]$Account.Graphics,
            [string]$Account.FramerateCap,
            [string]$Account.Volume,
            [string]$Account.Fullscreen)
}

function Get-RamExpectedClientSettings {
    param([Parameter(Mandatory)]$Account)
    $expected = [ordered]@{}
    $g = Convert-RamGraphicsToLevels -Graphics ([string]$Account.Graphics)
    if ($null -ne $g) {
        $expected.SavedQualityLevel=[string]$g.Saved
        $expected.GraphicsQualityLevel=[string]$g.Slider
        $expected.MaxQualityEnabled=[string]$g.MaxQuality
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Account.FramerateCap)) {
        $fps=0
        if ([int]::TryParse([string]$Account.FramerateCap,[ref]$fps)) { $expected.FramerateCap=[string][Math]::Max(0,$fps) }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Account.Volume)) {
        $vol=0
        if ([int]::TryParse([string]$Account.Volume,[ref]$vol)) {
            $vol=[Math]::Min(100,[Math]::Max(0,$vol))
            $expected.MasterVolume=([string][Math]::Round($vol/100.0,3)).Replace(',','.')
        }
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Account.Fullscreen)) {
        $expected.Fullscreen=$(if([string]$Account.Fullscreen -eq 'yes'){'true'}else{'false'})
    }
    return $expected
}

function Assert-RamClientSettingsXml {
    param([Parameter(Mandatory)][xml]$Xml,[Parameter(Mandatory)]$Account)
    $expected=Get-RamExpectedClientSettings -Account $Account
    foreach($name in $expected.Keys){
        $node=$Xml.SelectSingleNode("//*[@name='$name']")
        if($null-eq$node){throw "После записи в XML отсутствует поле $name."}
        if(([string]$node.InnerText).Trim() -ne ([string]$expected[$name]).Trim()){
            throw "Проверка XML не прошла: $name='$($node.InnerText)', ожидалось '$($expected[$name])'."
        }
    }
    return $true
}

function Apply-RamAccountClientSettings {
    <#
      Записывает настройки конкретного аккаунта в файл настроек Roblox.
      Вызывать НЕПОСРЕДСТВЕННО перед стартом этого клиента.

      Возвращает список того, что реально применилось (для журнала).
      Если у аккаунта ничего не задано — файл не трогается вообще.
    #>
    param([Parameter(Mandatory)]$Account)

    $script:ClientSettingsSkippedReason = ''
    if (-not (Test-RamAccountHasClientSettings -Account $Account)) { return @() }

    $path = Get-RamRobloxSettingsPath
    if (-not (Test-Path -LiteralPath $path)) {
        # Отсутствие XML бывает на чистой установке и у некоторых вариантов
        # пакетного клиента. Это не ошибка запуска самого Roblox. Первый клиент
        # должен открыться и получить шанс создать файл; персональные параметры
        # применим при следующем запуске. Настоящие ошибки чтения/записи ниже
        # по-прежнему бросают исключение и не маскируются.
        $script:ClientSettingsSkippedReason = 'Файл настроек Roblox пока не создан. Аккаунт запускается с обычными настройками; после появления XML AltHub применит персональные параметры при следующем запуске.'
        return @()
    }

    [void](Backup-RamRobloxSettings)

    $xml = New-Object xml
    $xml.Load($path)

    $applied = @()

    # --- графика
    $g = Convert-RamGraphicsToLevels -Graphics ([string]$Account.Graphics)
    if ($null -ne $g) {
        $ok1 = Set-RamXmlValue -Xml $xml -Name 'SavedQualityLevel'     -Value ([string]$g.Saved)
        $ok2 = Set-RamXmlValue -Xml $xml -Name 'GraphicsQualityLevel' -Value ([string]$g.Slider)
        $ok3 = Set-RamXmlValue -Xml $xml -Name 'MaxQualityEnabled'    -Value $g.MaxQuality
        if (-not ($ok1 -and $ok2 -and $ok3)) { throw 'Не все настройки графики удалось записать.' }
        $applied += $(if ($g.Saved -eq 0) { 'графика: авто' } else { "графика: $($g.Saved)" })
    }

    # --- предел кадров
    if (-not [string]::IsNullOrWhiteSpace([string]$Account.FramerateCap)) {
        $fps = 0
        if ([int]::TryParse([string]$Account.FramerateCap, [ref]$fps)) {
            if ($fps -lt 0) { $fps = 0 }
            if (-not (Set-RamXmlValue -Xml $xml -Name 'FramerateCap' -Value ([string]$fps))) { throw 'Не удалось записать предел FPS.' }
            $applied += $(if ($fps -eq 0) { 'FPS: без предела' } else { "FPS: $fps" })
        }
    }

    # --- громкость (у нас 0..100, у Roblox 0..1)
    if (-not [string]::IsNullOrWhiteSpace([string]$Account.Volume)) {
        $vol = 0
        if ([int]::TryParse([string]$Account.Volume, [ref]$vol)) {
            if ($vol -lt 0)   { $vol = 0 }
            if ($vol -gt 100) { $vol = 100 }
            $f = [math]::Round($vol / 100.0, 3)
            if (-not (Set-RamXmlValue -Xml $xml -Name 'MasterVolume' -Value ([string]$f).Replace(',', '.'))) { throw 'Не удалось записать громкость.' }
            $applied += "звук: $vol%"
        }
    }

    # --- полноэкранный режим
    if (-not [string]::IsNullOrWhiteSpace([string]$Account.Fullscreen)) {
        $fs = ([string]$Account.Fullscreen -eq 'yes')
        if (-not (Set-RamXmlValue -Xml $xml -Name 'Fullscreen' -Value $(if ($fs) { 'true' } else { 'false' }))) { throw 'Не удалось записать полноэкранный режим.' }
        $applied += $(if ($fs) { 'полный экран' } else { 'в окне' })
    }

    if ($applied.Count -gt 0) {
        # Пишем через временный файл: если что-то пойдёт не так на середине,
        # настоящий файл настроек останется целым.
        $tmp = "$path.althub-tmp"
        $xml.Save($tmp)
        $verify = New-Object xml
        $verify.Load($tmp)
        [void](Assert-RamClientSettingsXml -Xml $verify -Account $Account)
        Move-Item -LiteralPath $tmp -Destination $path -Force
        Set-RamSettingsManagedHash
    }

    return $applied
}

function Get-RamGraphicsChoices {
    <# Варианты для выпадающего списка в настройках аккаунта. #>
    @(
        [pscustomobject]@{ Text = 'не трогать';      Value = ''     },
        [pscustomobject]@{ Text = 'Авто';            Value = 'auto' },
        [pscustomobject]@{ Text = '1 — минимум';     Value = '1'    },
        [pscustomobject]@{ Text = '2';               Value = '2'    },
        [pscustomobject]@{ Text = '3';               Value = '3'    },
        [pscustomobject]@{ Text = '4';               Value = '4'    },
        [pscustomobject]@{ Text = '5 — середина';    Value = '5'    },
        [pscustomobject]@{ Text = '6';               Value = '6'    },
        [pscustomobject]@{ Text = '7';               Value = '7'    },
        [pscustomobject]@{ Text = '8';               Value = '8'    },
        [pscustomobject]@{ Text = '9';               Value = '9'    },
        [pscustomobject]@{ Text = '10 — максимум';   Value = '10'   }
    )
}

function Get-RamFpsChoices {
    @(
        [pscustomobject]@{ Text = 'не трогать';   Value = ''    },
        [pscustomobject]@{ Text = 'без предела';  Value = '0'   },
        [pscustomobject]@{ Text = '30';           Value = '30'  },
        [pscustomobject]@{ Text = '60';           Value = '60'  },
        [pscustomobject]@{ Text = '120';          Value = '120' },
        [pscustomobject]@{ Text = '144';          Value = '144' },
        [pscustomobject]@{ Text = '240';          Value = '240' }
    )
}

function Get-RamFullscreenChoices {
    @(
        [pscustomobject]@{ Text = 'не трогать';   Value = ''    },
        [pscustomobject]@{ Text = 'в окне';       Value = 'no'  },
        [pscustomobject]@{ Text = 'полный экран'; Value = 'yes' }
    )
}

function Get-RamAccountSettingsSummary {
    <# Короткая подпись для карточки: «графика 3 · звук 0% · 60 FPS». #>
    param($Account)

    $parts = @()

    $g = [string]$Account.Graphics
    if ($g -eq 'auto')            { $parts += 'графика авто' }
    elseif (-not [string]::IsNullOrWhiteSpace($g)) { $parts += "графика $g" }

    $v = [string]$Account.Volume
    if (-not [string]::IsNullOrWhiteSpace($v)) { $parts += "звук $v%" }

    $f = [string]$Account.FramerateCap
    if ($f -eq '0')                { $parts += 'FPS без предела' }
    elseif (-not [string]::IsNullOrWhiteSpace($f)) { $parts += "$f FPS" }

    if ([string]$Account.Fullscreen -eq 'yes') { $parts += 'полный экран' }

    return ($parts -join '  ·  ')
}
