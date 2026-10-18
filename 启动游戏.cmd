@echo off
setlocal
set "ENGINE=%~dp0engine\Godot.exe"
if not exist "%ENGINE%" set "ENGINE=D:\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%ENGINE%" (
  echo Install Godot 4.7.2 or put Godot.exe inside the engine folder.
  pause
  exit /b 1
)
if not exist "%~dp0.godot\imported" (
  "%ENGINE%" --headless --editor --import --quit --path "%~dp0."
  if errorlevel 1 (
    echo Project import failed. Open project.godot in Godot to see diagnostics.
    pause
    exit /b 1
  )
)
start "ElectionVerse" "%ENGINE%" --path "%~dp0."
