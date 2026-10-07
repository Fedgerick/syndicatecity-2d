@echo off
REM Launch SyndicateCity - SimCity + GTA 2D
REM Just double-click this from your desktop.
setlocal
cd /d "%~dp0"
"C:\Users\russe\tools\godot-4.5\Godot_v4.5-stable_win64.exe" --path . --rendering-method gl_compatibility --resolution 1280x720
endlocal