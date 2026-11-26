# install the VSIX in DERAMMO_VSIX_FILE into vscode under a unique timestamped
# file name, for `cmake -P` at build time, so vscode treats every install as an
# update even when the version is unchanged; the stamped copy lives in
# DERAMMO_VSIX_STAGE_DIR, which is removed again afterwards
cmake_minimum_required(VERSION 3.20)

if(NOT DEFINED DERAMMO_VSIX_FILE)
	message(FATAL_ERROR "vsix_dev_install: DERAMMO_VSIX_FILE not set")
endif()
if(NOT DEFINED DERAMMO_VSIX_STAGE_DIR)
	message(FATAL_ERROR "vsix_dev_install: DERAMMO_VSIX_STAGE_DIR not set")
endif()
if(NOT EXISTS "${DERAMMO_VSIX_FILE}")
	message(FATAL_ERROR "vsix_dev_install: missing VSIX ${DERAMMO_VSIX_FILE}")
endif()

get_filename_component(DERAMMO_VSIX_STEM "${DERAMMO_VSIX_FILE}" NAME_WLE)
string(TIMESTAMP DERAMMO_VSIX_STAMP "%s")
set(DERAMMO_VSIX_STAMPED "${DERAMMO_VSIX_STAGE_DIR}/${DERAMMO_VSIX_STEM}.${DERAMMO_VSIX_STAMP}.vsix")

file(REMOVE_RECURSE "${DERAMMO_VSIX_STAGE_DIR}")
file(MAKE_DIRECTORY "${DERAMMO_VSIX_STAGE_DIR}")
configure_file("${DERAMMO_VSIX_FILE}" "${DERAMMO_VSIX_STAMPED}" COPYONLY)

# installing a VSIX makes vscode query the Marketplace for the extension id;
# routing the CLI through an unreachable proxy keeps private extension ids
# from leaving the machine
execute_process(
	COMMAND ${CMAKE_COMMAND} -E env HTTPS_PROXY=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9
		code --install-extension "${DERAMMO_VSIX_STAMPED}" --force
	RESULT_VARIABLE DERAMMO_VSIX_RESULT
)

file(REMOVE_RECURSE "${DERAMMO_VSIX_STAGE_DIR}")

if(DERAMMO_VSIX_RESULT)
	message(FATAL_ERROR "vsix_dev_install: code --install-extension failed with status ${DERAMMO_VSIX_RESULT}")
endif()
