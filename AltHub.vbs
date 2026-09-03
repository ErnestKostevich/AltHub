' ============================================================================
'  AltHub.vbs — запуск без чёрного окна
' ============================================================================
'  Обычный текстовый файл, открой блокнотом и прочитай: три строки.
'
'  Зачем он нужен. Запустить.cmd открывает окно консоли, и оно успевает
'  мигнуть, а иногда и остаётся висеть в панели задач второй иконкой. Здесь
'  PowerShell стартует с режимом окна 0 — то есть вообще не показывается.
'
'  Ничего не скачивает и не устанавливает. Запускает ровно один файл:
'  AltHub.ps1, лежащий рядом.
' ============================================================================

Option Explicit

Dim shell, fso, here, script, cmd

Set shell = CreateObject("WScript.Shell")
Set fso   = CreateObject("Scripting.FileSystemObject")

' Папка, где лежит этот файл
here   = fso.GetParentFolderName(WScript.ScriptFullName)
script = fso.BuildPath(here, "AltHub.ps1")

If Not fso.FileExists(script) Then
    MsgBox "Рядом с этим файлом нет AltHub.ps1." & vbCrLf & vbCrLf & _
           "Распакуй архив целиком, не по одному файлу.", _
           vbExclamation, "AltHub"
    WScript.Quit 1
End If

' -WindowStyle Hidden прячет консоль сам PowerShell, изнутри процесса.
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """ & script & """"

' ВНИМАНИЕ, ЗДЕСЬ БЫЛ БАГ. Раньше вторым доводом стоял 0 — «не показывать
' окно вообще». Выглядит логично, но 0 попадает в STARTUPINFO запускаемого
' процесса как SW_HIDE, а WinForms применяет его к ПЕРВОМУ окну программы.
' В итоге главное окно AltHub создавалось скрытым: программа работала, но
' её нигде не было видно — со стороны это выглядело как «не запускается,
' сразу закрывается».
'
' Поэтому здесь 1 (обычный режим), а консоль прячет сам PowerShell ключом
' -WindowStyle Hidden. На окно программы это уже не влияет.
shell.Run cmd, 1, False
