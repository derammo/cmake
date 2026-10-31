# fetch clang-format, clang-tidy, or both of LLVM's pinned release from the
# llvm-project GitHub release and install them for the current user:
#
#   cmake -DDERAMMO_LLVM_TOOL=clang-tidy -P fetch_llvm_tool.cmake
#
# DERAMMO_LLVM_TOOL is clang-format, clang-tidy, or `all` for both tools from
# the one download
#
# run by hand only, through the Makefile or the .cmd wrappers beside this
# script; nothing in the build calls it
#
# the release asset for this host, which is the whole toolchain, is downloaded
# into a temporary directory (DERAMMO_LLVM_TMP, given with -D or in the
# environment, or else a new directory under the system's temporary directory)
# and checked against the sha256 recorded below, always; then against the
# provenance LLVM publishes for it: the LLVM-* tarballs carry a GitHub build
# attestation, verified with `gh attestation verify` when gh is found, and the
# Windows clang+llvm-* tarball carries a PGP signature, verified with `gpg`
# against llvm-release-keys.asc beside this script when gpg is found; a missing
# provenance tool leaves only the hash checked and says so, and any failed check
# deletes the download and stops before anything is installed
#
# only the tools are extracted and installed: into ~/.local/bin, or
# %LOCALAPPDATA%\derammo\bin on Windows; clang-tidy also gets clang's builtin
# headers (stddef.h, stdarg.h, ...), which it needs to parse any source that
# includes a standard header, installed into ~/.local/lib/clang/<major>/include,
# or %LOCALAPPDATA%\derammo\lib\clang\<major>\include on Windows; that
# directory is not this script's to replace: when it already exists, from an
# earlier run or from another install of the same major, the script stops
# before downloading anything and says what to remove by hand; on Linux
# the release binaries link LLVM's shared libraries, so the ones the tools need
# are installed into ~/.local/lib/derammo-llvm-<version>, and each tool finds
# them through an rpath set by patchelf when patchelf is found, otherwise
# through a wrapper script that sets LD_LIBRARY_PATH and runs the binary
# installed beside it as <tool>.bin
#
# the temporary directory, <DERAMMO_LLVM_TMP>/derammo-llvm-<version>-<DERAMMO_LLVM_TOOL>-<random>
# and printed when it is made, is removed when the script finishes and on every
# failure the script detects; a stop inside CMake itself, while extracting,
# reading the binary's libraries or installing, can leave it behind for a person
# to delete
cmake_minimum_required(VERSION 3.20)

# the pinned release; the templates' first lines carry its major
set(DERAMMO_LLVM_VERSION 21.1.8)
string(REGEX MATCH "^[0-9]+" DERAMMO_LLVM_MAJOR "${DERAMMO_LLVM_VERSION}")

if(NOT DERAMMO_LLVM_TOOL MATCHES "^(clang-format|clang-tidy|all)$")
	message(FATAL_ERROR "fetch_llvm_tool: DERAMMO_LLVM_TOOL must be clang-format, clang-tidy or all, not '${DERAMMO_LLVM_TOOL}'")
endif()
if(DERAMMO_LLVM_TOOL STREQUAL "all")
	set(DERAMMO_LLVM_TOOLS clang-format clang-tidy)
else()
	set(DERAMMO_LLVM_TOOLS ${DERAMMO_LLVM_TOOL})
endif()

set(DERAMMO_LLVM_TAG "llvmorg-${DERAMMO_LLVM_VERSION}")
set(DERAMMO_LLVM_RELEASE_URL "https://github.com/llvm/llvm-project/releases/download/${DERAMMO_LLVM_TAG}")

# the host; CMAKE_HOST_SYSTEM_PROCESSOR is empty in script mode, so the
# processor is asked of the system instead
set(DERAMMO_LLVM_HOST_SYSTEM "${CMAKE_HOST_SYSTEM_NAME}")
set(DERAMMO_LLVM_HOST_PROCESSOR "${CMAKE_HOST_SYSTEM_PROCESSOR}")
if(DERAMMO_LLVM_HOST_PROCESSOR STREQUAL "")
	cmake_host_system_information(RESULT DERAMMO_LLVM_HOST_PROCESSOR QUERY OS_PLATFORM)
endif()
string(TOLOWER "${DERAMMO_LLVM_HOST_PROCESSOR}" DERAMMO_LLVM_HOST_PROCESSOR)

# per host: the release asset and its sha256, taken from the per-asset digest
# of the GitHub release API for llvmorg-21.1.8; LLVM publishes no macOS x86_64
# binary for this release
set(DERAMMO_LLVM_ASSET "")
if(DERAMMO_LLVM_HOST_SYSTEM STREQUAL "Darwin" AND DERAMMO_LLVM_HOST_PROCESSOR MATCHES "^(arm64|aarch64)$")
	set(DERAMMO_LLVM_ASSET "LLVM-${DERAMMO_LLVM_VERSION}-macOS-ARM64.tar.xz")
	set(DERAMMO_LLVM_SHA256 b95bdd32a33a81ee4d40363aaeb26728a26783fcef26a4d80f65457433ea4669)
elseif(DERAMMO_LLVM_HOST_SYSTEM STREQUAL "Linux" AND DERAMMO_LLVM_HOST_PROCESSOR MATCHES "^(x86_64|amd64)$")
	set(DERAMMO_LLVM_ASSET "LLVM-${DERAMMO_LLVM_VERSION}-Linux-X64.tar.xz")
	set(DERAMMO_LLVM_SHA256 b3b7f2801d15d50736acea3c73982994d025b01c2f035b91ae3b49d1b575732b)
elseif(DERAMMO_LLVM_HOST_SYSTEM STREQUAL "Linux" AND DERAMMO_LLVM_HOST_PROCESSOR MATCHES "^(aarch64|arm64)$")
	set(DERAMMO_LLVM_ASSET "LLVM-${DERAMMO_LLVM_VERSION}-Linux-ARM64.tar.xz")
	set(DERAMMO_LLVM_SHA256 65ce0b329514e5643407db2d02a5bd34bf33d159055dafa82825c8385bd01993)
elseif(DERAMMO_LLVM_HOST_SYSTEM STREQUAL "Windows" AND DERAMMO_LLVM_HOST_PROCESSOR MATCHES "^(amd64|x86_64)$")
	set(DERAMMO_LLVM_ASSET "clang+llvm-${DERAMMO_LLVM_VERSION}-x86_64-pc-windows-msvc.tar.xz")
	set(DERAMMO_LLVM_SHA256 749d22f565fcd5718dbed06512572d0e5353b502c03fe1f7f17ee8b8aca21a47)
endif()

# the install directory, and how the source-build instructions name it and
# the built tool
if(DERAMMO_LLVM_HOST_SYSTEM STREQUAL "Windows")
	set(DERAMMO_LLVM_EXE ".exe")
	file(TO_CMAKE_PATH "$ENV{LOCALAPPDATA}/derammo/bin" DERAMMO_LLVM_BIN_DIR)
	file(TO_CMAKE_PATH "$ENV{LOCALAPPDATA}/derammo/lib" DERAMMO_LLVM_USER_LIB_DIR)
	set(DERAMMO_LLVM_BIN_DIR_SHOWN "%LOCALAPPDATA%\\derammo\\bin")
	set(DERAMMO_LLVM_BUILT_PREFIX "llvm-build\\Release\\bin\\")
else()
	set(DERAMMO_LLVM_EXE "")
	set(DERAMMO_LLVM_BIN_DIR "$ENV{HOME}/.local/bin")
	set(DERAMMO_LLVM_USER_LIB_DIR "$ENV{HOME}/.local/lib")
	set(DERAMMO_LLVM_BIN_DIR_SHOWN "~/.local/bin")
	set(DERAMMO_LLVM_BUILT_PREFIX "llvm-build/bin/")
endif()
list(TRANSFORM DERAMMO_LLVM_TOOLS PREPEND "${DERAMMO_LLVM_BUILT_PREFIX}" OUTPUT_VARIABLE DERAMMO_LLVM_BUILT_SHOWN)
list(TRANSFORM DERAMMO_LLVM_BUILT_SHOWN APPEND "${DERAMMO_LLVM_EXE}")
list(JOIN DERAMMO_LLVM_BUILT_SHOWN " and " DERAMMO_LLVM_BUILT_SHOWN)
list(JOIN DERAMMO_LLVM_TOOLS " " DERAMMO_LLVM_TARGETS_SHOWN)
list(JOIN DERAMMO_LLVM_TOOLS " and " DERAMMO_LLVM_TOOLS_SHOWN)

if(DERAMMO_LLVM_ASSET STREQUAL "")
	message(FATAL_ERROR
		"fetch_llvm_tool: LLVM publishes no ${DERAMMO_LLVM_VERSION} binary for "
		"${DERAMMO_LLVM_HOST_SYSTEM} ${DERAMMO_LLVM_HOST_PROCESSOR}; build "
		"${DERAMMO_LLVM_TOOLS_SHOWN} from source at the release tag instead:\n"
		"  git clone --depth 1 --branch ${DERAMMO_LLVM_TAG} https://github.com/llvm/llvm-project.git\n"
		"  cmake -S llvm-project/llvm -B llvm-build -DCMAKE_BUILD_TYPE=Release -DLLVM_ENABLE_PROJECTS=\"clang;clang-tools-extra\"\n"
		"  cmake --build llvm-build --config Release --target ${DERAMMO_LLVM_TARGETS_SHOWN}\n"
		"then copy ${DERAMMO_LLVM_BUILT_SHOWN} into ${DERAMMO_LLVM_BIN_DIR_SHOWN}. The "
		"checkout is about 2 GB; the build needs about 20 GB of disk and takes "
		"an hour or more on an 8-core machine.")
endif()

# the asset's top-level directory, which holds bin/ and lib/
string(REGEX REPLACE "\\.tar\\.xz$" "" DERAMMO_LLVM_TOP "${DERAMMO_LLVM_ASSET}")
# the asset's name in its URL, with + escaped
string(REPLACE "+" "%2B" DERAMMO_LLVM_ASSET_URL "${DERAMMO_LLVM_RELEASE_URL}/${DERAMMO_LLVM_ASSET}")

set(DERAMMO_LLVM_LIB_DIR "$ENV{HOME}/.local/lib/derammo-llvm-${DERAMMO_LLVM_VERSION}")

# clang's builtin headers, at the place clang-tidy looks for them: it derives
# its resource directory from its own executable's path, as
# <bin>/../lib/clang/<major>, so with the headers installed there nothing else
# needs to name them; the Linux wrapper's <tool>.bin sits in the same bin
# directory and finds them the same way
set(DERAMMO_LLVM_RESOURCE_INCLUDE "lib/clang/${DERAMMO_LLVM_MAJOR}/include")
set(DERAMMO_LLVM_RESOURCE_INCLUDE_DIR "${DERAMMO_LLVM_USER_LIB_DIR}/clang/${DERAMMO_LLVM_MAJOR}/include")
if("clang-tidy" IN_LIST DERAMMO_LLVM_TOOLS AND EXISTS "${DERAMMO_LLVM_RESOURCE_INCLUDE_DIR}")
	message(FATAL_ERROR
		"fetch_llvm_tool: ${DERAMMO_LLVM_RESOURCE_INCLUDE_DIR} already exists, so clang "
		"${DERAMMO_LLVM_MAJOR} is installed there already, by an earlier run of this script "
		"or by something else; this script replaces nothing it did not just install. "
		"Remove that directory yourself if it is to be replaced, then run again.")
endif()

# the temporary directory, new and empty, removed when the script finishes and
# on every failure it detects; a stop inside CMake itself leaves it behind,
# which is why its path is printed
if(NOT DEFINED DERAMMO_LLVM_TMP)
	set(DERAMMO_LLVM_TMP "$ENV{DERAMMO_LLVM_TMP}")
endif()
if(DERAMMO_LLVM_TMP STREQUAL "")
	foreach(DERAMMO_LLVM_TMP_VARIABLE TMPDIR TEMP TMP)
		if(NOT "$ENV{${DERAMMO_LLVM_TMP_VARIABLE}}" STREQUAL "")
			set(DERAMMO_LLVM_TMP "$ENV{${DERAMMO_LLVM_TMP_VARIABLE}}")
			break()
		endif()
	endforeach()
	if(DERAMMO_LLVM_TMP STREQUAL "")
		set(DERAMMO_LLVM_TMP "/tmp")
	endif()
endif()
file(TO_CMAKE_PATH "${DERAMMO_LLVM_TMP}" DERAMMO_LLVM_TMP)
string(RANDOM LENGTH 8 DERAMMO_LLVM_RANDOM)
set(DERAMMO_LLVM_WORK "${DERAMMO_LLVM_TMP}/derammo-llvm-${DERAMMO_LLVM_VERSION}-${DERAMMO_LLVM_TOOL}-${DERAMMO_LLVM_RANDOM}")
file(REMOVE_RECURSE "${DERAMMO_LLVM_WORK}")
file(MAKE_DIRECTORY "${DERAMMO_LLVM_WORK}")
message(STATUS "working in ${DERAMMO_LLVM_WORK}")
set(DERAMMO_LLVM_DOWNLOAD "${DERAMMO_LLVM_WORK}/${DERAMMO_LLVM_ASSET}")

# remove the temporary directory, with the download in it, and stop
function(derammo_llvm_fail DERAMMO_LLVM_MESSAGE)
	file(REMOVE_RECURSE "${DERAMMO_LLVM_WORK}")
	message(FATAL_ERROR "fetch_llvm_tool: ${DERAMMO_LLVM_MESSAGE}")
endfunction()

# download URL into the file PATH, stopping on failure
function(derammo_llvm_download URL PATH)
	message(STATUS "downloading ${URL}")
	# TLS is verified whatever CMake's default for the version; a transfer
	# that stalls for a minute fails instead of hanging
	file(DOWNLOAD "${URL}" "${PATH}" SHOW_PROGRESS STATUS DERAMMO_LLVM_STATUS
		TLS_VERIFY ON INACTIVITY_TIMEOUT 60)
	list(GET DERAMMO_LLVM_STATUS 0 DERAMMO_LLVM_CODE)
	if(NOT DERAMMO_LLVM_CODE EQUAL 0)
		list(GET DERAMMO_LLVM_STATUS 1 DERAMMO_LLVM_REASON)
		derammo_llvm_fail("downloading ${URL} failed: ${DERAMMO_LLVM_REASON}")
	endif()
endfunction()

# the asset and its sha256, checked here rather than with EXPECTED_HASH, which
# stops the script with the mismatching download still in place
derammo_llvm_download("${DERAMMO_LLVM_ASSET_URL}" "${DERAMMO_LLVM_DOWNLOAD}")
file(SHA256 "${DERAMMO_LLVM_DOWNLOAD}" DERAMMO_LLVM_ACTUAL_SHA256)
if(NOT DERAMMO_LLVM_ACTUAL_SHA256 STREQUAL DERAMMO_LLVM_SHA256)
	derammo_llvm_fail("${DERAMMO_LLVM_ASSET} has sha256 ${DERAMMO_LLVM_ACTUAL_SHA256}, expected ${DERAMMO_LLVM_SHA256}; the download was deleted")
endif()
message(STATUS "sha256 verified: ${DERAMMO_LLVM_SHA256}")

# provenance
if(DERAMMO_LLVM_ASSET MATCHES "^LLVM-")
	find_program(DERAMMO_LLVM_GH NAMES gh)
	if(DERAMMO_LLVM_GH)
		derammo_llvm_download("${DERAMMO_LLVM_ASSET_URL}.jsonl" "${DERAMMO_LLVM_DOWNLOAD}.jsonl")
		execute_process(
			COMMAND "${DERAMMO_LLVM_GH}" attestation verify "${DERAMMO_LLVM_DOWNLOAD}"
				--owner llvm --bundle "${DERAMMO_LLVM_DOWNLOAD}.jsonl"
			RESULT_VARIABLE DERAMMO_LLVM_RESULT
		)
		if(NOT DERAMMO_LLVM_RESULT EQUAL 0)
			derammo_llvm_fail("gh attestation verify rejected ${DERAMMO_LLVM_ASSET}; the download was deleted")
		endif()
		message(STATUS "GitHub build attestation verified")
	else()
		message(NOTICE "gh not found: the build attestation of ${DERAMMO_LLVM_ASSET} was not verified, only its sha256")
	endif()
else()
	find_program(DERAMMO_LLVM_GPG NAMES gpg gpg2)
	if(DERAMMO_LLVM_GPG)
		derammo_llvm_download("${DERAMMO_LLVM_ASSET_URL}.sig" "${DERAMMO_LLVM_DOWNLOAD}.sig")
		# a keyring of only LLVM's release keys, in the temporary directory
		set(DERAMMO_LLVM_GNUPGHOME "${DERAMMO_LLVM_WORK}/gnupg")
		file(MAKE_DIRECTORY "${DERAMMO_LLVM_GNUPGHOME}")
		execute_process(
			COMMAND "${DERAMMO_LLVM_GPG}" --batch --homedir "${DERAMMO_LLVM_GNUPGHOME}"
				--import "${CMAKE_CURRENT_LIST_DIR}/llvm-release-keys.asc"
			RESULT_VARIABLE DERAMMO_LLVM_RESULT
		)
		if(NOT DERAMMO_LLVM_RESULT EQUAL 0)
			derammo_llvm_fail("gpg could not import llvm-release-keys.asc")
		endif()
		execute_process(
			COMMAND "${DERAMMO_LLVM_GPG}" --batch --homedir "${DERAMMO_LLVM_GNUPGHOME}"
				--verify "${DERAMMO_LLVM_DOWNLOAD}.sig" "${DERAMMO_LLVM_DOWNLOAD}"
			RESULT_VARIABLE DERAMMO_LLVM_RESULT
		)
		if(NOT DERAMMO_LLVM_RESULT EQUAL 0)
			derammo_llvm_fail("gpg rejected the signature of ${DERAMMO_LLVM_ASSET}; the download was deleted")
		endif()
		message(STATUS "PGP signature verified")
	else()
		message(NOTICE "gpg not found: the signature of ${DERAMMO_LLVM_ASSET} was not verified, only its sha256")
	endif()
endif()

# extract the tools, clang's builtin headers for clang-tidy, and on Linux every
# shared library a tool could link
set(DERAMMO_LLVM_PATTERNS "")
foreach(DERAMMO_LLVM_ONE IN LISTS DERAMMO_LLVM_TOOLS)
	list(APPEND DERAMMO_LLVM_PATTERNS "${DERAMMO_LLVM_TOP}/bin/${DERAMMO_LLVM_ONE}${DERAMMO_LLVM_EXE}")
endforeach()
if("clang-tidy" IN_LIST DERAMMO_LLVM_TOOLS)
	list(APPEND DERAMMO_LLVM_PATTERNS "${DERAMMO_LLVM_TOP}/${DERAMMO_LLVM_RESOURCE_INCLUDE}/*")
endif()
if(DERAMMO_LLVM_HOST_SYSTEM STREQUAL "Linux")
	list(APPEND DERAMMO_LLVM_PATTERNS
		"${DERAMMO_LLVM_TOP}/lib/libclang-cpp.so*"
		"${DERAMMO_LLVM_TOP}/lib/libLLVM*.so*")
endif()
set(DERAMMO_LLVM_EXTRACTED "${DERAMMO_LLVM_WORK}/extracted")
message(STATUS "extracting ${DERAMMO_LLVM_TOOLS_SHOWN}")
file(ARCHIVE_EXTRACT INPUT "${DERAMMO_LLVM_DOWNLOAD}" DESTINATION "${DERAMMO_LLVM_EXTRACTED}" PATTERNS ${DERAMMO_LLVM_PATTERNS})
file(REMOVE "${DERAMMO_LLVM_DOWNLOAD}")
set(DERAMMO_LLVM_EXTRACTED_BIN "${DERAMMO_LLVM_EXTRACTED}/${DERAMMO_LLVM_TOP}/bin")
set(DERAMMO_LLVM_BINARIES "")
foreach(DERAMMO_LLVM_ONE IN LISTS DERAMMO_LLVM_TOOLS)
	set(DERAMMO_LLVM_BINARY "${DERAMMO_LLVM_EXTRACTED_BIN}/${DERAMMO_LLVM_ONE}${DERAMMO_LLVM_EXE}")
	if(NOT EXISTS "${DERAMMO_LLVM_BINARY}")
		derammo_llvm_fail("${DERAMMO_LLVM_ASSET} holds no bin/${DERAMMO_LLVM_ONE}${DERAMMO_LLVM_EXE}")
	endif()
	list(APPEND DERAMMO_LLVM_BINARIES "${DERAMMO_LLVM_BINARY}")
endforeach()
set(DERAMMO_LLVM_RESOURCE_EXTRACTED "${DERAMMO_LLVM_EXTRACTED}/${DERAMMO_LLVM_TOP}/${DERAMMO_LLVM_RESOURCE_INCLUDE}")
if("clang-tidy" IN_LIST DERAMMO_LLVM_TOOLS AND NOT EXISTS "${DERAMMO_LLVM_RESOURCE_EXTRACTED}/stddef.h")
	derammo_llvm_fail("${DERAMMO_LLVM_ASSET} holds no ${DERAMMO_LLVM_RESOURCE_INCLUDE}/stddef.h")
endif()

set(DERAMMO_LLVM_PERMISSIONS
	OWNER_READ OWNER_WRITE OWNER_EXECUTE
	GROUP_READ GROUP_EXECUTE
	WORLD_READ WORLD_EXECUTE)
file(MAKE_DIRECTORY "${DERAMMO_LLVM_BIN_DIR}")

set(DERAMMO_LLVM_LIBRARIES "")
if(DERAMMO_LLVM_HOST_SYSTEM STREQUAL "Linux")
	# the LLVM shared libraries the binaries need, read from their dynamic
	# sections and found among the extracted ones; CMake reads an ELF binary
	# with objdump, so objdump (binutils) must be installed, and without it
	# CMake stops here with an error and leaves the temporary directory
	# behind; the host libraries the release binaries link beyond LLVM's own
	# (libzstd, libxml2, libedit and the like) are expected from the platform,
	# and the --version run at the end shows when one is absent
	file(GET_RUNTIME_DEPENDENCIES
		EXECUTABLES ${DERAMMO_LLVM_BINARIES}
		RESOLVED_DEPENDENCIES_VAR DERAMMO_LLVM_LIBRARIES
		UNRESOLVED_DEPENDENCIES_VAR DERAMMO_LLVM_UNRESOLVED
		DIRECTORIES "${DERAMMO_LLVM_EXTRACTED}/${DERAMMO_LLVM_TOP}/lib"
		PRE_INCLUDE_REGEXES "^lib(clang-cpp|LLVM)"
		PRE_EXCLUDE_REGEXES ".*"
	)
	if(DERAMMO_LLVM_UNRESOLVED)
		derammo_llvm_fail("${DERAMMO_LLVM_TOOLS_SHOWN} need ${DERAMMO_LLVM_UNRESOLVED}, which ${DERAMMO_LLVM_ASSET} does not hold")
	endif()
	if(DERAMMO_LLVM_LIBRARIES)
		file(MAKE_DIRECTORY "${DERAMMO_LLVM_LIB_DIR}")
		foreach(DERAMMO_LLVM_LIBRARY IN LISTS DERAMMO_LLVM_LIBRARIES)
			# the file under the name the binary asks for, which in the
			# archive may be a symbolic link to it
			get_filename_component(DERAMMO_LLVM_LIBRARY_NAME "${DERAMMO_LLVM_LIBRARY}" NAME)
			file(REAL_PATH "${DERAMMO_LLVM_LIBRARY}" DERAMMO_LLVM_LIBRARY_FILE)
			file(INSTALL "${DERAMMO_LLVM_LIBRARY_FILE}" DESTINATION "${DERAMMO_LLVM_LIB_DIR}"
				RENAME "${DERAMMO_LLVM_LIBRARY_NAME}"
				FILE_PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ)
		endforeach()
		find_program(DERAMMO_LLVM_PATCHELF NAMES patchelf)
	endif()
endif()

foreach(DERAMMO_LLVM_ONE IN LISTS DERAMMO_LLVM_TOOLS)
	set(DERAMMO_LLVM_BINARY "${DERAMMO_LLVM_EXTRACTED_BIN}/${DERAMMO_LLVM_ONE}${DERAMMO_LLVM_EXE}")
	set(DERAMMO_LLVM_INSTALLED "${DERAMMO_LLVM_BIN_DIR}/${DERAMMO_LLVM_ONE}${DERAMMO_LLVM_EXE}")
	if(DERAMMO_LLVM_LIBRARIES AND DERAMMO_LLVM_PATCHELF)
		# the binary itself, with its rpath pointed at the libraries
		execute_process(
			COMMAND "${DERAMMO_LLVM_PATCHELF}" --set-rpath "${DERAMMO_LLVM_LIB_DIR}" "${DERAMMO_LLVM_BINARY}"
			RESULT_VARIABLE DERAMMO_LLVM_RESULT
		)
		if(NOT DERAMMO_LLVM_RESULT EQUAL 0)
			derammo_llvm_fail("patchelf could not set the rpath of ${DERAMMO_LLVM_ONE}")
		endif()
		file(REMOVE "${DERAMMO_LLVM_INSTALLED}.bin")
		file(INSTALL "${DERAMMO_LLVM_BINARY}" DESTINATION "${DERAMMO_LLVM_BIN_DIR}"
			FILE_PERMISSIONS ${DERAMMO_LLVM_PERMISSIONS})
		message(STATUS "rpath of ${DERAMMO_LLVM_INSTALLED} set to ${DERAMMO_LLVM_LIB_DIR} with patchelf")
	elseif(DERAMMO_LLVM_LIBRARIES)
		# the binary as <tool>.bin, run by a wrapper of the tool's name that
		# points LD_LIBRARY_PATH at the libraries
		file(INSTALL "${DERAMMO_LLVM_BINARY}" DESTINATION "${DERAMMO_LLVM_BIN_DIR}"
			RENAME "${DERAMMO_LLVM_ONE}.bin"
			FILE_PERMISSIONS ${DERAMMO_LLVM_PERMISSIONS})
		file(WRITE "${DERAMMO_LLVM_WORK}/${DERAMMO_LLVM_ONE}"
			"#!/bin/sh\n"
			"export LD_LIBRARY_PATH=\"${DERAMMO_LLVM_LIB_DIR}\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}\"\n"
			"exec \"${DERAMMO_LLVM_INSTALLED}.bin\" \"\$@\"\n")
		file(INSTALL "${DERAMMO_LLVM_WORK}/${DERAMMO_LLVM_ONE}" DESTINATION "${DERAMMO_LLVM_BIN_DIR}"
			FILE_PERMISSIONS ${DERAMMO_LLVM_PERMISSIONS})
		message(STATUS "patchelf not found: ${DERAMMO_LLVM_INSTALLED} is a wrapper setting LD_LIBRARY_PATH to ${DERAMMO_LLVM_LIB_DIR}")
	else()
		# a binary that links no LLVM shared library, as on macOS and Windows;
		# the .bin of an earlier wrapper install is removed
		if(DERAMMO_LLVM_HOST_SYSTEM STREQUAL "Linux")
			file(REMOVE "${DERAMMO_LLVM_INSTALLED}.bin")
		endif()
		file(INSTALL "${DERAMMO_LLVM_BINARY}" DESTINATION "${DERAMMO_LLVM_BIN_DIR}"
			FILE_PERMISSIONS ${DERAMMO_LLVM_PERMISSIONS})
	endif()
endforeach()

if("clang-tidy" IN_LIST DERAMMO_LLVM_TOOLS)
	# checked absent above, before the download
	file(MAKE_DIRECTORY "${DERAMMO_LLVM_RESOURCE_INCLUDE_DIR}")
	file(INSTALL "${DERAMMO_LLVM_RESOURCE_EXTRACTED}/" DESTINATION "${DERAMMO_LLVM_RESOURCE_INCLUDE_DIR}" MESSAGE_NEVER
		FILE_PERMISSIONS OWNER_READ OWNER_WRITE GROUP_READ WORLD_READ)
	message(STATUS "installed clang's builtin headers into ${DERAMMO_LLVM_RESOURCE_INCLUDE_DIR}")
endif()

file(REMOVE_RECURSE "${DERAMMO_LLVM_WORK}")

foreach(DERAMMO_LLVM_ONE IN LISTS DERAMMO_LLVM_TOOLS)
	set(DERAMMO_LLVM_INSTALLED "${DERAMMO_LLVM_BIN_DIR}/${DERAMMO_LLVM_ONE}${DERAMMO_LLVM_EXE}")

	# file(INSTALL) keeps the release's timestamp, which is older than any
	# build tree; the installed tool is a make prerequisite of the generated
	# build tree, so it is given the current time for the next make to
	# reconfigure
	file(TOUCH "${DERAMMO_LLVM_INSTALLED}")

	execute_process(
		COMMAND "${DERAMMO_LLVM_INSTALLED}" --version
		OUTPUT_VARIABLE DERAMMO_LLVM_INSTALLED_VERSION
		OUTPUT_STRIP_TRAILING_WHITESPACE
		RESULT_VARIABLE DERAMMO_LLVM_RESULT
	)
	if(NOT DERAMMO_LLVM_RESULT EQUAL 0)
		message(FATAL_ERROR "fetch_llvm_tool: ${DERAMMO_LLVM_INSTALLED} --version failed with status ${DERAMMO_LLVM_RESULT}")
	endif()
	message(STATUS "installed ${DERAMMO_LLVM_INSTALLED}:\n${DERAMMO_LLVM_INSTALLED_VERSION}")
endforeach()
