@echo off
rem ---------------------------------------------------------------------------
rem  Zapusk s vidimym oknom konsoli — chtoby uvidet oshibku.
rem
rem  Nuzhen odnoy veshi: esli AltHub ne otkryvaetsya ili "srazu zakryvaetsya",
rem  zapusti etot fayl. Okno konsoli ostanetsya otkrytym, i v nyom budet vidno
rem  tochnoe soobshchenie ob oshibke — ego mozhno prislat avtoru.
rem
rem  Nichego ne menyaet i nikuda ne otpravlyaet: tot zhe AltHub.ps1, prosto
rem  bez pryatanya konsoli.
rem ---------------------------------------------------------------------------
chcp 65001 >nul
cd /d "%~dp0"

echo.
echo  AltHub — запуск с показом ошибок
echo  --------------------------------------------------
echo  Папка: %~dp0
echo.

if not exist "%~dp0AltHub.ps1" (
    echo  [!] Рядом нет AltHub.ps1.
    echo      Распакуй архив целиком, не по одному файлу.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0AltHub.ps1"

echo.
echo  --------------------------------------------------
echo  Программа завершилась. Код выхода: %errorlevel%
echo.
echo  Если выше есть красный текст — это и есть причина.
echo  Пришли его автору вместе с файлом из data\logs.
echo.
pause
