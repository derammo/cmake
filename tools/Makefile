# fetch LLVM's own release build of clang-format or clang-tidy, at the version
# the lint templates are written for, into ~/.local/bin; run by hand from the
# project root when configure reports the tool missing or of another major:
#
#   make -C cmake/tools               both tools, from one download
#   make -C cmake/tools clang-format
#   make -C cmake/tools clang-tidy
#
# each run downloads the whole LLVM toolchain for this host (1.5 to 2 GB) once
# and installs only the tools asked for; DERAMMO_LLVM_TMP in the environment
# names the directory to download into instead of the system's temporary
# directory
.PHONY: all clang-format clang-tidy

all:
	cmake -DDERAMMO_LLVM_TOOL=all -P fetch_llvm_tool.cmake

clang-format clang-tidy:
	cmake -DDERAMMO_LLVM_TOOL=$@ -P fetch_llvm_tool.cmake
