@echo off
REM fetch LLVM's own release build of clang-tidy into %LOCALAPPDATA%\derammo\bin, run from the project root as cmake\tools\clang-tidy.cmd
cmake -DDERAMMO_LLVM_TOOL=clang-tidy -P "%~dp0fetch_llvm_tool.cmake"
