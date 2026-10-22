#requires -Version 5.1
param([switch]$NoPause)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'AltHub.ps1') -NoAutoStart
function Assert-Twins {param([bool]$Value,[string]$Message) if(-not $Value){throw $Message}}
Assert-Twins ($null -ne (Get-Command Invoke-RamToggleTwinkWindows -ErrorAction SilentlyContinue)) 'Twink window toggle missing'
$script:FocusTestDir=Join-Path ([IO.Path]::GetTempPath()) ('althub-focus-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $script:FocusTestDir)
function Get-RamDataDir {$script:FocusTestDir}
function Show-RamMessage {param($Message,$Kind) $script:FocusWarnings++}
function Save-RamSettings {param($Settings) $script:FocusSaves++}
function Get-FocusPlacement {
    param($Form)
    $p=New-Object Ram.Native+WINDOWPLACEMENT
    $p.length=[Runtime.InteropServices.Marshal]::SizeOf($p)
    Assert-Twins ([Ram.Native]::GetWindowPlacement($Form.Handle,[ref]$p)) 'GetWindowPlacement failed'
    return $p
}
function Get-FocusRectKey {param($Placement) $r=$Placement.rcNormalPosition;return "$($r.Left),$($r.Top),$($r.Right),$($r.Bottom)"}
$forms=@{}
try {
    foreach($id in @('main','normal','max','min','foreign')) {
        $f=New-Object Windows.Forms.Form
        $f.Text='AltHub synthetic '+$id;$f.ShowInTaskbar=$false;$f.Opacity=0
        $f.StartPosition='Manual';$f.Bounds=New-Object Drawing.Rectangle(60,70,320,180)
        [void]$f.Handle
        [void][Ram.Native]::ShowWindow($f.Handle,4)
        $forms[$id]=$f
    }
    [void][Ram.Native]::ShowWindow($forms.max.Handle,3)
    [void][Ram.Native]::ShowWindow($forms.min.Handle,6)
    $script:Settings=Get-RamDefaultSettings
    $script:Settings.MainAccountId='';$script:Settings.UiLanguage='en'
    $script:FocusWarnings=0;$script:FocusSaves=0
    $script:Accounts=@();$script:Instances=@{}
    foreach($id in @('main','normal','max','min')) {
        $script:Accounts += [pscustomobject]@{Id=$id;Alias=$id;Order=$script:Accounts.Count}
        $script:Instances[$id]=[pscustomobject]@{Handle=$forms[$id].Handle;ProcessId=$PID}
    }
    $normalBefore=Get-FocusPlacement $forms.normal
    $maxBefore=Get-FocusPlacement $forms.max
    Invoke-RamToggleTwinkWindows
    $script:Settings.MainAccountId='missing'
    Invoke-RamToggleTwinkWindows
    Assert-Twins ($script:FocusWarnings -eq 2 -and @($script:TwinkWindowSnapshot).Count -eq 0 -and -not [Ram.Native]::IsIconic($forms.normal.Handle)) 'Missing main changed windows'
    'PASS: absent/deleted main warns without choosing or moving windows'

    Set-RamTheme -Name dark | Out-Null
    $menu=New-RamTileWindowsMenu
    try {
        $mainMenu=$menu.Items[$menu.Items.Count-1]
        $method=[Windows.Forms.ToolStripDropDownItem].GetMethod('OnDropDownShow',[Reflection.BindingFlags]'Instance,NonPublic')
        [void]$method.Invoke($mainMenu,@([EventArgs]::Empty))
        Assert-Twins ($mainMenu.DropDownItems.Count -eq 4 -and $script:Settings.MainAccountId -eq 'missing') 'Opening selector silently chose main'
        $mainMenu.DropDownItems[0].PerformClick()
        Assert-Twins ($script:Settings.MainAccountId -eq 'main' -and $script:FocusSaves -eq 1) 'Explicit main selection not saved'
    } finally {$menu.Dispose()}
    'PASS: explicit main selector saves only selected main, opening it is cancellable'

    Invoke-RamToggleTwinkWindows
    Assert-Twins (@($script:TwinkWindowSnapshot).Count -eq 2 -and [Ram.Native]::IsIconic($forms.normal.Handle) -and [Ram.Native]::IsIconic($forms.max.Handle)) 'Normal/max alts were not captured and minimized'
    Assert-Twins (-not [Ram.Native]::IsIconic($forms.main.Handle) -and -not [Ram.Native]::IsIconic($forms.foreign.Handle)) 'Main or untracked window was minimized'
    Invoke-RamToggleTwinkWindows
    $normalAfter=Get-FocusPlacement $forms.normal;$maxAfter=Get-FocusPlacement $forms.max
    Assert-Twins ($normalAfter.showCmd -eq $normalBefore.showCmd -and (Get-FocusRectKey $normalAfter) -eq (Get-FocusRectKey $normalBefore)) 'Normal placement was not restored'
    Assert-Twins ($maxAfter.showCmd -eq 3 -and (Get-FocusRectKey $maxAfter) -eq (Get-FocusRectKey $maxBefore)) 'Maximized placement was not restored'
    Assert-Twins ([Ram.Native]::IsIconic($forms.min.Handle) -and @($script:TwinkWindowSnapshot).Count -eq 0) 'Already minimized window changed'
    'PASS: native normal/max restore, explicit main/untracked untouched, already minimized stays minimized'

    Invoke-RamToggleTwinkWindows
    $old=$script:Instances.normal
    $script:Instances.normal=[pscustomobject]@{Handle=$old.Handle;ProcessId=$PID}
    Invoke-RamToggleTwinkWindows
    Assert-Twins ([Ram.Native]::IsIconic($forms.normal.Handle) -and -not [Ram.Native]::IsIconic($forms.max.Handle)) 'Replacement instance was restored'
    $script:Instances.normal=$old
    [void][Ram.Native]::ShowWindow($forms.normal.Handle,4)
    'PASS: relaunched/replaced instance is skipped even with same PID and handle'

    Invoke-RamToggleTwinkWindows
    $oldHandle=$script:Instances.normal.Handle
    $script:Instances.normal.Handle=$forms.foreign.Handle
    Invoke-RamToggleTwinkWindows
    Assert-Twins ([Ram.Native]::IsIconic($forms.normal.Handle) -and -not [Ram.Native]::IsIconic($forms.foreign.Handle)) 'Changed/reused handle affected another window'
    $script:Instances.normal.Handle=$oldHandle
    [void][Ram.Native]::ShowWindow($forms.normal.Handle,4)
    'PASS: changed window handle cannot restore an unrelated window'

    Invoke-RamToggleTwinkWindows
    foreach($saved in $script:TwinkWindowSnapshot){if($saved.Id -eq 'normal'){$saved.StartTicks=0}}
    $forms.max.Close()
    Invoke-RamToggleTwinkWindows
    Assert-Twins ([Ram.Native]::IsIconic($forms.normal.Handle) -and @($script:TwinkWindowSnapshot).Count -eq 0) 'Closed window or changed process lifetime restored'
    'PASS: closed window and mismatched process creation time are skipped'

    [void][Ram.Native]::ShowWindow($forms.normal.Handle,4)
    $script:Instances.normal.ProcessId=$PID+100000
    Invoke-RamToggleTwinkWindows
    Assert-Twins (-not [Ram.Native]::IsIconic($forms.normal.Handle) -and @($script:TwinkWindowSnapshot).Count -eq 0) 'Wrong PID minimized a window'
    Assert-Twins ((Get-RamWindowTitle -Handle $forms.main.Handle) -eq 'AltHub synthetic main' -and (Get-RamWindowTitle -Handle ([IntPtr]::Zero)) -eq '') 'Title reader contract failed'
    Assert-Twins ((Get-RamWindowProcessId -Handle $forms.main.Handle) -eq $PID -and (Get-RamWindowProcessId -Handle ([IntPtr]::Zero)) -eq 0) 'Window PID reader contract failed'
    'PASS: wrong PID is rejected and window-title helper is bounded'
} finally {
    $script:TwinkWindowSnapshot=@()
    foreach($f in $forms.Values){$f.Dispose()}
}

# Real application forms, no Show() and no tray publication or user storage.
$script:Accounts=@();$script:Instances=@{};$script:Section='accounts';$script:ReadOnly=$true
try {
    foreach($language in @('ru','en')) {
        foreach($scale in @(1.0,1.5,2.0)) {
            $Global:RamForceScale=$scale;$script:RamDpiScale=$null
            $Global:RamForceWorkArea=[pscustomobject]@{Width=[int](1600*$scale);Height=[int](1200*$scale)}
            foreach($style in @('water','classic','wide')) {
                $script:Settings=Get-RamDefaultSettings
                $script:Settings.UiLanguage=$language;$script:Settings.MenuStyle=$style
                Set-RamTheme -Name dark | Out-Null
                $script:UI=@{};$script:Cards=@{}
                $form=New-RamMainForm
                try {
                    foreach($v in $script:UI.Values){if($v -is [Windows.Forms.Timer]){$v.Stop()}}
                    Assert-Twins ($null -ne $script:UI.BtnTwinks) "Alts button missing: $style"
                    foreach($width in @($form.MinimumSize.Width,[int](1400*$scale))) {
                        $form.Width=$width
                        Show-RamSection -Key accounts
                        Update-RamAfterResize -Force
                        $button=$script:UI.BtnTwinks
                        Assert-Twins ($button.Left -ge 0 -and $button.Right -le $button.Parent.ClientSize.Width -and $button.Top -ge 0 -and $button.Bottom -le $button.Parent.ClientSize.Height) "Alts button outside parent: $style/$language/$scale/$width"
                        foreach($sibling in $button.Parent.Controls) {
                            if($sibling -eq $button -or $sibling -isnot [Windows.Forms.Button]){continue}
                            Assert-Twins (-not $button.Bounds.IntersectsWith($sibling.Bounds)) "Alts button overlaps $($sibling.Text): $style/$language/$scale/$width"
                        }
                    }
                    "PASS: $style/$language/DPI$([int](100*$scale)) Alts button fits minimum and wide toolbar"
                } finally {Dispose-RamFormRuntime;$form.Dispose()}
            }
        }
    }
} finally {$Global:RamForceScale=$null;$Global:RamForceWorkArea=$null}
if(-not $NoPause){[void](Read-Host 'Enter')}
