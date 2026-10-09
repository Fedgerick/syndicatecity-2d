@echo off
REM ==============================================================
REM  SyndicateCity 2D - SHOWCASE launcher
REM  Renders 4 city views (noon / dusk / night / top-down) and
REM  opens the resulting PNGs in your default viewer. Works on
REM  systems with no graphical desktop session because each
REM  frame is rendered to disk via -- --capture, then the
REM  process quits before the display server timeout.
REM ==============================================================
setlocal
set "PROJECT=%~dp0"
set "ENGINE=C:\Users\russe\tools\godot-4.5\Godot_v4.5-stable_win64_console.exe"
set "OUTDIR=%APPDATA%\Godot\app_userdata\SyndicateCity 2D"

if not exist "%ENGINE%" (
  echo   [X] Godot 4.5 not found at %ENGINE%
  pause
  exit /b 1
)

if not exist "%OUTDIR%" mkdir "%OUTDIR%"

echo.
echo   SyndicateCity 2D - Showcase
echo   ===========================
echo   Rendering 4 views...
echo.

REM View 1: noon, isometric
echo   [1/4] noon, isometric...
"%ENGINE%" --path "%PROJECT%" --rendering-method gl_compatibility --resolution 1280x720 -- --capture --start --time=0.5 > nul 2>&1
copy /y "%OUTDIR%\capture.png" "%PROJECT%\screenshots\showcase_noon.png" > nul

REM View 2: dusk, isometric
echo   [2/4] dusk, isometric...
"%ENGINE%" --path "%PROJECT%" --rendering-method gl_compatibility --resolution 1280x720 -- --capture --start --time=0.75 > nul 2>&1
copy /y "%OUTDIR%\capture.png" "%PROJECT%\screenshots\showcase_dusk.png" > nul

REM View 3: night, isometric
echo   [3/4] night, isometric...
"%ENGINE%" --path "%PROJECT%" --rendering-method gl_compatibility --resolution 1280x720 -- --capture --start --time=0.15 > nul 2>&1
copy /y "%OUTDIR%\capture.png" "%PROJECT%\screenshots\showcase_night.png" > nul

REM View 4: topdown
echo   [4/4] topdown, day...
"%ENGINE%" --path "%PROJECT%" --rendering-method gl_compatibility --resolution 1280x720 -- --capture --start --time=0.5 --topdown > nul 2>&1
copy /y "%OUTDIR%\capture.png" "%PROJECT%\screenshots\showcase_topdown.png" > nul

echo.
echo   Done. Open:
echo     %PROJECT%\screenshots\showcase_noon.png
echo     %PROJECT%\screenshots\showcase_dusk.png
echo     %PROJECT%\screenshots\showcase_night.png
echo     %PROJECT%\screenshots\showcase_topdown.png
echo.

REM Open them all in default viewer
start "" "%PROJECT%\screenshots\showcase_noon.png"
timeout /t 1 /nobreak > nul
start "" "%PROJECT%\screenshots\showcase_dusk.png"
timeout /t 1 /nobreak > nul
start "" "%PROJECT%\screenshots\showcase_night.png"
timeout /t 1 /nobreak > nul
start "" "%PROJECT%\screenshots\showcase_topdown.png"

endlocal