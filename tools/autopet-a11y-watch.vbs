' Silent entry point for the AutoPet accessibility watchdog.
' WScript starts the PowerShell watchdog with a hidden window so nothing flashes at logon.
Option Explicit

Dim fso, shell, baseDir, cmd
Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

baseDir = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ _
      & baseDir & "\autopet-a11y-watch.ps1"""

' 0 = hidden window, False = do not wait
shell.Run cmd, 0, False
