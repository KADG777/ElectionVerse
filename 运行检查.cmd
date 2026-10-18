@echo off
setlocal
set "ENGINE=D:\godot\Godot_v4.7.2-stable_win64_console.exe"
if not exist "%ENGINE%" set "ENGINE=%~dp0engine\Godot.exe"
"%ENGINE%" --headless --path "%~dp0." --script res://tests/TestRunner.gd
if errorlevel 1 goto done
"%ENGINE%" --headless --path "%~dp0." --script res://tests/TestLLM.gd
:done
pause
