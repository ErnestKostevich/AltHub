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

cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File """ & script & """"

' 0 — окно не показывать вообще, False — не ждать завершения
shell.Run cmd, 0, False
