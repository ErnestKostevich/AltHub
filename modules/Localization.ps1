#requires -Version 5.1
$script:RamEnglishCatalog=$null

function Get-RamDefaultUiLanguage {
    param([Globalization.CultureInfo]$Culture=[Globalization.CultureInfo]::CurrentUICulture)
    if ($null -ne $Culture -and $Culture.TwoLetterISOLanguageName -eq 'ru') { return 'ru' }
    return 'en'
}

function Get-RamUiLanguage {
    if ($null -ne $script:Settings) {
        if ($script:Settings.PSObject.Properties.Name -contains 'UiLanguage' -and $script:Settings.UiLanguage -in @('ru','en')) { return $script:Settings.UiLanguage }
        return Get-RamDefaultUiLanguage
    }
    if($script:RamStartupUiLanguage -in @('ru','en')){return $script:RamStartupUiLanguage}
    return Get-RamDefaultUiLanguage
}

function Get-RamEnglishCatalog {
    if ($null -ne $script:RamEnglishCatalog) { return $script:RamEnglishCatalog }
    $catalog=New-Object 'Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'locales') -Filter 'en-*.json' -File | Sort-Object Name)) {
        $entries=ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($file.FullName,[Text.Encoding]::UTF8))
        foreach($entry in $entries) {
            if ($entry.Source -isnot [string] -or $entry.Translation -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.Translation)) { throw "Invalid English language entry in $($file.Name)." }
            # PS1 files use CRLF in release archives; JSON source keys use LF.
            $source=$entry.Source.Replace("`r`n","`n")
            if ($catalog.ContainsKey($source) -and $catalog[$source] -ne $entry.Translation) { throw "Conflicting English language entry in $($file.Name)." }
            $catalog[$source]=$entry.Translation
        }
    }
    $script:RamEnglishCatalog=$catalog
    return $catalog
}

function Get-RamText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [object[]]$Arguments=@())
    $template=$Text
    if ((Get-RamUiLanguage) -eq 'en') {
        $catalog=Get-RamEnglishCatalog
        $source=$Text.Replace("`r`n","`n")
        if ($catalog.ContainsKey($source)) { $template=$catalog[$source] }
    }
    if ($Arguments.Count) { return [string]::Format([Globalization.CultureInfo]::CurrentCulture,$template,[object[]]$Arguments) }
    return $template
}

function Get-RamErrorText {
    param([AllowEmptyString()][string]$Text)
    if ((Get-RamUiLanguage) -ne 'en' -or $Text -notmatch '[А-Яа-яЁё]') { return $Text }
    $catalog=Get-RamEnglishCatalog
    $normalized=$Text.Replace("`r`n","`n")
    if($catalog.ContainsKey($normalized)){return $catalog[$normalized]}
    foreach($source in $catalog.Keys) {
        if($source -notmatch '\{\d+\}'){continue}
        $pattern='\A'+[regex]::Escape($source)+'\z'
        $pattern=[regex]::Replace($pattern,'\\\{(\d+)\\\}',{param($m) '(?<p'+$m.Groups[1].Value+'>.*?)'})
        try { $match=[regex]::Match($normalized,$pattern,[Text.RegularExpressions.RegexOptions]::Singleline,[TimeSpan]::FromMilliseconds(100)) }
        catch [Text.RegularExpressions.RegexMatchTimeoutException] { continue }
        if(-not $match.Success){continue}
        $values=@();$i=0
        while($match.Groups['p'+$i].Success){$values+=@($match.Groups['p'+$i].Value);$i++}
        if($values.Count){return Get-RamText -Text $source -Arguments $values}
    }
    return $Text
}
