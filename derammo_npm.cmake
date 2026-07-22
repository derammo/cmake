include_guard()

# template expansion script, run directly by node without compilation
set(DERAMMO_NPM_GENERATOR "${CMAKE_SOURCE_DIR}/cmake/scripts/generate_npm_package_json.ts")

# internal: expand _package_template.json into package.json in the current source
# directory; DERAMMO_NPM_WORKSPACES_JSON is a JSON array of workspace folders when
# generating for a workspace root, or empty
function(derammo_npm_generate DERAMMO_NPM_WORKSPACES_JSON)
	# template search path: package local templates, then workspace root templates,
	# then standard templates from this submodule; missing folders are ignored by
	# the generator
	set(DERAMMO_NPM_TEMPLATE_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/templates")
	if(DEFINED DERAMMO_NPM_WORKSPACE_ROOT)
		list(APPEND DERAMMO_NPM_TEMPLATE_DIRS "${DERAMMO_NPM_WORKSPACE_ROOT}/templates")
	endif()
	list(APPEND DERAMMO_NPM_TEMPLATE_DIRS "${CMAKE_SOURCE_DIR}/cmake/npm_package_templates")
	list(REMOVE_DUPLICATES DERAMMO_NPM_TEMPLATE_DIRS)
	string(JOIN ":" DERAMMO_NPM_TEMPLATE_PATH ${DERAMMO_NPM_TEMPLATE_DIRS})

	# rerun cmake when any template that may have contributed changes
	set_property(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" APPEND PROPERTY
		CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/_package_template.json")
	foreach(DERAMMO_NPM_TEMPLATE_DIR ${DERAMMO_NPM_TEMPLATE_DIRS})
		file(GLOB DERAMMO_NPM_TEMPLATES "${DERAMMO_NPM_TEMPLATE_DIR}/_package_template*.json")
		set_property(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" APPEND PROPERTY
			CMAKE_CONFIGURE_DEPENDS ${DERAMMO_NPM_TEMPLATES})
	endforeach()

	message(STATUS "generating package.json in '${CMAKE_CURRENT_SOURCE_DIR}'")
	execute_process(
		COMMAND ${CMAKE_COMMAND} -E env
			"DERAMMO_NPM_PACKAGE_TEMPLATE_PATH=${DERAMMO_NPM_TEMPLATE_PATH}"
			"DERAMMO_NPM_WORKSPACES=${DERAMMO_NPM_WORKSPACES_JSON}"
			node "${DERAMMO_NPM_GENERATOR}"
		WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
		COMMAND_ERROR_IS_FATAL ANY
	)
endfunction()

# declare an npm package in the current source directory, generating its
# package.json from _package_template.json at configure time; inside a workspace
# the workspace root builds and tests all packages, so a standalone package
# creates its own targets
function(derammo_npm)
	derammo_npm_generate("")

	# register with the enclosing workspace, if any
	set_property(GLOBAL APPEND PROPERTY DERAMMO_NPM_PACKAGES "${CMAKE_CURRENT_SOURCE_DIR}")

	# the clean target removes our npm installation
	set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES "${CMAKE_CURRENT_SOURCE_DIR}/node_modules")

	if(NOT DEFINED DERAMMO_NPM_WORKSPACE_ROOT)
		file(RELATIVE_PATH DERAMMO_RELATIVE_CURRENT_SOURCE_DIR "${CMAKE_SOURCE_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}")
		string(REPLACE "/" "_" DERAMMO_CURRENT_TARGET_PREFIX ${DERAMMO_RELATIVE_CURRENT_SOURCE_DIR})
		add_custom_target(${DERAMMO_CURRENT_TARGET_PREFIX}_npm ALL
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
			COMMAND npm install
			COMMAND npm run build --if-present
		)
		add_test(NAME ${DERAMMO_CURRENT_TARGET_PREFIX}_npm
			COMMAND npm run test --if-present
			WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
		)
	endif()
endfunction()

# declare the current source directory as an npm workspace root: automatically
# adds all subdirectories that have a CMakeLists.txt, generates a package.json
# whose workspaces list contains every folder below that declared derammo_npm(),
# and builds and tests all workspaces via npm from here
function(derammo_workspaces_auto)
	# visible to all subdirectories added below
	set(DERAMMO_NPM_WORKSPACE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}")

	file(GLOB DERAMMO_NPM_CANDIDATES RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}/*/CMakeLists.txt")
	foreach(DERAMMO_NPM_CANDIDATE ${DERAMMO_NPM_CANDIDATES})
		get_filename_component(DERAMMO_NPM_SUBDIRECTORY "${DERAMMO_NPM_CANDIDATE}" DIRECTORY)
		add_subdirectory("${DERAMMO_NPM_SUBDIRECTORY}")
	endforeach()

	# collect the packages that registered from within this workspace
	get_property(DERAMMO_NPM_PACKAGES GLOBAL PROPERTY DERAMMO_NPM_PACKAGES)
	set(DERAMMO_NPM_WORKSPACE_FOLDERS "")
	foreach(DERAMMO_NPM_PACKAGE ${DERAMMO_NPM_PACKAGES})
		file(RELATIVE_PATH DERAMMO_NPM_RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "${DERAMMO_NPM_PACKAGE}")
		if(NOT DERAMMO_NPM_RELATIVE MATCHES "^\\.\\.")
			list(APPEND DERAMMO_NPM_WORKSPACE_FOLDERS "\"${DERAMMO_NPM_RELATIVE}\"")
		endif()
	endforeach()
	string(JOIN "," DERAMMO_NPM_WORKSPACES_JOINED ${DERAMMO_NPM_WORKSPACE_FOLDERS})
	derammo_npm_generate("[${DERAMMO_NPM_WORKSPACES_JOINED}]")

	# the clean target removes our npm installation
	set_property(DIRECTORY APPEND PROPERTY ADDITIONAL_CLEAN_FILES "${CMAKE_CURRENT_SOURCE_DIR}/node_modules")

	file(RELATIVE_PATH DERAMMO_RELATIVE_CURRENT_SOURCE_DIR "${CMAKE_SOURCE_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}")
	string(REPLACE "/" "_" DERAMMO_CURRENT_TARGET_PREFIX ${DERAMMO_RELATIVE_CURRENT_SOURCE_DIR})
	add_custom_target(${DERAMMO_CURRENT_TARGET_PREFIX}_npm ALL
		WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
		COMMAND npm install
		COMMAND npm run build --workspaces --if-present
	)
	add_test(NAME ${DERAMMO_CURRENT_TARGET_PREFIX}_npm
		COMMAND npm run test --workspaces --if-present
		WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
	)
endfunction()
