# make file used to initialize directories with cmake support, to be run from those directories
#
# e.g. make -f cmake/setup.make root
# e.g. make -f ../cmake/setup.make executable

# initialize a new project to use this cmake system via a "cmake" folder in that project's root
root: Makefile CMakeLists.txt .gitignore

# default library type
DERAMMO_LIBRARY_TYPE=SHARED

# initialize a library target in a subfolder of the root
library: ../CMakeLists.txt
	PROJECT_NAME=$$(basename $$(pwd)) && \
	echo "add_library($${PROJECT_NAME} $(DERAMMO_LIBRARY_TYPE))" \
		> CMakeLists.txt && \
	echo "target_include_directories($${PROJECT_NAME} PUBLIC include)" \
		>> CMakeLists.txt && \
	echo "target_include_directories($${PROJECT_NAME} PRIVATE src)" \
		>> CMakeLists.txt && \
	echo "include(sources.cmake)" \
		>> CMakeLists.txt && \
	for local in *.cpp *.h ; do \
		[ -f $${local} ] && echo "target_sources($${PROJECT_NAME} PUBLIC $${local})" > sources.cmake || true ; \
	done ; \
	for interface in $$(find include -name '*.h') ; do \
		[ -f $${interface} ] && echo "target_sources($${PROJECT_NAME} INTERFACE $${interface})" >> sources.cmake || true ; \
	done ; \
	for private in $$(find src -name '*.cpp' -or -name '*.c' -or -name '*.h') ; do \
		[ -f $${private} ] && echo "target_sources($${PROJECT_NAME} PRIVATE $${private})" >> sources.cmake || true ; \
	done 

# initialize a static library target in a subfolder of the root
static:
	${MAKE} -f ../cmake/setup.make DERAMMO_LIBRARY_TYPE=STATIC library

# initialize an executable target in a subfolder of the root
executable: ../CMakeLists.txt
	PROJECT_NAME=$$(basename $$(pwd)) && \
	echo "add_executable($${PROJECT_NAME})" \
		> CMakeLists.txt && \
	echo "target_include_directories($${PROJECT_NAME} PRIVATE include)" \
		>> CMakeLists.txt && \
	echo "include(sources.cmake)" \
		>> CMakeLists.txt && \
	for local in *.cpp *.h ; do \
		[ -f $${local} ] && echo "target_sources($${PROJECT_NAME} PUBLIC $${local})" > sources.cmake || true ; \
	done ; \
	for private in $$(find src -name '*.cpp' -or -name '*.c' -or -name '*.h') ; do \
		[ -f $${private} ] && echo "target_sources($${PROJECT_NAME} PRIVATE $${private})" > sources.cmake || true ; \
	done 

Makefile: | cmake/setup_templates/Makefile.init
	cp cmake/setup_templates/Makefile.init $@

CMakeLists.txt: | cmake/setup_templates/CMakeLists.init
	PROJECT_NAME=$$(basename $$(pwd)) && \
	sed -e s/REPLACE_PROJECT_NAME/$${PROJECT_NAME}/ < cmake/setup_templates/CMakeLists.init > $@

	# create initial list of subdirectories by exclusion of known names
	PROJECTS="$$(find . -maxdepth 1 \
		-name "$(strip $(DERAMMO_PLATFORM))" -prune -or \
		-name "Windows" -prune -or \
		-name "cmake" -prune -or \
		-name "build" -prune -or \
		-name "bin" -prune -or \
		-name "lib" -prune -or \
		-name "include" -prune -or \
		-name ".git" -prune -or \
		-name "." -or \
		-type d -print )" && \
	echo $$PROJECTS && \
	for project in $$PROJECTS ; \
		do \
		echo "add_subdirectory($$(basename $${project}))" >> $@ ;\
	done 
	echo >> $@
	echo "# packaging support" >> $@
	echo "include(CPack)" >> $@

# default gitignore file
.gitignore: | cmake/setup_templates/gitignore.init
	# may duplicate things, but that is the safer choice than overwriting
	@if [ -f .gitignore ] ; then \
		echo merging gitignore files ; \
		cp .gitignore .gitignore.old ; \
		cat .gitignore.old cmake/setup_templates/gitignore.init | sort -u > .gitignore ; \
	else \
		echo creating gitignore file ; \
		cp cmake/setup_templates/gitignore.init .gitignore ; \
	fi
	