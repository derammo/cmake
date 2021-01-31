function(derammo_maven_build)
	message(STATUS "building maven projects with output to '${DERAMMO_RELATIVE_BINARY_DIR}/${DERAMMO_JAVABUILD_OUTPUT}'")

	string(REPLACE "${CMAKE_SOURCE_DIR}/" "" DERAMMO_RELATIVE_CURRENT_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR})
	string(REPLACE "/" "_" DERAMMO_CURRENT_TARGET_PREFIX ${DERAMMO_RELATIVE_CURRENT_SOURCE_DIR} )

	add_custom_target(${DERAMMO_CURRENT_TARGET_PREFIX}_java ALL
		DEPENDS jdk
		
		WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}

		# build all jars and collect third party ones
		COMMAND JAVA_HOME=${JDK} mvn 
			-DskipTests
			install 
			dependency:copy-dependencies 
		
		# unpack all the archives so we can path into them for licenses and inspection
		COMMAND mkdir -p ${CMAKE_BINARY_DIR}/${DERAMMO_JAVABUILD_OUTPUT}/unpack
		COMMAND cd ${CMAKE_BINARY_DIR}/${DERAMMO_JAVABUILD_OUTPUT}/lib \; for archive in *.jar \; do unzip -q -d ../unpack/$$\{archive\} -o -u $$\{archive\} META-INF/\\* \; done
		
		# declare what files we created
		BYPRODUCTS ${CMAKE_BINARY_DIR}/${DERAMMO_JAVABUILD_OUTPUT}
	)
endfunction()

function(derammo_configure_pom)
    # set up absolute paths in the main maven project file and make it read only
    configure_file(${CMAKE_CURRENT_SOURCE_DIR}/pom.xml.in ${CMAKE_CURRENT_BINARY_DIR}/pom.xml @ONLY)
    file(COPY ${CMAKE_CURRENT_BINARY_DIR}/pom.xml
        DESTINATION ${CMAKE_CURRENT_SOURCE_DIR}
        PATTERN *.xml
        PERMISSIONS
            OWNER_READ
            GROUP_READ
            WORLD_READ
    )
    file (RENAME ${CMAKE_CURRENT_BINARY_DIR}/pom.xml ${CMAKE_CURRENT_BINARY_DIR}/pom.xml.generated)
endfunction()

function(derammo_install_thirdparty_java DERAMMO_COMPONENT_NAME)
	cmake_parse_arguments(PARSE_ARGV 1 DERAMMO_INSTALL 
		""
		"JAR;PACKAGE_LICENSE_PATH"
		"LICENSES"
	)

	# create commands to copy and install each license and accumulate a list of output paths for dependencies 
	set(DERAMMO_LICENSE_OUTPUT_PATHS "")
	foreach (DERAMMO_LICENSE_FRAGMENT ${DERAMMO_INSTALL_LICENSES})

		string(REGEX MATCH "^META-INF/(.*)$" DERAMMO_LICENSE_IN_JAR ${DERAMMO_LICENSE_FRAGMENT})
		if("${DERAMMO_LICENSE_IN_JAR}" STREQUAL "")
			# regular path
			set(DERAMMO_LICENSE_FILE ${DERAMMO_LICENSE_FRAGMENT})
		else()
			# path into the META-INF from unpacked jar
			set(DERAMMO_LICENSE_FILE ${CMAKE_BINARY_DIR}/${DERAMMO_JAVABUILD_OUTPUT}/unpack/${DERAMMO_INSTALL_JAR}/${DERAMMO_LICENSE_FRAGMENT})
		endif()
		get_filename_component(DERAMMO_INSTALL_LICENSE_NAME ${DERAMMO_LICENSE_FILE} NAME)

		set(DERAMMO_LICENSE_OUTPUT_PATH ${CMAKE_SOURCE_DIR}/thirdparty/licenses/${DERAMMO_INSTALL_PACKAGE_LICENSE_PATH}/${DERAMMO_INSTALL_LICENSE_NAME})

		# copy license
        get_filename_component(DERAMMO_LICENSE_OUTPUT_DIR "${DERAMMO_LICENSE_OUTPUT_PATH}" DIRECTORY)
		add_custom_command(
			OUTPUT "${DERAMMO_LICENSE_OUTPUT_PATH}"
			DEPENDS "${DERAMMO_LICENSE_FILE}"
            COMMAND ${CMAKE_COMMAND} -E make_directory "${DERAMMO_LICENSE_OUTPUT_DIR}"
            COMMAND ${CMAKE_COMMAND} -E copy_if_different "${DERAMMO_LICENSE_FILE}" "${DERAMMO_LICENSE_OUTPUT_PATH}"
		)
		list(APPEND DERAMMO_LICENSE_OUTPUT_PATHS ${DERAMMO_LICENSE_OUTPUT_PATH})

		# install license
		install(FILES
			${DERAMMO_LICENSE_OUTPUT_PATH}
			COMPONENT ${DERAMMO_COMPONENT_NAME}
        	DESTINATION ${DERAMMO_INSTALL_LICENSEDIR}/${DERAMMO_INSTALL_PACKAGE_LICENSE_PATH}
    	)
	endforeach()

	# a target to do any build-time prep for this library
	string(REPLACE "/" "-" DERAMMO_INSTALL_TARGET_SUFFIX ${DERAMMO_INSTALL_PACKAGE_LICENSE_PATH})
	add_custom_target(derammo-prepare-licenses-${DERAMMO_INSTALL_TARGET_SUFFIX}
		ALL
		DEPENDS ${DERAMMO_LICENSE_OUTPUT_PATHS}
	)

	# install jar
	install(FILES 
		${CMAKE_BINARY_DIR}/${DERAMMO_JAVABUILD_OUTPUT}/lib/${DERAMMO_INSTALL_JAR} 
		COMPONENT ${DERAMMO_COMPONENT_NAME}
		DESTINATION ${DERAMMO_INSTALL_LIBDIR}
	)
endfunction()
