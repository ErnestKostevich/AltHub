#requires -Version 5.1
<#
  Read-only diagnostic. Prints only client settings, timestamps and file hashes.
  Never opens accounts.dat, browser data, Roblox logs or process arguments.
#>
param([switch]$Once)

$ErrorActionPreference = 'Stop'
$localRoot = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\')
$fileName = 'GlobalBasicSettings_13.xml'
$fieldNames = @('SavedQualityLevel','GraphicsQualityLevel','MaxQualityEnabled',
                'FramerateCap','MasterVolume','Fullscreen')

function Get-DisplayPath {
    param([string]$Path)
    if ($Path.StartsWith($localRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        return '%LOCALAPPDATA%' + $Path.Substring($localRoot.Length)
    }
    return '[outside LOCALAPPDATA]'
}

function Get-SettingsFiles {
    $roots = @((Join-Path $localRoot 'Roblox'))
    $packages = Join-Path $localRoot 'Packages'
    if (Test-Path -LiteralPath $packages) {
        $roots += @(Get-ChildItem -LiteralPath $packages -Directory -Filter '*Roblox*' -ErrorAction SilentlyContinue |
                    ForEach-Object FullName)
    }
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -File -Recurse -Filter $fileName -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $fileName }
    }
}

function Get-SettingsSnapshot {
    $files = @(Get-SettingsFiles | Sort-Object FullName -Unique)
    $players = @(Get-Process -Name RobloxPlayerBeta -ErrorAction SilentlyContinue).Count
    if ($files.Count -eq 0) {
        return "RobloxPlayerBeta=$players; XML не найден"
    }

    $parts = @("RobloxPlayerBeta=$players; XML-файлов=$($files.Count)")
    foreach ($file in $files) {
        try {
            $xml = New-Object xml
            $xml.Load($file.FullName)
            $values = @()
            foreach ($name in $fieldNames) {
                $node = $xml.SelectSingleNode("//*[@name='$name']")
                if ($null -eq $node) { $values += "${name}=нет" }
                else { $values += "${name}=$(([string]$node.InnerText).Trim())" }
            }
            $stamp = $file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss.fff')
            $parts += "$(Get-DisplayPath $file.FullName); изменён=$stamp; $($values -join '; ')"
        } catch {
            $parts += "$(Get-DisplayPath $file.FullName); ошибка чтения XML: $($_.Exception.GetType().Name)"
        }
    }
    return ($parts -join "`n  ")
}

Write-Host 'AltHub: проверка настроек Roblox (только чтение)' -ForegroundColor Cyan
$module = Join-Path (Split-Path -Parent $PSScriptRoot) 'modules\RobloxSettings.ps1'
if (Test-Path -LiteralPath $module) {
    $stream = [IO.File]::OpenRead($module)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '')
        Write-Host ('Модуль AltHub SHA-256: ' + $hash)
    } finally {
        $sha.Dispose()
        $stream.Dispose()
    }
}

$seconds = if ($Once) { @(0) } else { @(0,3,8,15,25,40) }
$previous = ''
$start = Get-Date
foreach ($second in $seconds) {
    $wait = $second - [int]((Get-Date) - $start).TotalSeconds
    if ($wait -gt 0) { Start-Sleep -Seconds $wait }
    $snapshot = Get-SettingsSnapshot
    if ($snapshot -ne $previous -or $second -eq $seconds[-1]) {
        Write-Host ("`nЧерез {0} с:" -f $second)
        Write-Host "  $snapshot"
        $previous = $snapshot
    }
}

if (-not $Once) {
    Write-Host "`nГотово. Можно прислать весь текст этого окна. Кук и паролей здесь нет."
    Write-Host 'Нажми Enter, чтобы закрыть.'
    [void][Console]::ReadLine()
}
