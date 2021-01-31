@echo off
REM create build files for Windows, all other platforms use Makefile
IF exist cmake ( cmake -B Windows -A x64 ) ELSE ( echo "run from parent directory as 'cmake\make.cmd'" )