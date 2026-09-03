@echo off
rem ---------------------------------------------------------------------------
rem  AltHub - zapusk s vidimym oknom konsoli.
rem
rem  Nuzhen odnoy veshchi: esli AltHub ne otkryvaetsya ili "srazu zakryvaetsya",
rem  zapusti etot fayl. Okno ostanetsya otkrytym, i v nyom budet vidno tochnoe
rem  soobshchenie ob oshibke - ego mozhno prislat avtoru.
rem
rem  Nichego ne menyaet i nikuda ne otpravlyaet: tot zhe AltHub.ps1, prosto
rem  bez pryatanya konsoli.
rem ---------------------------------------------------------------------------
cd /d "%~dp0"

echo.
echo  AltHub - diagnostic start
echo  --------------------------------------------------
echo  Folder: %~dp0
echo.

if not exist "%~dp0AltHub.ps1" (
    echo  [!] AltHub.ps1 not found next to this file.
    echo      Raspakuy arhiv CELIKOM i zapuskay iz raspakovannoy papki,
    echo      a ne pryamo iz arhiva.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0AltHub.ps1"

echo.
echo  --------------------------------------------------
echo  Exit code: %errorlevel%
echo.
echo  Esli vyshe est krasnyy tekst - eto i est prichina.
echo  Prishli ego avtoru vmeste s faylom iz data\logs.
echo.
pause
