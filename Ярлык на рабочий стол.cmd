@echo off
rem ---------------------------------------------------------------------------
rem  Sozdayot yarlyk "AltHub" na rabochem stole.
rem  Yarlyk ukazyvaet na AltHub.vbs — zapusk bez okna konsoli.
rem  Ikonka beryotsya iz data\althub.ico, kotoruyu AltHub risuet sam pri
rem  pervom zapuske. Esli eyo poka net — yarlyk prosto budet s obychnoy ikonkoy.
rem ---------------------------------------------------------------------------
cd /d "%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
  "$here = (Get-Location).Path;" ^
  "$target = Join-Path $here 'AltHub.vbs';" ^
  "if (-not (Test-Path -LiteralPath $target)) { Write-Host 'Ne nashyol AltHub.vbs ryadom.' -ForegroundColor Red; exit 1 };" ^
  "$ico = Join-Path $here 'data\althub.ico';" ^
  "$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'AltHub.lnk';" ^
  "$sh = New-Object -ComObject WScript.Shell;" ^
  "$s = $sh.CreateShortcut($lnk);" ^
  "$s.TargetPath = 'wscript.exe';" ^
  "$s.Arguments = '\"' + $target + '\"';" ^
  "$s.WorkingDirectory = $here;" ^
  "$s.Description = 'AltHub - menedzher akkauntov Roblox';" ^
  "if (Test-Path -LiteralPath $ico) { $s.IconLocation = $ico };" ^
  "$s.Save();" ^
  "Write-Host ('Gotovo: ' + $lnk) -ForegroundColor Green"

echo.
pause
