# run `npm install` in the current directory, for `cmake -P` at build time:
# lines that only say nothing happened are dropped, everything else (including
# warnings and errors, which npm writes to stderr) is printed once npm
# finishes, and a failed install fails this script
cmake_minimum_required(VERSION 3.20)

execute_process(
	COMMAND npm install
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
	message(FATAL_ERROR "npm install failed with status ${DERAMMO_NPM_RESULT}")
endif()
