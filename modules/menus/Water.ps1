#requires -Version 5.1
function Get-RamWaterMenuStyle {
    <#
      Layout       — какой вариант раскладки строит окно: classic или water.
      MaxColumns   — сколько карточек может встать в ряд.
      MinCardWidth — уже этой ширины (в точках при 100%) карточка не бывает;
                     из неё считается, сколько колонок помещается.
      BaseContent  — стартовая ширина содержимого окна при первом запуске.
    #>
    [pscustomobject]@{
        Key='water'; Title='H₂O Original'; Description='Авторская раскладка H₂O: боковые действия и рисованные иконки.'
        Layout='water'; MaxColumns=2; MinCardWidth=560; BaseContent=760; NavPrefix='  '
    }
}
