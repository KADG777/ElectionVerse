@echo off
setlocal
set "ENGINE=%~dp0engine\Godot.exe"
if not exist "%ENGINE%" set "ENGINE=D:\godot\Godot_v4.7.2-stable_win64.exe"
start "ElectionVerse Editor" "%ENGINE%" --editor --path "%~dp0."
