#requires -Version 5.1
param(
    [string]$Version = '1.4',
    [string]$Output = (Join-Path (Split-Path -Parent $PSScriptRoot) 'AltHub-1.4.zip')
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
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

    $forbidden = @('data','link','.bak','accounts.dat','Cookies','History','Login Data')
    foreach ($entry in Get-ChildItem -LiteralPath $stage -Recurse -Force) {
        if ($forbidden -contains $entry.Name) { throw "В релиз попал запрещённый путь: $($entry.FullName)" }
    }
    foreach ($required in @('extension\icon16.png','extension\icon48.png','extension\icon128.png','modules\UiModern.ps1','modules\menus\Classic.ps1','docs\settings.png')) {
        if (-not (Test-Path -LiteralPath (Join-Path $stage $required))) { throw "В staging нет $required" }
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $Output) { Remove-Item -LiteralPath $Output -Force }
    [IO.Compression.ZipFile]::CreateFromDirectory($stageRoot, $Output, [IO.Compression.CompressionLevel]::Optimal, $false)

    $zip = [IO.Compression.ZipFile]::OpenRead($Output)
    try {
        $names = @($zip.Entries | ForEach-Object FullName)
        if ($names | Where-Object { $_ -match '(^|/)(data|link|\.bak)/|accounts\.dat|Network/Cookies|Login Data' }) {
            throw 'Финальный архив содержит пользовательские данные.'
        }
        "Готово: $Output"
        "Файлов: $($zip.Entries.Count); размер: $([Math]::Round((Get-Item $Output).Length / 1KB)) КБ"
    } finally { $zip.Dispose() }
} finally {
    if (Test-Path -LiteralPath $stageRoot) { Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
