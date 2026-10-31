# install the npm dependencies of the package in the current directory, for
# `cmake -P` at build time:
#
# locally built tarball dependencies (file:<path>.tgz, of this package and of
# every workspace member when this is a workspace root) are updated first,
# because a tarball rebuilt on another machine no longer matches the integrity
# hash the lock file recorded for it and a plain `npm install` refuses it;
# then `npm install` runs for everything else
#
# lines that only say nothing happened are dropped, everything else (including
# warnings and errors, which npm writes to stderr) is printed once npm
# finishes, and a failed step fails this script
cmake_minimum_required(VERSION 3.20)

include("${CMAKE_CURRENT_LIST_DIR}/../derammo_npm_tarballs.cmake")

# run one npm command, printing its filtered output, failing on error
function(derammo_npm_run)
	execute_process(
		COMMAND npm ${ARGN}
		OUTPUT_VARIABLE DERAMMO_NPM_OUTPUT
		ERROR_VARIABLE DERAMMO_NPM_OUTPUT
		RESULT_VARIABLE DERAMMO_NPM_RESULT
	)
	string(REPLACE "\n" ";" DERAMMO_NPM_LINES "${DERAMMO_NPM_OUTPUT}")
	list(FILTER DERAMMO_NPM_LINES EXCLUDE REGEX "^(up to date|[0-9]+ packages? (is|are) looking for funding|[ \t]*run `npm fund`|found 0 vulnerabilities|[ \t]*$)")
	string(JOIN "\n" DERAMMO_NPM_OUTPUT ${DERAMMO_NPM_LINES})
	if(NOT DERAMMO_NPM_OUTPUT STREQUAL "")
		message("${DERAMMO_NPM_OUTPUT}")
	endif()
	if(DERAMMO_NPM_RESULT)
		string(JOIN " " DERAMMO_NPM_ARGUMENTS ${ARGN})
		message(FATAL_ERROR "npm ${DERAMMO_NPM_ARGUMENTS} failed with status ${DERAMMO_NPM_RESULT}")
	endif()
endfunction()

# the package itself, then every workspace member (entries may be globs)
set(DERAMMO_NPM_PACKAGE_DIRS "${CMAKE_CURRENT_SOURCE_DIR}")
file(READ "${CMAKE_CURRENT_SOURCE_DIR}/package.json" DERAMMO_NPM_PACKAGE_JSON)
string(JSON DERAMMO_NPM_WORKSPACES ERROR_VARIABLE DERAMMO_NPM_JSON_ERROR GET "${DERAMMO_NPM_PACKAGE_JSON}" workspaces)
if(NOT DERAMMO_NPM_JSON_ERROR)
	string(JSON DERAMMO_NPM_WORKSPACE_COUNT LENGTH "${DERAMMO_NPM_WORKSPACES}")
	if(DERAMMO_NPM_WORKSPACE_COUNT GREATER 0)
		math(EXPR DERAMMO_NPM_WORKSPACE_LAST "${DERAMMO_NPM_WORKSPACE_COUNT} - 1")
		foreach(DERAMMO_NPM_WORKSPACE_INDEX RANGE ${DERAMMO_NPM_WORKSPACE_LAST})
			string(JSON DERAMMO_NPM_WORKSPACE GET "${DERAMMO_NPM_WORKSPACES}" ${DERAMMO_NPM_WORKSPACE_INDEX})
			file(GLOB DERAMMO_NPM_WORKSPACE_DIRS LIST_DIRECTORIES true "${CMAKE_CURRENT_SOURCE_DIR}/${DERAMMO_NPM_WORKSPACE}")
			foreach(DERAMMO_NPM_WORKSPACE_DIR ${DERAMMO_NPM_WORKSPACE_DIRS})
				if(EXISTS "${DERAMMO_NPM_WORKSPACE_DIR}/package.json")
					list(APPEND DERAMMO_NPM_PACKAGE_DIRS "${DERAMMO_NPM_WORKSPACE_DIR}")
				endif()
			endforeach()
		endforeach()
	endif()
endif()

set(DERAMMO_NPM_TARBALL_NAMES "")
foreach(DERAMMO_NPM_PACKAGE_DIR ${DERAMMO_NPM_PACKAGE_DIRS})
	derammo_npm_tarball_dependency_list("${DERAMMO_NPM_PACKAGE_DIR}" DERAMMO_NPM_NAMES DERAMMO_NPM_TARBALLS)
	list(APPEND DERAMMO_NPM_TARBALL_NAMES ${DERAMMO_NPM_NAMES})
endforeach()
list(REMOVE_DUPLICATES DERAMMO_NPM_TARBALL_NAMES)

if(NOT DERAMMO_NPM_TARBALL_NAMES STREQUAL "")
	derammo_npm_run(update ${DERAMMO_NPM_TARBALL_NAMES})
endif()
derammo_npm_run(install)
