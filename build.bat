@echo off
rem Build websolver.exe
rem The solver core is optimized separately: dmd -O hits a false "null dereference" error in ae's JSON code.
cd /d "%~dp0"
dmd -c -m64 -O -release -inline -I. localscores.d -oflocalscores.obj || exit /b 1
dmd -lowmem -m64 -release -i=-localscores -I. websolver.d localscores.obj ssl.lib crypto.lib -ofwebsolver.exe || exit /b 1
echo OK
