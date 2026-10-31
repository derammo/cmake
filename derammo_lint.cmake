include_guard()

# code quality for every C and C++ target registered with derammo_lint_target:
# strict warnings as errors at compile time, and one ctest per file and check
# with the label `lint`
#
# the checks are switched on by tracked files at the source root, each naming
# on its first line the tool major it was written for:
#
#   .clang-format   `# clang-format <major>`   lint_format tests, `clang-format` target
#   .clang-tidy     `# clang-tidy <major>`
#
# a check whose switch file is absent, or whose tool is not found in that
# major, is disabled with a status line; with DERAMMO_LINT_REQUIRED a present
# switch file without its tool fails configure instead; a tool of another
# major is never used, since a different clang-format formats differently and
# a different clang-tidy names its checks differently
#
# lint_size tests need no tool and are always registered
#
# the files checked are the SOURCES of the registered targets, headers
# included; a C or C++ file beside a registered target that no registered
# target lists is named by a status line at configure and is not checked
#
# a file is third party when a directory segment of its path relative to the
# source root is named `thirdparty`; third party files get no tests, and a
# registered target's own `thirdparty` directory is a SYSTEM include, so the
# strict warnings do not fire in vendored headers

# clang-tidy reads the compile database; the Visual Studio and Xcode
# generators write none, so _derammo_lint_check disables tidy under those
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(DERAMMO_LINT_REQUIRED "fail configure when a lint switch file is present but its tool is missing or of another major" OFF)
option(DERAMMO_LINT_STRICT "compile registered targets with the strict warnings as errors" ON)

set(DERAMMO_LINT_MAX_LINES 200 CACHE STRING "most lines of code a production file may have")

set(DERAMMO_LINT_SIZE_SCRIPT "${CMAKE_CURRENT_LIST_DIR}/scripts/lint_size.cmake")

# file extensions that the lint set considers C or C++
set(DERAMMO_LINT_EXTENSIONS c cc cpp cxx h hh hpp)

# internal: the major version number in the output of a tool's --version, set
# in OUT_MAJOR, or empty when there is none
function(_derammo_lint_version_major DERAMMO_LINT_VERSION OUT_MAJOR)
	if(DERAMMO_LINT_VERSION MATCHES "version ([0-9]+)\\.")
		set(${OUT_MAJOR} "${CMAKE_MATCH_1}" PARENT_SCOPE)
	else()
		set(${OUT_MAJOR} "" PARENT_SCOPE)
	endif()
endfunction()

# internal: run the candidate DERAMMO_LINT_CANDIDATE for _derammo_lint_find_tool
# unless it was run already, and record it in the caller's variables: a
# candidate whose major is DERAMMO_LINT_MAJOR in DERAMMO_LINT_MATCH_PATH and
# DERAMMO_LINT_MATCH_VERSION, the first other candidate that reports a version
# in DERAMMO_LINT_FIRST_PATH and DERAMMO_LINT_FIRST_VERSION
macro(_derammo_lint_probe_candidate DERAMMO_LINT_CANDIDATE)
	if(NOT "${DERAMMO_LINT_CANDIDATE}" IN_LIST DERAMMO_LINT_PROBED)
		list(APPEND DERAMMO_LINT_PROBED "${DERAMMO_LINT_CANDIDATE}")
		set(DERAMMO_LINT_OUTPUT "")
		execute_process(
			COMMAND "${DERAMMO_LINT_CANDIDATE}" --version
			OUTPUT_VARIABLE DERAMMO_LINT_OUTPUT
			ERROR_QUIET
			TIMEOUT 10
		)
		# clang-format prints its version on the only line, clang-tidy on the
		# second, after a line naming LLVM's home page
		if(DERAMMO_LINT_OUTPUT MATCHES "[^\n]*version [0-9]+\\.[^\n]*")
			string(STRIP "${CMAKE_MATCH_0}" DERAMMO_LINT_VERSION)
			_derammo_lint_version_major("${DERAMMO_LINT_VERSION}" DERAMMO_LINT_FOUND_MAJOR)
			if(DERAMMO_LINT_FOUND_MAJOR STREQUAL DERAMMO_LINT_MAJOR)
				set(DERAMMO_LINT_MATCH_PATH "${DERAMMO_LINT_CANDIDATE}")
				set(DERAMMO_LINT_MATCH_VERSION "${DERAMMO_LINT_VERSION}")
			elseif(DERAMMO_LINT_FIRST_PATH STREQUAL "")
				set(DERAMMO_LINT_FIRST_PATH "${DERAMMO_LINT_CANDIDATE}")
				set(DERAMMO_LINT_FIRST_VERSION "${DERAMMO_LINT_VERSION}")
			endif()
		endif()
	endif()
endmacro()

# internal: find the tool DERAMMO_LINT_TOOL of major DERAMMO_LINT_MAJOR, looking
# in order in the directory `cmake/tools` installs into
# (%LOCALAPPDATA%\derammo\bin on Windows, ~/.local/bin elsewhere), each PATH
# entry, Homebrew's LLVM prefixes, and on macOS `xcrun --find`; candidates are
# run in that order and the search stops at the first whose major matches, so
# xcrun, which can raise the Command Line Tools install dialog, runs only when
# nothing earlier matched; the matching candidate is returned, its path in
# OUT_PATH and its version line in OUT_VERSION; when none matches, the first
# candidate that reported a version is returned instead, so the caller tells a
# mismatch from a missing tool by its major; both are empty when nothing is
# found
#
# the result is not cached, so every configure searches afresh: a tool
# installed later, or a switch file that comes to name another major, is
# picked up by the rerun of configure that main.make and make.cmd trigger,
# which a cached path would ignore
function(_derammo_lint_find_tool DERAMMO_LINT_TOOL DERAMMO_LINT_MAJOR OUT_PATH OUT_VERSION)
	set(DERAMMO_LINT_INSTALL_DIR "")
	if(NOT CMAKE_HOST_WIN32)
		set(DERAMMO_LINT_INSTALL_DIR "$ENV{HOME}/.local/bin")
	elseif(DEFINED ENV{LOCALAPPDATA})
		file(TO_CMAKE_PATH "$ENV{LOCALAPPDATA}/derammo/bin" DERAMMO_LINT_INSTALL_DIR)
	endif()
	file(TO_CMAKE_PATH "$ENV{PATH}" DERAMMO_LINT_PATH_DIRS)
	set(DERAMMO_LINT_DIRS
		${DERAMMO_LINT_INSTALL_DIR}
		${DERAMMO_LINT_PATH_DIRS}
		/opt/homebrew/opt/llvm/bin
		/usr/local/opt/llvm/bin
	)

	set(DERAMMO_LINT_PROBED "")
	set(DERAMMO_LINT_MATCH_PATH "")
	set(DERAMMO_LINT_MATCH_VERSION "")
	set(DERAMMO_LINT_FIRST_PATH "")
	set(DERAMMO_LINT_FIRST_VERSION "")
	foreach(DERAMMO_LINT_DIR IN LISTS DERAMMO_LINT_DIRS)
		# find_program before CMake 3.21 can only return through the cache, so
		# the entry is removed again at once
		find_program(_DERAMMO_LINT_PROGRAM NAMES ${DERAMMO_LINT_TOOL} PATHS "${DERAMMO_LINT_DIR}" NO_DEFAULT_PATH)
		set(DERAMMO_LINT_PROGRAM "")
		if(_DERAMMO_LINT_PROGRAM)
			set(DERAMMO_LINT_PROGRAM "${_DERAMMO_LINT_PROGRAM}")
		endif()
		unset(_DERAMMO_LINT_PROGRAM CACHE)
		unset(_DERAMMO_LINT_PROGRAM)
		if(NOT DERAMMO_LINT_PROGRAM STREQUAL "")
			_derammo_lint_probe_candidate("${DERAMMO_LINT_PROGRAM}")
			if(NOT DERAMMO_LINT_MATCH_PATH STREQUAL "")
				break()
			endif()
		endif()
	endforeach()
	if(DERAMMO_LINT_MATCH_PATH STREQUAL "" AND CMAKE_HOST_APPLE)
		execute_process(
			COMMAND xcrun --find ${DERAMMO_LINT_TOOL}
			RESULT_VARIABLE DERAMMO_LINT_XCRUN_RESULT
			OUTPUT_VARIABLE DERAMMO_LINT_XCRUN_PATH
			OUTPUT_STRIP_TRAILING_WHITESPACE
			ERROR_QUIET
		)
		if(DERAMMO_LINT_XCRUN_RESULT EQUAL 0 AND EXISTS "${DERAMMO_LINT_XCRUN_PATH}")
			_derammo_lint_probe_candidate("${DERAMMO_LINT_XCRUN_PATH}")
		endif()
	endif()

	if(NOT DERAMMO_LINT_MATCH_PATH STREQUAL "")
		set(${OUT_PATH} "${DERAMMO_LINT_MATCH_PATH}" PARENT_SCOPE)
		set(${OUT_VERSION} "${DERAMMO_LINT_MATCH_VERSION}" PARENT_SCOPE)
	else()
		set(${OUT_PATH} "${DERAMMO_LINT_FIRST_PATH}" PARENT_SCOPE)
		set(${OUT_VERSION} "${DERAMMO_LINT_FIRST_VERSION}" PARENT_SCOPE)
	endif()
endfunction()

# internal: decide whether the check DERAMMO_LINT_CHECK (`format`, `tidy`) runs,
# given its switch file DERAMMO_LINT_SWITCH at the source root and its tool
# DERAMMO_LINT_TOOL; prints the check's status line and sets OUT_PATH to the
# matching tool's path, or to empty when the check is disabled
function(_derammo_lint_check DERAMMO_LINT_CHECK DERAMMO_LINT_SWITCH DERAMMO_LINT_TOOL OUT_PATH)
	set(${OUT_PATH} "" PARENT_SCOPE)
	set(DERAMMO_LINT_SWITCH_FILE "${CMAKE_SOURCE_DIR}/${DERAMMO_LINT_SWITCH}")
	if(NOT EXISTS "${DERAMMO_LINT_SWITCH_FILE}")
		message(STATUS "${DERAMMO_LINT_CHECK}: disabled (${DERAMMO_LINT_SWITCH} absent)")
		return()
	endif()

	# editing or deleting the switch file reruns configure
	set_property(DIRECTORY "${CMAKE_SOURCE_DIR}" APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${DERAMMO_LINT_SWITCH_FILE}")

	set(DERAMMO_LINT_REMEDY "make -C cmake/tools ${DERAMMO_LINT_TOOL}")
	file(STRINGS "${DERAMMO_LINT_SWITCH_FILE}" DERAMMO_LINT_FIRST_LINE LIMIT_COUNT 1)
	if(DERAMMO_LINT_FIRST_LINE MATCHES "^#[ \t]*${DERAMMO_LINT_TOOL}[ \t]+([0-9]+)")
		set(DERAMMO_LINT_MAJOR "${CMAKE_MATCH_1}")
	else()
		set(DERAMMO_LINT_MAJOR "")
	endif()
	if(DERAMMO_LINT_TOOL STREQUAL "clang-tidy" AND CMAKE_GENERATOR MATCHES "^(Visual Studio|Xcode)")
		# without a compile database clang-tidy runs every file without flags
		# and reports errors that have nothing to do with the code
		set(DERAMMO_LINT_STATUS "${DERAMMO_LINT_CHECK}: disabled (the ${CMAKE_GENERATOR} generator writes no compile database)")
	elseif(DERAMMO_LINT_MAJOR STREQUAL "")
		set(DERAMMO_LINT_STATUS "${DERAMMO_LINT_CHECK}: disabled (${DERAMMO_LINT_SWITCH} does not name the ${DERAMMO_LINT_TOOL} major on its first line, as `# ${DERAMMO_LINT_TOOL} <major>`)")
	elseif(DERAMMO_LINT_TOOL STREQUAL "clang-tidy" AND DERAMMO_LINT_MAJOR LESS 19)
		# the tidy tests pass --exclude-header-filter, which clang-tidy has
		# from 19 on
		set(DERAMMO_LINT_STATUS "${DERAMMO_LINT_CHECK}: disabled (${DERAMMO_LINT_SWITCH} names clang-tidy ${DERAMMO_LINT_MAJOR}; the lint provider needs clang-tidy 19 or newer)")
	else()
		_derammo_lint_find_tool(${DERAMMO_LINT_TOOL} ${DERAMMO_LINT_MAJOR} DERAMMO_LINT_PATH DERAMMO_LINT_VERSION)
		_derammo_lint_version_major("${DERAMMO_LINT_VERSION}" DERAMMO_LINT_FOUND_MAJOR)
		if(DERAMMO_LINT_PATH STREQUAL "")
			set(DERAMMO_LINT_STATUS "${DERAMMO_LINT_CHECK}: disabled (${DERAMMO_LINT_TOOL} not found; ${DERAMMO_LINT_REMEDY})")
		elseif(NOT DERAMMO_LINT_FOUND_MAJOR STREQUAL DERAMMO_LINT_MAJOR)
			string(REGEX MATCH "[0-9]+\\.[0-9.]+" DERAMMO_LINT_NUMBER "${DERAMMO_LINT_VERSION}")
			set(DERAMMO_LINT_STATUS "${DERAMMO_LINT_CHECK}: disabled (${DERAMMO_LINT_TOOL} ${DERAMMO_LINT_NUMBER} found at ${DERAMMO_LINT_PATH}, ${DERAMMO_LINT_SWITCH} wants ${DERAMMO_LINT_MAJOR}; ${DERAMMO_LINT_REMEDY})")
		else()
			message(STATUS "${DERAMMO_LINT_TOOL}: ${DERAMMO_LINT_PATH} (${DERAMMO_LINT_VERSION})")
			# Apple numbers its clang independently of LLVM, so a matching
			# major from Xcode's tool is a coincidence; it is used anyway,
			# since it does work on a plain macOS machine
			if(DERAMMO_LINT_VERSION MATCHES "Apple")
				message(STATUS "${DERAMMO_LINT_TOOL}: this is Apple's ${DERAMMO_LINT_TOOL}, whose version ${DERAMMO_LINT_FOUND_MAJOR} is not LLVM ${DERAMMO_LINT_MAJOR}; its results may differ from the LLVM release, which ${DERAMMO_LINT_REMEDY} installs")
			endif()
			message(STATUS "${DERAMMO_LINT_CHECK}: enabled")
			# deleting or replacing the tool reruns configure, which then
			# disables the check or finds another tool, and depends on it no
			# more (a tool that appears is a make prerequisite, see main.make)
			set_property(DIRECTORY "${CMAKE_SOURCE_DIR}" APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${DERAMMO_LINT_PATH}")
			set(${OUT_PATH} "${DERAMMO_LINT_PATH}" PARENT_SCOPE)
			return()
		endif()
	endif()

	if(DERAMMO_LINT_REQUIRED)
		message(FATAL_ERROR "${DERAMMO_LINT_STATUS}")
	endif()
	message(STATUS "${DERAMMO_LINT_STATUS}")
endfunction()

_derammo_lint_check(format .clang-format clang-format DERAMMO_CLANG_FORMAT)
_derammo_lint_check(tidy .clang-tidy clang-tidy DERAMMO_CLANG_TIDY)

# strict compilation for registered targets: warnings as errors in every
# configuration; options that only exist for C++ are not given to C; the flag
# style follows the compiler's front end, so clang-cl (id Clang, MSVC front
# end) gets the MSVC set; compiler ids other than GNU, Clang, AppleClang and
# MSVC receive no strict flags; with DERAMMO_LINT_STRICT off the target stays,
# so registered targets still link it, but carries no flags, for a project
# that updates this submodule before it cleans up its warnings
add_library(derammo_strict INTERFACE)
add_library(derammo::strict ALIAS derammo_strict)
if(DERAMMO_LINT_STRICT)
	message(STATUS "strict: enabled")
else()
	message(STATUS "strict: disabled (DERAMMO_LINT_STRICT is off)")
endif()
set(DERAMMO_STRICT_FLAGS
	-Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wsign-conversion
	-Wnull-dereference -Wimplicit-fallthrough -Wformat=2 -Werror
)
set(DERAMMO_STRICT_CXX_FLAGS -Wold-style-cast -Wnon-virtual-dtor -Woverloaded-virtual)
set(DERAMMO_STRICT_MSVC_FLAGS /W4 /WX)
set(DERAMMO_STRICT_MSVC_CXX_FLAGS /permissive-)
foreach(DERAMMO_STRICT_LANG C CXX)
	set(DERAMMO_STRICT_GNU_STYLE "$<OR:$<COMPILE_LANG_AND_ID:${DERAMMO_STRICT_LANG},GNU,AppleClang>,$<AND:$<COMPILE_LANG_AND_ID:${DERAMMO_STRICT_LANG},Clang>,$<STREQUAL:${CMAKE_${DERAMMO_STRICT_LANG}_COMPILER_FRONTEND_VARIANT},GNU>>>")
	set(DERAMMO_STRICT_MSVC_STYLE "$<OR:$<COMPILE_LANG_AND_ID:${DERAMMO_STRICT_LANG},MSVC>,$<AND:$<COMPILE_LANG_AND_ID:${DERAMMO_STRICT_LANG},Clang>,$<STREQUAL:${CMAKE_${DERAMMO_STRICT_LANG}_COMPILER_FRONTEND_VARIANT},MSVC>>>")
	if(DERAMMO_STRICT_LANG STREQUAL "CXX")
		set(DERAMMO_STRICT_GNU_LANG_FLAGS ${DERAMMO_STRICT_FLAGS} ${DERAMMO_STRICT_CXX_FLAGS})
		set(DERAMMO_STRICT_MSVC_LANG_FLAGS ${DERAMMO_STRICT_MSVC_FLAGS} ${DERAMMO_STRICT_MSVC_CXX_FLAGS})
	else()
		set(DERAMMO_STRICT_GNU_LANG_FLAGS ${DERAMMO_STRICT_FLAGS})
		set(DERAMMO_STRICT_MSVC_LANG_FLAGS ${DERAMMO_STRICT_MSVC_FLAGS})
	endif()
	if(DERAMMO_LINT_STRICT)
		target_compile_options(derammo_strict INTERFACE
			"$<${DERAMMO_STRICT_GNU_STYLE}:${DERAMMO_STRICT_GNU_LANG_FLAGS}>"
			"$<${DERAMMO_STRICT_MSVC_STYLE}:${DERAMMO_STRICT_MSVC_LANG_FLAGS}>"
		)
	endif()
endforeach()

# register a C or C++ target for code quality checks: it is compiled with the
# strict flags, its own `thirdparty` directory (if any) becomes a SYSTEM
# include so vendored headers are exempt from them, and its sources join the
# lint set that derammo_lint_finalize turns into tests; call once per target,
# from the directory that created it
function(derammo_lint_target DERAMMO_LINT_TARGET)
	# a private link, written to the property directly rather than through
	# target_link_libraries(PRIVATE), so it works for targets whose own links
	# use either signature, and a static library does not carry the strict
	# target into its link interface
	set_property(TARGET ${DERAMMO_LINT_TARGET} APPEND PROPERTY LINK_LIBRARIES derammo::strict)
	if(IS_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/thirdparty")
		target_include_directories(${DERAMMO_LINT_TARGET} SYSTEM PRIVATE thirdparty)
	endif()
	set_property(GLOBAL APPEND PROPERTY DERAMMO_LINT_TARGETS "${DERAMMO_LINT_TARGET};${CMAKE_CURRENT_SOURCE_DIR}")
endfunction()

# internal: append to the list named OUT_FILES the absolute paths of the
# SOURCES and INTERFACE_SOURCES of the registered target DERAMMO_LINT_TARGET,
# the files that get the tests (derammo_add_sources adds a library's include/
# headers as INTERFACE sources); append to the list named OUT_FOUND the files
# the standard source globs of its directory DERAMMO_LINT_DIR find, for a
# production target, or the gtest globs for a gtest target, so that
# derammo_lint_finalize can name the files beside a target that no target lists
#
# a gtest target never globs production directories, so the sources of a
# production library that is not registered itself never land in the size
# exempt gtest set through a neighbouring gtest target; for the same reason the
# files under its directory's include/, which derammo_add_gtest_target adds to
# its SOURCES, are dropped: they are the library's, and are checked through the
# library when it lists them
function(_derammo_lint_collect DERAMMO_LINT_TARGET DERAMMO_LINT_DIR DERAMMO_LINT_GTEST OUT_FILES OUT_FOUND)
	set(DERAMMO_LINT_FILES "")

	get_target_property(DERAMMO_LINT_SOURCE_DIR ${DERAMMO_LINT_TARGET} SOURCE_DIR)
	set(DERAMMO_LINT_SOURCES "")
	foreach(DERAMMO_LINT_PROPERTY SOURCES INTERFACE_SOURCES)
		get_target_property(DERAMMO_LINT_PROPERTY_VALUE ${DERAMMO_LINT_TARGET} ${DERAMMO_LINT_PROPERTY})
		if(DERAMMO_LINT_PROPERTY_VALUE)
			list(APPEND DERAMMO_LINT_SOURCES ${DERAMMO_LINT_PROPERTY_VALUE})
		endif()
	endforeach()
	foreach(DERAMMO_LINT_SOURCE IN LISTS DERAMMO_LINT_SOURCES)
		# an entry holding a generator expression names no file at configure
		# time and is skipped
		if(NOT DERAMMO_LINT_SOURCE MATCHES "\\$<")
			get_filename_component(DERAMMO_LINT_SOURCE "${DERAMMO_LINT_SOURCE}" ABSOLUTE BASE_DIR "${DERAMMO_LINT_SOURCE_DIR}")
			list(APPEND DERAMMO_LINT_FILES "${DERAMMO_LINT_SOURCE}")
		endif()
	endforeach()

	# the patterns of derammo_sources.cmake for production targets, and of
	# derammo_gtest.cmake for gtest targets; CONFIGURE_DEPENDS so a new file
	# is reported at the next build
	set(DERAMMO_LINT_FLAT_PATTERNS "")
	set(DERAMMO_LINT_RECURSE_PATTERNS "")
	foreach(DERAMMO_LINT_EXTENSION IN LISTS DERAMMO_LINT_EXTENSIONS)
		if(DERAMMO_LINT_GTEST)
			list(APPEND DERAMMO_LINT_RECURSE_PATTERNS "${DERAMMO_LINT_DIR}/gtest/*.${DERAMMO_LINT_EXTENSION}")
		else()
			list(APPEND DERAMMO_LINT_FLAT_PATTERNS "${DERAMMO_LINT_DIR}/*.${DERAMMO_LINT_EXTENSION}")
			list(APPEND DERAMMO_LINT_RECURSE_PATTERNS
				"${DERAMMO_LINT_DIR}/include/*.${DERAMMO_LINT_EXTENSION}"
				"${DERAMMO_LINT_DIR}/src/*.${DERAMMO_LINT_EXTENSION}")
		endif()
	endforeach()
	set(DERAMMO_LINT_FLAT "")
	if(DERAMMO_LINT_FLAT_PATTERNS)
		file(GLOB DERAMMO_LINT_FLAT LIST_DIRECTORIES false CONFIGURE_DEPENDS ${DERAMMO_LINT_FLAT_PATTERNS})
	endif()
	file(GLOB_RECURSE DERAMMO_LINT_RECURSE LIST_DIRECTORIES false CONFIGURE_DEPENDS ${DERAMMO_LINT_RECURSE_PATTERNS})

	if(DERAMMO_LINT_GTEST)
		set(DERAMMO_LINT_INCLUDE_DIR "${DERAMMO_LINT_DIR}/include/")
		set(DERAMMO_LINT_KEPT "")
		foreach(DERAMMO_LINT_FILE IN LISTS DERAMMO_LINT_FILES)
			string(FIND "${DERAMMO_LINT_FILE}" "${DERAMMO_LINT_INCLUDE_DIR}" DERAMMO_LINT_INCLUDE_POSITION)
			if(NOT DERAMMO_LINT_INCLUDE_POSITION EQUAL 0)
				list(APPEND DERAMMO_LINT_KEPT "${DERAMMO_LINT_FILE}")
			endif()
		endforeach()
		set(DERAMMO_LINT_FILES ${DERAMMO_LINT_KEPT})
	endif()

	set(${OUT_FILES} ${${OUT_FILES}} ${DERAMMO_LINT_FILES} PARENT_SCOPE)
	set(${OUT_FOUND} ${${OUT_FOUND}} ${DERAMMO_LINT_FLAT} ${DERAMMO_LINT_RECURSE} PARENT_SCOPE)
endfunction()

# internal: reduce the list named DERAMMO_LINT_LIST to the files to check, as
# paths relative to the source root: C and C++ extensions only, nothing in the
# build tree (generated sources, fetched dependencies), nothing outside the
# source root, nothing third party; sorted and without duplicates
function(_derammo_lint_filter DERAMMO_LINT_LIST)
	set(DERAMMO_LINT_KEPT "")
	foreach(DERAMMO_LINT_FILE IN LISTS ${DERAMMO_LINT_LIST})
		get_filename_component(DERAMMO_LINT_EXTENSION "${DERAMMO_LINT_FILE}" LAST_EXT)
		string(REGEX REPLACE "^\\." "" DERAMMO_LINT_EXTENSION "${DERAMMO_LINT_EXTENSION}")
		if(NOT DERAMMO_LINT_EXTENSION IN_LIST DERAMMO_LINT_EXTENSIONS)
			continue()
		endif()
		string(FIND "${DERAMMO_LINT_FILE}" "${CMAKE_BINARY_DIR}/" DERAMMO_LINT_BINARY_POSITION)
		if(DERAMMO_LINT_BINARY_POSITION EQUAL 0)
			continue()
		endif()
		file(RELATIVE_PATH DERAMMO_LINT_RELATIVE "${CMAKE_SOURCE_DIR}" "${DERAMMO_LINT_FILE}")
		if(DERAMMO_LINT_RELATIVE MATCHES "^\\.\\./" OR DERAMMO_LINT_RELATIVE MATCHES "(^|/)thirdparty/")
			continue()
		endif()
		list(APPEND DERAMMO_LINT_KEPT "${DERAMMO_LINT_RELATIVE}")
	endforeach()
	list(REMOVE_DUPLICATES DERAMMO_LINT_KEPT)
	list(SORT DERAMMO_LINT_KEPT)
	set(${DERAMMO_LINT_LIST} "${DERAMMO_LINT_KEPT}" PARENT_SCOPE)
endfunction()

# internal: label a lint test and configure its output like every other test
function(_derammo_lint_test_properties DERAMMO_LINT_TEST)
	set_tests_properties(${DERAMMO_LINT_TEST} PROPERTIES LABELS lint)
	derammo_test_output(${DERAMMO_LINT_TEST})
endfunction()

# turn the lint set of every registered target into tests and the `format`
# target; deferred to the end of the root CMakeLists.txt, so every
# subdirectory has registered its targets by then
#
# files of gtest targets that are not also files of a production target form
# the gtest set, which is exempt from the size rule
function(derammo_lint_finalize)
	# every file of an in-source build is under the build tree, which the lint
	# set excludes; with DERAMMO_LINT_REQUIRED and a switch file present that
	# fails configure, since nothing would be checked
	if(CMAKE_BINARY_DIR STREQUAL CMAKE_SOURCE_DIR)
		set(DERAMMO_LINT_STATUS "lint: no lint tests, the lint set is empty because the build tree is the source tree")
		if(DERAMMO_LINT_REQUIRED AND (EXISTS "${CMAKE_SOURCE_DIR}/.clang-format" OR EXISTS "${CMAKE_SOURCE_DIR}/.clang-tidy"))
			message(FATAL_ERROR "${DERAMMO_LINT_STATUS}")
		endif()
		message(STATUS "${DERAMMO_LINT_STATUS}")
		return()
	endif()

	get_property(DERAMMO_LINT_TARGETS GLOBAL PROPERTY DERAMMO_LINT_TARGETS)
	get_property(DERAMMO_LINT_GTEST_TARGETS GLOBAL PROPERTY DERAMMO_LINT_GTEST_TARGETS)

	set(DERAMMO_LINT_PRODUCTION_FILES "")
	set(DERAMMO_LINT_GTEST_FILES "")
	set(DERAMMO_LINT_FOUND_FILES "")
	list(LENGTH DERAMMO_LINT_TARGETS DERAMMO_LINT_LENGTH)
	if(DERAMMO_LINT_LENGTH GREATER 0)
		math(EXPR DERAMMO_LINT_LAST "${DERAMMO_LINT_LENGTH} - 1")
		foreach(DERAMMO_LINT_INDEX RANGE 0 ${DERAMMO_LINT_LAST} 2)
			math(EXPR DERAMMO_LINT_DIR_INDEX "${DERAMMO_LINT_INDEX} + 1")
			list(GET DERAMMO_LINT_TARGETS ${DERAMMO_LINT_INDEX} DERAMMO_LINT_TARGET)
			list(GET DERAMMO_LINT_TARGETS ${DERAMMO_LINT_DIR_INDEX} DERAMMO_LINT_DIR)
			if(DERAMMO_LINT_TARGET IN_LIST DERAMMO_LINT_GTEST_TARGETS)
				_derammo_lint_collect(${DERAMMO_LINT_TARGET} "${DERAMMO_LINT_DIR}" TRUE DERAMMO_LINT_GTEST_FILES DERAMMO_LINT_FOUND_FILES)
			else()
				_derammo_lint_collect(${DERAMMO_LINT_TARGET} "${DERAMMO_LINT_DIR}" FALSE DERAMMO_LINT_PRODUCTION_FILES DERAMMO_LINT_FOUND_FILES)
			endif()
		endforeach()
	endif()
	_derammo_lint_filter(DERAMMO_LINT_PRODUCTION_FILES)
	_derammo_lint_filter(DERAMMO_LINT_GTEST_FILES)
	_derammo_lint_filter(DERAMMO_LINT_FOUND_FILES)
	if(DERAMMO_LINT_PRODUCTION_FILES)
		list(REMOVE_ITEM DERAMMO_LINT_GTEST_FILES ${DERAMMO_LINT_PRODUCTION_FILES})
	endif()
	set(DERAMMO_LINT_ALL ${DERAMMO_LINT_PRODUCTION_FILES} ${DERAMMO_LINT_GTEST_FILES})
	list(SORT DERAMMO_LINT_ALL)

	# a file beside a registered target that no registered target lists gets
	# no tests; it is named here, once per configure, so that listing it is a
	# decision rather than an oversight
	if(DERAMMO_LINT_ALL)
		list(REMOVE_ITEM DERAMMO_LINT_FOUND_FILES ${DERAMMO_LINT_ALL})
	endif()
	if(DERAMMO_LINT_FOUND_FILES)
		list(JOIN DERAMMO_LINT_FOUND_FILES "\n  " DERAMMO_LINT_FOUND_TEXT)
		message(STATUS "lint: not sources of any registered target, so not checked:\n  ${DERAMMO_LINT_FOUND_TEXT}")
	endif()

	if(DERAMMO_CLANG_FORMAT)
		set(DERAMMO_LINT_FORMAT_RSP "${CMAKE_BINARY_DIR}/lint/format.rsp")
		set(DERAMMO_LINT_FORMAT_LINES "")
		foreach(DERAMMO_LINT_FILE IN LISTS DERAMMO_LINT_ALL)
			add_test(NAME lint_format/${DERAMMO_LINT_FILE}
				COMMAND ${DERAMMO_CLANG_FORMAT} --dry-run -Werror --style=file "${CMAKE_SOURCE_DIR}/${DERAMMO_LINT_FILE}"
				WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
			)
			_derammo_lint_test_properties(lint_format/${DERAMMO_LINT_FILE})
			string(APPEND DERAMMO_LINT_FORMAT_LINES "\"${CMAKE_SOURCE_DIR}/${DERAMMO_LINT_FILE}\"\n")
		endforeach()

		# one path per line in a response file, so no command line carries the
		# file list; with no files, clang-format would read standard input
		file(WRITE "${DERAMMO_LINT_FORMAT_RSP}" "${DERAMMO_LINT_FORMAT_LINES}")
		if(DERAMMO_LINT_ALL)
			add_custom_target(clang-format
				COMMAND ${DERAMMO_CLANG_FORMAT} -i --style=file "@${DERAMMO_LINT_FORMAT_RSP}"
				WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
				COMMENT "formatting the lint set with ${DERAMMO_CLANG_FORMAT}"
				VERBATIM
			)
		else()
			add_custom_target(clang-format COMMENT "no files to format")
		endif()
		derammo_format_target(clang-format)
	endif()

	if(DERAMMO_CLANG_TIDY)
		# headers are judged through the translation units that include them:
		# findings in any header under the source root are reported, except in
		# third party and fetched (_deps) headers and in the build tree; the
		# third party segment is matched only below the source root, so a
		# checkout inside a directory named thirdparty is still checked; both
		# roots are escaped, since a path may hold regex characters such as `.`
		# or `+`; --exclude-header-filter needs clang-tidy 19 or newer, which
		# _derammo_lint_check enforces
		derammo_escape_regex_operators("${CMAKE_SOURCE_DIR}" DERAMMO_LINT_SOURCE_REGEX)
		derammo_escape_regex_operators("${CMAKE_BINARY_DIR}" DERAMMO_LINT_BINARY_REGEX)
		set(DERAMMO_LINT_TIDY_ARGS
			-p ${CMAKE_BINARY_DIR}
			--quiet
			"--header-filter=^${DERAMMO_LINT_SOURCE_REGEX}/"
			"--exclude-header-filter=^${DERAMMO_LINT_SOURCE_REGEX}/(.*/)?(thirdparty|_deps)/|^${DERAMMO_LINT_BINARY_REGEX}/"
		)
		# CMake 4 does not set CMAKE_OSX_SYSROOT by default, and then the
		# compile commands name no SDK. Without one, clang-tidy finds no system
		# headers. The SDK path is taken from xcrun at configure time and passed
		# ahead of the compile command's own arguments. An -isysroot already in
		# the compile command wins, because clang keeps the last one.
		if(APPLE AND NOT CMAKE_OSX_SYSROOT)
			execute_process(
				COMMAND xcrun --show-sdk-path
				RESULT_VARIABLE DERAMMO_LINT_SDK_RESULT
				OUTPUT_VARIABLE DERAMMO_LINT_SDK
				OUTPUT_STRIP_TRAILING_WHITESPACE
				ERROR_QUIET
			)
			if(DERAMMO_LINT_SDK_RESULT EQUAL 0 AND IS_DIRECTORY "${DERAMMO_LINT_SDK}")
				list(APPEND DERAMMO_LINT_TIDY_ARGS "--extra-arg-before=-isysroot${DERAMMO_LINT_SDK}")
			endif()
		endif()

		# one test per translation unit that a registered target compiles,
		# production and gtest alike; gtest units pick up the gtest/.clang-tidy
		# beside them by directory
		foreach(DERAMMO_LINT_FILE IN LISTS DERAMMO_LINT_ALL)
			if(NOT DERAMMO_LINT_FILE MATCHES "\\.(c|cc|cpp|cxx)$")
				continue()
			endif()
			add_test(NAME lint_tidy/${DERAMMO_LINT_FILE}
				COMMAND ${DERAMMO_CLANG_TIDY} ${DERAMMO_LINT_TIDY_ARGS} "${CMAKE_SOURCE_DIR}/${DERAMMO_LINT_FILE}"
				WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
			)
			_derammo_lint_test_properties(lint_tidy/${DERAMMO_LINT_FILE})
		endforeach()
	endif()

	foreach(DERAMMO_LINT_FILE IN LISTS DERAMMO_LINT_PRODUCTION_FILES)
		add_test(NAME lint_size/${DERAMMO_LINT_FILE}
			COMMAND ${CMAKE_COMMAND}
				"-DDERAMMO_LINT_FILE=${CMAKE_SOURCE_DIR}/${DERAMMO_LINT_FILE}"
				"-DDERAMMO_LINT_MAX_LINES=${DERAMMO_LINT_MAX_LINES}"
				-P "${DERAMMO_LINT_SIZE_SCRIPT}"
		)
		_derammo_lint_test_properties(lint_size/${DERAMMO_LINT_FILE})
	endforeach()
endfunction()

cmake_language(DEFER DIRECTORY ${CMAKE_SOURCE_DIR} CALL derammo_lint_finalize)
