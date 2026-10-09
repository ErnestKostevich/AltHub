#requires -Version 5.1
param(
    [string]$Version = '1.5.0-rc1',
    [string]$Output = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Output)) { $Output = Join-Path $root ("AltHub-$Version.zip") }
$stageRoot = Join-Path ([IO.Path]::GetTempPath()) ('althub-release-' + [guid]::NewGuid().ToString('N'))
$packageName = "AltHub-$Version"
$stage = Join-Path $stageRoot $packageName

$rootFiles = @(
    'AltHub.ps1','AltHub.vbs','LICENSE','README.md','ПРОЧТИ МЕНЯ.txt',
    'Запустить AltHub.cmd','Ярлык на рабочий стол.cmd'
)
$trees = @('modules','extension','tools','Проверки','docs')

try {
    [void](New-Item -ItemType Directory -Path $stage -Force)
    foreach ($name in $rootFiles) {
        $src = Join-Path $root $name
        if (-not (Test-Path -LiteralPath $src)) { throw "Нет обязательного файла: $name" }
        Copy-Item -LiteralPath $src -Destination (Join-Path $stage $name) -Force
    }
    foreach ($name in $trees) {
        $src = Join-Path $root $name
        if (-not (Test-Path -LiteralPath $src)) { throw "Нет обязательной папки: $name" }
        Copy-Item -LiteralPath $src -Destination (Join-Path $stage $name) -Recurse -Force
    }

    # PowerShell 5.1 распознаёт кириллицу надёжно только в UTF-8 BOM.
    $bom = New-Object Text.UTF8Encoding($true)
    foreach ($file in Get-ChildItem -LiteralPath $stage -Filter '*.ps1' -Recurse -File) {
        $text = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8) -replace "(?<!`r)`n", "`r`n"
        [IO.File]::WriteAllText($file.FullName, $text, $bom)
        $errors=$null; $tokens=$null
        [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
        if ($errors.Count) { throw "$($file.FullName):$($errors[0].Extent.StartLineNumber): $($errors[0].Message)" }
    }
    $byteEncoding = [Text.Encoding]::GetEncoding(28591)
    foreach ($file in Get-ChildItem -LiteralPath $stage -Filter '*.cmd' -Recurse -File) {
        $content = $byteEncoding.GetString([IO.File]::ReadAllBytes($file.FullName)) -replace "(?<!`r)`n", "`r`n"
        [IO.File]::WriteAllBytes($file.FullName,$byteEncoding.GetBytes($content))
    }

    $forbidden = @('data','link','.bak','accounts.dat','Cookies','History','Login Data')
    foreach ($entry in Get-ChildItem -LiteralPath $stage -Recurse -Force) {
        if ($forbidden -contains $entry.Name) { throw "В релиз попал запрещённый путь: $($entry.FullName)" }
    }
    foreach ($required in @('extension\icon16.png','extension\icon48.png','extension\icon128.png','modules\UiModern.ps1','modules\menus\Classic.ps1','docs\settings.png','docs\launch-center.png','Проверки\Проверка очереди.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $stage $required))) { throw "В staging нет $required" }
    }
    $stamp = Join-Path $stage 'docs\screenshots-version.txt'
    if (-not (Test-Path -LiteralPath $stamp) -or [IO.File]::ReadAllText($stamp).Trim() -ne $Version) {
        throw 'Скриншоты не соответствуют версии. Сначала выполни tools\Capture-Docs.ps1.'
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $Output) { Remove-Item -LiteralPath $Output -Force }
    [IO.Compression.ZipFile]::CreateFromDirectory($stageRoot, $Output, [IO.Compression.CompressionLevel]::Optimal, $false)

    $zip = [IO.Compression.ZipFile]::OpenRead($Output)
    try {
        $names = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\','/') })
        if ($names | Where-Object { $_ -match '(^|/)(data|link|\.bak)/|accounts\.dat|Network/Cookies|Login Data' }) {
            throw 'Финальный архив содержит пользовательские данные.'
        }
        "Готово: $Output"
        "Файлов: $($zip.Entries.Count); размер: $([Math]::Round((Get-Item $Output).Length / 1KB)) КБ"
    } finally { $zip.Dispose() }
} finally {
    $resolvedStage = [IO.Path]::GetFullPath($stageRoot)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if ($resolvedStage.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolvedStage) -match '^althub-release-[0-9a-f]{32}$' -and (Test-Path -LiteralPath $resolvedStage)) {
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force -ErrorAction SilentlyContinue
    }
}
