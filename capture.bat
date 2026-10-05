@echo off
REM ==============================================================
REM  SyndicateCity 2D - capture launcher
REM  Renders one frame via Godot 4.5's -- --capture flag and exits.
REM  Works on systems that have no graphical desktop session
REM  (display server fails when window not drawn, capture sidesteps).
REM ==============================================================
setlocal

set "PROJECT=%~dp0"
set "ENGINE=C:\Users\russe\tools\godot-4.5\Godot_v4.5-stable_win64_console.exe"

if not exist "%ENGINE%" (
  echo   [X] Godot 4.5 not found at %ENGINE%
  pause
  exit /b 1
)

"%ENGINE%" --path "%PROJECT%" --rendering-method gl_compatibility --resolution 1280x720 -- --capture

endlocal