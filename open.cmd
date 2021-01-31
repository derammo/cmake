@echo off
call cmake\make.cmd
for /R %%i in (Windows\*.sln) DO echo opening %%i
for /R %%i in (Windows\*.sln) DO start %%i
