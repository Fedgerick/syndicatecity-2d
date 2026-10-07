@echo off
REM SyndicateCity 2D - desktop shortcut creator
REM Run once to drop a desktop icon that launches the game.
setlocal
set "PROJECT=%~dp0"
set "ENGINE=C:\Users\russe\tools\godot-4.5\Godot_v4.5-stable_win64.exe"
set "SHORTCUT=%USERPROFILE%\Desktop\Scripts\SyndicateCity.lnk"
set "WORKDIR=%PROJECT%"

REM Build a minimal .vbs that calls WshShell.CreateShortcut
set "VBS=%TEMP%\mk_sc_shortcut.vbs"
> "%VBS%" echo Set sh = CreateObject("WScript.Shell")
>>"%VBS%" echo Set lnk = sh.CreateShortcut("%SHORTCUT%")
>>"%VBS%" echo lnk.TargetPath = "%ENGINE%"
>>"%VBS%" echo lnk.Arguments = "--path ""%PROJECT%"" --rendering-method gl_compatibility --resolution 1280x720"
>>"%VBS%" echo lnk.WorkingDirectory = "%WORKDIR%"
>>"%VBS%" echo lnk.WindowStyle = "1"
>>"%VBS%" echo lnk.Description = "SyndicateCity 2D - SimCity + GTA"
>>"%VBS%" echo lnk.IconLocation = "%ENGINE%, 0"
>>"%VBS%" echo lnk.Save

cscript //nologo "%VBS%"
del "%VBS%"

if exist "%SHORTCUT%" (
  echo.
  echo   Desktop shortcut created:
  echo     %SHORTCUT%
  echo.
) else (
  echo.
  echo   Could not create shortcut. Try right-click install manually.
  echo.
)
endlocal