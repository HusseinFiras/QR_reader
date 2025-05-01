Set WshShell = CreateObject("WScript.Shell")
WshShell.Run "py " & Chr(34) & WScript.Arguments(0) & Chr(34), 0, False
Set WshShell = Nothing 