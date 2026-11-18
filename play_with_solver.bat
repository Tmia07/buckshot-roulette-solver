@echo off
rem Starts the solver server and Buckshot Roulette with the solver bridge (single-player only).
rem The original game exe is not modified: the patched game data is loaded with --main-pack.
rem Steam must be running. See bridge\README.md for building the PCK.

rem --- Adjust these paths ---
set PHP=php.exe
set GAME=C:\Program Files (x86)\Steam\steamapps\common\Buckshot Roulette\Buckshot Roulette_windows
rem ---------------------------

set SOLVER=%~dp0

rem Start the solver server unless something already listens on port 8000
netstat -ano | findstr /R /C:":8000 .*LISTENING" >nul
if errorlevel 1 (
	start "Solver server" /min "%PHP%" -S 127.0.0.1:8000 -t "%SOLVER%."
)

start "" "http://127.0.0.1:8000"

cd /d "%GAME%"
start "" "Buckshot Roulette.exe" --main-pack "Buckshot Roulette (solver).pck"
