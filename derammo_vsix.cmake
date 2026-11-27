# VS Code extension (VSIX) support on top of derammo_npm.cmake: an extension
# is an npm package whose generated package.json carries the extension
# manifest and a package:vsix script; derammo_vsix() builds the package,
# packages the VSIX next to it, and offers a dev install target
include_guard()

include("${CMAKE_CURRENT_LIST_DIR}/derammo_npm.cmake")

# the ignore list every extension is packaged with; the package:vsix script
# reads its location from the environment under the same name
set(DERAMMO_VSIX_IGNORE_FILE "${CMAKE_CURRENT_LIST_DIR}/vsix_vscodeignore")

set(DERAMMO_VSIX_DEV_INSTALL "${CMAKE_CURRENT_LIST_DIR}/scripts/vsix_dev_install.cmake")
set(DERAMMO_VSIX_COPY_IF_CONTENT_DIFFERS "${CMAKE_CURRENT_LIST_DIR}/scripts/zip_copy_if_content_differs.ts")

# declare a VS Code extension in the current source directory: a derammo_npm()
# package plus
#   <prefix>_vsix (ALL)  package the built extension as <publisher>.<name>-<version>.vsix
#   <prefix>_dev         install that VSIX into vscode under a unique version,
#                        so vscode treats every install as an update
function(derammo_vsix)
	derammo_npm()
	derammo_calculate_current_target_prefix()

	file(READ "${CMAKE_CURRENT_SOURCE_DIR}/package.json" DERAMMO_VSIX_PACKAGE_JSON)
	string(JSON DERAMMO_VSIX_NAME GET "${DERAMMO_VSIX_PACKAGE_JSON}" name)
	string(JSON DERAMMO_VSIX_PUBLISHER GET "${DERAMMO_VSIX_PACKAGE_JSON}" publisher)
	string(JSON DERAMMO_VSIX_VERSION GET "${DERAMMO_VSIX_PACKAGE_JSON}" version)
	set(DERAMMO_VSIX_FILE "${DERAMMO_VSIX_PUBLISHER}.${DERAMMO_VSIX_NAME}-${DERAMMO_VSIX_VERSION}.vsix")

	# packaging runs through the quick build script with a stamp of its own, so
	# `QUICK=1 make` skips repackaging exactly when it would skip rebuilding;
	# a deleted VSIX with nothing else changed is invisible to the quick check,
	# like any output the records cannot show, and a full build recovers it;
	# the package:vsix script takes the ignore list and the output name from
	# its environment
	derammo_npm_build_commands("${CMAKE_CURRENT_SOURCE_DIR}"
		"${CMAKE_CURRENT_BINARY_DIR}/derammo_vsix.buildinfo.json"
		DERAMMO_VSIX_COMMANDS
		${CMAKE_COMMAND} -E env
			"DERAMMO_VSIX_IGNORE_FILE=${DERAMMO_VSIX_IGNORE_FILE}"
			"DERAMMO_VSIX_FILE=${DERAMMO_VSIX_FILE}"
		npm run package:vsix --silent)
	add_custom_target(${DERAMMO_CURRENT_TARGET_PREFIX}_vsix ALL
		WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
		${DERAMMO_VSIX_COMMANDS}
		COMMENT "packaging ${DERAMMO_VSIX_FILE}"
	)
	add_dependencies(${DERAMMO_CURRENT_TARGET_PREFIX}_vsix ${DERAMMO_CURRENT_TARGET_PREFIX}_npm)
	set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES
		"${CMAKE_CURRENT_SOURCE_DIR}/${DERAMMO_VSIX_FILE}")

	add_custom_target(${DERAMMO_CURRENT_TARGET_PREFIX}_dev
		WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
		COMMAND ${CMAKE_COMMAND}
			"-DDERAMMO_VSIX_FILE=${CMAKE_CURRENT_SOURCE_DIR}/${DERAMMO_VSIX_FILE}"
			"-DDERAMMO_VSIX_STAGE_DIR=${CMAKE_CURRENT_BINARY_DIR}/derammo_vsix_dev"
			-P "${DERAMMO_VSIX_DEV_INSTALL}"
		COMMENT "installing ${DERAMMO_VSIX_FILE} into vscode"
		VERBATIM
	)
	add_dependencies(${DERAMMO_CURRENT_TARGET_PREFIX}_dev ${DERAMMO_CURRENT_TARGET_PREFIX}_vsix)

	# registration for derammo_vsix_dist() and the `dev` umbrella target
	set_property(GLOBAL APPEND PROPERTY DERAMMO_VSIX_FILES "${CMAKE_CURRENT_SOURCE_DIR}/${DERAMMO_VSIX_FILE}")
	set_property(GLOBAL APPEND PROPERTY DERAMMO_VSIX_TARGETS ${DERAMMO_CURRENT_TARGET_PREFIX}_vsix)
	set_property(GLOBAL APPEND PROPERTY DERAMMO_VSIX_DEV_TARGETS ${DERAMMO_CURRENT_TARGET_PREFIX}_dev)
endfunction()

# define the vsix_dist target (ALL), which copies the VSIX of every extension
# declared so far into DERAMMO_VSIX_DIST_DIR; call from the root
# CMakeLists.txt after the last add_subdirectory() that declares extensions;
# packaging records the time of the build inside a VSIX, so one that was only
# built again differs as a file, and it is copied only when its content differs
function(derammo_vsix_dist DERAMMO_VSIX_DIST_DIR)
	get_property(DERAMMO_VSIX_FILES GLOBAL PROPERTY DERAMMO_VSIX_FILES)
	get_property(DERAMMO_VSIX_TARGETS GLOBAL PROPERTY DERAMMO_VSIX_TARGETS)

	set(DERAMMO_VSIX_COPY_COMMANDS "")
	foreach(DERAMMO_VSIX_FILE IN LISTS DERAMMO_VSIX_FILES)
		cmake_path(GET DERAMMO_VSIX_FILE FILENAME DERAMMO_VSIX_FILE_NAME)
		list(APPEND DERAMMO_VSIX_COPY_COMMANDS
			COMMAND node "${DERAMMO_VSIX_COPY_IF_CONTENT_DIFFERS}" "${DERAMMO_VSIX_FILE}" "${DERAMMO_VSIX_DIST_DIR}/${DERAMMO_VSIX_FILE_NAME}")
	endforeach()
	add_custom_target(vsix_dist ALL
		${DERAMMO_VSIX_COPY_COMMANDS}
		COMMENT "copying VSIX files into ${DERAMMO_VSIX_DIST_DIR}"
		VERBATIM
	)
	if(DERAMMO_VSIX_TARGETS)
		add_dependencies(vsix_dist ${DERAMMO_VSIX_TARGETS})
	endif()
endfunction()

# the `dev` target installs every declared extension into vscode; deferred to
# the end of configure, when every extension has registered
function(derammo_vsix_finalize)
	get_property(DERAMMO_VSIX_DEV_TARGETS GLOBAL PROPERTY DERAMMO_VSIX_DEV_TARGETS)
	add_custom_target(dev)
	if(DERAMMO_VSIX_DEV_TARGETS)
		add_dependencies(dev ${DERAMMO_VSIX_DEV_TARGETS})
	endif()
endfunction()
cmake_language(DEFER DIRECTORY ${CMAKE_SOURCE_DIR} CALL derammo_vsix_finalize)
