#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'AltHub.ps1') -NoAutoStart
$script:Settings=Get-RamDefaultSettings
$Global:RamForceScale=1
$Global:RamForceWorkArea=[pscustomobject]@{Width=1920;Height=1040}
Set-RamTheme -Name dark | Out-Null
function Assert-Order { param([bool]$Value,[string]$Message) if(-not $Value){throw $Message} }
function Assert-Swap {
    param([string]$First,[string]$Second)
    $before=@(Get-RamOrderedAccounts | ForEach-Object Id)
    $expected=@($before)
    $ai=[array]::IndexOf($before,$First);$bi=[array]::IndexOf($before,$Second)
    $expected[$ai]=$Second;$expected[$bi]=$First
    Assert-Order (Swap-RamAccountOrder -Id $First -WithId $Second) 'Обмен отклонён'
    $after=@(Get-RamOrderedAccounts | ForEach-Object Id)
    Assert-Order (($after -join ',') -eq ($expected -join ',')) 'Обмен двух карточек не совпал с целью; остальные аккаунты сдвинулись'
}
function Send-FixtureMouse {
    param($Control,[string]$Event,[System.Drawing.Point]$ScreenPoint,[System.Windows.Forms.MouseButtons]$Button=[System.Windows.Forms.MouseButtons]::Left)
    $point=$Control.PointToClient($ScreenPoint)
    $mouseEvent=[System.Windows.Forms.MouseEventArgs]::new($Button,1,$point.X,$point.Y,0)
    $method=[System.Windows.Forms.Control].GetMethod($Event,[Reflection.BindingFlags]'Instance,NonPublic')
    [void]$method.Invoke($Control,[object[]]@($mouseEvent.PSObject.BaseObject))
}
$script:Accounts=@(1..13 | ForEach-Object {$a=New-RamAccount -Alias "Fixture-$_";$a.Order=$_*10;$a.Color=if($_ -in @(4,6,7)){'orange'}else{''};$a.Group=if($_ -lt 5){'Основные'}else{'Твины'};$a})
$script:Accounts[3].Order=10
$script:Accounts[5].Order=10
Assert-Swap -First $script:Accounts[0].Id -Second $script:Accounts[3].Id
Assert-Order (@(Get-RamOrderedAccounts | ForEach-Object Order | Sort-Object -Unique).Count -eq 13) 'Дубли порядка остались после исправления'
'PASS: duplicate ranks and orange labels no longer block an exact swap'
$added=New-RamAccount -Alias 'New account'
$beforeAdd=@(Get-RamOrderedAccounts | ForEach-Object Id)
$script:Accounts+=@($added)
$afterAdd=@(Get-RamOrderedAccounts | ForEach-Object Id)
Assert-Order (($afterAdd[0..12] -join ',') -eq ($beforeAdd -join ',') -and $afterAdd[13] -eq $added.Id) 'Новый аккаунт занял чужое место вместо конца списка'
Assert-Swap -First $added.Id -Second $script:Accounts[5].Id
'PASS: new accounts append after existing ranks and can move to any position'
$script:GroupFilter='Твины'
$visible=@(Get-RamVisibleAccounts)
Assert-Swap -First $visible[0].Id -Second $visible[-1].Id
$script:GroupFilter=''
$json=ConvertTo-Json -InputObject @($script:Accounts) -Depth 6
$expected=@(Get-RamOrderedAccounts | ForEach-Object Id)
$script:Accounts=ConvertFrom-Json -InputObject $json
Assert-Order ((@(Get-RamOrderedAccounts | ForEach-Object Id) -join ',') -eq ($expected -join ',')) 'Порядок после загрузки не сохранился'
'PASS: filtered swaps retain hidden positions and order survives JSON reload'
$script:Instances=@{};$script:FocusedFixtureHandle=[IntPtr]::Zero
function Set-RamWindowForeground {param($Handle) $script:FocusedFixtureHandle=$Handle;return $true}
for($i=0;$i -lt $expected.Count;$i++){$script:Instances[$expected[$i]]=[pscustomobject]@{Handle=[IntPtr]::new(100+$i)}}
for($i=1;$i -le 9;$i++){Invoke-RamFocusAccountByIndex -Index $i;Assert-Order ($script:FocusedFixtureHandle -eq [IntPtr]::new(99+$i)) "Ctrl+$i выбрал не ту карточку"}
'PASS: Ctrl+1 through Ctrl+9 match the reloaded displayed order'
$script:Instances=@{}
$script:Accounts=@(1..40 | ForEach-Object {$a=New-RamAccount -Alias "Tie-$_";$a.Order=10;$a})
Assert-Order ((@(Get-RamOrderedAccounts | ForEach-Object Alias) -join ',') -eq ((1..40 | ForEach-Object {"Tie-$_"}) -join ',')) 'Дубли сортируются нестабильно'
Assert-Swap -First $script:Accounts[0].Id -Second $script:Accounts[-1].Id
$script:UndoStack=New-Object Collections.ArrayList
$beforeUndo=@(Get-RamOrderedAccounts | ForEach-Object Id)
Push-RamUndo -Label 'fixture swap'
Assert-Swap -First $script:Accounts[3].Id -Second $script:Accounts[28].Id
Invoke-RamUndo
Assert-Order ((@(Get-RamOrderedAccounts | ForEach-Object Id) -join ',') -eq ($beforeUndo -join ',')) 'Ctrl+Z не вернул порядок'
'PASS: 40 tied ranks retain a deterministic order; undo restores exactly'
$persistDir=Join-Path ([IO.Path]::GetTempPath()) ('althub-order-test-'+[guid]::NewGuid().ToString('N'))
function Get-RamDataDir { return $script:OrderFixtureDirectory }
$script:OrderFixtureDirectory=$persistDir
[void](New-Item -ItemType Directory -Path $persistDir)
try {
    $script:ReadOnly=$false
    Save-RamAccounts -Accounts $script:Accounts
    $script:ReadOnly=$true
    $script:Accounts=Load-RamAccounts
    Assert-Order ((@(Get-RamOrderedAccounts | ForEach-Object Id) -join ',') -eq ($beforeUndo -join ',')) 'Перезапуск из зашифрованного файла потерял порядок'
    'PASS: encrypted save and reload preserve the repaired order'
} finally {
    $script:ReadOnly=$true
    $resolved=[IO.Path]::GetFullPath($persistDir)
    if($resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -match '^althub-order-test-[a-f0-9]{32}$') {Remove-Item -LiteralPath $resolved -Recurse -Force}
}

foreach($style in @('classic','water','wide')) {
    $script:Settings.MenuStyle=$style;$script:Settings.CompactCards=$true
    $script:Settings.OnClose='exit';$script:Settings.ConfirmOnExit=$false
    $script:Accounts=@(1..13 | ForEach-Object {$a=New-RamAccount -Alias "Mouse-$_";$a.Color=if($_ -in @(4,6,7)){'orange'}else{''};$a})
    $script:UI=@{};$script:Cards=@{};$script:CheckedIds=@{};$script:Filter='';$script:GroupFilter='';$script:Section='accounts'
    $form=New-RamMainForm
    try {
        $form.ShowInTaskbar=$false;$form.Opacity=0
        $form.Show();[Windows.Forms.Application]::DoEvents()
        Update-RamAfterResize -Force
        Build-RamCards
        $before=@(Get-RamOrderedAccounts | ForEach-Object Id)
        $source=$script:Cards[$before[3]].Name
        $target=$script:Cards[$before[0]].Card
        $start=$source.PointToScreen([Drawing.Point]::new(3,3))
        $release=$target.PointToScreen([Drawing.Point]::new([int]($target.Width/2),[int]($target.Height/2)))
        Send-FixtureMouse -Control $source -Event OnMouseDown -ScreenPoint $start
        Send-FixtureMouse -Control $source -Event OnMouseMove -ScreenPoint $release
        Assert-Order ($script:DragOverId -eq $before[0]) "$style неверная цель: moved=$($script:DragMoved); source=$($script:DragId); over=$($script:DragOverId); local=$($script:UI.Cards.PointToClient($release)); target=$($target.Bounds); viewport=$($script:UI.Cards.ClientRectangle)"
        # MouseUp на третьей карточке без дополнительного MouseMove: цель — место отпускания.
        $actualTarget=$script:Cards[$before[2]].Card
        $release=$actualTarget.PointToScreen([Drawing.Point]::new(5,5))
        Send-FixtureMouse -Control $source -Event OnMouseUp -ScreenPoint $release
        $expected=@($before);$expected[2]=$before[3];$expected[3]=$before[2]
        Assert-Order ((@(Get-RamOrderedAccounts | ForEach-Object Id) -join ',') -eq ($expected -join ',')) "$style использовал устаревшую цель отпускания"
        Assert-Order (-not $script:DragId -and -not $script:DragOverId) "$style не очистил перетаскивание"
        $source=$script:Cards[$before[3]].Avatar
        $start=$source.PointToScreen([Drawing.Point]::new(3,3))
        Send-FixtureMouse -Control $source -Event OnMouseDown -ScreenPoint $start
        Send-FixtureMouse -Control $source -Event OnMouseMove -ScreenPoint ($script:Cards[$before[0]].Card.PointToScreen([Drawing.Point]::new(5,5)))
        Send-FixtureMouse -Control $source -Event OnMouseUp -ScreenPoint ($script:UI.Cards.PointToScreen([Drawing.Point]::new(-5,-5)))
        Assert-Order ((@(Get-RamOrderedAccounts | ForEach-Object Id) -join ',') -eq ($expected -join ',')) "$style обменял карточку за пределами списка"
        Send-FixtureMouse -Control $source -Event OnMouseDown -ScreenPoint $start
        $captureMethod=[Windows.Forms.Control].GetMethod('OnMouseCaptureChanged',[Reflection.BindingFlags]'Instance,NonPublic')
        [void]$captureMethod.Invoke($source,@([EventArgs]::Empty))
        Assert-Order (-not $script:DragId -and -not $script:DragOverId) "$style не отменил потерянный захват мыши"
        # Bounds уже учитывают прокрутку: сравниваем с реальной точкой видимой карточки.
        $hostPanel=$script:UI.Cards
        $hostPanel.Height=150
        $hostPanel.PerformLayout()
        $hostPanel.AutoScrollPosition=[Drawing.Point]::new(0,180)
        $hostPanel.PerformLayout()
        foreach($card in $hostPanel.Controls){
            $local=[Drawing.Point]::new(($card.Left+5),($card.Top+5))
            if($hostPanel.ClientRectangle.Contains($local)) {
                Assert-Order ((Get-RamCardAtScreenPoint -Point ($hostPanel.PointToScreen($local))) -eq $card.Tag.AccountId) "$style не нашёл карточку после прокрутки"
            }
        }
        Assert-Order (-not(Get-RamCardAtScreenPoint -Point ($hostPanel.PointToScreen([Drawing.Point]::new(5,-5))))) "$style выбрал скрытую карточку выше списка"
        "PASS: $style compact mouse drag respects release point, capture loss and scrolled viewport"
    } finally {Dispose-RamFormRuntime;$form.Dispose()}
}
if(-not $NoPause){[void](Read-Host 'Enter')}
