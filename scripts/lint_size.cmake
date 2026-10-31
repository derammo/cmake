# check that the C or C++ file DERAMMO_LINT_FILE has no more than
# DERAMMO_LINT_MAX_LINES lines of code, for `cmake -P` as a ctest; clang-tidy
# has no file-length check, so this one mirrors eslint's max-lines
#
# a line of code is any line that is not blank and does not start, after
# optional whitespace, with `//`; block comments are counted as code, which
# is a known approximation
#
# the only exemption is a tag on the first line, after an optional UTF-8 byte
# order mark, that states its reason:
#
#   // NOLINTFILE(max-lines): generated dispatch table, one row per opcode
#
# an exempted file passes and prints `exempt: <reason>`, so an exemption is
# never silent; a tag without a reason fails
cmake_minimum_required(VERSION 3.20)

if(NOT DEFINED DERAMMO_LINT_FILE)
	message(FATAL_ERROR "lint_size: DERAMMO_LINT_FILE not set")
endif()
if(NOT DEFINED DERAMMO_LINT_MAX_LINES)
	message(FATAL_ERROR "lint_size: DERAMMO_LINT_MAX_LINES not set")
endif()

# print the finding as one plain line and exit with status 1; a fatal error
# would wrap the line inside cmake's own error banner, so it is the fallback
# only where `cmake_language(EXIT)` does not exist yet
function(derammo_lint_size_fail DERAMMO_LINT_MESSAGE)
	message("${DERAMMO_LINT_MESSAGE}")
	if(CMAKE_VERSION VERSION_GREATER_EQUAL 3.29)
		cmake_language(EXIT 1)
	endif()
	message(FATAL_ERROR "lint_size: failed")
endfunction()

# the content after a leading UTF-8 byte order mark, if any, so the tag is
# found on a first line that starts with one
file(READ "${DERAMMO_LINT_FILE}" DERAMMO_LINT_HEAD LIMIT 3 HEX)
if(DERAMMO_LINT_HEAD STREQUAL "efbbbf")
	file(READ "${DERAMMO_LINT_FILE}" DERAMMO_LINT_CONTENT OFFSET 3)
else()
	file(READ "${DERAMMO_LINT_FILE}" DERAMMO_LINT_CONTENT)
endif()
string(REPLACE "\r" "" DERAMMO_LINT_CONTENT "${DERAMMO_LINT_CONTENT}")

# the exemption tag, read from the unmodified first line
string(REGEX MATCH "^[^\n]*" DERAMMO_LINT_FIRST_LINE "${DERAMMO_LINT_CONTENT}")
if(DERAMMO_LINT_FIRST_LINE MATCHES "^//[ \t]*NOLINTFILE\\(max-lines\\)")
	if(DERAMMO_LINT_FIRST_LINE MATCHES "^//[ \t]*NOLINTFILE\\(max-lines\\):[ \t]*(.+)$")
		string(STRIP "${CMAKE_MATCH_1}" DERAMMO_LINT_REASON)
	else()
		set(DERAMMO_LINT_REASON "")
	endif()
	if(DERAMMO_LINT_REASON STREQUAL "")
		derammo_lint_size_fail("${DERAMMO_LINT_FILE}: NOLINTFILE(max-lines) requires a reason")
	endif()
	message("exempt: ${DERAMMO_LINT_REASON}")
	return()
endif()

# characters that carry meaning in a cmake list are replaced by one that does
# not, so each line becomes exactly one list element; the replacement is not
# whitespace, so no line changes between blank and not blank
string(REGEX REPLACE "[][;\\]" "_" DERAMMO_LINT_CONTENT "${DERAMMO_LINT_CONTENT}")
string(REPLACE "\n" ";" DERAMMO_LINT_LINES "${DERAMMO_LINT_CONTENT}")

set(DERAMMO_LINT_COUNT 0)
foreach(DERAMMO_LINT_LINE IN LISTS DERAMMO_LINT_LINES)
	if(NOT DERAMMO_LINT_LINE MATCHES "^[ \t]*$" AND NOT DERAMMO_LINT_LINE MATCHES "^[ \t]*//")
		math(EXPR DERAMMO_LINT_COUNT "${DERAMMO_LINT_COUNT} + 1")
	endif()
endforeach()

if(DERAMMO_LINT_COUNT GREATER DERAMMO_LINT_MAX_LINES)
	derammo_lint_size_fail("${DERAMMO_LINT_FILE}: ${DERAMMO_LINT_COUNT} lines, limit ${DERAMMO_LINT_MAX_LINES}")
endif()
