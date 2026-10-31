@echo off
REM fetch LLVM's own release build of clang-format into %LOCALAPPDATA%\derammo\bin, run from the project root as cmake\tools\clang-format.cmd
cmake -DDERAMMO_LLVM_TOOL=clang-format -P "%~dp0fetch_llvm_tool.cmake"
