#requires -Version 5.1
function Get-RamWideMenuStyle {
    <#
      Layout       — какой вариант раскладки строит окно: classic, water или modern.
      Ключ остался «wide»: под ним вид уже записан в настройках у людей.
      MaxColumns   — сколько карточек может встать в ряд.
      MinCardWidth — уже этой ширины (в точках при 100%) карточка не бывает;
                     из неё считается, сколько колонок помещается.
      BaseContent  — стартовая ширина содержимого окна при первом запуске.
    #>
    [pscustomobject]@{
        Key='wide'; Title='Dashboard'; Description='Современная широкая панель: вкладки сверху и адаптивная сетка карточек.'
        Layout='modern'; MaxColumns=4; MinCardWidth=320; BaseContent=980; NavPrefix=''
    }
}
