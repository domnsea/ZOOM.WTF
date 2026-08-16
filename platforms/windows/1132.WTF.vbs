' 1132.WTF quiet launcher.
' Opens the app window with no console flash. This is the file a desktop
' shortcut should point at.
Option Explicit

Dim shell, fso, folder, target
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
folder = fso.GetParentFolderName(WScript.ScriptFullName)
target = folder & "\1132.WTF.bat"

If Not fso.FileExists(target) Then
    MsgBox "1132.WTF.bat is missing from:" & vbCrLf & folder & vbCrLf & vbCrLf & _
           "Keep every file in this folder together.", 16, "1132.WTF"
    WScript.Quit 1
End If

shell.Run """" & target & """", 0, False
