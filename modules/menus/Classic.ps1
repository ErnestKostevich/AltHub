#requires -Version 5.1
function Get-RamClassicMenuStyle {
    <#
      Layout       — какой вариант раскладки строит окно: classic или water.
      MaxColumns   — сколько карточек может встать в ряд.
      MinCardWidth — уже этой ширины (в точках при 100%) карточка не бывает;
                     из неё считается, сколько колонок помещается.
      BaseContent  — стартовая ширина содержимого окна при первом запуске.
    #>
    [pscustomobject]@{
        Key='classic'; Title='Pulse'; Description='Компактный рабочий список: быстрые действия, минимум шума, без иконок H₂O.'
        Layout='classic'; MaxColumns=1; MinCardWidth=560; BaseContent=800; NavPrefix='   '
    }
}
